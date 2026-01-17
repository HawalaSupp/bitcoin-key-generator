//
//  HawalaBridge.swift
//  Hawala
//
//  Unified Rust FFI Bridge - Phase 7 Complete Rewiring
//  ALL backend logic goes through this bridge to Rust
//

import Foundation
import RustBridge

// MARK: - Core Types

/// Supported blockchain networks (mirrors Rust Chain enum)
public enum HawalaChain: String, Codable, CaseIterable, Sendable {
    case bitcoin = "bitcoin"
    case bitcoinTestnet = "bitcoin_testnet"
    case litecoin = "litecoin"
    case ethereum = "ethereum"
    case ethereumSepolia = "ethereum_sepolia"
    case bnb = "bnb"
    case polygon = "polygon"
    case arbitrum = "arbitrum"
    case optimism = "optimism"
    case base = "base"
    case avalanche = "avalanche"
    case solana = "solana"
    case solanaDevnet = "solana_devnet"
    case xrp = "xrp"
    case xrpTestnet = "xrp_testnet"
    case monero = "monero"
    
    public var isEVM: Bool {
        switch self {
        case .ethereum, .ethereumSepolia, .bnb, .polygon, .arbitrum, .optimism, .base, .avalanche:
            return true
        default:
            return false
        }
    }
    
    public var isUTXO: Bool {
        switch self {
        case .bitcoin, .bitcoinTestnet, .litecoin:
            return true
        default:
            return false
        }
    }
    
    public var symbol: String {
        switch self {
        case .bitcoin, .bitcoinTestnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereum, .ethereumSepolia: return "ETH"
        case .bnb: return "BNB"
        case .polygon: return "MATIC"
        case .arbitrum, .optimism, .base: return "ETH"
        case .avalanche: return "AVAX"
        case .solana, .solanaDevnet: return "SOL"
        case .xrp, .xrpTestnet: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    public var chainId: UInt64? {
        switch self {
        case .ethereum: return 1
        case .ethereumSepolia: return 11155111
        case .bnb: return 56
        case .polygon: return 137
        case .arbitrum: return 42161
        case .optimism: return 10
        case .base: return 8453
        case .avalanche: return 43114
        default: return nil
        }
    }
    
    public var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .litecoin: return "Litecoin"
        case .ethereum: return "Ethereum"
        case .ethereumSepolia: return "Sepolia Testnet"
        case .bnb: return "BNB Chain"
        case .polygon: return "Polygon"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .base: return "Base"
        case .avalanche: return "Avalanche"
        case .solana: return "Solana"
        case .solanaDevnet: return "Solana Devnet"
        case .xrp: return "XRP"
        case .xrpTestnet: return "XRP Testnet"
        case .monero: return "Monero"
        }
    }
}

/// Error from Rust backend
public struct HawalaError: Codable, Error, Sendable {
    public let code: String
    public let message: String
    public let details: String?
    
    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// Standard API response wrapper
struct HawalaResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: HawalaError?
}

// MARK: - Wallet Types

public struct HawalaBitcoinKeys: Codable, Sendable {
    public let privateHex: String
    public let privateWif: String
    public let publicCompressedHex: String
    public let address: String
    public let taprootAddress: String?
    public let xOnlyPubkey: String?
    
    enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
        case taprootAddress = "taproot_address"
        case xOnlyPubkey = "x_only_pubkey"
    }
}

public struct HawalaEthereumKeys: Codable, Sendable {
    public let privateHex: String
    public let publicUncompressedHex: String
    public let address: String
    
    enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

public struct HawalaSolanaKeys: Codable, Sendable {
    public let privateSeedHex: String
    public let privateKeyBase58: String
    public let publicKeyBase58: String
    
    enum CodingKeys: String, CodingKey {
        case privateSeedHex = "private_seed_hex"
        case privateKeyBase58 = "private_key_base58"
        case publicKeyBase58 = "public_key_base58"
    }
}

public struct HawalaXrpKeys: Codable, Sendable {
    public let privateHex: String
    public let publicCompressedHex: String
    public let classicAddress: String
    
    enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicCompressedHex = "public_compressed_hex"
        case classicAddress = "classic_address"
    }
}

public struct HawalaMoneroKeys: Codable, Sendable {
    public let privateSpendHex: String
    public let privateViewHex: String
    public let publicSpendHex: String
    public let publicViewHex: String
    public let address: String
    
    enum CodingKeys: String, CodingKey {
        case privateSpendHex = "private_spend_hex"
        case privateViewHex = "private_view_hex"
        case publicSpendHex = "public_spend_hex"
        case publicViewHex = "public_view_hex"
        case address
    }
}

public struct HawalaAllKeys: Codable, Sendable {
    public let bitcoin: HawalaBitcoinKeys
    public let bitcoinTestnet: HawalaBitcoinKeys
    public let litecoin: HawalaBitcoinKeys
    public let ethereum: HawalaEthereumKeys
    public let ethereumSepolia: HawalaEthereumKeys
    public let bnb: HawalaEthereumKeys
    public let solana: HawalaSolanaKeys
    public let xrp: HawalaXrpKeys
    public let monero: HawalaMoneroKeys
    
    enum CodingKeys: String, CodingKey {
        case bitcoin
        case bitcoinTestnet = "bitcoin_testnet"
        case litecoin
        case ethereum
        case ethereumSepolia = "ethereum_sepolia"
        case bnb
        case solana
        case xrp
        case monero
    }
}

public struct HawalaWalletResponse: Codable, Sendable {
    public let mnemonic: String
    public let keys: HawalaAllKeys
}

// MARK: - Fee Types

public struct HawalaFeeLevel: Codable, Sendable {
    public let label: String
    public let rate: UInt64
    public let estimatedMinutes: UInt32
    
    enum CodingKeys: String, CodingKey {
        case label
        case rate
        case estimatedMinutes = "estimated_minutes"
    }
}

public struct HawalaBitcoinFees: Codable, Sendable {
    public let fastest: HawalaFeeLevel
    public let fast: HawalaFeeLevel
    public let medium: HawalaFeeLevel
    public let slow: HawalaFeeLevel
    public let minimum: HawalaFeeLevel
}

public struct HawalaEvmFees: Codable, Sendable {
    public let baseFee: String
    public let priorityFeeLow: String
    public let priorityFeeMedium: String
    public let priorityFeeHigh: String
    public let gasPriceLegacy: String
    
    enum CodingKeys: String, CodingKey {
        case baseFee = "base_fee"
        case priorityFeeLow = "priority_fee_low"
        case priorityFeeMedium = "priority_fee_medium"
        case priorityFeeHigh = "priority_fee_high"
        case gasPriceLegacy = "gas_price_legacy"
    }
}

public struct HawalaFeeIntelligence: Codable, Sendable {
    public let isNetworkCongested: Bool
    public let recommendedWait: Bool
    public let confidenceHigh: UInt64
    public let confidenceLow: UInt64
    public let mempoolDepth: UInt64
    public let suggestion: String
    
    enum CodingKeys: String, CodingKey {
        case isNetworkCongested = "is_network_congested"
        case recommendedWait = "recommended_wait"
        case confidenceHigh = "confidence_high"
        case confidenceLow = "confidence_low"
        case mempoolDepth = "mempool_depth"
        case suggestion
    }
}

// MARK: - Transaction Types

public struct HawalaSignedTransaction: Codable, Sendable {
    public let rawTx: String
    public let txid: String
    public let chain: String
    
    enum CodingKeys: String, CodingKey {
        case rawTx = "raw_tx"
        case txid
        case chain
    }
}

public struct HawalaBroadcastResult: Codable, Sendable {
    public let txid: String
    public let chain: String
    public let explorerUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case txid
        case chain
        case explorerUrl = "explorer_url"
    }
}

public struct HawalaTransactionStatus: Codable, Sendable {
    public let txid: String
    public let status: String
    public let confirmations: UInt32
    public let blockHeight: UInt64?
    public let timestamp: UInt64?
    
    enum CodingKeys: String, CodingKey {
        case txid
        case status
        case confirmations
        case blockHeight = "block_height"
        case timestamp
    }
}

public struct HawalaCancellationResult: Codable, Sendable {
    public let originalTxid: String
    public let replacementTxid: String
    public let rawTx: String
    public let newFee: UInt64
    
    enum CodingKeys: String, CodingKey {
        case originalTxid = "original_txid"
        case replacementTxid = "replacement_txid"
        case rawTx = "raw_tx"
        case newFee = "new_fee"
    }
}

// MARK: - UTXO Types (Phase 6)

public enum HawalaUTXOSource: String, Codable, Sendable, CaseIterable {
    case unknown = "unknown"
    case mining = "mining"
    case exchange = "exchange"
    case personal = "personal"
    case business = "business"
    case coinjoin = "coinjoin"
    case payroll = "payroll"
}

public enum HawalaUTXOSelectionStrategy: String, Codable, Sendable, CaseIterable {
    case largestFirst = "largest_first"
    case smallestFirst = "smallest_first"
    case oldestFirst = "oldest_first"
    case newestFirst = "newest_first"
    case privacyOptimized = "privacy_optimized"
    case optimal = "optimal"
}

public struct HawalaUTXOMetadata: Codable, Sendable {
    public var label: String
    public var source: HawalaUTXOSource
    public var isFrozen: Bool
    public var note: String
    
    public init(label: String = "", source: HawalaUTXOSource = .unknown, isFrozen: Bool = false, note: String = "") {
        self.label = label
        self.source = source
        self.isFrozen = isFrozen
        self.note = note
    }
    
    enum CodingKeys: String, CodingKey {
        case label
        case source
        case isFrozen = "is_frozen"
        case note
    }
}

public struct HawalaManagedUTXO: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(txid):\(vout)" }
    public let txid: String
    public let vout: UInt32
    public let value: UInt64
    public let confirmations: UInt32
    public let scriptPubKey: String
    public let metadata: HawalaUTXOMetadata
    public let privacyScore: Int
    
    enum CodingKeys: String, CodingKey {
        case txid
        case vout
        case value
        case confirmations
        case scriptPubKey = "script_pubkey"
        case metadata
        case privacyScore = "privacy_score"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(txid)
        hasher.combine(vout)
    }
    
    public static func == (lhs: HawalaManagedUTXO, rhs: HawalaManagedUTXO) -> Bool {
        lhs.txid == rhs.txid && lhs.vout == rhs.vout
    }
}

public struct HawalaUTXOSelection: Codable, Sendable {
    public let selected: [HawalaManagedUTXO]
    public let totalValue: UInt64
    public let estimatedFee: UInt64
    public let change: UInt64
    
    enum CodingKeys: String, CodingKey {
        case selected
        case totalValue = "total_value"
        case estimatedFee = "estimated_fee"
        case change
    }
}

// MARK: - Nonce Types (Phase 6)

public enum HawalaNonceSource: String, Codable, Sendable {
    case pending = "pending"
    case latest = "latest"
    case cached = "cached"
}

public struct HawalaNonceResult: Codable, Sendable {
    public let nonce: UInt64
    public let source: HawalaNonceSource
    public let chainId: UInt64
    
    enum CodingKeys: String, CodingKey {
        case nonce
        case source
        case chainId = "chain_id"
    }
}

public struct HawalaNonceGap: Codable, Sendable {
    public let gapStart: UInt64
    public let gapEnd: UInt64
    public let count: UInt64
    
    enum CodingKeys: String, CodingKey {
        case gapStart = "gap_start"
        case gapEnd = "gap_end"
        case count
    }
}

// MARK: - History Types (Phase 5)

public struct HawalaHistoryEntry: Codable, Sendable, Identifiable {
    public var id: String { txid }
    public let txid: String
    public let chain: String
    public let direction: String
    public let amount: String
    public let fee: String?
    public let timestamp: UInt64
    public let confirmations: UInt32
    public let counterparty: String?
    public let status: String
}

// MARK: - Balance Types

public struct HawalaAddressBalance: Codable, Sendable {
    public let address: String
    public let chain: String
    public let balance: String
    public let formatted: String
}

public struct HawalaTokenBalance: Codable, Sendable {
    public let address: String
    public let tokenContract: String
    public let balance: String
    public let decimals: UInt8
    public let symbol: String?
    
    enum CodingKeys: String, CodingKey {
        case address
        case tokenContract = "token_contract"
        case balance
        case decimals
        case symbol
    }
}

// MARK: - HawalaBridge

/// Unified bridge to Rust backend - ALL backend operations go through this class
public final class HawalaBridge: @unchecked Sendable {
    public static let shared = HawalaBridge()
    
    private init() {}
    
    // MARK: - Helper Methods
    
    private func freeRustString(_ ptr: UnsafeMutablePointer<CChar>) {
        hawala_free_string(ptr)
    }
    
    private func callRustFFI<T: Codable>(_ ffiCall: () -> UnsafePointer<CChar>?) throws -> T {
        guard let outputCString = ffiCall() else {
            throw HawalaError(code: "internal", message: "FFI returned null", details: nil)
        }
        
        let json = String(cString: outputCString)
        freeRustString(UnsafeMutablePointer(mutating: outputCString))
        
        guard let data = json.data(using: .utf8) else {
            throw HawalaError(code: "encoding", message: "Invalid UTF-8 response", details: nil)
        }
        
        let response = try JSONDecoder().decode(HawalaResponse<T>.self, from: data)
        
        if let result = response.data {
            return result
        } else if let error = response.error {
            throw error
        } else {
            throw HawalaError(code: "unknown", message: "Unknown error", details: nil)
        }
    }
    
    private func callRustFFIWithInput<T: Codable>(_ input: String, _ ffiCall: (UnsafePointer<CChar>) -> UnsafePointer<CChar>?) throws -> T {
        guard let inputCString = input.cString(using: .utf8) else {
            throw HawalaError(code: "encoding", message: "Invalid input encoding", details: nil)
        }
        
        return try callRustFFI { ffiCall(inputCString) }
    }
    
    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - Wallet Operations
    
    /// Generate a new wallet with mnemonic and keys
    public func generateWallet() throws -> HawalaWalletResponse {
        try callRustFFI { hawala_generate_wallet() }
    }
    
    /// Restore wallet from mnemonic
    public func restoreWallet(mnemonic: String) throws -> HawalaAllKeys {
        struct RestoreRequest: Encodable { let mnemonic: String }
        let input = try encodeJSON(RestoreRequest(mnemonic: mnemonic))
        return try callRustFFIWithInput(input) { hawala_restore_wallet($0) }
    }
    
    /// Validate a mnemonic phrase
    public func validateMnemonic(_ mnemonic: String) -> Bool {
        struct ValidateRequest: Encodable { let mnemonic: String }
        struct ValidateResponse: Codable { let valid: Bool }
        
        guard let input = try? encodeJSON(ValidateRequest(mnemonic: mnemonic)),
              let result: ValidateResponse = try? callRustFFIWithInput(input, { hawala_validate_mnemonic($0) }) else {
            return false
        }
        return result.valid
    }
    
    /// Validate an address for a specific chain
    public func validateAddress(_ address: String, chain: HawalaChain) -> (valid: Bool, normalized: String?) {
        struct ValidateRequest: Encodable { let address: String; let chain: String }
        struct ValidateResponse: Codable { let valid: Bool; let normalized: String? }
        
        guard let input = try? encodeJSON(ValidateRequest(address: address, chain: chain.rawValue)),
              let result: ValidateResponse = try? callRustFFIWithInput(input, { hawala_validate_address($0) }) else {
            return (false, nil)
        }
        return (result.valid, result.normalized)
    }
    
    // MARK: - Fee Operations (Phase 3)
    
    /// Estimate fees for a UTXO chain
    public func estimateBitcoinFees(chain: HawalaChain) throws -> HawalaBitcoinFees {
        struct FeeRequest: Encodable { let chain: String }
        let input = try encodeJSON(FeeRequest(chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_estimate_fees($0) }
    }
    
    /// Estimate fees for an EVM chain
    public func estimateEvmFees(chain: HawalaChain) throws -> HawalaEvmFees {
        struct FeeRequest: Encodable { let chain: String }
        let input = try encodeJSON(FeeRequest(chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_estimate_fees($0) }
    }
    
    /// Estimate gas for an EVM transaction
    public func estimateGas(from: String, to: String, data: String?, value: String?, chainId: UInt64) throws -> UInt64 {
        struct GasRequest: Encodable {
            let from: String
            let to: String
            let data: String?
            let value: String?
            let chainId: UInt64
            enum CodingKeys: String, CodingKey { case from, to, data, value, chainId = "chain_id" }
        }
        struct GasResponse: Codable { let gasLimit: UInt64; enum CodingKeys: String, CodingKey { case gasLimit = "gas_limit" } }
        
        let input = try encodeJSON(GasRequest(from: from, to: to, data: data, value: value, chainId: chainId))
        let result: GasResponse = try callRustFFIWithInput(input) { hawala_estimate_gas($0) }
        return result.gasLimit
    }
    
    /// Get fee intelligence/analysis
    public func analyzeFees(chain: HawalaChain) throws -> HawalaFeeIntelligence {
        struct AnalyzeRequest: Encodable { let chain: String }
        let input = try encodeJSON(AnalyzeRequest(chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_analyze_fees($0) }
    }
    
    // MARK: - Transaction Pipeline (Phase 2)
    
    /// Sign a Bitcoin/UTXO transaction
    public func signBitcoinTransaction(
        chain: HawalaChain,
        recipient: String,
        amountSats: UInt64,
        feeRate: UInt64,
        senderWif: String,
        utxos: [HawalaManagedUTXO]? = nil
    ) throws -> HawalaSignedTransaction {
        struct SignRequest: Encodable {
            let chain: String
            let recipient: String
            let amountSats: UInt64
            let feeRate: UInt64
            let senderWif: String
            let utxos: [UTXOInput]?
            
            struct UTXOInput: Encodable {
                let txid: String
                let vout: UInt32
                let value: UInt64
                let scriptPubKey: String
                enum CodingKeys: String, CodingKey { case txid, vout, value, scriptPubKey = "script_pubkey" }
            }
            enum CodingKeys: String, CodingKey {
                case chain, recipient, utxos
                case amountSats = "amount_sats"
                case feeRate = "fee_rate"
                case senderWif = "sender_wif"
            }
        }
        
        let utxoInputs = utxos?.map { SignRequest.UTXOInput(txid: $0.txid, vout: $0.vout, value: $0.value, scriptPubKey: $0.scriptPubKey) }
        let request = SignRequest(chain: chain.rawValue, recipient: recipient, amountSats: amountSats, feeRate: feeRate, senderWif: senderWif, utxos: utxoInputs)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_sign_transaction($0) }
    }
    
    /// Sign an EVM transaction
    public func signEvmTransaction(
        recipient: String,
        amountWei: String,
        chainId: UInt64,
        senderKeyHex: String,
        nonce: UInt64,
        gasLimit: UInt64,
        maxFeePerGas: String?,
        maxPriorityFee: String?,
        data: String? = nil
    ) throws -> HawalaSignedTransaction {
        struct SignRequest: Encodable {
            let chain: String
            let recipient: String
            let amountWei: String
            let chainId: UInt64
            let senderKey: String
            let nonce: UInt64
            let gasLimit: UInt64
            let maxFeePerGas: String?
            let maxPriorityFee: String?
            let data: String?
            enum CodingKeys: String, CodingKey {
                case chain, recipient, nonce, data
                case amountWei = "amount_wei"
                case chainId = "chain_id"
                case senderKey = "sender_key"
                case gasLimit = "gas_limit"
                case maxFeePerGas = "max_fee_per_gas"
                case maxPriorityFee = "max_priority_fee"
            }
        }
        
        let chain = chainIdToChainString(chainId)
        let request = SignRequest(chain: chain, recipient: recipient, amountWei: amountWei, chainId: chainId, senderKey: senderKeyHex, nonce: nonce, gasLimit: gasLimit, maxFeePerGas: maxFeePerGas, maxPriorityFee: maxPriorityFee, data: data)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_sign_transaction($0) }
    }
    
    /// Broadcast a signed transaction
    public func broadcastTransaction(chain: HawalaChain, rawTx: String) throws -> HawalaBroadcastResult {
        struct BroadcastRequest: Encodable {
            let chain: String
            let rawTx: String
            enum CodingKeys: String, CodingKey { case chain, rawTx = "raw_tx" }
        }
        let input = try encodeJSON(BroadcastRequest(chain: chain.rawValue, rawTx: rawTx))
        return try callRustFFIWithInput(input) { hawala_broadcast_transaction($0) }
    }
    
    // MARK: - Transaction Cancellation (Phase 4)
    
    /// Cancel a Bitcoin transaction using RBF
    public func cancelBitcoinTransaction(
        originalTxid: String,
        utxos: [HawalaManagedUTXO],
        returnAddress: String,
        privateKeyWif: String,
        newFeeRate: UInt64,
        isTestnet: Bool,
        isLitecoin: Bool = false
    ) throws -> HawalaCancellationResult {
        struct CancelRequest: Encodable {
            let originalTxid: String
            let utxos: [UTXOInput]
            let returnAddress: String
            let privateKeyWif: String
            let newFeeRate: UInt64
            let isTestnet: Bool
            let isLitecoin: Bool
            
            struct UTXOInput: Encodable {
                let txid: String; let vout: UInt32; let value: UInt64; let scriptPubKey: String
                enum CodingKeys: String, CodingKey { case txid, vout, value, scriptPubKey = "script_pubkey" }
            }
            enum CodingKeys: String, CodingKey {
                case utxos
                case originalTxid = "original_txid"
                case returnAddress = "return_address"
                case privateKeyWif = "private_key_wif"
                case newFeeRate = "new_fee_rate"
                case isTestnet = "is_testnet"
                case isLitecoin = "is_litecoin"
            }
        }
        
        let utxoInputs = utxos.map { CancelRequest.UTXOInput(txid: $0.txid, vout: $0.vout, value: $0.value, scriptPubKey: $0.scriptPubKey) }
        let request = CancelRequest(originalTxid: originalTxid, utxos: utxoInputs, returnAddress: returnAddress, privateKeyWif: privateKeyWif, newFeeRate: newFeeRate, isTestnet: isTestnet, isLitecoin: isLitecoin)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_cancel_bitcoin($0) }
    }
    
    /// Speed up a Bitcoin transaction using RBF
    public func speedUpBitcoinTransaction(
        originalTxid: String,
        utxos: [HawalaManagedUTXO],
        originalRecipient: String,
        originalAmount: UInt64,
        privateKeyWif: String,
        newFeeRate: UInt64,
        changeAddress: String,
        isTestnet: Bool,
        isLitecoin: Bool = false
    ) throws -> HawalaCancellationResult {
        struct SpeedUpRequest: Encodable {
            let originalTxid: String
            let utxos: [UTXOInput]
            let originalRecipient: String
            let originalAmount: UInt64
            let privateKeyWif: String
            let newFeeRate: UInt64
            let changeAddress: String
            let isTestnet: Bool
            let isLitecoin: Bool
            
            struct UTXOInput: Encodable {
                let txid: String; let vout: UInt32; let value: UInt64; let scriptPubKey: String
                enum CodingKeys: String, CodingKey { case txid, vout, value, scriptPubKey = "script_pubkey" }
            }
            enum CodingKeys: String, CodingKey {
                case utxos
                case originalTxid = "original_txid"
                case originalRecipient = "original_recipient"
                case originalAmount = "original_amount"
                case privateKeyWif = "private_key_wif"
                case newFeeRate = "new_fee_rate"
                case changeAddress = "change_address"
                case isTestnet = "is_testnet"
                case isLitecoin = "is_litecoin"
            }
        }
        
        let utxoInputs = utxos.map { SpeedUpRequest.UTXOInput(txid: $0.txid, vout: $0.vout, value: $0.value, scriptPubKey: $0.scriptPubKey) }
        let request = SpeedUpRequest(originalTxid: originalTxid, utxos: utxoInputs, originalRecipient: originalRecipient, originalAmount: originalAmount, privateKeyWif: privateKeyWif, newFeeRate: newFeeRate, changeAddress: changeAddress, isTestnet: isTestnet, isLitecoin: isLitecoin)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_speedup_bitcoin($0) }
    }
    
    /// Cancel an EVM transaction using nonce replacement
    public func cancelEvmTransaction(
        originalTxid: String,
        nonce: UInt64,
        fromAddress: String,
        privateKeyHex: String,
        newGasPrice: String,
        chainId: UInt64
    ) throws -> HawalaCancellationResult {
        struct CancelRequest: Encodable {
            let originalTxid: String
            let nonce: UInt64
            let fromAddress: String
            let privateKeyHex: String
            let newGasPrice: String
            let chainId: UInt64
            enum CodingKeys: String, CodingKey {
                case nonce
                case originalTxid = "original_txid"
                case fromAddress = "from_address"
                case privateKeyHex = "private_key_hex"
                case newGasPrice = "new_gas_price"
                case chainId = "chain_id"
            }
        }
        
        let request = CancelRequest(originalTxid: originalTxid, nonce: nonce, fromAddress: fromAddress, privateKeyHex: privateKeyHex, newGasPrice: newGasPrice, chainId: chainId)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_cancel_evm($0) }
    }
    
    /// Speed up an EVM transaction
    public func speedUpEvmTransaction(
        originalTxid: String,
        nonce: UInt64,
        recipient: String,
        amountWei: String,
        privateKeyHex: String,
        newGasPrice: String,
        gasLimit: UInt64,
        chainId: UInt64,
        data: String? = nil
    ) throws -> HawalaCancellationResult {
        struct SpeedUpRequest: Encodable {
            let originalTxid: String
            let nonce: UInt64
            let recipient: String
            let amountWei: String
            let privateKeyHex: String
            let newGasPrice: String
            let gasLimit: UInt64
            let chainId: UInt64
            let data: String?
            enum CodingKeys: String, CodingKey {
                case nonce, recipient, data
                case originalTxid = "original_txid"
                case amountWei = "amount_wei"
                case privateKeyHex = "private_key_hex"
                case newGasPrice = "new_gas_price"
                case gasLimit = "gas_limit"
                case chainId = "chain_id"
            }
        }
        
        let request = SpeedUpRequest(originalTxid: originalTxid, nonce: nonce, recipient: recipient, amountWei: amountWei, privateKeyHex: privateKeyHex, newGasPrice: newGasPrice, gasLimit: gasLimit, chainId: chainId, data: data)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_speedup_evm($0) }
    }
    
    // MARK: - Transaction Tracking (Phase 4)
    
    /// Track a transaction's status
    public func trackTransaction(txid: String, chain: HawalaChain) throws -> HawalaTransactionStatus {
        struct TrackRequest: Encodable { let txid: String; let chain: String }
        let input = try encodeJSON(TrackRequest(txid: txid, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_track_transaction($0) }
    }
    
    /// Get confirmations for a transaction
    public func getConfirmations(txid: String, chain: HawalaChain) throws -> (confirmations: UInt32, required: UInt32, isConfirmed: Bool) {
        struct ConfirmRequest: Encodable { let txid: String; let chain: String }
        struct ConfirmResponse: Codable {
            let confirmations: UInt32
            let required: UInt32
            let isConfirmed: Bool
            enum CodingKeys: String, CodingKey { case confirmations, required, isConfirmed = "is_confirmed" }
        }
        
        let input = try encodeJSON(ConfirmRequest(txid: txid, chain: chain.rawValue))
        let result: ConfirmResponse = try callRustFFIWithInput(input) { hawala_get_confirmations($0) }
        return (result.confirmations, result.required, result.isConfirmed)
    }
    
    /// Get transaction status
    public func getTransactionStatus(txid: String, chain: HawalaChain) throws -> HawalaTransactionStatus {
        struct StatusRequest: Encodable { let txid: String; let chain: String }
        let input = try encodeJSON(StatusRequest(txid: txid, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_get_tx_status($0) }
    }
    
    // MARK: - UTXO Management (Phase 6)
    
    /// Fetch UTXOs for an address
    public func fetchUTXOs(address: String, chain: HawalaChain) throws -> [HawalaManagedUTXO] {
        struct UTXORequest: Encodable { let address: String; let chain: String }
        let input = try encodeJSON(UTXORequest(address: address, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_fetch_utxos($0) }
    }
    
    /// Select optimal UTXOs for a transaction
    public func selectUTXOs(
        address: String,
        chain: HawalaChain,
        amount: UInt64,
        feeRate: UInt64,
        strategy: HawalaUTXOSelectionStrategy = .optimal
    ) throws -> HawalaUTXOSelection {
        struct SelectRequest: Encodable {
            let address: String
            let chain: String
            let amount: UInt64
            let feeRate: UInt64
            let strategy: String
            enum CodingKeys: String, CodingKey { case address, chain, amount, strategy, feeRate = "fee_rate" }
        }
        
        let request = SelectRequest(address: address, chain: chain.rawValue, amount: amount, feeRate: feeRate, strategy: strategy.rawValue)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_select_utxos($0) }
    }
    
    /// Set metadata for a UTXO
    public func setUTXOMetadata(key: String, metadata: HawalaUTXOMetadata) throws {
        struct MetadataRequest: Encodable {
            let key: String
            let label: String
            let source: String
            let isFrozen: Bool
            let note: String
            enum CodingKeys: String, CodingKey { case key, label, source, note, isFrozen = "is_frozen" }
        }
        
        let request = MetadataRequest(key: key, label: metadata.label, source: metadata.source.rawValue, isFrozen: metadata.isFrozen, note: metadata.note)
        let input = try encodeJSON(request)
        struct SuccessResponse: Codable { let success: Bool }
        let _: SuccessResponse = try callRustFFIWithInput(input) { hawala_set_utxo_metadata($0) }
    }
    
    // MARK: - Nonce Management (Phase 6)
    
    /// Get next available nonce for an EVM address
    public func getNonce(address: String, chainId: UInt64) throws -> HawalaNonceResult {
        struct NonceRequest: Encodable {
            let address: String
            let chainId: UInt64
            enum CodingKeys: String, CodingKey { case address, chainId = "chain_id" }
        }
        let input = try encodeJSON(NonceRequest(address: address, chainId: chainId))
        return try callRustFFIWithInput(input) { hawala_get_nonce($0) }
    }
    
    /// Reserve a nonce for a pending transaction
    public func reserveNonce(address: String, chainId: UInt64, nonce: UInt64) throws {
        struct ReserveRequest: Encodable {
            let address: String
            let chainId: UInt64
            let nonce: UInt64
            enum CodingKeys: String, CodingKey { case address, nonce, chainId = "chain_id" }
        }
        let input = try encodeJSON(ReserveRequest(address: address, chainId: chainId, nonce: nonce))
        struct ReserveResponse: Codable { let reserved: UInt64 }
        let _: ReserveResponse = try callRustFFIWithInput(input) { hawala_reserve_nonce($0) }
    }
    
    /// Confirm a nonce (transaction included in block)
    public func confirmNonce(address: String, chainId: UInt64, nonce: UInt64) throws {
        struct ConfirmRequest: Encodable {
            let address: String
            let chainId: UInt64
            let nonce: UInt64
            enum CodingKeys: String, CodingKey { case address, nonce, chainId = "chain_id" }
        }
        let input = try encodeJSON(ConfirmRequest(address: address, chainId: chainId, nonce: nonce))
        struct ConfirmResponse: Codable { let confirmed: UInt64 }
        let _: ConfirmResponse = try callRustFFIWithInput(input) { hawala_confirm_nonce($0) }
    }
    
    /// Detect nonce gaps
    public func detectNonceGaps(address: String, chainId: UInt64) throws -> [HawalaNonceGap] {
        struct GapRequest: Encodable {
            let address: String
            let chainId: UInt64
            enum CodingKeys: String, CodingKey { case address, chainId = "chain_id" }
        }
        let input = try encodeJSON(GapRequest(address: address, chainId: chainId))
        return try callRustFFIWithInput(input) { hawala_detect_nonce_gaps($0) }
    }
    
    // MARK: - History Operations (Phase 5)
    
    /// Fetch transaction history for a chain
    public func fetchHistory(address: String, chain: HawalaChain, limit: UInt32 = 50) throws -> [HawalaHistoryEntry] {
        struct HistoryRequest: Encodable { let address: String; let chain: String; let limit: UInt32 }
        let input = try encodeJSON(HistoryRequest(address: address, chain: chain.rawValue, limit: limit))
        return try callRustFFIWithInput(input) { hawala_fetch_chain_history($0) }
    }
    
    /// Fetch history for multiple addresses
    public func fetchMultiHistory(addresses: [(address: String, chain: HawalaChain)]) throws -> [HawalaHistoryEntry] {
        struct MultiHistoryRequest: Encodable {
            let addresses: [AddressEntry]
            struct AddressEntry: Encodable { let address: String; let chain: String }
        }
        let entries = addresses.map { MultiHistoryRequest.AddressEntry(address: $0.address, chain: $0.chain.rawValue) }
        let input = try encodeJSON(MultiHistoryRequest(addresses: entries))
        return try callRustFFIWithInput(input) { hawala_fetch_history($0) }
    }
    
    // MARK: - Balance Operations (Phase 5)
    
    /// Fetch balance for a single address
    public func fetchBalance(address: String, chain: HawalaChain) throws -> HawalaAddressBalance {
        struct BalanceRequest: Encodable { let address: String; let chain: String }
        let input = try encodeJSON(BalanceRequest(address: address, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_fetch_balance($0) }
    }
    
    /// Fetch balances for multiple addresses
    public func fetchBalances(addresses: [(address: String, chain: HawalaChain)]) throws -> [HawalaAddressBalance] {
        struct MultiBalanceRequest: Encodable {
            let addresses: [AddressEntry]
            struct AddressEntry: Encodable { let address: String; let chain: String }
        }
        let entries = addresses.map { MultiBalanceRequest.AddressEntry(address: $0.address, chain: $0.chain.rawValue) }
        let input = try encodeJSON(MultiBalanceRequest(addresses: entries))
        return try callRustFFIWithInput(input) { hawala_fetch_balances($0) }
    }
    
    /// Fetch ERC-20 token balance
    public func fetchTokenBalance(address: String, tokenContract: String, chain: HawalaChain) throws -> HawalaTokenBalance {
        struct TokenRequest: Encodable {
            let address: String
            let tokenContract: String
            let chain: String
            enum CodingKeys: String, CodingKey { case address, chain, tokenContract = "token_contract" }
        }
        let input = try encodeJSON(TokenRequest(address: address, tokenContract: tokenContract, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_fetch_token_balance($0) }
    }
    
    /// Fetch SPL token balance (Solana)
    public func fetchSPLBalance(address: String, mint: String, chain: HawalaChain) throws -> HawalaTokenBalance {
        struct SPLRequest: Encodable { let address: String; let mint: String; let chain: String }
        let input = try encodeJSON(SPLRequest(address: address, mint: mint, chain: chain.rawValue))
        return try callRustFFIWithInput(input) { hawala_fetch_spl_balance($0) }
    }
    
    // MARK: - Security Operations (Phase 5)
    
    /// Threat assessment result
    public struct ThreatAssessment: Codable {
        public let riskLevel: String
        public let threats: [ThreatInfo]
        public let recommendations: [String]
        public let allowTransaction: Bool
        
        public struct ThreatInfo: Codable {
            public let threatType: String
            public let severity: String
            public let description: String
            
            enum CodingKeys: String, CodingKey {
                case threatType = "threat_type"
                case severity
                case description
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case riskLevel = "risk_level"
            case threats
            case recommendations
            case allowTransaction = "allow_transaction"
        }
        
        public var isHighRisk: Bool {
            ["high", "critical"].contains(riskLevel.lowercased())
        }
    }
    
    /// Assess a transaction for security threats
    public func assessThreat(walletId: String, recipient: String, amount: String, chain: HawalaChain) throws -> ThreatAssessment {
        struct ThreatRequest: Encodable {
            let walletId: String
            let recipient: String
            let amount: String
            let chain: String
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
                case recipient
                case amount
                case chain
            }
        }
        
        let request = ThreatRequest(walletId: walletId, recipient: recipient, amount: amount, chain: chain.rawValue)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_assess_threat($0) }
    }
    
    /// Blacklist an address (scam protection)
    public func blacklistAddress(_ address: String, reason: String) throws {
        struct BlacklistRequest: Encodable { let address: String; let reason: String }
        let input = try encodeJSON(BlacklistRequest(address: address, reason: reason))
        let _: [String: Bool] = try callRustFFIWithInput(input) { hawala_blacklist_address($0) }
    }
    
    /// Whitelist an address for a wallet
    public func whitelistAddress(walletId: String, address: String) throws {
        struct WhitelistRequest: Encodable {
            let walletId: String
            let address: String
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
                case address
            }
        }
        let input = try encodeJSON(WhitelistRequest(walletId: walletId, address: address))
        let _: [String: Bool] = try callRustFFIWithInput(input) { hawala_whitelist_address($0) }
    }
    
    /// Policy check result
    public struct PolicyCheckResult: Codable {
        public let allowed: Bool
        public let violations: [PolicyViolation]
        public let warnings: [String]
        public let remainingDaily: String?
        public let remainingWeekly: String?
        public let requiresApproval: Bool
        
        public struct PolicyViolation: Codable {
            public let violationType: String
            public let message: String
            
            enum CodingKeys: String, CodingKey {
                case violationType = "violation_type"
                case message
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case allowed
            case violations
            case warnings
            case remainingDaily = "remaining_daily"
            case remainingWeekly = "remaining_weekly"
            case requiresApproval = "requires_approval"
        }
    }
    
    /// Check transaction against spending policies
    public func checkPolicy(walletId: String, recipient: String, amount: String, chain: HawalaChain) throws -> PolicyCheckResult {
        struct PolicyRequest: Encodable {
            let walletId: String
            let recipient: String
            let amount: String
            let chain: String
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
                case recipient
                case amount
                case chain
            }
        }
        
        let request = PolicyRequest(walletId: walletId, recipient: recipient, amount: amount, chain: chain.rawValue)
        let input = try encodeJSON(request)
        return try callRustFFIWithInput(input) { hawala_check_policy($0) }
    }
    
    /// Set spending limits for a wallet
    public func setSpendingLimits(
        walletId: String,
        perTxLimit: String? = nil,
        dailyLimit: String? = nil,
        weeklyLimit: String? = nil,
        monthlyLimit: String? = nil,
        requireWhitelist: Bool? = nil
    ) throws {
        struct LimitsRequest: Encodable {
            let walletId: String
            let perTxLimit: String?
            let dailyLimit: String?
            let weeklyLimit: String?
            let monthlyLimit: String?
            let requireWhitelist: Bool?
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
                case perTxLimit = "per_tx_limit"
                case dailyLimit = "daily_limit"
                case weeklyLimit = "weekly_limit"
                case monthlyLimit = "monthly_limit"
                case requireWhitelist = "require_whitelist"
            }
        }
        
        let request = LimitsRequest(
            walletId: walletId,
            perTxLimit: perTxLimit,
            dailyLimit: dailyLimit,
            weeklyLimit: weeklyLimit,
            monthlyLimit: monthlyLimit,
            requireWhitelist: requireWhitelist
        )
        let input = try encodeJSON(request)
        let _: [String: Bool] = try callRustFFIWithInput(input) { hawala_set_spending_limits($0) }
    }
    
    /// Challenge for authentication
    public struct AuthChallenge: Codable {
        public let challengeId: String
        public let message: String
        public let expiresAt: UInt64
        
        enum CodingKeys: String, CodingKey {
            case challengeId = "challenge_id"
            case message
            case expiresAt = "expires_at"
        }
    }
    
    /// Create an authentication challenge
    public func createChallenge(address: String, domain: String? = nil) throws -> AuthChallenge {
        struct ChallengeRequest: Encodable { let address: String; let domain: String? }
        let input = try encodeJSON(ChallengeRequest(address: address, domain: domain))
        return try callRustFFIWithInput(input) { hawala_create_challenge($0) }
    }
    
    /// Challenge verification result
    public struct ChallengeVerifyResult: Codable {
        public let valid: Bool
        public let signer: String?
        public let error: String?
    }
    
    /// Verify a signed challenge
    public func verifyChallenge(challengeId: String, signature: String, signer: String) throws -> ChallengeVerifyResult {
        struct VerifyRequest: Encodable {
            let challengeId: String
            let signature: String
            let signer: String
            
            enum CodingKeys: String, CodingKey {
                case challengeId = "challenge_id"
                case signature
                case signer
            }
        }
        let input = try encodeJSON(VerifyRequest(challengeId: challengeId, signature: signature, signer: signer))
        return try callRustFFIWithInput(input) { hawala_verify_challenge($0) }
    }
    
    /// Key version info
    public struct KeyVersionInfo: Codable {
        public let version: UInt32
        public let createdAt: UInt64
        public let status: String
        
        enum CodingKeys: String, CodingKey {
            case version
            case createdAt = "created_at"
            case status
        }
    }
    
    /// Register a key version for rotation tracking
    public func registerKeyVersion(walletId: String, keyType: String, algorithm: String, derivationPath: String? = nil) throws -> KeyVersionInfo {
        struct KeyRequest: Encodable {
            let walletId: String
            let keyType: String
            let derivationPath: String?
            let algorithm: String
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
                case keyType = "key_type"
                case derivationPath = "derivation_path"
                case algorithm
            }
        }
        let input = try encodeJSON(KeyRequest(walletId: walletId, keyType: keyType, derivationPath: derivationPath, algorithm: algorithm))
        return try callRustFFIWithInput(input) { hawala_register_key_version($0) }
    }
    
    /// Key rotation check result
    public struct KeyRotationCheck: Codable {
        public let needsRotation: Bool
        public let keysToRotate: [KeyRotationInfo]
        public let warnings: [String]
        
        public struct KeyRotationInfo: Codable {
            public let keyType: String
            public let version: UInt32
            public let ageDays: UInt64
            public let reason: String
            
            enum CodingKeys: String, CodingKey {
                case keyType = "key_type"
                case version
                case ageDays = "age_days"
                case reason
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case needsRotation = "needs_rotation"
            case keysToRotate = "keys_to_rotate"
            case warnings
        }
    }
    
    /// Check if key rotation is needed
    public func checkKeyRotation(walletId: String) throws -> KeyRotationCheck {
        struct RotationRequest: Encodable {
            let walletId: String
            
            enum CodingKeys: String, CodingKey {
                case walletId = "wallet_id"
            }
        }
        let input = try encodeJSON(RotationRequest(walletId: walletId))
        return try callRustFFIWithInput(input) { hawala_check_key_rotation($0) }
    }
    
    /// Securely compare two strings (constant-time)
    public func secureCompare(_ a: String, _ b: String) throws -> Bool {
        struct CompareRequest: Encodable { let a: String; let b: String }
        struct CompareResult: Codable { let equal: Bool }
        let input = try encodeJSON(CompareRequest(a: a, b: b))
        let result: CompareResult = try callRustFFIWithInput(input) { hawala_secure_compare($0) }
        return result.equal
    }
    
    /// Redact sensitive data for logging
    public func redact(_ data: String) throws -> String {
        struct RedactRequest: Encodable { let data: String }
        struct RedactResult: Codable { let redacted: String }
        let input = try encodeJSON(RedactRequest(data: data))
        let result: RedactResult = try callRustFFIWithInput(input) { hawala_redact($0) }
        return result.redacted
    }
    
    // MARK: - Helper Methods
    
    private func chainIdToChainString(_ chainId: UInt64) -> String {
        switch chainId {
        case 1: return "ethereum"
        case 11155111: return "ethereum_sepolia"
        case 56: return "bnb"
        case 137: return "polygon"
        case 42161: return "arbitrum"
        case 10: return "optimism"
        case 8453: return "base"
        case 43114: return "avalanche"
        default: return "ethereum"
        }
    }
    
    // MARK: - Legacy Compatibility API (Deprecated)
    
    @available(*, deprecated, message: "Use generateWallet() instead")
    public func generateKeys() -> String {
        guard let cString = generate_keys_ffi() else { return "{}" }
        let result = String(cString: cString)
        freeRustString(UnsafeMutablePointer(mutating: cString))
        return result
    }
    
    @available(*, deprecated, message: "Use restoreWallet(mnemonic:) instead")
    public func restoreWalletLegacy(mnemonic: String) -> String {
        guard let inputCString = mnemonic.cString(using: .utf8) else { return "{}" }
        guard let outputCString = restore_wallet_ffi(inputCString) else { return "{}" }
        let result = String(cString: outputCString)
        freeRustString(UnsafeMutablePointer(mutating: outputCString))
        return result
    }
    
    @available(*, deprecated, message: "Use validateMnemonic(_:) instead")
    public func validateMnemonicLegacy(_ mnemonic: String) -> Bool {
        guard let mnemonicCString = mnemonic.cString(using: .utf8) else { return false }
        return validate_mnemonic_ffi(mnemonicCString)
    }
    
    @available(*, deprecated, message: "Use fetchBalances(addresses:) instead")
    public func fetchBalancesLegacy(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else { return "[]" }
        guard let outputCString = fetch_balances_ffi(inputCString) else { return "[]" }
        let result = String(cString: outputCString)
        freeRustString(UnsafeMutablePointer(mutating: outputCString))
        return result
    }
    
    @available(*, deprecated, message: "Use fetchHistory(address:chain:) instead")
    public func fetchBitcoinHistory(address: String) -> String {
        guard let addressCString = address.cString(using: .utf8) else { return "[]" }
        guard let outputCString = fetch_bitcoin_history_ffi(addressCString) else { return "[]" }
        let result = String(cString: outputCString)
        freeRustString(UnsafeMutablePointer(mutating: outputCString))
        return result
    }
}

// MARK: - RustService Compatibility

extension RustService {
    /// Use HawalaBridge for new code
    @MainActor
    var bridge: HawalaBridge {
        return HawalaBridge.shared
    }
}

// MARK: - Convenience Extensions

extension HawalaChain {
    /// Convert from legacy Chain enum (defined in SendView.swift)
    init?(from legacyChain: Chain) {
        switch legacyChain {
        case .bitcoinMainnet: self = .bitcoin
        case .bitcoinTestnet: self = .bitcoinTestnet
        case .litecoin: self = .litecoin
        case .ethereumMainnet: self = .ethereum
        case .ethereumSepolia: self = .ethereumSepolia
        case .polygon: self = .polygon
        case .bnb: self = .bnb
        case .solanaMainnet: self = .solana
        case .solanaDevnet: self = .solanaDevnet
        case .xrpMainnet: self = .xrp
        case .xrpTestnet: self = .xrpTestnet
        case .monero: self = .monero
        }
    }
}
