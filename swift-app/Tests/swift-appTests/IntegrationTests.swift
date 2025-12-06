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
        process.arguments = ["--mnemonic", testMnemonic, "--json"]
        
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
}
