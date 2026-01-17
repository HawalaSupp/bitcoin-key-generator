import Foundation

enum RustCLIError: Error {
    case binaryNotFound
    case executionFailed(Int, String)
    case outputParsingFailed
    case invalidInput
}

final class RustCLIBridge: Sendable {
    static let shared = RustCLIBridge()
    
    private let binaryPath: String?
    
    private init() {
        // Try to locate the binary
        // Priority: absolute path first (most reliable), then relative paths
        
        let possiblePaths = [
            // Absolute path - most reliable
            "/Users/x/Desktop/888/rust-app/target/debug/rust-app",
            "/Users/x/Desktop/888/rust-app/target/release/rust-app",
            // Relative paths from swift-app directory
            "../rust-app/target/debug/rust-app",
            "../rust-app/target/release/rust-app"
        ]
        
        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }
        
        self.binaryPath = foundPath
        
        #if DEBUG
        if let path = self.binaryPath {
            print("✅ Found Rust binary at: \(path)")
        } else {
            print("⚠️ Warning: Rust binary not found. Please run 'cargo build' in rust-app directory.")
            print("   Searched paths: \(possiblePaths)")
        }
        #endif
    }
    
    private func runCommand(args: [String]) throws -> String {
        guard let binaryPath = binaryPath else {
            throw RustCLIError.binaryNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
        } catch {
            throw RustCLIError.executionFailed(-1, "Failed to launch process: \(error)")
        }
        
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Log stderr for debugging but don't include in output
        if let stderrOutput = String(data: stderrData, encoding: .utf8), !stderrOutput.isEmpty {
            #if DEBUG
            print("[Rust stderr] \(stderrOutput)")
            #endif
        }
        
        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw RustCLIError.outputParsingFailed
        }
        
        if process.terminationStatus != 0 {
            let errorOutput = String(data: stderrData, encoding: .utf8) ?? output
            throw RustCLIError.executionFailed(Int(process.terminationStatus), errorOutput)
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Key Generation
    
    struct KeysOutput: Codable {
        let mnemonic: String?
        let keys: AllKeys
    }
    
    struct AllKeys: Codable {
        let bitcoin: BitcoinKeys
        let bitcoin_testnet: BitcoinKeys
        let ethereum: EthereumKeys
        let solana: SolanaKeys
        let monero: MoneroKeys
        let xrp: XRPKeys
    }
    
    struct BitcoinKeys: Codable {
        let private_wif: String
        let address: String
        // Taproot (P2TR) fields
        let taproot_address: String?
        let x_only_pubkey: String?
    }
    
    struct EthereumKeys: Codable {
        let private_hex: String
        let address: String
    }
    
    struct SolanaKeys: Codable {
        let private_key_base58: String
        let public_key_base58: String
    }
    
    struct MoneroKeys: Codable {
        let private_spend_hex: String
        let private_view_hex: String
        let address: String
    }
    
    struct XRPKeys: Codable {
        let private_hex: String
        let classic_address: String
    }
    
    // Helper structs for Rust interop
    struct RustUTXO: Codable {
        let txid: String
        let vout: UInt32
        let value: UInt64
        let status: RustUTXOStatus
    }
    
    struct RustUTXOStatus: Codable {
        let confirmed: Bool
        let block_height: UInt32?
        let block_hash: String?
        let block_time: UInt64?
    }
    
    func generateKeys(mnemonic: String) throws -> AllKeys {
        let args = ["gen-keys", "--mnemonic", mnemonic, "--json"]
        let jsonString = try runCommand(args: args)
        
        guard let data = jsonString.data(using: .utf8) else {
            throw RustCLIError.outputParsingFailed
        }
        
        let output = try JSONDecoder().decode(KeysOutput.self, from: data)
        return output.keys
    }

    // MARK: - Bitcoin
    
    func signBitcoin(recipient: String, amountSats: UInt64, feeRate: UInt64, senderWIF: String, utxos: [RustUTXO]? = nil) throws -> String {
        var args = [
            "sign-btc",
            "--recipient", recipient,
            "--amount-sats", String(amountSats),
            "--fee-rate", String(feeRate),
            "--sender-wif", senderWIF
        ]
        
        if let utxos = utxos {
            let encoder = JSONEncoder()
            let data = try encoder.encode(utxos)
            if let jsonString = String(data: data, encoding: .utf8) {
                args.append("--utxos")
                args.append(jsonString)
            }
        }
        
        return try runCommand(args: args)
    }
    
    /// Sign a Taproot (P2TR) transaction - ~7% fee savings via Schnorr signatures
    func signBitcoinTaproot(recipient: String, amountSats: UInt64, feeRate: UInt64, senderWIF: String, utxos: [RustUTXO]? = nil) throws -> String {
        // Build JSON request for Taproot FFI
        struct TaprootRequest: Encodable {
            let recipient: String
            let amount_sats: UInt64
            let fee_rate: UInt64
            let sender_wif: String
            let utxos: [RustUTXO]?
        }
        
        let request = TaprootRequest(
            recipient: recipient,
            amount_sats: amountSats,
            fee_rate: feeRate,
            sender_wif: senderWIF,
            utxos: utxos
        )
        
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        guard let requestJson = String(data: requestData, encoding: .utf8) else {
            throw RustCLIError.invalidInput
        }
        
        // Call FFI via RustService
        let result = RustService.shared.prepareTaprootTransaction(jsonInput: requestJson)
        
        // Parse result
        struct TaprootResponse: Decodable {
            let success: Bool?
            let tx_hex: String?
            let error: String?
        }
        
        guard let resultData = result.data(using: .utf8) else {
            throw RustCLIError.outputParsingFailed
        }
        
        let response = try JSONDecoder().decode(TaprootResponse.self, from: resultData)
        
        if let error = response.error {
            throw RustCLIError.executionFailed(-1, error)
        }
        
        guard let txHex = response.tx_hex else {
            throw RustCLIError.outputParsingFailed
        }
        
        return txHex
    }
    
    // MARK: - Ethereum
    
    func signEthereum(recipient: String, amountWei: String, chainId: UInt64, senderKey: String, nonce: UInt64, gasLimit: UInt64, gasPrice: String? = nil, maxFeePerGas: String? = nil, maxPriorityFeePerGas: String? = nil, data: String = "") throws -> String {
        var args = [
            "sign-eth",
            "--recipient", recipient,
            "--amount-wei", amountWei,
            "--chain-id", String(chainId),
            "--sender-key", senderKey,
            "--nonce", String(nonce),
            "--gas-limit", String(gasLimit)
        ]
        
        if let gasPrice = gasPrice {
            args.append("--gas-price")
            args.append(gasPrice)
        }
        
        if let maxFee = maxFeePerGas {
            args.append("--max-fee-per-gas")
            args.append(maxFee)
        }
        
        if let priorityFee = maxPriorityFeePerGas {
            args.append("--max-priority-fee-per-gas")
            args.append(priorityFee)
        }
        
        if !data.isEmpty {
            args.append("--data")
            args.append(data)
        }
        
        return try runCommand(args: args)
    }
    
    // MARK: - Solana
    
    func signSolana(recipient: String, amountSol: Double, recentBlockhash: String, senderBase58: String) throws -> String {
        let args = [
            "sign-sol",
            "--recipient", recipient,
            "--amount-sol", String(amountSol),
            "--recent-blockhash", recentBlockhash,
            "--sender-base58", senderBase58
        ]
        return try runCommand(args: args)
    }
    
    // MARK: - Monero
    
    func signMonero(recipient: String, amountXmr: Double, senderSpendHex: String, senderViewHex: String) throws -> String {
        let args = [
            "sign-xmr",
            "--recipient", recipient,
            "--amount-xmr", String(amountXmr),
            "--sender-spend-hex", senderSpendHex,
            "--sender-view-hex", senderViewHex
        ]
        return try runCommand(args: args)
    }
    
    // MARK: - XRP
    
    func signXRP(recipient: String, amountDrops: UInt64, senderSeedHex: String, sequence: UInt32, destinationTag: UInt32? = nil) throws -> String {
        var args = [
            "sign-xrp",
            "--recipient", recipient,
            "--amount-drops", String(amountDrops),
            "--sender-seed-hex", senderSeedHex,
            "--sequence", String(sequence)
        ]
        
        if let tag = destinationTag {
            args.append(contentsOf: ["--destination-tag", String(tag)])
        }
        
        return try runCommand(args: args)
    }
    
    // MARK: - Litecoin
    
    func signLitecoin(recipient: String, amountLits: UInt64, feeRate: UInt64, senderWIF: String, senderAddress: String, utxos: [RustUTXO]? = nil) throws -> String {
        var args = [
            "sign-ltc",
            "--recipient", recipient,
            "--amount-lits", String(amountLits),
            "--fee-rate", String(feeRate),
            "--sender-wif", senderWIF,
            "--sender-address", senderAddress
        ]
        
        if let utxos = utxos {
            let encoder = JSONEncoder()
            let data = try encoder.encode(utxos)
            if let jsonString = String(data: data, encoding: .utf8) {
                args.append("--utxos")
                args.append(jsonString)
            }
        }
        
        return try runCommand(args: args)
    }
}
