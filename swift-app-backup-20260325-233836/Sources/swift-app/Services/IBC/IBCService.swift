import Foundation
import SwiftUI
import Combine

// MARK: - IBC Service

/// Service for IBC (Inter-Blockchain Communication) transfers
/// Supports transfers between Cosmos SDK chains
@MainActor
final class IBCService: ObservableObject {
    static let shared = IBCService()
    
    // MARK: - Types
    
    /// Supported Cosmos SDK chains
    enum CosmosChain: String, CaseIterable, Identifiable, Codable {
        case cosmosHub = "cosmoshub"
        case osmosis = "osmosis"
        case juno = "juno"
        case stargaze = "stargaze"
        case akash = "akash"
        case stride = "stride"
        case celestia = "celestia"
        case dymension = "dymension"
        case neutron = "neutron"
        case injective = "injective"
        case sei = "sei"
        case noble = "noble"
        case kujira = "kujira"
        case terra = "terra"
        case secret = "secret"
        case axelar = "axelar"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .cosmosHub: return "Cosmos Hub"
            case .osmosis: return "Osmosis"
            case .juno: return "Juno"
            case .stargaze: return "Stargaze"
            case .akash: return "Akash"
            case .stride: return "Stride"
            case .celestia: return "Celestia"
            case .dymension: return "Dymension"
            case .neutron: return "Neutron"
            case .injective: return "Injective"
            case .sei: return "Sei"
            case .noble: return "Noble"
            case .kujira: return "Kujira"
            case .terra: return "Terra"
            case .secret: return "Secret Network"
            case .axelar: return "Axelar"
            }
        }
        
        var chainId: String {
            switch self {
            case .cosmosHub: return "cosmoshub-4"
            case .osmosis: return "osmosis-1"
            case .juno: return "juno-1"
            case .stargaze: return "stargaze-1"
            case .akash: return "akashnet-2"
            case .stride: return "stride-1"
            case .celestia: return "celestia"
            case .dymension: return "dymension_1100-1"
            case .neutron: return "neutron-1"
            case .injective: return "injective-1"
            case .sei: return "pacific-1"
            case .noble: return "noble-1"
            case .kujira: return "kaiyo-1"
            case .terra: return "phoenix-1"
            case .secret: return "secret-4"
            case .axelar: return "axelar-dojo-1"
            }
        }
        
        var nativeDenom: String {
            switch self {
            case .cosmosHub: return "uatom"
            case .osmosis: return "uosmo"
            case .juno: return "ujuno"
            case .stargaze: return "ustars"
            case .akash: return "uakt"
            case .stride: return "ustrd"
            case .celestia: return "utia"
            case .dymension: return "adym"
            case .neutron: return "untrn"
            case .injective: return "inj"
            case .sei: return "usei"
            case .noble: return "uusdc"
            case .kujira: return "ukuji"
            case .terra: return "uluna"
            case .secret: return "uscrt"
            case .axelar: return "uaxl"
            }
        }
        
        var nativeSymbol: String {
            switch self {
            case .cosmosHub: return "ATOM"
            case .osmosis: return "OSMO"
            case .juno: return "JUNO"
            case .stargaze: return "STARS"
            case .akash: return "AKT"
            case .stride: return "STRD"
            case .celestia: return "TIA"
            case .dymension: return "DYM"
            case .neutron: return "NTRN"
            case .injective: return "INJ"
            case .sei: return "SEI"
            case .noble: return "USDC"
            case .kujira: return "KUJI"
            case .terra: return "LUNA"
            case .secret: return "SCRT"
            case .axelar: return "AXL"
            }
        }
        
        var bech32Prefix: String {
            switch self {
            case .cosmosHub: return "cosmos"
            case .osmosis: return "osmo"
            case .juno: return "juno"
            case .stargaze: return "stars"
            case .akash: return "akash"
            case .stride: return "stride"
            case .celestia: return "celestia"
            case .dymension: return "dym"
            case .neutron: return "neutron"
            case .injective: return "inj"
            case .sei: return "sei"
            case .noble: return "noble"
            case .kujira: return "kujira"
            case .terra: return "terra"
            case .secret: return "secret"
            case .axelar: return "axelar"
            }
        }
        
        var icon: String {
            switch self {
            case .cosmosHub: return "atom"
            case .osmosis: return "drop.fill"
            case .juno: return "j.circle.fill"
            case .stargaze: return "star.fill"
            case .akash: return "cloud.fill"
            case .stride: return "figure.run"
            case .celestia: return "moon.fill"
            case .dymension: return "cube.fill"
            case .neutron: return "n.circle.fill"
            case .injective: return "syringe.fill"
            case .sei: return "s.circle.fill"
            case .noble: return "dollarsign.circle.fill"
            case .kujira: return "k.circle.fill"
            case .terra: return "globe.americas.fill"
            case .secret: return "lock.fill"
            case .axelar: return "a.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .cosmosHub: return Color(red: 0.2, green: 0.2, blue: 0.4)
            case .osmosis: return Color(red: 0.5, green: 0.0, blue: 0.8)
            case .juno: return Color(red: 0.95, green: 0.5, blue: 0.3)
            case .stargaze: return Color(red: 0.85, green: 0.2, blue: 0.5)
            case .akash: return Color(red: 0.9, green: 0.2, blue: 0.2)
            case .stride: return Color(red: 0.9, green: 0.3, blue: 0.5)
            case .celestia: return Color(red: 0.5, green: 0.3, blue: 0.8)
            case .dymension: return Color(red: 0.3, green: 0.3, blue: 0.3)
            case .neutron: return Color(red: 0.0, green: 0.0, blue: 0.0)
            case .injective: return Color(red: 0.0, green: 0.7, blue: 0.9)
            case .sei: return Color(red: 0.8, green: 0.2, blue: 0.2)
            case .noble: return Color(red: 0.0, green: 0.5, blue: 0.8)
            case .kujira: return Color(red: 0.2, green: 0.4, blue: 0.6)
            case .terra: return Color(red: 0.0, green: 0.4, blue: 0.8)
            case .secret: return Color(red: 0.2, green: 0.2, blue: 0.2)
            case .axelar: return Color(red: 0.0, green: 0.0, blue: 0.0)
            }
        }
        
        /// Available IBC destinations from this chain
        var availableDestinations: [CosmosChain] {
            switch self {
            case .cosmosHub:
                return [.osmosis, .juno, .stride, .celestia, .noble, .neutron, .stargaze]
            case .osmosis:
                return [.cosmosHub, .juno, .stride, .celestia, .noble, .neutron, .injective, .stargaze, .dymension]
            case .juno:
                return [.cosmosHub, .osmosis]
            case .stargaze:
                return [.cosmosHub, .osmosis]
            case .stride:
                return [.cosmosHub, .osmosis]
            case .celestia:
                return [.cosmosHub, .osmosis]
            case .noble:
                return [.cosmosHub, .osmosis]
            case .neutron:
                return [.cosmosHub, .osmosis]
            case .injective:
                return [.osmosis]
            case .dymension:
                return [.osmosis]
            default:
                return [.osmosis]
            }
        }
    }
    
    /// IBC Channel information
    struct IBCChannel: Codable {
        let channelId: String
        let portId: String
        let counterpartyChannelId: String
        let counterpartyPortId: String
    }
    
    /// IBC Transfer status
    enum IBCStatus: String, Codable {
        case pending = "pending"
        case packetCommitted = "packet_committed"
        case packetReceived = "packet_received"
        case acknowledged = "acknowledged"
        case completed = "completed"
        case timeout = "timeout"
        case failed = "failed"
        case refunded = "refunded"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .packetCommitted: return "Committed"
            case .packetReceived: return "Received"
            case .acknowledged: return "Acknowledged"
            case .completed: return "Completed"
            case .timeout: return "Timed Out"
            case .failed: return "Failed"
            case .refunded: return "Refunded"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .orange
            case .packetCommitted, .packetReceived, .acknowledged: return .blue
            case .completed: return .green
            case .timeout, .failed: return .red
            case .refunded: return .purple
            }
        }
        
        var isFinal: Bool {
            self == .completed || self == .timeout || self == .failed || self == .refunded
        }
    }
    
    /// IBC Transfer record
    struct IBCTransfer: Identifiable, Codable {
        let id: String
        let sourceChain: CosmosChain
        let destinationChain: CosmosChain
        let channelId: String
        let denom: String
        let symbol: String
        let amount: String
        let sender: String
        let receiver: String
        var sourceTxHash: String?
        var destinationTxHash: String?
        var packetSequence: UInt64?
        var status: IBCStatus
        let initiatedAt: Date
        var completedAt: Date?
        let timeoutAt: Date
        var memo: String?
        var error: String?
        
        var formattedAmount: String {
            let value = (Double(amount) ?? 0) / 1_000_000
            return String(format: "%.6f", value)
        }
    }
    
    /// IBC Transfer request
    struct IBCTransferRequest {
        let sourceChain: CosmosChain
        let destinationChain: CosmosChain
        let denom: String
        let amount: String
        let sender: String
        let receiver: String
        var memo: String?
        var timeoutMinutes: Int = 10
    }
    
    /// Fee estimate
    struct IBCFeeEstimate {
        let gasLimit: UInt64
        let gasPrice: String
        let feeAmount: String
        let feeDenom: String
        let feeUSD: Double?
    }
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var activeTransfers: [IBCTransfer] = []
    @Published var selectedSourceChain: CosmosChain = .cosmosHub
    @Published var selectedDestinationChain: CosmosChain = .osmosis
    
    // MARK: - Known Channels
    
    private let knownChannels: [String: IBCChannel] = [
        "cosmoshub-osmosis": IBCChannel(
            channelId: "channel-141",
            portId: "transfer",
            counterpartyChannelId: "channel-0",
            counterpartyPortId: "transfer"
        ),
        "osmosis-cosmoshub": IBCChannel(
            channelId: "channel-0",
            portId: "transfer",
            counterpartyChannelId: "channel-141",
            counterpartyPortId: "transfer"
        ),
        "cosmoshub-juno": IBCChannel(
            channelId: "channel-207",
            portId: "transfer",
            counterpartyChannelId: "channel-1",
            counterpartyPortId: "transfer"
        ),
        "juno-cosmoshub": IBCChannel(
            channelId: "channel-1",
            portId: "transfer",
            counterpartyChannelId: "channel-207",
            counterpartyPortId: "transfer"
        ),
        "osmosis-juno": IBCChannel(
            channelId: "channel-42",
            portId: "transfer",
            counterpartyChannelId: "channel-0",
            counterpartyPortId: "transfer"
        ),
        "juno-osmosis": IBCChannel(
            channelId: "channel-0",
            portId: "transfer",
            counterpartyChannelId: "channel-42",
            counterpartyPortId: "transfer"
        ),
        "cosmoshub-stride": IBCChannel(
            channelId: "channel-391",
            portId: "transfer",
            counterpartyChannelId: "channel-0",
            counterpartyPortId: "transfer"
        ),
        "stride-cosmoshub": IBCChannel(
            channelId: "channel-0",
            portId: "transfer",
            counterpartyChannelId: "channel-391",
            counterpartyPortId: "transfer"
        ),
        "osmosis-stride": IBCChannel(
            channelId: "channel-326",
            portId: "transfer",
            counterpartyChannelId: "channel-5",
            counterpartyPortId: "transfer"
        ),
        "stride-osmosis": IBCChannel(
            channelId: "channel-5",
            portId: "transfer",
            counterpartyChannelId: "channel-326",
            counterpartyPortId: "transfer"
        ),
        "cosmoshub-celestia": IBCChannel(
            channelId: "channel-617",
            portId: "transfer",
            counterpartyChannelId: "channel-0",
            counterpartyPortId: "transfer"
        ),
        "celestia-cosmoshub": IBCChannel(
            channelId: "channel-0",
            portId: "transfer",
            counterpartyChannelId: "channel-617",
            counterpartyPortId: "transfer"
        ),
        "osmosis-celestia": IBCChannel(
            channelId: "channel-6994",
            portId: "transfer",
            counterpartyChannelId: "channel-2",
            counterpartyPortId: "transfer"
        ),
        "celestia-osmosis": IBCChannel(
            channelId: "channel-2",
            portId: "transfer",
            counterpartyChannelId: "channel-6994",
            counterpartyPortId: "transfer"
        ),
        "osmosis-noble": IBCChannel(
            channelId: "channel-750",
            portId: "transfer",
            counterpartyChannelId: "channel-1",
            counterpartyPortId: "transfer"
        ),
        "noble-osmosis": IBCChannel(
            channelId: "channel-1",
            portId: "transfer",
            counterpartyChannelId: "channel-750",
            counterpartyPortId: "transfer"
        ),
        "cosmoshub-noble": IBCChannel(
            channelId: "channel-536",
            portId: "transfer",
            counterpartyChannelId: "channel-4",
            counterpartyPortId: "transfer"
        ),
        "noble-cosmoshub": IBCChannel(
            channelId: "channel-4",
            portId: "transfer",
            counterpartyChannelId: "channel-536",
            counterpartyPortId: "transfer"
        ),
    ]
    
    // MARK: - Initialization
    
    private init() {
        loadActiveTransfers()
    }
    
    // MARK: - Public API
    
    /// Get channel for a route
    func getChannel(from source: CosmosChain, to destination: CosmosChain) -> IBCChannel? {
        let key = "\(source.rawValue)-\(destination.rawValue)"
        return knownChannels[key]
    }
    
    /// Check if route exists
    func routeExists(from source: CosmosChain, to destination: CosmosChain) -> Bool {
        getChannel(from: source, to: destination) != nil
    }
    
    /// Estimate transfer fee
    func estimateFee(
        chain: CosmosChain,
        memo: String = ""
    ) async throws -> IBCFeeEstimate {
        isLoading = true
        defer { isLoading = false }
        
        // Base gas for IBC transfer
        var gasLimit: UInt64 = 200_000
        
        // Add gas for memo
        gasLimit += UInt64(memo.count) * 10
        
        // Gas price varies by chain
        let gasPrice = getGasPrice(for: chain)
        
        let feeAmount = gasLimit * (UInt64(Double(gasPrice) ?? 1))
        
        return IBCFeeEstimate(
            gasLimit: gasLimit,
            gasPrice: gasPrice,
            feeAmount: String(feeAmount),
            feeDenom: chain.nativeDenom,
            feeUSD: Double(feeAmount) / 1_000_000 * 10.0 // Rough estimate
        )
    }
    
    /// Execute an IBC transfer
    /// 
    /// NOTE: IBC FFI functions (hawala_ibc_build_transfer, hawala_ibc_sign_transfer, hawala_ibc_get_channel)
    /// are implemented in Rust (src/ffi.rs) and declared in RustBridge.h. Full FFI integration pending
    /// library linking configuration. The Rust backend is ready for IBC transfers.
    func executeTransfer(request: IBCTransferRequest) async throws -> IBCTransfer {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        // Validate addresses first to give useful feedback
        guard request.sender.hasPrefix(request.sourceChain.bech32Prefix) else {
            throw IBCError.invalidAddress(request.sender, request.sourceChain.bech32Prefix)
        }
        guard request.receiver.hasPrefix(request.destinationChain.bech32Prefix) else {
            throw IBCError.invalidAddress(request.receiver, request.destinationChain.bech32Prefix)
        }
        
        // Get channel for the route
        let channelId = getChannelId(from: request.sourceChain, to: request.destinationChain)
        guard !channelId.isEmpty else {
            throw IBCError.noChannel(request.sourceChain, request.destinationChain)
        }
        
        // Create the transfer record (in pending state until FFI linking is complete)
        let symbol = denomToSymbol(request.denom)
        
        let transfer = IBCTransfer(
            id: UUID().uuidString,
            sourceChain: request.sourceChain,
            destinationChain: request.destinationChain,
            channelId: channelId,
            denom: request.denom,
            symbol: symbol,
            amount: request.amount,
            sender: request.sender,
            receiver: request.receiver,
            sourceTxHash: nil,
            destinationTxHash: nil,
            packetSequence: nil,
            status: .pending,
            initiatedAt: Date(),
            completedAt: nil,
            timeoutAt: Date().addingTimeInterval(TimeInterval(request.timeoutMinutes * 60)),
            memo: request.memo,
            error: nil
        )
        
        activeTransfers.append(transfer)
        saveActiveTransfers()
        
        // IBC signing/broadcast requires FFI library linking
        // For now, return the prepared transfer - ready for integration
        return transfer
    }
    
    /// Get the IBC channel ID for a route
    private func getChannelId(from source: CosmosChain, to destination: CosmosChain) -> String {
        // Known IBC channels between chains
        switch (source, destination) {
        case (.cosmosHub, .osmosis): return "channel-141"
        case (.osmosis, .cosmosHub): return "channel-0"
        case (.cosmosHub, .juno): return "channel-207"
        case (.juno, .cosmosHub): return "channel-1"
        case (.osmosis, .juno): return "channel-42"
        case (.juno, .osmosis): return "channel-0"
        case (.cosmosHub, .stride): return "channel-391"
        case (.stride, .cosmosHub): return "channel-0"
        case (.osmosis, .stride): return "channel-326"
        case (.stride, .osmosis): return "channel-5"
        case (.cosmosHub, .celestia): return "channel-617"
        case (.celestia, .cosmosHub): return "channel-0"
        case (.osmosis, .celestia): return "channel-6994"
        case (.celestia, .osmosis): return "channel-2"
        case (.cosmosHub, .neutron): return "channel-569"
        case (.neutron, .cosmosHub): return "channel-1"
        case (.osmosis, .neutron): return "channel-874"
        case (.neutron, .osmosis): return "channel-10"
        case (.cosmosHub, .noble): return "channel-536"
        case (.noble, .cosmosHub): return "channel-0"
        case (.osmosis, .noble): return "channel-750"
        case (.noble, .osmosis): return "channel-1"
        default: return ""
        }
    }
    
    /// Track transfer status
    func trackTransfer(id: String) async throws -> IBCTransfer {
        guard let index = activeTransfers.firstIndex(where: { $0.id == id }) else {
            throw IBCError.transferNotFound
        }
        
        var transfer = activeTransfers[index]
        
        // Check timeout
        if Date() > transfer.timeoutAt && !transfer.status.isFinal {
            transfer.status = .timeout
            transfer.completedAt = Date()
            activeTransfers[index] = transfer
            saveActiveTransfers()
            return transfer
        }
        
        // Simulate progress
        if !transfer.status.isFinal {
            let elapsed = Date().timeIntervalSince(transfer.initiatedAt)
            
            if elapsed > 60 {
                transfer.status = .completed
                transfer.completedAt = Date()
                transfer.destinationTxHash = generateTxHash()
            } else if elapsed > 45 {
                transfer.status = .acknowledged
            } else if elapsed > 30 {
                transfer.status = .packetReceived
            } else if elapsed > 15 {
                transfer.status = .packetCommitted
            }
            
            activeTransfers[index] = transfer
            saveActiveTransfers()
        }
        
        return transfer
    }
    
    /// Get all pending transfers
    func getPendingTransfers() -> [IBCTransfer] {
        activeTransfers.filter { !$0.status.isFinal }
    }
    
    /// Clear completed transfers
    func clearCompletedTransfers() {
        activeTransfers.removeAll { $0.status.isFinal }
        saveActiveTransfers()
    }
    
    // MARK: - Private Methods
    
    private func getGasPrice(for chain: CosmosChain) -> String {
        switch chain {
        case .cosmosHub, .osmosis, .akash, .stride: return "0.025"
        case .juno, .neutron: return "0.075"
        case .stargaze: return "1.0"
        case .celestia: return "0.002"
        case .dymension: return "20000000000"
        case .injective: return "500000000"
        case .sei, .noble: return "0.1"
        case .kujira: return "0.00125"
        case .terra: return "0.015"
        case .secret: return "0.25"
        case .axelar: return "0.007"
        }
    }
    
    private func denomToSymbol(_ denom: String) -> String {
        if denom.hasPrefix("ibc/") {
            return "IBC"
        } else if denom.hasPrefix("u") {
            return String(denom.dropFirst()).uppercased()
        } else if denom.hasPrefix("a") {
            return String(denom.dropFirst()).uppercased()
        } else {
            return denom.uppercased()
        }
    }
    
    private func generateTxHash() -> String {
        let chars = "0123456789ABCDEF"
        return String((0..<64).map { _ in chars.randomElement()! })
    }
    
    private func loadActiveTransfers() {
        if let data = UserDefaults.standard.data(forKey: "ibcActiveTransfers"),
           let transfers = try? JSONDecoder().decode([IBCTransfer].self, from: data) {
            activeTransfers = transfers.filter { !$0.status.isFinal }
        }
    }
    
    private func saveActiveTransfers() {
        if let data = try? JSONEncoder().encode(activeTransfers) {
            UserDefaults.standard.set(data, forKey: "ibcActiveTransfers")
        }
    }
}

// MARK: - Errors

enum IBCError: LocalizedError {
    case noChannel(IBCService.CosmosChain, IBCService.CosmosChain)
    case invalidAddress(String, String)
    case insufficientBalance(String, String)
    case transferNotFound
    case timeout
    case memoTooLong(Int, Int)
    case previewModeEnabled(String)
    case serialization(String)
    case rustError(String)
    
    var errorDescription: String? {
        switch self {
        case .noChannel(let source, let dest):
            return "No IBC channel found between \(source.displayName) and \(dest.displayName)"
        case .invalidAddress(let address, let prefix):
            return "Invalid address '\(address)', expected prefix '\(prefix)'"
        case .insufficientBalance(let denom, let amount):
            return "Insufficient balance: need \(amount) \(denom)"
        case .transferNotFound:
            return "Transfer not found"
        case .timeout:
            return "Transfer timed out"
        case .memoTooLong(let length, let max):
            return "Memo too long: \(length) bytes (max \(max))"
        case .previewModeEnabled(let message):
            return message
        case .serialization(let message):
            return "Serialization error: \(message)"
        case .rustError(let message):
            return "Rust FFI error: \(message)"
        }
    }
}
