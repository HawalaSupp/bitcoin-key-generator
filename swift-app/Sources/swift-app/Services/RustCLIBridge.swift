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
        // Try to locate the binary relative to the current working directory
        // When running via `swift run`, we are in the package root.
        // The binary is in ../rust-app/target/debug/rust-app
        
        let possiblePaths = [
            "../rust-app/target/debug/rust-app",
            "../rust-app/target/release/rust-app",
            "./rust-app",
            "/Users/x/Desktop/888/rust-app/target/debug/rust-app" // Fallback absolute path for this environment
        ]
        
        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }
        
        self.binaryPath = foundPath
        
        if let path = self.binaryPath {
            print("Found Rust binary at: \(path)")
        } else {
            print("Warning: Rust binary not found in expected locations.")
        }
    }
    
    private func runCommand(args: [String]) throws -> String {
        guard let binaryPath = binaryPath else {
            throw RustCLIError.binaryNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
        } catch {
            throw RustCLIError.executionFailed(-1, "Failed to launch process: \(error)")
        }
        
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw RustCLIError.outputParsingFailed
        }
        
        if process.terminationStatus != 0 {
            throw RustCLIError.executionFailed(Int(process.terminationStatus), output)
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
    
    func signBitcoin(recipient: String, amountSats: UInt64, feeRate: UInt64, senderWIF: String) throws -> String {
        let args = [
            "sign-btc",
            "--recipient", recipient,
            "--amount-sats", String(amountSats),
            "--fee-rate", String(feeRate),
            "--sender-wif", senderWIF
        ]
        return try runCommand(args: args)
    }
    
    // MARK: - Ethereum
    
    func signEthereum(recipient: String, amountWei: String, chainId: UInt64, senderKey: String, nonce: UInt64, gasLimit: UInt64, gasPrice: String, data: String = "") throws -> String {
        var args = [
            "sign-eth",
            "--recipient", recipient,
            "--amount-wei", amountWei,
            "--chain-id", String(chainId),
            "--sender-key", senderKey,
            "--nonce", String(nonce),
            "--gas-limit", String(gasLimit),
            "--gas-price", gasPrice
        ]
        
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
    
    func signXRP(recipient: String, amountDrops: UInt64, senderSeedHex: String, sequence: UInt32) throws -> String {
        let args = [
            "sign-xrp",
            "--recipient", recipient,
            "--amount-drops", String(amountDrops),
            "--sender-seed-hex", senderSeedHex,
            "--sequence", String(sequence)
        ]
        return try runCommand(args: args)
    }
}
