//
//  LedgerWallet.swift
//  Hawala
//
//  Main Ledger Hardware Wallet Implementation
//
//  Implements the HardwareWallet protocol for Ledger devices,
//  routing operations to the appropriate chain-specific app.
//

import Foundation

// MARK: - Ledger Wallet

/// Main Ledger hardware wallet implementation
public actor LedgerWallet: HardwareWallet {
    // Device info
    private let deviceInfo: DiscoveredDevice
    private let transport: LedgerTransportProtocol
    
    // State
    private var _isConnected = false
    private var _currentApp: String?
    private var _firmwareVersion: String?
    private var _deviceStatus: HardwareDeviceStatus = .disconnected
    
    // Chain-specific apps
    private lazy var bitcoinApp = LedgerBitcoinApp(transport: transport)
    private lazy var ethereumApp = LedgerEthereumApp(transport: transport)
    private lazy var solanaApp = LedgerSolanaApp(transport: transport)
    private lazy var cosmosApp = LedgerCosmosApp(transport: transport)
    
    // MARK: - HardwareWallet Protocol
    
    public nonisolated var name: String {
        deviceInfo.name ?? deviceInfo.deviceType.displayName
    }
    
    public nonisolated var deviceType: HardwareDeviceType {
        deviceInfo.deviceType
    }
    
    public var connectionStatus: HardwareDeviceStatus {
        _deviceStatus
    }
    
    public var isConnected: Bool {
        _isConnected
    }
    
    public var supportedChains: [SupportedChain] {
        [.bitcoin, .ethereum, .solana, .cosmos, .polygon, .arbitrum, .optimism, .bsc]
    }
    
    public var firmwareVersion: String? {
        _firmwareVersion
    }
    
    // MARK: - Initialization
    
    public init(deviceInfo: DiscoveredDevice) {
        self.deviceInfo = deviceInfo
        self.transport = LedgerTransportFactory.create(for: deviceInfo)
    }
    
    // MARK: - Connection
    
    public func connect() async throws {
        _deviceStatus = .connecting
        
        do {
            try await transport.open()
            _isConnected = true
            
            // Get device info
            let info = try await getDeviceInfo()
            _firmwareVersion = info.firmwareVersion
            _currentApp = try? await getCurrentAppName()
            
            _deviceStatus = _currentApp != nil ? .ready : .requiresAppOpen(appName: "any")
        } catch {
            _deviceStatus = .error(.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    public func disconnect() async throws {
        try await transport.close()
        _isConnected = false
        _currentApp = nil
        _deviceStatus = .disconnected
    }
    
    // MARK: - Public Key
    
    public func getPublicKey(path: DerivationPath, curve: EllipticCurveType) async throws -> PublicKeyResult {
        // Determine which app to use based on the curve and path
        let app = try getAppForPath(path)
        
        switch app {
        case .bitcoin:
            return try await bitcoinApp.getPublicKey(path: path)
        case .ethereum:
            return try await ethereumApp.getPublicKey(path: path)
        case .solana:
            return try await solanaApp.getPublicKey(path: path)
        case .cosmos:
            return try await cosmosApp.getPublicKey(path: path)
        default:
            throw HWError.unsupportedChain(app.rawValue)
        }
    }
    
    // MARK: - Address
    
    public func getAddress(path: DerivationPath, chain: SupportedChain, display: Bool) async throws -> AddressResult {
        try await ensureAppOpen(for: chain)
        
        switch chain {
        case .bitcoin:
            return try await bitcoinApp.getAddress(path: path, display: display)
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc:
            return try await ethereumApp.getAddress(path: path, display: display)
        case .solana:
            return try await solanaApp.getAddress(path: path, display: display)
        case .cosmos:
            return try await cosmosApp.getAddress(path: path, display: display)
        default:
            throw HWError.unsupportedChain(chain.rawValue)
        }
    }
    
    // MARK: - Transaction Signing
    
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction, chain: SupportedChain) async throws -> SignatureResult {
        try await ensureAppOpen(for: chain)
        
        switch chain {
        case .bitcoin:
            return try await bitcoinApp.signTransaction(path: path, transaction: transaction)
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc:
            return try await ethereumApp.signTransaction(path: path, transaction: transaction, chainId: chain.getChainId())
        case .solana:
            return try await solanaApp.signTransaction(path: path, transaction: transaction)
        case .cosmos:
            return try await cosmosApp.signTransaction(path: path, transaction: transaction)
        default:
            throw HWError.unsupportedChain(chain.rawValue)
        }
    }
    
    // MARK: - Message Signing
    
    public func signMessage(path: DerivationPath, message: Data, chain: SupportedChain) async throws -> SignatureResult {
        try await ensureAppOpen(for: chain)
        
        switch chain {
        case .bitcoin:
            return try await bitcoinApp.signMessage(path: path, message: message)
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc:
            return try await ethereumApp.signMessage(path: path, message: message)
        case .solana:
            return try await solanaApp.signMessage(path: path, message: message)
        case .cosmos:
            throw HWError.unsupportedOperation("Cosmos message signing not supported on Ledger")
        default:
            throw HWError.unsupportedChain(chain.rawValue)
        }
    }
    
    // MARK: - EIP-712 Typed Data
    
    public func signTypedData(path: DerivationPath, domainHash: Data, messageHash: Data) async throws -> SignatureResult {
        try await ensureAppOpen(for: .ethereum)
        return try await ethereumApp.signTypedData(path: path, domainHash: domainHash, messageHash: messageHash)
    }
    
    // MARK: - App Management
    
    /// Get the current app name running on the device
    public func getCurrentAppName() async throws -> String {
        let apdu = LedgerAPDUCommand.build(cla: 0xB0, ins: 0x01, p1: 0, p2: 0)
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse app info response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response format: format (1) + name length (1) + name + version length (1) + version + flags length (1) + flags
        guard parsed.data.count >= 2 else {
            throw HWError.invalidResponse("App info response too short")
        }
        
        let nameLength = Int(parsed.data[1])
        guard parsed.data.count >= 2 + nameLength else {
            throw HWError.invalidResponse("Invalid name length in app info")
        }
        
        let nameData = parsed.data[2..<(2 + nameLength)]
        guard let name = String(data: nameData, encoding: .ascii) else {
            throw HWError.invalidResponse("Failed to decode app name")
        }
        
        _currentApp = name
        return name
    }
    
    /// Open a specific app on the device
    public func openApp(_ appName: String) async throws {
        let nameData = appName.data(using: .ascii) ?? Data()
        let apdu = LedgerAPDUCommand.build(cla: 0xE0, ins: 0xD8, p1: 0, p2: 0, data: nameData)
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse open app response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Wait for app to open
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Verify app is open
        let currentApp = try await getCurrentAppName()
        guard currentApp.lowercased() == appName.lowercased() else {
            throw HWError.wrongApp(expected: appName, current: currentApp)
        }
        
        _currentApp = currentApp
        _deviceStatus = .ready
    }
    
    /// Close the current app
    public func closeApp() async throws {
        let apdu = LedgerAPDUCommand.build(cla: 0xB0, ins: 0xA7, p1: 0, p2: 0)
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse close app response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        _currentApp = nil
        _deviceStatus = .requiresAppOpen(appName: "any")
    }
    
    // MARK: - Device Info
    
    /// Get device information
    public func getDeviceInfo() async throws -> DeviceInfo {
        // This APDU works on the dashboard
        let apdu = LedgerAPDUCommand.build(cla: 0xE0, ins: 0x01, p1: 0, p2: 0)
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse device info response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Parse firmware version from response
        let data = parsed.data
        var version = "unknown"
        var seVersion: String?
        var mcuVersion: String?
        
        if data.count >= 4 {
            // Target ID (4 bytes)
            // Version string follows
            if data.count > 4 {
                let versionData = data.dropFirst(4)
                if let idx = versionData.firstIndex(of: 0) {
                    if let v = String(data: versionData[..<idx], encoding: .ascii) {
                        version = v
                    }
                }
            }
        }
        
        return DeviceInfo(
            manufacturer: "Ledger",
            model: deviceType.displayName,
            firmwareVersion: version,
            serialNumber: nil,
            mcuVersion: mcuVersion,
            seVersion: seVersion
        )
    }
    
    // MARK: - Private Helpers
    
    /// Get the appropriate app for a derivation path
    private func getAppForPath(_ path: DerivationPath) throws -> SupportedChain {
        guard let purpose = path.components.first else {
            throw HWError.invalidPath("Empty derivation path")
        }
        
        guard path.components.count >= 2 else {
            throw HWError.invalidPath("Path too short")
        }
        
        let coinType = path.components[1].index
        
        switch coinType {
        case 0: return .bitcoin
        case 60: return .ethereum
        case 501: return .solana
        case 118: return .cosmos
        case 9000: return .avalanche
        default:
            throw HWError.unsupportedChain("Unknown coin type: \(coinType)")
        }
    }
    
    /// Ensure the correct app is open for the chain
    private func ensureAppOpen(for chain: SupportedChain) async throws {
        let requiredApp = chain.ledgerAppName
        
        if let currentApp = _currentApp, currentApp.lowercased() == requiredApp.lowercased() {
            return // Already open
        }
        
        // Try to get current app
        if let currentApp = try? await getCurrentAppName() {
            if currentApp.lowercased() == requiredApp.lowercased() {
                return
            }
            
            // Close current app first
            try? await closeApp()
        }
        
        // Open the required app
        throw HWError.appNotOpen(appName: requiredApp)
    }
}

// MARK: - Chain Extensions

extension SupportedChain {
    /// Get EVM chain ID
    func getChainId() -> UInt64 {
        switch self {
        case .ethereum: return 1
        case .polygon: return 137
        case .arbitrum: return 42161
        case .optimism: return 10
        case .bsc: return 56
        case .avalanche: return 43114
        default: return 1
        }
    }
}
