import Foundation

// MARK: - EVM Transaction Signer

/// Signer for Ethereum and EVM-compatible chains (BSC, Polygon, etc.)
@MainActor
final class EVMTransactionSigner: TransactionSigner {
    
    let chainId: ChainIdentifier
    private let evmChainId: UInt64
    private let signerManager: TransactionSignerManager
    
    /// Chain ID mapping for EVM networks
    private static let chainIdMap: [ChainIdentifier: UInt64] = [
        .ethereum: 1,
        .bnb: 56,
        // Polygon would be 137
        // Sepolia testnet: 11155111
    ]
    
    init(chainId: ChainIdentifier) {
        precondition(
            Self.chainIdMap.keys.contains(chainId),
            "EVMTransactionSigner only supports EVM chains"
        )
        self.chainId = chainId
        self.evmChainId = Self.chainIdMap[chainId] ?? 1
        self.signerManager = .shared
    }
    
    // MARK: - TransactionSigner Protocol
    
    func sign(
        unsignedTx: UnsignedTransaction,
        context: SigningContext
    ) async throws -> SignedTransaction {
        // Validate chain
        guard Self.chainIdMap.keys.contains(unsignedTx.chainId) else {
            throw TransactionSignerError.unsupportedChain(unsignedTx.chainId)
        }
        
        // Get EVM inputs
        guard case .evm(let evmInputs) = unsignedTx.inputs else {
            throw TransactionSignerError.invalidInputs("EVM chain requires EVM inputs")
        }
        
        // Retrieve signing keys
        let keys = try await signerManager.retrieveKeys(
            walletId: context.walletId,
            chain: chainId
        )
        
        // Get private key hex for the appropriate chain
        let privateKeyHex: String
        
        switch chainId {
        case .ethereum:
            privateKeyHex = keys.ethereum.privateKey
        case .bnb:
            privateKeyHex = keys.bnb.privateKey
        default:
            throw TransactionSignerError.unsupportedChain(chainId)
        }
        
        guard !privateKeyHex.isEmpty else {
            throw TransactionSignerError.keyDerivationFailed
        }
        
        // Calculate gas cost
        let gasPrice = evmInputs.gasPrice
        let gasLimit = evmInputs.gasLimit
        let maxGasCost = gasPrice * gasLimit
        
        // For native transfers, ensure sufficient balance
        // (This would need balance checking - simplified here)
        
        // Convert data if present
        let dataHex = unsignedTx.data.map { "0x" + $0.hexString } ?? "0x"
        
        // Build and sign transaction using existing Ethereum builder
        do {
            let signedHex: String
            
            if evmInputs.useEIP1559, let maxPriorityFee = evmInputs.maxPriorityFee {
                // EIP-1559 transaction
                signedHex = try EthereumTransaction.buildAndSignEIP1559(
                    to: unsignedTx.to,
                    value: String(unsignedTx.amount),
                    gasLimit: Int(gasLimit),
                    maxFeePerGas: String(gasPrice),
                    maxPriorityFeePerGas: String(maxPriorityFee),
                    nonce: Int(evmInputs.nonce),
                    chainId: Int(evmInputs.chainIdNumber),
                    privateKeyHex: privateKeyHex,
                    data: dataHex
                )
            } else {
                // Legacy transaction
                signedHex = try EthereumTransaction.buildAndSign(
                    to: unsignedTx.to,
                    value: String(unsignedTx.amount),
                    gasLimit: Int(gasLimit),
                    gasPrice: String(gasPrice),
                    nonce: Int(evmInputs.nonce),
                    chainId: Int(evmInputs.chainIdNumber),
                    privateKeyHex: privateKeyHex,
                    data: dataHex
                )
            }
            
            // Calculate txid from signed transaction
            // For EVM, this is keccak256(rlp(signedTx))
            let txid = calculateEVMTxid(signedHex: signedHex)
            
            return SignedTransaction(
                chainId: chainId,
                txid: txid,
                rawHex: signedHex,
                size: signedHex.count / 2, // Hex to bytes
                fee: maxGasCost
            )
        } catch {
            throw TransactionSignerError.signingFailed(error)
        }
    }
    
    func canSign(forAddress address: String) async -> Bool {
        // Check if address format is valid for EVM
        return address.hasPrefix("0x") && address.count == 42
    }
    
    // MARK: - Helpers
    
    /// Calculate transaction hash from signed transaction hex
    private func calculateEVMTxid(signedHex: String) -> String {
        // This would use keccak256 on the raw transaction bytes
        // For now, return a placeholder - the actual txid comes from broadcast
        return "0x" + signedHex.prefix(64)
    }
}

// MARK: - EVM Send Flow Helper

/// High-level helper for EVM send flows
@MainActor
final class EVMSendFlow: ObservableObject {
    
    @Published var isLoading = false
    @Published var error: Error?
    @Published var signedTransaction: SignedTransaction?
    @Published var estimatedGas: UInt64?
    
    private let signer: EVMTransactionSigner
    private let feeService: FeeEstimationService
    private let chainId: ChainIdentifier
    
    init(chainId: ChainIdentifier) {
        self.chainId = chainId
        self.signer = EVMTransactionSigner(chainId: chainId)
        self.feeService = FeeEstimationService.shared
    }
    
    /// Prepare and sign an EVM transaction
    /// - Parameters:
    ///   - recipient: Destination address
    ///   - amount: Amount in wei
    ///   - nonce: Transaction nonce
    ///   - gasPrice: Gas price in wei (or nil to use suggested)
    ///   - gasLimit: Gas limit (or nil for default 21000)
    ///   - walletId: Wallet ID for key lookup
    ///   - data: Optional call data for smart contracts
    /// - Returns: Signed transaction ready for broadcast
    func prepareTransaction(
        recipient: String,
        amount: UInt64,
        nonce: UInt64,
        gasPrice: UInt64? = nil,
        gasLimit: UInt64? = nil,
        walletId: UUID,
        data: Data? = nil
    ) async throws -> SignedTransaction {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Get gas price if not provided
            let effectiveGasPrice: UInt64
            if let gasPrice = gasPrice {
                effectiveGasPrice = gasPrice
            } else {
                await feeService.refreshAll()
                // Convert gwei to wei
                let gweiPrice = feeService.ethereumFees?.medium.gasPrice ?? 30.0
                effectiveGasPrice = UInt64(gweiPrice * 1_000_000_000)
            }
            
            // Use default gas limit for simple transfers
            let effectiveGasLimit = gasLimit ?? 21000
            
            // Get EVM chain ID
            let evmChainId: UInt64
            switch chainId {
            case .ethereum:
                evmChainId = 1
            case .bnb:
                evmChainId = 56
            default:
                evmChainId = 1
            }
            
            // Create unsigned transaction
            let unsignedTx = UnsignedTransaction(
                chainId: chainId,
                to: recipient,
                amount: amount,
                data: data,
                inputs: .evm(EVMInputs(
                    nonce: nonce,
                    gasLimit: effectiveGasLimit,
                    gasPrice: effectiveGasPrice,
                    maxPriorityFee: nil, // Use legacy for now
                    chainIdNumber: evmChainId,
                    useEIP1559: false
                ))
            )
            
            // Sign
            let context = SigningContext(
                isTestnet: false, // Determine from chain
                walletId: walletId,
                requireBiometric: true
            )
            
            let signedTx = try await signer.sign(unsignedTx: unsignedTx, context: context)
            self.signedTransaction = signedTx
            return signedTx
            
        } catch {
            self.error = error
            throw error
        }
    }
    
    /// Prepare a speed-up transaction (same nonce, higher gas)
    func prepareSpeedUp(
        originalNonce: UInt64,
        recipient: String,
        amount: UInt64,
        originalGasPrice: UInt64,
        walletId: UUID,
        data: Data? = nil
    ) async throws -> SignedTransaction {
        // Increase gas price by 10% minimum (required for replacement)
        let newGasPrice = originalGasPrice * 110 / 100
        
        return try await prepareTransaction(
            recipient: recipient,
            amount: amount,
            nonce: originalNonce,
            gasPrice: newGasPrice,
            walletId: walletId,
            data: data
        )
    }
    
    /// Prepare a cancellation transaction (0 value to self)
    func prepareCancellation(
        senderAddress: String,
        originalNonce: UInt64,
        originalGasPrice: UInt64,
        walletId: UUID
    ) async throws -> SignedTransaction {
        // Send 0 wei to self with higher gas
        let newGasPrice = originalGasPrice * 110 / 100
        
        return try await prepareTransaction(
            recipient: senderAddress,
            amount: 0,
            nonce: originalNonce,
            gasPrice: newGasPrice,
            walletId: walletId
        )
    }
}

// MARK: - EthereumTransaction Extension

extension EthereumTransaction {
    /// Build and sign an EIP-1559 transaction (Type 2)
    /// EIP-1559 is the preferred format for post-London networks (Ethereum mainnet, Sepolia)
    static func buildAndSignEIP1559(
        to recipient: String,
        value: String,
        gasLimit: Int,
        maxFeePerGas: String,
        maxPriorityFeePerGas: String,
        nonce: Int,
        chainId: Int,
        privateKeyHex: String,
        data: String = "0x"
    ) throws -> String {
        // Use EIP-1559 transaction format - pass maxFeePerGas and maxPriorityFeePerGas to Rust FFI
        return try RustService.shared.signEthereumThrowing(
            recipient: recipient,
            amountWei: value,
            chainId: UInt64(chainId),
            senderKey: privateKeyHex,
            nonce: UInt64(nonce),
            gasLimit: UInt64(gasLimit),
            gasPrice: nil, // Not used for EIP-1559
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            data: data.isEmpty ? "" : data
        )
    }
}

// Note: Data.hexString extension is defined in BitcoinTransaction.swift
