import XCTest
import Foundation

final class IntegrationTests: XCTestCase {
    
    // Known test vector
    // Mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    // Seed: ...
    // Expected Addresses:
    // Bitcoin (Bech32): bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
    // Ethereum: 0x9858EfFD232B4033E47d90003D41aca026742726
    // Solana: ... (need to verify)
    
    let testMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    
    // Expected values derived from standard tools (e.g. iancoleman.io)
    // Path m/84'/0'/0'/0/0
    let expectedBitcoinAddress = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
    
    // Path m/44'/60'/0'/0/0 (Standard ETH) - Note: Our Rust app might use a different path or derivation
    // Let's check rust-app/src/lib.rs for derivation paths.
    // Bitcoin: m/84'/0'/0'/0/0 -> Correct
    // Ethereum: m/44'/60'/0'/0/0 -> Let's verify in lib.rs
    
    func testRustCLIIntegration() throws {
        // 1. Locate the binary
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        // Assuming we are running from the project root or swift-app folder
        // We need to find rust-app/target/debug/rust-app
        
        // Try to find the binary relative to the test execution
        // We'll try a few common paths relative to the workspace root.
        
        let possiblePaths = [
            "../rust-app/target/debug/rust-app",
            "rust-app/target/debug/rust-app",
            "/Users/x/Desktop/888/rust-app/target/debug/rust-app" // Absolute path for certainty in this env
        ]
        
        var binaryURL: URL?
        for path in possiblePaths {
            let url: URL
            if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path)
            } else {
                let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                url = currentDirectory.appendingPathComponent(path).standardized
            }
            
            if fileManager.fileExists(atPath: url.path) {
                binaryURL = url
                print("Found binary at: \(url.path)")
                break
            }
        }
        
        guard let executableURL = binaryURL else {
            XCTFail("Could not find rust-app binary. Checked paths: \(possiblePaths)")
            return
        }
        
        // 2. Run the binary
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["gen-keys", "--mnemonic", testMnemonic, "--json"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        
        guard process.terminationStatus == 0 else {
            XCTFail("Rust binary failed with status \(process.terminationStatus)")
            return
        }
        
        // 3. Parse Output
        struct RustOutput: Codable {
            let mnemonic: String
            let keys: AllKeys
        }
        
        struct AllKeys: Codable {
            let bitcoin: BitcoinKeys
            let ethereum: EthereumKeys
            // Add others as needed
        }
        
        struct BitcoinKeys: Codable {
            let address: String
        }
        
        struct EthereumKeys: Codable {
            let address: String
        }
        
        let decoder = JSONDecoder()
        let output = try decoder.decode(RustOutput.self, from: data)
        
        // 4. Assertions
        XCTAssertEqual(output.mnemonic, testMnemonic)
        XCTAssertEqual(output.keys.bitcoin.address, expectedBitcoinAddress, "Bitcoin address mismatch")
        
        // Note: Update this expectation once we confirm the exact derivation path used in Rust
        let expectedEthereumAddress = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        XCTAssertEqual(output.keys.ethereum.address, expectedEthereumAddress, "Ethereum address mismatch")
        
        print("✅ Integration Test Passed: Bitcoin address matches expected vector.")
    }
    
    // MARK: - Signing Tests
    
    func testRustCLISigning() throws {
        // 1. Locate the binary
        let fileManager = FileManager.default
        let possiblePaths = [
            "../rust-app/target/debug/rust-app",
            "rust-app/target/debug/rust-app",
            "/Users/x/Desktop/888/rust-app/target/debug/rust-app"
        ]
        
        var binaryURL: URL?
        for path in possiblePaths {
            let url: URL
            if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path)
            } else {
                let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                url = currentDirectory.appendingPathComponent(path).standardized
            }
            
            if fileManager.fileExists(atPath: url.path) {
                binaryURL = url
                break
            }
        }
        
        guard let executableURL = binaryURL else {
            XCTFail("Could not find rust-app binary")
            return
        }
        
        // 2. Generate Keys first to get valid inputs
        let genProcess = Process()
        genProcess.executableURL = executableURL
        genProcess.arguments = ["gen-keys", "--mnemonic", testMnemonic, "--json"]
        let genPipe = Pipe()
        genProcess.standardOutput = genPipe
        try genProcess.run()
        genProcess.waitUntilExit()
        
        let genData = genPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Define structs for parsing
        struct RustOutput: Codable {
            let keys: AllKeys
        }
        struct AllKeys: Codable {
            let bitcoin_testnet: BitcoinKeys
            let ethereum: EthereumKeys
            let solana: SolanaKeys
            let monero: MoneroKeys
            let xrp: XRPKeys
        }
        struct BitcoinKeys: Codable { let private_wif: String; let address: String }
        struct EthereumKeys: Codable { let private_hex: String; let address: String }
        struct SolanaKeys: Codable { let private_key_base58: String; let public_key_base58: String }
        struct MoneroKeys: Codable { let private_spend_hex: String; let private_view_hex: String; let address: String }
        struct XRPKeys: Codable { let private_hex: String; let classic_address: String }
        
        let output = try JSONDecoder().decode(RustOutput.self, from: genData)
        let keys = output.keys
        
        // 3. Test Bitcoin Signing (Testnet)
        let btcProcess = Process()
        btcProcess.executableURL = executableURL
        btcProcess.arguments = [
            "sign-btc",
            "--recipient", "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",
            "--amount-sats", "10000",
            "--fee-rate", "5",
            "--sender-wif", keys.bitcoin_testnet.private_wif
        ]
        let btcPipe = Pipe()
        btcProcess.standardOutput = btcPipe
        try btcProcess.run()
        btcProcess.waitUntilExit()
        
        let btcData = btcPipe.fileHandleForReading.readDataToEndOfFile()
        let btcHex = String(data: btcData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(btcHex.isEmpty, "Bitcoin signed hex should not be empty")
        // Basic hex validation
        XCTAssertTrue(btcHex.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil, "Bitcoin output should be hex")
        
        // 4. Test Ethereum Signing
        let ethProcess = Process()
        ethProcess.executableURL = executableURL
        ethProcess.arguments = [
            "sign-eth",
            "--recipient", "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
            "--amount-wei", "100000000000000000", // 0.1 ETH
            "--chain-id", "11155111", // Sepolia
            "--sender-key", keys.ethereum.private_hex,
            "--nonce", "0",
            "--gas-limit", "21000",
            "--gas-price", "20000000000" // 20 Gwei
        ]
        let ethPipe = Pipe()
        ethProcess.standardOutput = ethPipe
        try ethProcess.run()
        ethProcess.waitUntilExit()
        
        let ethData = ethPipe.fileHandleForReading.readDataToEndOfFile()
        let ethHex = String(data: ethData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(ethHex.isEmpty, "Ethereum signed hex should not be empty")
        XCTAssertTrue(ethHex.hasPrefix("0x"), "Ethereum output should start with 0x")
        
        // 5. Test Solana Signing
        let solProcess = Process()
        solProcess.executableURL = executableURL
        // Use a dummy blockhash (base58 encoded 32 bytes)
        let dummyBlockhash = "5PzkxHs7eG8W4sc5JJAZJEfeR4ePvrvFRFgmLedaxBMF" 
        solProcess.arguments = [
            "sign-sol",
            "--recipient", "2RTAE8LaTbs6cQKxDNeFQRYATHPfcnrz2hGNygxsX66P",
            "--amount-sol", "0.1",
            "--recent-blockhash", dummyBlockhash,
            "--sender-base58", keys.solana.private_key_base58
        ]
        let solPipe = Pipe()
        solProcess.standardOutput = solPipe
        try solProcess.run()
        solProcess.waitUntilExit()
        
        let solData = solPipe.fileHandleForReading.readDataToEndOfFile()
        let solTx = String(data: solData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(solTx.isEmpty, "Solana signed tx should not be empty")
        
        // 6. Test Monero Signing (Validation)
        let xmrProcess = Process()
        xmrProcess.executableURL = executableURL
        xmrProcess.arguments = [
            "sign-xmr",
            "--recipient", keys.monero.address, // Send to self for validation
            "--amount-xmr", "1.5",
            "--sender-spend-hex", keys.monero.private_spend_hex,
            "--sender-view-hex", keys.monero.private_view_hex
        ]
        let xmrPipe = Pipe()
        xmrProcess.standardOutput = xmrPipe
        try xmrProcess.run()
        xmrProcess.waitUntilExit()
        
        let xmrData = xmrPipe.fileHandleForReading.readDataToEndOfFile()
        let xmrTx = String(data: xmrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(xmrTx.isEmpty, "Monero signed tx (mock) should not be empty")
        
        // 7. Test XRP Signing
        let xrpProcess = Process()
        xrpProcess.executableURL = executableURL
        xrpProcess.arguments = [
            "sign-xrp",
            "--recipient", "rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe",
            "--amount-drops", "1000000", // 1 XRP
            "--sender-seed-hex", keys.xrp.private_hex,
            "--sequence", "1"
        ]
        let xrpPipe = Pipe()
        xrpProcess.standardOutput = xrpPipe
        try xrpProcess.run()
        xrpProcess.waitUntilExit()
        
        let xrpData = xrpPipe.fileHandleForReading.readDataToEndOfFile()
        let xrpTx = String(data: xrpData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(xrpTx.isEmpty, "XRP signed tx should not be empty")
    }
}
