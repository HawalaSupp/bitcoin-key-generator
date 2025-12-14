import Foundation

// MARK: - Bitcoin Transaction Signer

/// Signer for Bitcoin and Litecoin transactions.
/// Uses the existing BitcoinTransactionBuilder for signing.
@MainActor
final class BitcoinTransactionSigner: TransactionSigner {
    
    let chainId: ChainIdentifier
    private let signerManager: TransactionSignerManager
    
    init(chainId: ChainIdentifier) {
        precondition(
            [.bitcoin, .bitcoinTestnet, .litecoin].contains(chainId),
            "BitcoinTransactionSigner only supports Bitcoin and Litecoin"
        )
        self.chainId = chainId
        self.signerManager = .shared
    }
    
    // MARK: - TransactionSigner Protocol
    
    func sign(
        unsignedTx: UnsignedTransaction,
        context: SigningContext
    ) async throws -> SignedTransaction {
        // Validate chain
        guard [.bitcoin, .bitcoinTestnet, .litecoin].contains(unsignedTx.chainId) else {
            throw TransactionSignerError.unsupportedChain(unsignedTx.chainId)
        }
        
        // Get UTXO inputs
        guard case .utxo(let utxoInputs) = unsignedTx.inputs else {
            throw TransactionSignerError.invalidInputs("Bitcoin requires UTXO inputs")
        }
        
        // Validate UTXOs
        guard !utxoInputs.utxos.isEmpty else {
            throw TransactionSignerError.invalidInputs("No UTXOs provided")
        }
        
        // Calculate totals
        let totalInput = utxoInputs.utxos.reduce(Int64(0)) { $0 + $1.value }
        let amount = Int64(unsignedTx.amount)
        
        // Estimate transaction size and fee
        let inputCount = utxoInputs.utxos.count
        let outputCount = 2 // recipient + change (simplified)
        let estimatedVsize = estimateVsize(inputCount: inputCount, outputCount: outputCount)
        let fee = Int64(estimatedVsize) * utxoInputs.feeRate
        
        // Check sufficient funds
        guard totalInput >= amount + fee else {
            throw TransactionSignerError.insufficientFunds(
                available: UInt64(totalInput),
                required: UInt64(amount + fee)
            )
        }
        
        // Calculate change
        let change = totalInput - amount - fee
        let dustLimit: Int64 = 546 // Satoshis
        
        // Retrieve signing keys
        let keys = try await signerManager.retrieveKeys(
            walletId: context.walletId,
            chain: chainId
        )
        
        // Get WIF for the appropriate chain
        let wif: String
        let isTestnet: Bool
        
        switch chainId {
        case .bitcoin:
            wif = keys.bitcoin.wif ?? ""
            isTestnet = false
        case .bitcoinTestnet:
            wif = keys.bitcoinTestnet.wif ?? ""
            isTestnet = true
        case .litecoin:
            wif = keys.litecoin.wif ?? ""
            isTestnet = false
        default:
            throw TransactionSignerError.unsupportedChain(chainId)
        }
        
        guard !wif.isEmpty else {
            throw TransactionSignerError.keyDerivationFailed
        }
        
        // Convert inputs to builder format
        let builderInputs = utxoInputs.utxos.map { utxo in
            BitcoinTransactionBuilder.Input(
                txid: utxo.txid,
                vout: utxo.vout,
                value: utxo.value,
                scriptPubKey: utxo.scriptPubKey
            )
        }
        
        // Build outputs
        var builderOutputs: [BitcoinTransactionBuilder.Output] = [
            BitcoinTransactionBuilder.Output(
                address: unsignedTx.to,
                value: amount
            )
        ]
        
        // Add change output if above dust
        if change > dustLimit {
            let changeAddress = utxoInputs.changeAddress ?? utxoInputs.utxos.first?.address ?? ""
            guard !changeAddress.isEmpty else {
                throw TransactionSignerError.invalidInputs("No change address available")
            }
            builderOutputs.append(
                BitcoinTransactionBuilder.Output(
                    address: changeAddress,
                    value: change
                )
            )
        }
        
        // Sign transaction using the existing builder
        do {
            let signedTx = try BitcoinTransactionBuilder.buildAndSign(
                inputs: builderInputs,
                outputs: builderOutputs,
                privateKeyWIF: wif,
                isTestnet: isTestnet
            )
            
            return SignedTransaction(
                chainId: chainId,
                txid: signedTx.txid,
                rawHex: signedTx.rawHex,
                size: signedTx.size,
                vsize: signedTx.vsize,
                fee: UInt64(fee)
            )
        } catch {
            throw TransactionSignerError.signingFailed(error)
        }
    }
    
    func canSign(forAddress address: String) async -> Bool {
        // Check if we have keys for this address
        // In a real implementation, we'd check against stored addresses
        return true
    }
    
    // MARK: - Helpers
    
    /// Estimate virtual size for fee calculation
    private func estimateVsize(inputCount: Int, outputCount: Int) -> Int {
        // P2WPKH SegWit transaction vsize estimation
        // Base: 10.5 vB
        // Per input: ~68 vB (SegWit witness discount)
        // Per output: ~31 vB
        let base = 10
        let perInput = 68
        let perOutput = 31
        return base + (inputCount * perInput) + (outputCount * perOutput)
    }
}

// MARK: - Bitcoin Send Flow Helper

/// High-level helper for the send flow
@MainActor
final class BitcoinSendFlow: ObservableObject {
    
    @Published var isLoading = false
    @Published var error: Error?
    @Published var signedTransaction: SignedTransaction?
    
    private let signer: BitcoinTransactionSigner
    private let utxoStore: UTXOStore
    private let feeService: FeeEstimationService
    
    init(chainId: ChainIdentifier) {
        self.signer = BitcoinTransactionSigner(chainId: chainId)
        self.utxoStore = UTXOStore.shared
        self.feeService = FeeEstimationService.shared
    }
    
    /// Prepare and sign a Bitcoin transaction
    /// - Parameters:
    ///   - recipient: Destination address
    ///   - amount: Amount in satoshis
    ///   - feeRate: Fee rate in sat/vB (or nil to use suggested rate)
    ///   - walletId: Wallet ID for key lookup
    ///   - changeAddress: Change address (or nil to use sender's address)
    /// - Returns: Signed transaction ready for broadcast
    func prepareTransaction(
        recipient: String,
        amount: UInt64,
        feeRate: Int64? = nil,
        walletId: UUID,
        changeAddress: String?
    ) async throws -> SignedTransaction {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Get fee rate if not provided
            let effectiveFeeRate: Int64
            if let feeRate = feeRate {
                effectiveFeeRate = feeRate
            } else {
                await feeService.refreshAll()
                effectiveFeeRate = Int64(feeService.bitcoinFees?.medium.satPerByte ?? 10)
            }
            
            // Get UTXOs for selection
            // Note: This needs walletId mapping to address - simplified for now
            let chainId = signer.chainId.rawValue
            let utxos = try await utxoStore.fetchUnspent(
                walletId: walletId.uuidString,
                chainId: chainId
            )
            
            guard !utxos.isEmpty else {
                throw TransactionSignerError.invalidInputs("No UTXOs available")
            }
            
            // Convert to UTXO inputs
            let utxoInputs = utxos.map { record in
                UTXOInput(
                    txid: record.txHash,
                    vout: UInt32(record.outputIndex),
                    value: record.amount,
                    scriptPubKey: Data(hex: record.scriptPubKey) ?? Data(),
                    address: record.address
                )
            }
            
            // Create unsigned transaction
            let unsignedTx = UnsignedTransaction(
                chainId: signer.chainId,
                to: recipient,
                amount: amount,
                inputs: .utxo(UTXOInputs(
                    utxos: utxoInputs,
                    feeRate: effectiveFeeRate,
                    changeAddress: changeAddress,
                    rbfEnabled: true
                ))
            )
            
            // Sign
            let context = SigningContext(
                isTestnet: signer.chainId == .bitcoinTestnet,
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
}
