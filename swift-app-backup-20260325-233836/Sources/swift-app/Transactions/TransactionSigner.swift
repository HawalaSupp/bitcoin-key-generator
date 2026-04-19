import Foundation

// MARK: - Transaction Signer Protocol

/// Protocol for signing transactions across different chains.
/// Abstracts the key retrieval and signing process.
protocol TransactionSigner: Sendable {
    /// Chain this signer supports
    var chainId: ChainIdentifier { get }
    
    /// Sign a transaction
    /// - Parameters:
    ///   - unsignedTx: The unsigned transaction data
    ///   - signingContext: Additional context for signing (chain-specific)
    /// - Returns: Signed transaction hex string
    func sign(unsignedTx: UnsignedTransaction, context: SigningContext) async throws -> SignedTransaction
    
    /// Check if this signer can sign for a given address
    func canSign(forAddress address: String) async -> Bool
}

// MARK: - Unsigned Transaction

/// Generic unsigned transaction representation
struct UnsignedTransaction: Sendable {
    /// Chain identifier
    let chainId: ChainIdentifier
    
    /// Recipient address
    let to: String
    
    /// Amount in smallest unit (satoshis, wei, lamports, etc.)
    let amount: UInt64
    
    /// Optional data (for smart contract calls)
    let data: Data?
    
    /// Chain-specific inputs (UTXOs for BTC, nonce for ETH)
    let inputs: TransactionInputs
    
    init(
        chainId: ChainIdentifier,
        to: String,
        amount: UInt64,
        data: Data? = nil,
        inputs: TransactionInputs = .none
    ) {
        self.chainId = chainId
        self.to = to
        self.amount = amount
        self.data = data
        self.inputs = inputs
    }
}

// MARK: - Transaction Inputs

/// Chain-specific transaction inputs
enum TransactionInputs: Sendable {
    /// No inputs needed
    case none
    
    /// Bitcoin/Litecoin UTXOs
    case utxo(UTXOInputs)
    
    /// EVM transaction parameters
    case evm(EVMInputs)
    
    /// Solana transaction parameters
    case solana(SolanaInputs)
    
    /// XRP transaction parameters
    case xrp(XRPInputs)
}

/// UTXO inputs for Bitcoin-like chains
struct UTXOInputs: Sendable {
    /// Selected UTXOs to spend
    let utxos: [UTXOInput]
    
    /// Fee rate in sat/vB
    let feeRate: Int64
    
    /// Change address (optional, auto-derived if nil)
    let changeAddress: String?
    
    /// Enable RBF (default true)
    let rbfEnabled: Bool
}

/// Single UTXO input
struct UTXOInput: Sendable {
    let txid: String
    let vout: UInt32
    let value: Int64
    let scriptPubKey: Data
    let address: String
}

/// EVM transaction inputs
struct EVMInputs: Sendable {
    /// Transaction nonce
    let nonce: UInt64
    
    /// Gas limit
    let gasLimit: UInt64
    
    /// Gas price (legacy) or max fee per gas (EIP-1559)
    let gasPrice: UInt64
    
    /// Max priority fee per gas (EIP-1559 only)
    let maxPriorityFee: UInt64?
    
    /// Chain ID (1 = mainnet, 11155111 = sepolia, 56 = BSC, 137 = Polygon)
    let chainIdNumber: UInt64
    
    /// Use EIP-1559 fee model
    let useEIP1559: Bool
}

/// Solana transaction inputs
struct SolanaInputs: Sendable {
    /// Recent blockhash
    let recentBlockhash: String
    
    /// Compute unit limit (optional)
    let computeUnitLimit: UInt32?
    
    /// Priority fee in micro-lamports
    let priorityFee: UInt64?
}

/// XRP transaction inputs
struct XRPInputs: Sendable {
    /// Account sequence number
    let sequence: UInt32
    
    /// Fee in drops
    let fee: UInt64
    
    /// Destination tag (optional)
    let destinationTag: UInt32?
}

// MARK: - Signing Context

/// Additional context for signing
struct SigningContext: Sendable {
    /// Whether this is a testnet transaction
    let isTestnet: Bool
    
    /// Wallet ID for key lookup
    let walletId: UUID
    
    /// Whether biometric auth is required
    let requireBiometric: Bool
    
    init(
        isTestnet: Bool = false,
        walletId: UUID,
        requireBiometric: Bool = true
    ) {
        self.isTestnet = isTestnet
        self.walletId = walletId
        self.requireBiometric = requireBiometric
    }
}

// MARK: - Signed Transaction

/// Signed transaction ready for broadcast
struct SignedTransaction: Sendable {
    /// Chain identifier
    let chainId: ChainIdentifier
    
    /// Transaction ID (hash)
    let txid: String
    
    /// Raw signed transaction hex
    let rawHex: String
    
    /// Transaction size in bytes
    let size: Int
    
    /// Virtual size for fee calculation (vsize for SegWit)
    let vsize: Int
    
    /// Total fee paid
    let fee: UInt64
    
    init(
        chainId: ChainIdentifier,
        txid: String,
        rawHex: String,
        size: Int,
        vsize: Int? = nil,
        fee: UInt64
    ) {
        self.chainId = chainId
        self.txid = txid
        self.rawHex = rawHex
        self.size = size
        self.vsize = vsize ?? size
        self.fee = fee
    }
}

// MARK: - Transaction Signer Errors

enum TransactionSignerError: LocalizedError {
    case walletNotFound
    case seedPhraseNotFound
    case keyDerivationFailed
    case invalidInputs(String)
    case signingFailed(Error)
    case insufficientFunds(available: UInt64, required: UInt64)
    case dustOutput(amount: UInt64, dustLimit: UInt64)
    case unsupportedChain(ChainIdentifier)
    case biometricFailed
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .walletNotFound:
            return "Wallet not found"
        case .seedPhraseNotFound:
            return "Seed phrase not found in secure storage"
        case .keyDerivationFailed:
            return "Failed to derive signing keys"
        case .invalidInputs(let reason):
            return "Invalid transaction inputs: \(reason)"
        case .signingFailed(let error):
            return "Transaction signing failed: \(error.localizedDescription)"
        case .insufficientFunds(let available, let required):
            let availableStr = formatAmount(available)
            let requiredStr = formatAmount(required)
            return "Insufficient funds. Available: \(availableStr), Required: \(requiredStr)"
        case .dustOutput(let amount, let limit):
            return "Output amount (\(amount)) is below dust limit (\(limit))"
        case .unsupportedChain(let chain):
            return "Chain \(chain.rawValue) is not supported for signing"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .cancelled:
            return "Transaction was cancelled"
        }
    }
    
    private func formatAmount(_ amount: UInt64) -> String {
        // Simple formatting - can be enhanced
        return "\(amount)"
    }
}

// MARK: - Transaction Signer Manager

/// Central manager for transaction signers
@MainActor
final class TransactionSignerManager: ObservableObject {
    static let shared = TransactionSignerManager()
    
    private var signers: [ChainIdentifier: any TransactionSigner] = [:]
    private let walletManager: WalletManager
    private let keyDerivation: KeyDerivationService
    private let secureStorage: SecureStorageProtocol
    
    init(
        walletManager: WalletManager = .shared,
        keyDerivation: KeyDerivationService = .shared,
        secureStorage: SecureStorageProtocol = KeychainSecureStorage.shared
    ) {
        self.walletManager = walletManager
        self.keyDerivation = keyDerivation
        self.secureStorage = secureStorage
        
        // Register default signers
        registerDefaultSigners()
    }
    
    private func registerDefaultSigners() {
        // These will be registered after implementation
        // signers[.bitcoin] = BitcoinTransactionSigner()
        // signers[.ethereum] = EVMTransactionSigner(chainId: .ethereum)
    }
    
    /// Register a signer for a chain
    func register(_ signer: any TransactionSigner, for chain: ChainIdentifier) {
        signers[chain] = signer
    }
    
    /// Get signer for a chain
    func signer(for chain: ChainIdentifier) -> (any TransactionSigner)? {
        signers[chain]
    }
    
    /// Sign a transaction
    func sign(
        transaction: UnsignedTransaction,
        context: SigningContext
    ) async throws -> SignedTransaction {
        guard let signer = signers[transaction.chainId] else {
            throw TransactionSignerError.unsupportedChain(transaction.chainId)
        }
        
        return try await signer.sign(unsignedTx: transaction, context: context)
    }
    
    // MARK: - Key Retrieval
    
    /// Retrieve signing keys for a wallet and chain
    /// This is the secure path for getting keys - only used during signing
    func retrieveKeys(
        walletId: UUID,
        chain: ChainIdentifier
    ) async throws -> DerivedKeys {
        // Get seed phrase from secure storage (requires biometric)
        let seedKey = SecureStorageKey.seedPhrase(walletId: walletId)
        guard let seedData = try await secureStorage.load(forKey: seedKey),
              let seedPhrase = String(data: seedData, encoding: .utf8) else {
            throw TransactionSignerError.seedPhraseNotFound
        }
        
        // Get optional passphrase
        let passphraseKey = SecureStorageKey.passphrase(walletId: walletId)
        let passphrase: String
        if let passphraseData = try? await secureStorage.load(forKey: passphraseKey),
           let passphraseStr = String(data: passphraseData, encoding: .utf8) {
            passphrase = passphraseStr
        } else {
            passphrase = ""
        }
        
        // Derive keys
        do {
            let keys = try await keyDerivation.restoreWallet(from: seedPhrase, passphrase: passphrase)
            return keys
        } catch {
            throw TransactionSignerError.keyDerivationFailed
        }
    }
}
