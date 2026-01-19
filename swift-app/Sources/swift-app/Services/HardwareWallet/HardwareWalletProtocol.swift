//
//  HardwareWalletProtocol.swift
//  Hawala
//
//  Hardware Wallet Abstraction Layer
//
//  This module defines the common protocol for all hardware wallet integrations
//  (Ledger, Trezor, etc.) enabling unified transaction signing with offline keys.
//

import Foundation

// MARK: - Hardware Wallet Protocol

/// Common interface for hardware wallet implementations
public protocol HardwareWallet: AnyObject, Sendable {
    /// Human-readable device name
    var name: String { get }
    
    /// Device model type
    var deviceType: HardwareDeviceType { get }
    
    /// Current connection status
    var connectionStatus: HardwareDeviceStatus { get async }
    
    /// Whether the device is currently connected
    var isConnected: Bool { get async }
    
    /// Chains supported by this device/app
    var supportedChains: [SupportedChain] { get async }
    
    /// Firmware version if available
    var firmwareVersion: String? { get async }
    
    /// Connect to the hardware wallet
    func connect() async throws
    
    /// Disconnect from the hardware wallet
    func disconnect() async throws
    
    /// Get public key for derivation path
    /// - Parameters:
    ///   - path: BIP32 derivation path (e.g., "m/44'/60'/0'/0/0")
    ///   - curve: Elliptic curve to use
    /// - Returns: Public key bytes
    func getPublicKey(path: DerivationPath, curve: EllipticCurveType) async throws -> PublicKeyResult
    
    /// Get address for derivation path with optional on-device verification
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - chain: Target blockchain
    ///   - display: Whether to show address on device for verification
    /// - Returns: Address string
    func getAddress(path: DerivationPath, chain: SupportedChain, display: Bool) async throws -> AddressResult
    
    /// Sign a transaction
    /// - Parameters:
    ///   - path: BIP32 derivation path for the signing key
    ///   - transaction: Unsigned transaction data
    ///   - chain: Target blockchain
    /// - Returns: Signature bytes
    func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction, chain: SupportedChain) async throws -> SignatureResult
    
    /// Sign a message (personal sign)
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - message: Message bytes to sign
    ///   - chain: Target blockchain
    /// - Returns: Signature bytes
    func signMessage(path: DerivationPath, message: Data, chain: SupportedChain) async throws -> SignatureResult
    
    /// Sign EIP-712 typed data (Ethereum only)
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - domainHash: EIP-712 domain separator hash
    ///   - messageHash: EIP-712 message hash
    /// - Returns: Signature bytes
    func signTypedData(path: DerivationPath, domainHash: Data, messageHash: Data) async throws -> SignatureResult
}

// MARK: - Device Types

/// Supported hardware wallet device types
public enum HardwareDeviceType: String, CaseIterable, Codable, Sendable {
    // Ledger devices
    case ledgerNanoS = "ledger_nano_s"
    case ledgerNanoSPlus = "ledger_nano_s_plus"
    case ledgerNanoX = "ledger_nano_x"
    case ledgerStax = "ledger_stax"
    
    // Trezor devices
    case trezorOne = "trezor_one"
    case trezorModelT = "trezor_model_t"
    case trezorSafe3 = "trezor_safe_3"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .ledgerNanoS: return "Ledger Nano S"
        case .ledgerNanoSPlus: return "Ledger Nano S Plus"
        case .ledgerNanoX: return "Ledger Nano X"
        case .ledgerStax: return "Ledger Stax"
        case .trezorOne: return "Trezor One"
        case .trezorModelT: return "Trezor Model T"
        case .trezorSafe3: return "Trezor Safe 3"
        }
    }
    
    /// Device manufacturer
    public var manufacturer: HardwareWalletManufacturer {
        switch self {
        case .ledgerNanoS, .ledgerNanoSPlus, .ledgerNanoX, .ledgerStax:
            return .ledger
        case .trezorOne, .trezorModelT, .trezorSafe3:
            return .trezor
        }
    }
    
    /// USB Vendor ID
    public var vendorId: UInt16 {
        switch manufacturer {
        case .ledger: return 0x2c97
        case .trezor: return 0x1209
        }
    }
    
    /// USB Product IDs
    public var productIds: [UInt16] {
        switch self {
        case .ledgerNanoS: return [0x0001, 0x1011]
        case .ledgerNanoSPlus: return [0x5011]
        case .ledgerNanoX: return [0x0004, 0x4011]
        case .ledgerStax: return [0x6011]
        case .trezorOne: return [0x53C1]
        case .trezorModelT: return [0x53C0]
        case .trezorSafe3: return [0x53C0] // Same as Model T
        }
    }
    
    /// Supports Bluetooth
    public var supportsBluetooth: Bool {
        switch self {
        case .ledgerNanoX, .ledgerStax: return true
        default: return false
        }
    }
    
    /// Supports USB
    public var supportsUSB: Bool {
        return true // All devices support USB
    }
}

/// Hardware wallet manufacturers
public enum HardwareWalletManufacturer: String, Codable, Sendable {
    case ledger
    case trezor
}

// MARK: - Device Status

/// Device connection status
public enum HardwareDeviceStatus: Sendable {
    case disconnected
    case connecting
    case connected
    case requiresPinEntry
    case requiresPassphrase
    case requiresAppOpen(appName: String)
    case ready
    case busy
    case error(HWError)
    
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Supported Chains

/// Blockchains supported by hardware wallets
public enum SupportedChain: String, CaseIterable, Codable, Sendable {
    case bitcoin = "bitcoin"
    case ethereum = "ethereum"
    case solana = "solana"
    case cosmos = "cosmos"
    case polygon = "polygon"
    case arbitrum = "arbitrum"
    case optimism = "optimism"
    case avalanche = "avalanche"
    case bsc = "bsc"
    
    /// Ledger app name for this chain
    public var ledgerAppName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .solana: return "Solana"
        case .cosmos: return "Cosmos"
        case .polygon: return "Ethereum" // Uses Ethereum app
        case .arbitrum: return "Ethereum"
        case .optimism: return "Ethereum"
        case .avalanche: return "Avalanche"
        case .bsc: return "Ethereum"
        }
    }
    
    /// BIP44 coin type
    public var coinType: UInt32 {
        switch self {
        case .bitcoin: return 0
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc: return 60
        case .solana: return 501
        case .cosmos: return 118
        case .avalanche: return 9000
        }
    }
    
    /// Default derivation path
    public var defaultPath: String {
        switch self {
        case .bitcoin: return "m/84'/0'/0'/0/0"  // Native SegWit
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc: return "m/44'/60'/0'/0/0"
        case .solana: return "m/44'/501'/0'/0'"
        case .cosmos: return "m/44'/118'/0'/0/0"
        case .avalanche: return "m/44'/9000'/0'/0/0"
        }
    }
    
    /// Elliptic curve used
    public var curve: EllipticCurveType {
        switch self {
        case .bitcoin, .ethereum, .polygon, .arbitrum, .optimism, .bsc, .avalanche, .cosmos:
            return .secp256k1
        case .solana:
            return .ed25519
        }
    }
}

// MARK: - Elliptic Curves

/// Elliptic curve types used in hardware wallets
public enum EllipticCurveType: String, Codable, Sendable {
    case secp256k1
    case ed25519
    case nist256p1 // P-256 / secp256r1
    case sr25519   // Polkadot/Substrate
}

// MARK: - Derivation Path

/// BIP32 derivation path
public struct DerivationPath: CustomStringConvertible, Sendable {
    /// Path components
    public let components: [PathComponent]
    
    /// A single path component
    public struct PathComponent: Sendable {
        public let index: UInt32
        public let hardened: Bool
        
        public init(index: UInt32, hardened: Bool = false) {
            self.index = index
            self.hardened = hardened
        }
        
        public var value: UInt32 {
            hardened ? (index | 0x80000000) : index
        }
    }
    
    /// Create from string like "m/44'/60'/0'/0/0"
    public init?(string: String) {
        var pathStr = string
        if pathStr.hasPrefix("m/") {
            pathStr = String(pathStr.dropFirst(2))
        }
        
        var comps: [PathComponent] = []
        for part in pathStr.split(separator: "/") {
            var str = String(part)
            let hardened = str.hasSuffix("'") || str.hasSuffix("h") || str.hasSuffix("H")
            if hardened {
                str = String(str.dropLast())
            }
            guard let index = UInt32(str) else { return nil }
            comps.append(PathComponent(index: index, hardened: hardened))
        }
        
        self.components = comps
    }
    
    /// Create from components
    public init(components: [PathComponent]) {
        self.components = components
    }
    
    /// Standard BIP44 path for coin type
    public static func bip44(coinType: UInt32, account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> DerivationPath {
        DerivationPath(components: [
            PathComponent(index: 44, hardened: true),
            PathComponent(index: coinType, hardened: true),
            PathComponent(index: account, hardened: true),
            PathComponent(index: change, hardened: false),
            PathComponent(index: index, hardened: false)
        ])
    }
    
    /// BIP84 path for native SegWit Bitcoin
    public static func bip84(account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> DerivationPath {
        DerivationPath(components: [
            PathComponent(index: 84, hardened: true),
            PathComponent(index: 0, hardened: true),
            PathComponent(index: account, hardened: true),
            PathComponent(index: change, hardened: false),
            PathComponent(index: index, hardened: false)
        ])
    }
    
    public var description: String {
        "m/" + components.map { comp in
            "\(comp.index)" + (comp.hardened ? "'" : "")
        }.joined(separator: "/")
    }
    
    /// Serialize for Ledger APDU
    public func serialize() -> Data {
        var data = Data([UInt8(components.count)])
        for comp in components {
            // Big-endian 4-byte value
            var value = comp.value.bigEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
}

// MARK: - Result Types

/// Public key result from hardware wallet
public struct PublicKeyResult: Sendable {
    /// Raw public key bytes
    public let publicKey: Data
    
    /// Chain code (for HD derivation)
    public let chainCode: Data?
    
    /// Address derived from public key (if returned by device)
    public let address: String?
    
    public init(publicKey: Data, chainCode: Data? = nil, address: String? = nil) {
        self.publicKey = publicKey
        self.chainCode = chainCode
        self.address = address
    }
}

/// Address result from hardware wallet
public struct AddressResult: Sendable {
    /// The blockchain address
    public let address: String
    
    /// Associated public key
    public let publicKey: Data?
    
    /// Derivation path used
    public let path: DerivationPath
    
    public init(address: String, publicKey: Data? = nil, path: DerivationPath) {
        self.address = address
        self.publicKey = publicKey
        self.path = path
    }
}

/// Signature result from hardware wallet
public struct SignatureResult: Sendable {
    /// Signature bytes (DER or raw depending on chain)
    public let signature: Data
    
    /// Recovery ID for ECDSA (v value, 0 or 1)
    public let recoveryId: UInt8?
    
    /// Full EIP-155 v value for Ethereum
    public let ethereumV: UInt64?
    
    public init(signature: Data, recoveryId: UInt8? = nil, ethereumV: UInt64? = nil) {
        self.signature = signature
        self.recoveryId = recoveryId
        self.ethereumV = ethereumV
    }
    
    /// R component (first 32 bytes for 64-byte signature)
    public var r: Data? {
        guard signature.count >= 32 else { return nil }
        return signature.prefix(32)
    }
    
    /// S component (second 32 bytes for 64-byte signature)
    public var s: Data? {
        guard signature.count >= 64 else { return nil }
        return signature.dropFirst(32).prefix(32)
    }
}

// MARK: - Transaction Types

/// Unsigned transaction for hardware wallet signing
public struct HardwareWalletTransaction: Sendable {
    /// Serialized unsigned transaction data
    public let rawData: Data
    
    /// Pre-computed hash(es) to sign
    public let preImageHashes: [Data]?
    
    /// Human-readable transaction details for display
    public let displayInfo: TransactionDisplayInfo?
    
    public init(rawData: Data, preImageHashes: [Data]? = nil, displayInfo: TransactionDisplayInfo? = nil) {
        self.rawData = rawData
        self.preImageHashes = preImageHashes
        self.displayInfo = displayInfo
    }
}

/// Transaction information for hardware wallet display
public struct TransactionDisplayInfo: Sendable {
    public let type: String // "Send", "Swap", "Contract Call"
    public let amount: String?
    public let recipient: String?
    public let fee: String?
    public let network: String?
    
    public init(type: String, amount: String? = nil, recipient: String? = nil, fee: String? = nil, network: String? = nil) {
        self.type = type
        self.amount = amount
        self.recipient = recipient
        self.fee = fee
        self.network = network
    }
}

// MARK: - Hardware Wallet Errors

/// Errors that can occur during hardware wallet operations (V2)
/// Named HWError to avoid conflict with existing HWError
public enum HWError: LocalizedError, Sendable {
    // Connection errors
    case deviceNotFound
    case connectionFailed(String)
    case deviceDisconnected
    case timeout
    case permissionDenied
    
    // App errors
    case appNotOpen(appName: String)
    case appVersionUnsupported(required: String, current: String)
    case wrongApp(expected: String, current: String)
    
    // User interaction
    case userRejected
    case pinRequired
    case pinIncorrect
    case passphraseRequired
    case deviceLocked
    
    // Protocol errors
    case invalidResponse(String)
    case communicationError(String)
    case apduError(statusWord: UInt16)
    
    // Transaction errors
    case unsupportedChain(String)
    case unsupportedOperation(String)
    case invalidTransaction(String)
    case invalidPath(String)
    
    // General
    case notImplemented(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Hardware wallet not found. Please connect your device."
        case .connectionFailed(let reason):
            return "Failed to connect: \(reason)"
        case .deviceDisconnected:
            return "Hardware wallet disconnected unexpectedly."
        case .timeout:
            return "Operation timed out. Please try again."
        case .permissionDenied:
            return "Permission denied. Please grant USB access."
            
        case .appNotOpen(let appName):
            return "Please open the \(appName) app on your device."
        case .appVersionUnsupported(let required, let current):
            return "App version \(current) is not supported. Please update to \(required) or later."
        case .wrongApp(let expected, let current):
            return "Wrong app open. Expected \(expected), found \(current)."
            
        case .userRejected:
            return "Operation rejected on device."
        case .pinRequired:
            return "Please enter your PIN on the device."
        case .pinIncorrect:
            return "Incorrect PIN entered."
        case .passphraseRequired:
            return "Please enter your passphrase."
        case .deviceLocked:
            return "Device is locked. Please unlock it."
            
        case .invalidResponse(let details):
            return "Invalid response from device: \(details)"
        case .communicationError(let details):
            return "Communication error: \(details)"
        case .apduError(let sw):
            return "Device error: 0x\(String(sw, radix: 16, uppercase: true))"
            
        case .unsupportedChain(let chain):
            return "Unsupported blockchain: \(chain)"
        case .unsupportedOperation(let op):
            return "Unsupported operation: \(op)"
        case .invalidTransaction(let reason):
            return "Invalid transaction: \(reason)"
        case .invalidPath(let path):
            return "Invalid derivation path: \(path)"
            
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .unknown(let message):
            return message
        }
    }
    
    /// Parse Ledger APDU status word to error
    public static func fromStatusWord(_ sw: UInt16) -> HWError? {
        switch sw {
        case 0x9000:
            return nil // Success
        case 0x6985:
            return .userRejected
        case 0x6982:
            return .pinRequired
        case 0x6700:
            return .invalidTransaction("Incorrect data length")
        case 0x6A80:
            return .invalidTransaction("Invalid data")
        case 0x6A82:
            return .appNotOpen(appName: "required")
        case 0x6B00:
            return .invalidPath("Incorrect P1/P2")
        case 0x6D00:
            return .unsupportedOperation("INS not supported")
        case 0x6E00:
            return .wrongApp(expected: "correct", current: "wrong")
        case 0x6F00:
            return .unknown("Technical error")
        default:
            return .apduError(statusWord: sw)
        }
    }
}

// MARK: - Device Discovery Delegate

/// Delegate for hardware wallet discovery events
public protocol HardwareWalletDiscoveryDelegate: AnyObject {
    /// Called when a device is discovered
    func didDiscoverDevice(_ device: DiscoveredDevice)
    
    /// Called when a device is removed
    func didRemoveDevice(_ device: DiscoveredDevice)
    
    /// Called when discovery encounters an error
    func didEncounterError(_ error: HWError)
}

/// Discovered hardware wallet device
public struct DiscoveredDevice: Identifiable, Sendable {
    public let id: String
    public let deviceType: HardwareDeviceType
    public let connectionType: ConnectionType
    public let name: String?
    
    /// Connection method
    public enum ConnectionType: String, Sendable {
        case usb
        case bluetooth
    }
    
    public init(id: String, deviceType: HardwareDeviceType, connectionType: ConnectionType, name: String? = nil) {
        self.id = id
        self.deviceType = deviceType
        self.connectionType = connectionType
        self.name = name
    }
}

// MARK: - Hardware Wallet Session

/// Active session with a hardware wallet
public protocol HardwareWalletSession: AnyObject {
    /// The connected device
    var device: HardwareWallet { get }
    
    /// Session ID
    var sessionId: String { get }
    
    /// Current app open on device (if known)
    var currentApp: String? { get async }
    
    /// Close the session
    func close() async throws
    
    /// Open a specific app on the device
    func openApp(_ appName: String) async throws
    
    /// Get device info
    func getDeviceInfo() async throws -> DeviceInfo
}

/// Device information
public struct DeviceInfo: Sendable {
    public let manufacturer: String
    public let model: String
    public let firmwareVersion: String
    public let serialNumber: String?
    public let mcuVersion: String?
    public let seVersion: String?
    
    public init(manufacturer: String, model: String, firmwareVersion: String, serialNumber: String? = nil, mcuVersion: String? = nil, seVersion: String? = nil) {
        self.manufacturer = manufacturer
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.serialNumber = serialNumber
        self.mcuVersion = mcuVersion
        self.seVersion = seVersion
    }
}
