import Foundation

// MARK: - Multisig Models

/// Configuration for a multisig wallet
struct MultisigConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    let requiredSignatures: Int // M in M-of-N
    let totalSigners: Int // N in M-of-N
    var publicKeys: [String] // Public keys of all signers
    let createdAt: Date
    var address: String? // Generated multisig address
    var redeemScript: String? // For P2SH
    var witnessScript: String? // For P2WSH
    let isTestnet: Bool
    
    var description: String {
        "\(requiredSignatures)-of-\(totalSigners) Multisig"
    }
    
    var isComplete: Bool {
        publicKeys.count == totalSigners && address != nil
    }
}

/// A partially signed Bitcoin transaction
struct PSBT: Identifiable, Codable {
    let id: UUID
    let multisigId: UUID
    var rawPSBT: String // Base64 encoded PSBT
    var signatures: [String: String] // pubkey -> signature
    let createdAt: Date
    var status: PSBTStatus
    let amount: Int64 // Satoshis
    let recipient: String
    let fee: Int64
    
    enum PSBTStatus: String, Codable {
        case pending
        case partiallySign
        case readyToBroadcast
        case broadcast
        case failed
    }
    
    var signatureCount: Int {
        signatures.count
    }
}

/// Public key info for a signer
struct SignerInfo: Identifiable, Codable {
    let id: UUID
    var name: String
    let publicKey: String
    let fingerprint: String? // Master key fingerprint
    let derivationPath: String?
    let isLocalKey: Bool // Whether we have the private key
}

// MARK: - Multisig Manager

@MainActor
class MultisigManager: ObservableObject {
    static let shared = MultisigManager()
    
    @Published var wallets: [MultisigConfig] = []
    @Published var pendingPSBTs: [PSBT] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let userDefaults = UserDefaults.standard
    private let walletsKey = "multisigWallets"
    private let psbtsKey = "pendingPSBTs"
    
    private init() {
        loadWallets()
        loadPSBTs()
    }
    
    // MARK: - Wallet Management
    
    /// Create a new multisig wallet configuration
    func createWallet(
        name: String,
        requiredSignatures: Int,
        totalSigners: Int,
        isTestnet: Bool = false
    ) -> MultisigConfig {
        let wallet = MultisigConfig(
            id: UUID(),
            name: name,
            requiredSignatures: requiredSignatures,
            totalSigners: totalSigners,
            publicKeys: [],
            createdAt: Date(),
            address: nil,
            redeemScript: nil,
            witnessScript: nil,
            isTestnet: isTestnet
        )
        wallets.append(wallet)
        saveWallets()
        return wallet
    }
    
    /// Add a public key to a multisig wallet
    func addPublicKey(_ pubKey: String, to walletId: UUID) throws {
        guard let index = wallets.firstIndex(where: { $0.id == walletId }) else {
            throw MultisigError.walletNotFound
        }
        
        guard wallets[index].publicKeys.count < wallets[index].totalSigners else {
            throw MultisigError.tooManyKeys
        }
        
        // Validate public key format (33 bytes compressed or 65 uncompressed)
        guard isValidPublicKey(pubKey) else {
            throw MultisigError.invalidPublicKey
        }
        
        // Check for duplicates
        guard !wallets[index].publicKeys.contains(pubKey) else {
            throw MultisigError.duplicateKey
        }
        
        wallets[index].publicKeys.append(pubKey)
        
        // If we have all keys, generate the address
        if wallets[index].publicKeys.count == wallets[index].totalSigners {
            try generateMultisigAddress(for: &wallets[index])
        }
        
        saveWallets()
    }
    
    /// Generate the multisig address from public keys
    private func generateMultisigAddress(for wallet: inout MultisigConfig) throws {
        // Sort public keys lexicographically (BIP-67)
        let sortedKeys = wallet.publicKeys.sorted()
        
        // Build redeem script: OP_M <pubkey1> <pubkey2> ... <pubkeyN> OP_N OP_CHECKMULTISIG
        var redeemScript = Data()
        
        // OP_M (0x51 = OP_1, 0x52 = OP_2, etc.)
        redeemScript.append(UInt8(0x50 + wallet.requiredSignatures))
        
        // Add public keys
        for pubKeyHex in sortedKeys {
            guard let pubKeyData = Data(hexString: pubKeyHex) else {
                throw MultisigError.invalidPublicKey
            }
            redeemScript.append(UInt8(pubKeyData.count)) // Push length
            redeemScript.append(pubKeyData)
        }
        
        // OP_N
        redeemScript.append(UInt8(0x50 + wallet.totalSigners))
        
        // OP_CHECKMULTISIG (0xAE)
        redeemScript.append(0xAE)
        
        wallet.redeemScript = redeemScript.hexEncodedString()
        
        // Generate P2WSH address (native segwit multisig)
        let witnessScript = redeemScript
        wallet.witnessScript = witnessScript.hexEncodedString()
        
        // SHA256 of witness script
        let scriptHash = sha256(witnessScript)
        
        // Generate bech32 address
        let hrp = wallet.isTestnet ? "tb" : "bc"
        let address = try encodeBech32(hrp: hrp, witnessVersion: 0, witnessProgram: scriptHash)
        
        wallet.address = address
    }
    
    /// Validate a public key format
    private func isValidPublicKey(_ hex: String) -> Bool {
        guard let data = Data(hexString: hex) else { return false }
        // Compressed: 33 bytes starting with 02 or 03
        // Uncompressed: 65 bytes starting with 04
        if data.count == 33 && (data[0] == 0x02 || data[0] == 0x03) {
            return true
        }
        if data.count == 65 && data[0] == 0x04 {
            return true
        }
        return false
    }
    
    /// Delete a multisig wallet
    func deleteWallet(_ wallet: MultisigConfig) {
        wallets.removeAll { $0.id == wallet.id }
        pendingPSBTs.removeAll { $0.multisigId == wallet.id }
        saveWallets()
        savePSBTs()
    }
    
    // MARK: - PSBT Management
    
    /// Create a new PSBT for a multisig wallet
    func createPSBT(
        walletId: UUID,
        recipient: String,
        amountSats: Int64,
        feeSats: Int64,
        utxos: [UTXO]
    ) throws -> PSBT {
        guard let wallet = wallets.first(where: { $0.id == walletId }) else {
            throw MultisigError.walletNotFound
        }
        
        guard wallet.isComplete else {
            throw MultisigError.walletIncomplete
        }
        
        // Build unsigned transaction
        let psbtData = try buildUnsignedPSBT(
            wallet: wallet,
            recipient: recipient,
            amountSats: amountSats,
            feeSats: feeSats,
            utxos: utxos
        )
        
        let psbt = PSBT(
            id: UUID(),
            multisigId: walletId,
            rawPSBT: psbtData.base64EncodedString(),
            signatures: [:],
            createdAt: Date(),
            status: .pending,
            amount: amountSats,
            recipient: recipient,
            fee: feeSats
        )
        
        pendingPSBTs.append(psbt)
        savePSBTs()
        
        return psbt
    }
    
    /// Build an unsigned PSBT
    private func buildUnsignedPSBT(
        wallet: MultisigConfig,
        recipient: String,
        amountSats: Int64,
        feeSats: Int64,
        utxos: [UTXO]
    ) throws -> Data {
        // PSBT format: https://github.com/bitcoin/bips/blob/master/bip-0174.mediawiki
        // This is a simplified implementation
        
        var psbt = Data()
        
        // Magic bytes: "psbt" + 0xff
        psbt.append(contentsOf: [0x70, 0x73, 0x62, 0x74, 0xff])
        
        // Global map (unsigned tx)
        // Key: 0x00 (unsigned tx)
        psbt.append(0x01) // Key length
        psbt.append(0x00) // PSBT_GLOBAL_UNSIGNED_TX
        
        // Build unsigned transaction
        let unsignedTx = try buildUnsignedTransaction(
            recipient: recipient,
            amountSats: amountSats,
            feeSats: feeSats,
            utxos: utxos,
            changeAddress: wallet.address ?? ""
        )
        
        // Value: serialized unsigned tx
        let txData = unsignedTx
        psbt.append(contentsOf: encodeVarInt(txData.count))
        psbt.append(txData)
        
        // Separator
        psbt.append(0x00)
        
        // Input maps (one per input)
        for utxo in utxos {
            // Witness UTXO
            psbt.append(0x01) // Key length
            psbt.append(0x01) // PSBT_IN_WITNESS_UTXO
            
            var witnessUtxo = Data()
            // Value (8 bytes LE)
            var value = UInt64(utxo.value)
            witnessUtxo.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
            // Script pubkey
            if let scriptPubKey = Data(hexString: utxo.scriptPubKey) {
                witnessUtxo.append(contentsOf: encodeVarInt(scriptPubKey.count))
                witnessUtxo.append(scriptPubKey)
            }
            
            psbt.append(contentsOf: encodeVarInt(witnessUtxo.count))
            psbt.append(witnessUtxo)
            
            // Witness script
            if let witnessScript = wallet.witnessScript, let scriptData = Data(hexString: witnessScript) {
                psbt.append(0x01)
                psbt.append(0x05) // PSBT_IN_WITNESS_SCRIPT
                psbt.append(contentsOf: encodeVarInt(scriptData.count))
                psbt.append(scriptData)
            }
            
            // Separator
            psbt.append(0x00)
        }
        
        // Output maps (simplified - just separators)
        psbt.append(0x00) // Recipient output
        psbt.append(0x00) // Change output (if any)
        
        return psbt
    }
    
    /// Build an unsigned transaction
    private func buildUnsignedTransaction(
        recipient: String,
        amountSats: Int64,
        feeSats: Int64,
        utxos: [UTXO],
        changeAddress: String
    ) throws -> Data {
        var tx = Data()
        
        // Version (4 bytes LE)
        var version: UInt32 = 2
        tx.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })
        
        // Marker and flag for segwit (not in unsigned)
        
        // Input count
        tx.append(contentsOf: encodeVarInt(utxos.count))
        
        // Inputs
        for utxo in utxos {
            // Previous outpoint (32 bytes txid + 4 bytes vout)
            if let txidData = Data(hexString: utxo.txid)?.reversed() {
                tx.append(contentsOf: txidData)
            }
            var vout = UInt32(utxo.vout)
            tx.append(contentsOf: withUnsafeBytes(of: &vout) { Array($0) })
            
            // Script sig (empty for unsigned)
            tx.append(0x00)
            
            // Sequence
            var sequence: UInt32 = 0xfffffffd // RBF enabled
            tx.append(contentsOf: withUnsafeBytes(of: &sequence) { Array($0) })
        }
        
        // Calculate change
        let totalInput = utxos.reduce(0) { $0 + $1.value }
        let change = totalInput - amountSats - feeSats
        
        // Output count
        let outputCount = change > 546 ? 2 : 1 // Include change if > dust
        tx.append(contentsOf: encodeVarInt(outputCount))
        
        // Recipient output
        var amount = UInt64(amountSats)
        tx.append(contentsOf: withUnsafeBytes(of: &amount) { Array($0) })
        let recipientScript = try addressToScriptPubKey(recipient)
        tx.append(contentsOf: encodeVarInt(recipientScript.count))
        tx.append(recipientScript)
        
        // Change output
        if change > 546 {
            var changeAmount = UInt64(change)
            tx.append(contentsOf: withUnsafeBytes(of: &changeAmount) { Array($0) })
            let changeScript = try addressToScriptPubKey(changeAddress)
            tx.append(contentsOf: encodeVarInt(changeScript.count))
            tx.append(changeScript)
        }
        
        // Locktime
        var locktime: UInt32 = 0
        tx.append(contentsOf: withUnsafeBytes(of: &locktime) { Array($0) })
        
        return tx
    }
    
    /// Convert an address to scriptPubKey
    private func addressToScriptPubKey(_ address: String) throws -> Data {
        // Detect address type and convert
        if address.lowercased().hasPrefix("bc1") || address.lowercased().hasPrefix("tb1") {
            // Bech32 address
            let (_, witnessProgram) = try decodeBech32(address)
            if witnessProgram.count == 20 {
                // P2WPKH: OP_0 <20 bytes>
                var script = Data([0x00, 0x14])
                script.append(witnessProgram)
                return script
            } else if witnessProgram.count == 32 {
                // P2WSH: OP_0 <32 bytes>
                var script = Data([0x00, 0x20])
                script.append(witnessProgram)
                return script
            }
        }
        
        throw MultisigError.unsupportedAddressType
    }
    
    /// Add a signature to a PSBT
    func addSignature(psbtId: UUID, pubKey: String, signature: String) throws {
        guard let index = pendingPSBTs.firstIndex(where: { $0.id == psbtId }) else {
            throw MultisigError.psbtNotFound
        }
        
        pendingPSBTs[index].signatures[pubKey] = signature
        
        // Check if we have enough signatures
        if let wallet = wallets.first(where: { $0.id == pendingPSBTs[index].multisigId }) {
            if pendingPSBTs[index].signatures.count >= wallet.requiredSignatures {
                pendingPSBTs[index].status = .readyToBroadcast
            } else {
                pendingPSBTs[index].status = .partiallySign
            }
        }
        
        savePSBTs()
    }
    
    /// Export PSBT as base64 for sharing
    func exportPSBT(_ psbt: PSBT) -> String {
        psbt.rawPSBT
    }
    
    /// Import a PSBT from base64
    func importPSBT(_ base64: String, for walletId: UUID) throws -> PSBT {
        guard Data(base64Encoded: base64) != nil else {
            throw MultisigError.invalidPSBT
        }
        
        // Parse and validate PSBT
        // This is simplified - real implementation would parse the PSBT format
        
        let psbt = PSBT(
            id: UUID(),
            multisigId: walletId,
            rawPSBT: base64,
            signatures: [:],
            createdAt: Date(),
            status: .pending,
            amount: 0,
            recipient: "",
            fee: 0
        )
        
        pendingPSBTs.append(psbt)
        savePSBTs()
        
        return psbt
    }
    
    // MARK: - Persistence
    
    private func loadWallets() {
        if let data = userDefaults.data(forKey: walletsKey),
           let loaded = try? JSONDecoder().decode([MultisigConfig].self, from: data) {
            wallets = loaded
        }
    }
    
    private func saveWallets() {
        if let data = try? JSONEncoder().encode(wallets) {
            userDefaults.set(data, forKey: walletsKey)
        }
    }
    
    private func loadPSBTs() {
        if let data = userDefaults.data(forKey: psbtsKey),
           let loaded = try? JSONDecoder().decode([PSBT].self, from: data) {
            pendingPSBTs = loaded
        }
    }
    
    private func savePSBTs() {
        if let data = try? JSONEncoder().encode(pendingPSBTs) {
            userDefaults.set(data, forKey: psbtsKey)
        }
    }
    
    // MARK: - Crypto Helpers
    
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    private func encodeVarInt(_ value: Int) -> [UInt8] {
        if value < 0xfd {
            return [UInt8(value)]
        } else if value <= 0xffff {
            return [0xfd, UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
        } else if value <= 0xffffffff {
            return [0xfe] + withUnsafeBytes(of: UInt32(value).littleEndian) { Array($0) }
        } else {
            return [0xff] + withUnsafeBytes(of: UInt64(value).littleEndian) { Array($0) }
        }
    }
    
    private func encodeBech32(hrp: String, witnessVersion: Int, witnessProgram: Data) throws -> String {
        // Simplified bech32 encoding
        // Real implementation would use proper bech32 encoding
        let programHex = witnessProgram.hexEncodedString()
        return "\(hrp)1q\(programHex.prefix(38))"
    }
    
    private func decodeBech32(_ address: String) throws -> (Int, Data) {
        // Simplified - extract witness program
        // Real implementation would properly decode bech32
        guard address.count > 4 else {
            throw MultisigError.invalidAddress
        }
        
        // For now, just return placeholder
        return (0, Data(repeating: 0, count: 32))
    }
}

// MARK: - Supporting Types

struct UTXO: Codable {
    let txid: String
    let vout: Int
    let value: Int64
    let scriptPubKey: String
}

// MARK: - Errors

enum MultisigError: LocalizedError {
    case walletNotFound
    case walletIncomplete
    case invalidPublicKey
    case duplicateKey
    case tooManyKeys
    case psbtNotFound
    case invalidPSBT
    case unsupportedAddressType
    case invalidAddress
    case insufficientSignatures
    
    var errorDescription: String? {
        switch self {
        case .walletNotFound: return "Multisig wallet not found"
        case .walletIncomplete: return "Wallet setup is incomplete"
        case .invalidPublicKey: return "Invalid public key format"
        case .duplicateKey: return "Public key already added"
        case .tooManyKeys: return "All signers already added"
        case .psbtNotFound: return "PSBT not found"
        case .invalidPSBT: return "Invalid PSBT format"
        case .unsupportedAddressType: return "Unsupported address type"
        case .invalidAddress: return "Invalid address"
        case .insufficientSignatures: return "Not enough signatures"
        }
    }
}

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
    
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// CommonCrypto import
import CommonCrypto
