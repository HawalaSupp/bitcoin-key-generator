//
//  HardwareWalletManagerV2.swift
//  Hawala
//
//  Hardware Wallet Manager - Unified Device Management
//
//  Coordinates hardware wallet discovery, connection management,
//  and signing operations across Ledger and Trezor devices.
//

import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid
import CoreBluetooth
import Combine

// MARK: - Hardware Wallet Manager

/// Manages hardware wallet devices and signing operations
@MainActor
public final class HardwareWalletManagerV2: ObservableObject, @unchecked Sendable {
    // MARK: - Singleton
    
    public static let shared = HardwareWalletManagerV2()
    
    // MARK: - Published State
    
    /// Currently discovered devices
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    
    /// Connected wallet sessions
    @Published public var connectedWallets: [String: HardwareWallet] = [:]
    
    /// Whether device scanning is active
    @Published public var isScanning = false
    
    /// Current error message
    @Published public var error: HWError?
    
    /// Saved hardware wallet accounts
    @Published public var savedAccounts: [HardwareWalletAccount] = []
    
    // MARK: - Private State
    
    private var hidManager: IOHIDManager?
    private var bluetoothManager: CBCentralManager?
    private var bluetoothDelegate: BluetoothDelegate?
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "hardwareWalletAccounts_v2"
    
    // Callbacks for UI
    public var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
    public var onDeviceRemoved: ((DiscoveredDevice) -> Void)?
    public var onPinRequired: (@Sendable () async -> String?)?
    public var onPassphraseRequired: (@Sendable () async -> String?)?
    public var onButtonConfirmationRequired: (@Sendable (String) async -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        loadSavedAccounts()
    }
    
    // MARK: - Device Discovery
    
    /// Start scanning for hardware wallets
    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        error = nil
        
        setupUSBScanning()
        setupBluetoothScanning()
    }
    
    /// Stop scanning for hardware wallets
    public func stopScanning() {
        isScanning = false
        
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        
        bluetoothManager?.stopScan()
    }
    
    /// Refresh device list
    public func refresh() {
        discoveredDevices.removeAll()
        stopScanning()
        startScanning()
    }
    
    // MARK: - USB Scanning
    
    private func setupUSBScanning() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            error = .connectionFailed("Failed to create HID manager")
            return
        }
        
        // Build matching dictionaries for all supported devices
        var matchingDicts: [[String: Any]] = []
        
        for deviceType in HardwareDeviceType.allCases {
            for productId in deviceType.productIds {
                matchingDicts.append([
                    kIOHIDVendorIDKey as String: deviceType.vendorId,
                    kIOHIDProductIDKey as String: productId
                ])
            }
        }
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)
        
        // Set up callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HardwareWalletManagerV2>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.handleUSBDeviceConnected(device)
            }
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HardwareWalletManagerV2>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.handleUSBDeviceDisconnected(device)
            }
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            error = .connectionFailed("Failed to open HID manager: \(result)")
        }
    }
    
    private func handleUSBDeviceConnected(_ device: IOHIDDevice) {
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let locationId = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        
        // Identify device type
        guard let deviceType = HardwareDeviceType.allCases.first(where: {
            $0.vendorId == vendorId && $0.productIds.contains(UInt16(productId))
        }) else { return }
        
        let discovered = DiscoveredDevice(
            id: "usb-\(locationId)",
            deviceType: deviceType,
            connectionType: .usb,
            name: deviceType.displayName
        )
        
        if !discoveredDevices.contains(where: { $0.id == discovered.id }) {
            discoveredDevices.append(discovered)
            onDeviceDiscovered?(discovered)
        }
    }
    
    private func handleUSBDeviceDisconnected(_ device: IOHIDDevice) {
        let locationId = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        let deviceId = "usb-\(locationId)"
        
        if let removed = discoveredDevices.first(where: { $0.id == deviceId }) {
            discoveredDevices.removeAll { $0.id == deviceId }
            connectedWallets.removeValue(forKey: deviceId)
            onDeviceRemoved?(removed)
        }
    }
    
    // MARK: - Bluetooth Scanning
    
    private func setupBluetoothScanning() {
        bluetoothDelegate = BluetoothDelegate(manager: self)
        bluetoothManager = CBCentralManager(delegate: bluetoothDelegate, queue: .main)
    }
    
    fileprivate func handleBluetoothDeviceDiscovered(_ peripheral: CBPeripheral, advertisementData: [String: Any]) {
        // Check if this is a Ledger device
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        
        if name.lowercased().contains("nano") || name.lowercased().contains("ledger") {
            let deviceType: HardwareDeviceType
            if name.lowercased().contains("x") {
                deviceType = .ledgerNanoX
            } else if name.lowercased().contains("stax") {
                deviceType = .ledgerStax
            } else {
                deviceType = .ledgerNanoX // Default BLE Ledger
            }
            
            let discovered = DiscoveredDevice(
                id: "ble-\(peripheral.identifier.uuidString)",
                deviceType: deviceType,
                connectionType: .bluetooth,
                name: name
            )
            
            if !discoveredDevices.contains(where: { $0.id == discovered.id }) {
                discoveredDevices.append(discovered)
                onDeviceDiscovered?(discovered)
            }
        }
    }
    
    // MARK: - Connection Management
    
    /// Connect to a discovered device
    /// - Parameter device: The device to connect to
    /// - Returns: The connected hardware wallet
    public func connect(to device: DiscoveredDevice) async throws -> HardwareWallet {
        // Create the appropriate wallet
        let wallet: HardwareWallet
        
        switch device.deviceType.manufacturer {
        case .ledger:
            wallet = LedgerWallet(deviceInfo: device)
        case .trezor:
            let trezorWallet = TrezorWallet(deviceInfo: device)
            
            // Set up callbacks
            await trezorWallet.setPinCallback(onPinRequired)
            await trezorWallet.setPassphraseCallback(onPassphraseRequired)
            await trezorWallet.setButtonCallback(onButtonConfirmationRequired)
            
            wallet = trezorWallet
        }
        
        // Connect
        try await wallet.connect()
        
        // Store connected wallet
        connectedWallets[device.id] = wallet
        
        return wallet
    }
    
    /// Disconnect from a device
    /// - Parameter deviceId: The device ID to disconnect
    public func disconnect(deviceId: String) async throws {
        guard let wallet = connectedWallets[deviceId] else { return }
        
        try await wallet.disconnect()
        connectedWallets.removeValue(forKey: deviceId)
    }
    
    /// Disconnect all devices
    public func disconnectAll() async {
        for (id, wallet) in connectedWallets {
            try? await wallet.disconnect()
            connectedWallets.removeValue(forKey: id)
        }
    }
    
    /// Get a connected wallet by ID
    public func getConnectedWallet(deviceId: String) -> HardwareWallet? {
        return connectedWallets[deviceId]
    }
    
    // MARK: - Signing Operations
    
    /// Get public key from hardware wallet
    public func getPublicKey(
        deviceId: String,
        path: DerivationPath,
        chain: SupportedChain
    ) async throws -> PublicKeyResult {
        guard let wallet = connectedWallets[deviceId] else {
            throw HWError.deviceNotFound
        }
        
        return try await wallet.getPublicKey(path: path, curve: chain.curve)
    }
    
    /// Get address with optional verification
    public func getAddress(
        deviceId: String,
        path: DerivationPath,
        chain: SupportedChain,
        verify: Bool = true
    ) async throws -> AddressResult {
        guard let wallet = connectedWallets[deviceId] else {
            throw HWError.deviceNotFound
        }
        
        return try await wallet.getAddress(path: path, chain: chain, display: verify)
    }
    
    /// Sign a transaction
    public func signTransaction(
        deviceId: String,
        path: DerivationPath,
        transaction: HardwareWalletTransaction,
        chain: SupportedChain
    ) async throws -> SignatureResult {
        guard let wallet = connectedWallets[deviceId] else {
            throw HWError.deviceNotFound
        }
        
        return try await wallet.signTransaction(path: path, transaction: transaction, chain: chain)
    }
    
    /// Sign a message
    public func signMessage(
        deviceId: String,
        path: DerivationPath,
        message: Data,
        chain: SupportedChain
    ) async throws -> SignatureResult {
        guard let wallet = connectedWallets[deviceId] else {
            throw HWError.deviceNotFound
        }
        
        return try await wallet.signMessage(path: path, message: message, chain: chain)
    }
    
    /// Sign EIP-712 typed data
    public func signTypedData(
        deviceId: String,
        path: DerivationPath,
        domainHash: Data,
        messageHash: Data
    ) async throws -> SignatureResult {
        guard let wallet = connectedWallets[deviceId] else {
            throw HWError.deviceNotFound
        }
        
        return try await wallet.signTypedData(path: path, domainHash: domainHash, messageHash: messageHash)
    }
    
    // MARK: - Account Management
    
    /// Add a hardware wallet account
    public func addAccount(_ account: HardwareWalletAccount) {
        if !savedAccounts.contains(where: { $0.id == account.id }) {
            savedAccounts.append(account)
            persistAccounts()
        }
    }
    
    /// Remove a hardware wallet account
    public func removeAccount(id: String) {
        savedAccounts.removeAll { $0.id == id }
        persistAccounts()
    }
    
    /// Update account label
    public func updateAccountLabel(id: String, label: String) {
        if let index = savedAccounts.firstIndex(where: { $0.id == id }) {
            savedAccounts[index] = HardwareWalletAccount(
                id: savedAccounts[index].id,
                deviceType: savedAccounts[index].deviceType,
                chain: savedAccounts[index].chain,
                derivationPath: savedAccounts[index].derivationPath,
                address: savedAccounts[index].address,
                publicKey: savedAccounts[index].publicKey,
                label: label,
                createdAt: savedAccounts[index].createdAt
            )
            persistAccounts()
        }
    }
    
    /// Get accounts for a specific chain
    public func getAccounts(for chain: SupportedChain) -> [HardwareWalletAccount] {
        return savedAccounts.filter { $0.chain == chain }
    }
    
    private func loadSavedAccounts() {
        if let data = userDefaults.data(forKey: accountsKey),
           let accounts = try? JSONDecoder().decode([HardwareWalletAccount].self, from: data) {
            savedAccounts = accounts
        }
    }
    
    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(savedAccounts) {
            userDefaults.set(data, forKey: accountsKey)
        }
    }
}

// MARK: - Hardware Wallet Account

/// Saved hardware wallet account
public struct HardwareWalletAccount: Identifiable, Codable, Sendable {
    public let id: String
    public let deviceType: HardwareDeviceType
    public let chain: SupportedChain
    public let derivationPath: String
    public let address: String
    public let publicKey: String
    public var label: String?
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        deviceType: HardwareDeviceType,
        chain: SupportedChain,
        derivationPath: String,
        address: String,
        publicKey: String,
        label: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceType = deviceType
        self.chain = chain
        self.derivationPath = derivationPath
        self.address = address
        self.publicKey = publicKey
        self.label = label
        self.createdAt = createdAt
    }
}

// MARK: - Bluetooth Delegate

/// Note: This class uses unchecked Sendable because CoreBluetooth delegates
/// require non-isolated callbacks, but our manager is @MainActor
private class BluetoothDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private weak var manager: HardwareWalletManagerV2?
    
    init(manager: HardwareWalletManagerV2) {
        self.manager = manager
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Scan for Ledger devices
            let ledgerServiceUUID = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")
            central.scanForPeripherals(withServices: [ledgerServiceUUID], options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Store the device info we need (peripheral name and identifier)
        let name = peripheral.name
        let identifier = peripheral.identifier.uuidString
        
        // Dispatch to main thread
        DispatchQueue.main.async {
            guard let manager = self.manager else { return }
            
            // Create device discovery info
            let device = DiscoveredDevice(
                id: identifier,
                deviceType: .ledgerNanoX,  // Assume Nano X for BLE
                connectionType: .bluetooth,
                name: name
            )
            
            if !manager.discoveredDevices.contains(where: { $0.id == identifier }) {
                manager.discoveredDevices.append(device)
            }
        }
    }
}

// MARK: - Trezor Callback Extension

extension TrezorWallet {
    func setPinCallback(_ callback: (@Sendable () async -> String?)?) async {
        self.pinCallback = callback
    }
    
    func setPassphraseCallback(_ callback: (@Sendable () async -> String?)?) async {
        self.passphraseCallback = callback
    }
    
    func setButtonCallback(_ callback: (@Sendable (String) async -> Void)?) async {
        self.buttonCallback = callback
    }
}
