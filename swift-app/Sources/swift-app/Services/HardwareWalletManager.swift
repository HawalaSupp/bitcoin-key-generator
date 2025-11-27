import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

// MARK: - Hardware Wallet Models

/// Supported hardware wallet types
enum HardwareWalletType: String, CaseIterable, Codable {
    case ledgerNanoS = "ledger_nano_s"
    case ledgerNanoX = "ledger_nano_x"
    case ledgerNanoSPlus = "ledger_nano_s_plus"
    case trezorOne = "trezor_one"
    case trezorT = "trezor_t"
    
    var displayName: String {
        switch self {
        case .ledgerNanoS: return "Ledger Nano S"
        case .ledgerNanoX: return "Ledger Nano X"
        case .ledgerNanoSPlus: return "Ledger Nano S Plus"
        case .trezorOne: return "Trezor One"
        case .trezorT: return "Trezor Model T"
        }
    }
    
    var vendorId: Int {
        switch self {
        case .ledgerNanoS, .ledgerNanoX, .ledgerNanoSPlus:
            return 0x2c97 // Ledger
        case .trezorOne, .trezorT:
            return 0x1209 // Trezor (SatoshiLabs)
        }
    }
    
    var productIds: [Int] {
        switch self {
        case .ledgerNanoS: return [0x0001, 0x1011]
        case .ledgerNanoX: return [0x0004, 0x4011]
        case .ledgerNanoSPlus: return [0x0005, 0x5011]
        case .trezorOne: return [0x53C1]
        case .trezorT: return [0x53C0]
        }
    }
    
    var isLedger: Bool {
        switch self {
        case .ledgerNanoS, .ledgerNanoX, .ledgerNanoSPlus: return true
        case .trezorOne, .trezorT: return false
        }
    }
}

/// Represents a connected hardware wallet
struct ConnectedHardwareWallet: Identifiable {
    let id: UUID
    let type: HardwareWalletType
    let devicePath: String
    var isConnected: Bool
    var appOpen: String? // e.g., "Bitcoin", "Ethereum"
    var firmwareVersion: String?
}

/// Address derived from hardware wallet
struct HardwareWalletAddress: Identifiable, Codable {
    let id: UUID
    let walletType: HardwareWalletType
    let chain: String
    let derivationPath: String
    let address: String
    let publicKey: String
    var label: String?
}

// MARK: - Ledger APDU Commands

struct LedgerAPDU {
    // CLA for Bitcoin app
    static let claBitcoin: UInt8 = 0xe0
    
    // INS commands
    static let insGetWalletPublicKey: UInt8 = 0x40
    static let insSignTransaction: UInt8 = 0x04
    static let insGetVersion: UInt8 = 0xc4
    
    // Common commands
    static func getVersion() -> Data {
        return Data([claBitcoin, insGetVersion, 0x00, 0x00, 0x00])
    }
    
    static func getPublicKey(path: String, display: Bool = false) -> Data {
        let pathData = serializeDerivationPath(path)
        var apdu = Data([claBitcoin, insGetWalletPublicKey, display ? 0x01 : 0x00, 0x00])
        apdu.append(UInt8(pathData.count))
        apdu.append(pathData)
        return apdu
    }
    
    // Serialize BIP32 path like "m/84'/0'/0'/0/0"
    static func serializeDerivationPath(_ path: String) -> Data {
        let components = path.replacingOccurrences(of: "m/", with: "")
            .split(separator: "/")
        
        var data = Data([UInt8(components.count)])
        
        for component in components {
            let str = String(component)
            let hardened = str.hasSuffix("'")
            let indexStr = hardened ? String(str.dropLast()) : str
            
            guard var index = UInt32(indexStr) else { continue }
            if hardened {
                index += 0x80000000
            }
            
            // Big-endian encoding
            data.append(contentsOf: withUnsafeBytes(of: index.bigEndian) { Array($0) })
        }
        
        return data
    }
}

// MARK: - Hardware Wallet Manager

@MainActor
class HardwareWalletManager: ObservableObject {
    static let shared = HardwareWalletManager()
    
    @Published var connectedDevices: [ConnectedHardwareWallet] = []
    @Published var savedAddresses: [HardwareWalletAddress] = []
    @Published var isScanning = false
    @Published var error: String?
    
    private var hidManager: IOHIDManager?
    private var deviceCallbacks: [String: ((Data) -> Void)] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let addressesKey = "hardwareWalletAddresses"
    
    private init() {
        loadSavedAddresses()
        setupHIDManager()
    }
    
    // Singleton - no deinit needed, manager lives for app lifetime
    
    // MARK: - HID Setup
    
    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            error = "Failed to create HID manager"
            return
        }
        
        // Build matching dictionaries for all supported devices
        var matchingDicts: [[String: Any]] = []
        
        for walletType in HardwareWalletType.allCases {
            for productId in walletType.productIds {
                matchingDicts.append([
                    kIOHIDVendorIDKey as String: walletType.vendorId,
                    kIOHIDProductIDKey as String: productId
                ])
            }
        }
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)
        
        // Set up callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HardwareWalletManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.deviceConnected(device)
            }
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HardwareWalletManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.deviceDisconnected(device)
            }
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            error = "Failed to open HID manager: \(result)"
        }
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let path = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? String ?? UUID().uuidString
        
        // Identify wallet type
        guard let walletType = HardwareWalletType.allCases.first(where: {
            $0.vendorId == vendorId && $0.productIds.contains(productId)
        }) else { return }
        
        let wallet = ConnectedHardwareWallet(
            id: UUID(),
            type: walletType,
            devicePath: path,
            isConnected: true,
            appOpen: nil,
            firmwareVersion: nil
        )
        
        connectedDevices.append(wallet)
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        let path = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? String ?? ""
        connectedDevices.removeAll { $0.devicePath == path }
    }
    
    // MARK: - Device Communication
    
    /// Send APDU command to Ledger device
    func sendLedgerAPDU(_ apdu: Data, to device: ConnectedHardwareWallet) async throws -> Data {
        // In a real implementation, this would:
        // 1. Open the HID device
        // 2. Frame the APDU according to Ledger's protocol
        // 3. Send chunks via IOHIDDeviceSetReport
        // 4. Receive response via IOHIDDeviceGetReport
        // 5. Parse and return the result
        
        // For now, throw not implemented
        throw HardwareWalletError.notImplemented("Direct USB communication requires additional entitlements and setup")
    }
    
    /// Get Bitcoin address from Ledger
    func getLedgerBitcoinAddress(device: ConnectedHardwareWallet, path: String = "m/84'/0'/0'/0/0", display: Bool = true) async throws -> HardwareWalletAddress {
        let apdu = LedgerAPDU.getPublicKey(path: path, display: display)
        let response = try await sendLedgerAPDU(apdu, to: device)
        
        // Parse response: pubkey length (1) + pubkey + address length (1) + address + chaincode (32)
        guard response.count > 2 else {
            throw HardwareWalletError.invalidResponse
        }
        
        let pubKeyLength = Int(response[0])
        let pubKey = response[1..<(1 + pubKeyLength)]
        
        let addressStart = 1 + pubKeyLength
        let addressLength = Int(response[addressStart])
        let addressData = response[(addressStart + 1)..<(addressStart + 1 + addressLength)]
        
        guard let address = String(data: addressData, encoding: .ascii) else {
            throw HardwareWalletError.invalidResponse
        }
        
        let hwAddress = HardwareWalletAddress(
            id: UUID(),
            walletType: device.type,
            chain: "bitcoin",
            derivationPath: path,
            address: address,
            publicKey: pubKey.hexEncodedString()
        )
        
        return hwAddress
    }
    
    /// Sign Bitcoin transaction with Ledger
    func signBitcoinTransaction(device: ConnectedHardwareWallet, txData: Data, path: String) async throws -> Data {
        // This would implement the multi-step Ledger signing protocol:
        // 1. Send transaction inputs
        // 2. Send transaction outputs
        // 3. Request signature
        // 4. User confirms on device
        // 5. Return signature
        
        throw HardwareWalletError.notImplemented("Transaction signing not yet implemented")
    }
    
    // MARK: - Address Management
    
    func saveAddress(_ address: HardwareWalletAddress) {
        savedAddresses.append(address)
        persistAddresses()
    }
    
    func deleteAddress(_ address: HardwareWalletAddress) {
        savedAddresses.removeAll { $0.id == address.id }
        persistAddresses()
    }
    
    private func loadSavedAddresses() {
        if let data = userDefaults.data(forKey: addressesKey),
           let loaded = try? JSONDecoder().decode([HardwareWalletAddress].self, from: data) {
            savedAddresses = loaded
        }
    }
    
    private func persistAddresses() {
        if let data = try? JSONEncoder().encode(savedAddresses) {
            userDefaults.set(data, forKey: addressesKey)
        }
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        isScanning = true
        // The HID manager callbacks will handle device detection
    }
    
    func stopScanning() {
        isScanning = false
    }
    
    func refreshDevices() {
        // Trigger a rescan
        connectedDevices.removeAll()
        // HID manager will repopulate via callbacks
    }
}

// MARK: - Errors

enum HardwareWalletError: LocalizedError {
    case notImplemented(String)
    case deviceNotFound
    case communicationFailed
    case invalidResponse
    case userRejected
    case appNotOpen(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let msg): return msg
        case .deviceNotFound: return "Hardware wallet not found"
        case .communicationFailed: return "Failed to communicate with device"
        case .invalidResponse: return "Invalid response from device"
        case .userRejected: return "User rejected the request on device"
        case .appNotOpen(let app): return "Please open the \(app) app on your device"
        case .timeout: return "Device communication timed out"
        }
    }
}

// MARK: - Data Extension
// Note: hexEncodedString() already defined elsewhere in codebase
