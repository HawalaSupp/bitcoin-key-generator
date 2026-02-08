import Foundation
import RustBridge

// MARK: - Error Types

enum RustServiceError: Error, LocalizedError {
    case ffiError(code: String, message: String)
    case invalidResponse
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .ffiError(let code, let message):
            return "[\(code)] \(message)"
        case .invalidResponse:
            return "Invalid response from Rust FFI"
        case .invalidInput:
            return "Invalid input for FFI call"
        }
    }
}

// MARK: - Response Parsing

private struct FFIResponse: Decodable {
    let success: Bool
    let data: FFIAnyCodable?
    let error: FFIError?
    
    struct FFIError: Decodable {
        let code: String
        let message: String
    }
}

// FFIAnyCodable to handle dynamic data (renamed to avoid conflict with EIP712Signer.AnyCodable)
private struct FFIAnyCodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: FFIAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([FFIAnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}

final class RustService: @unchecked Sendable {
    static let shared = RustService()
    
    /// Whether the Rust FFI backend passed its health check on launch
    private(set) var isHealthy: Bool = false
    /// Detailed health check failure reason, if any
    private(set) var healthCheckError: String?
    
    private init() {}
    
    // MARK: - Health Check (ROADMAP-01)
    
    /// Performs a health check on the Rust FFI backend.
    /// Verifies that the FFI layer is loaded, responsive, and can perform basic operations.
    /// Should be called once on app launch from `applicationDidFinishLaunching`.
    @discardableResult
    func performHealthCheck() -> Bool {
        // Test 1: Check that hawala_health_check FFI is reachable
        guard let cString = hawala_health_check() else {
            isHealthy = false
            healthCheckError = "Rust FFI returned null from health check"
            #if DEBUG
            print("❌ Rust health check FAILED: FFI returned null")
            #endif
            return false
        }
        
        let response = String(cString: cString)
        hawala_free_string(UnsafeMutablePointer(mutating: cString))
        
        // Parse the JSON response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool, success else {
            isHealthy = false
            healthCheckError = "Rust FFI health check returned invalid response: \(response)"
            #if DEBUG
            print("❌ Rust health check FAILED: invalid response — \(response)")
            #endif
            return false
        }
        
        // Test 2: Verify basic crypto operation (generate a wallet)
        let walletResult = generateKeys()
        guard walletResult != "{}" else {
            isHealthy = false
            healthCheckError = "Rust FFI cannot generate wallets"
            #if DEBUG
            print("❌ Rust health check FAILED: generateKeys returned empty")
            #endif
            return false
        }
        
        // Test 3: Verify mnemonic validation works
        let validMnemonic = validateMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        guard validMnemonic else {
            isHealthy = false
            healthCheckError = "Rust FFI mnemonic validation broken"
            #if DEBUG
            print("❌ Rust health check FAILED: validateMnemonic returned false for known-good mnemonic")
            #endif
            return false
        }
        
        isHealthy = true
        healthCheckError = nil
        #if DEBUG
        print("✅ Rust FFI health check PASSED")
        #endif
        return true
    }
    
    // MARK: - Response Parsing Helper
    
    /// Parse FFI JSON response and throw if error
    private func parseResponse(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw RustServiceError.invalidResponse
        }
        
        let response = try JSONDecoder().decode(FFIResponse.self, from: data)
        
        if !response.success {
            if let error = response.error {
                throw RustServiceError.ffiError(code: error.code, message: error.message)
            }
            throw RustServiceError.invalidResponse
        }
        
        // Return the data portion as JSON string if present, or the original for backward compat
        if let dataValue = response.data?.value {
            if let dataDict = dataValue as? [String: Any],
               let dataJson = try? JSONSerialization.data(withJSONObject: dataDict),
               let dataString = String(data: dataJson, encoding: .utf8) {
                return dataString
            }
        }
        
        return jsonString
    }
    
    /// Extract signed transaction hex from response
    private func extractSignedTx(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustServiceError.invalidResponse
        }
        
        // Check for error
        if let success = json["success"] as? Bool, !success {
            if let error = json["error"] as? [String: Any],
               let code = error["code"] as? String,
               let message = error["message"] as? String {
                throw RustServiceError.ffiError(code: code, message: message)
            }
            throw RustServiceError.invalidResponse
        }
        
        // Extract signed_tx from data
        if let dataObj = json["data"] as? [String: Any] {
            if let signedTx = dataObj["signed_tx"] as? String {
                return signedTx
            }
            if let txHex = dataObj["tx_hex"] as? String {
                return txHex
            }
        }
        
        // Try direct tx_hex field
        if let txHex = json["tx_hex"] as? String {
            return txHex
        }
        if let signedTx = json["signed_tx"] as? String {
            return signedTx
        }
        
        throw RustServiceError.invalidResponse
    }
    
    func generateKeys() -> String {
        guard let cString = generate_keys_ffi() else {
            return "{}"
        }
        
        let swiftString = String(cString: cString)
        free_string(UnsafeMutablePointer(mutating: cString))
        
        return swiftString
    }

    func fetchBalances(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else {
            return "{}"
        }
        
        guard let outputCString = fetch_balances_ffi(inputCString) else {
            return "{}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }

    func fetchBitcoinHistory(address: String) -> String {
        guard let addressCString = address.cString(using: .utf8) else {
            return "[]"
        }
        
        guard let outputCString = fetch_bitcoin_history_ffi(addressCString) else {
            return "[]"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }

    func prepareTransaction(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else {
            return "{\"error\": \"Invalid input string\"}"
        }
        
        guard let outputCString = prepare_transaction_ffi(inputCString) else {
            return "{\"error\": \"FFI returned null\"}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }

    func prepareEthereumTransaction(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else {
            return "{\"error\": \"Invalid input string\"}"
        }
        
        guard let outputCString = prepare_ethereum_transaction_ffi(inputCString) else {
            return "{\"error\": \"FFI returned null\"}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }
    
    func restoreWallet(mnemonic: String, passphrase: String = "") -> String {
        // Build JSON request with mnemonic and passphrase
        let request: [String: String] = [
            "mnemonic": mnemonic,
            "passphrase": passphrase
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let inputCString = jsonString.cString(using: .utf8) else {
            return "{}"
        }
        
        guard let outputCString = hawala_restore_wallet(inputCString) else {
            return "{}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        // Parse API response to extract data
        if let data = swiftString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, success,
           let dataObj = json["data"] {
            if let dataJson = try? JSONSerialization.data(withJSONObject: dataObj),
               let dataString = String(data: dataJson, encoding: .utf8) {
                return dataString
            }
        }
        
        return swiftString
    }

    func validateMnemonic(_ mnemonic: String) -> Bool {
        guard let mnemonicCString = mnemonic.cString(using: .utf8) else {
            return false
        }
        return validate_mnemonic_ffi(mnemonicCString)
    }

    func validateEthereumAddress(_ address: String) -> Bool {
        guard let addressCString = address.cString(using: .utf8) else {
            return false
        }
        return validate_ethereum_address_ffi(addressCString)
    }
    
    /// Prepare a Taproot (P2TR) transaction - ~7% fee savings vs SegWit
    func prepareTaprootTransaction(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else {
            return "{\"error\": \"Invalid input string\"}"
        }
        
        guard let outputCString = prepare_taproot_transaction_ffi(inputCString) else {
            return "{\"error\": \"FFI returned null\"}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }
    
    /// Derive Taproot address from WIF private key
    func deriveTaprootAddress(wif: String) -> String {
        guard let wifCString = wif.cString(using: .utf8) else {
            return "{\"error\": \"Invalid WIF string\"}"
        }
        
        guard let outputCString = derive_taproot_address_ffi(wifCString) else {
            return "{\"error\": \"FFI returned null\"}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }
    
    // MARK: - Unified Transaction Signing (FFI-based)
    
    /// Sign a transaction using the unified FFI interface
    /// - Parameter jsonInput: JSON containing chain, transaction details, and private key
    /// - Returns: JSON response with signed transaction or error
    func signTransaction(jsonInput: String) -> String {
        guard let inputCString = jsonInput.cString(using: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Invalid input string\"}}"
        }
        
        guard let outputCString = hawala_sign_transaction(inputCString) else {
            return "{\"success\": false, \"error\": {\"code\": \"ffi_error\", \"message\": \"FFI returned null\"}}"
        }
        
        let swiftString = String(cString: outputCString)
        hawala_free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }
    
    // MARK: - Chain-Specific Signing Helpers
    
    /// Sign a Bitcoin transaction
    func signBitcoin(recipient: String, amountSats: UInt64, feeRate: UInt64, senderWIF: String, utxos: [[String: Any]]? = nil) -> String {
        var request: [String: Any] = [
            "chain": "bitcoin",
            "recipient": recipient,
            "amount_sats": amountSats,
            "fee_rate": feeRate,
            "sender_wif": senderWIF
        ]
        
        if let utxos = utxos {
            request["utxos"] = utxos
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    /// Sign an Ethereum transaction
    func signEthereum(recipient: String, amountWei: String, chainId: UInt64, senderKey: String, nonce: UInt64, gasLimit: UInt64, gasPrice: String? = nil, maxFeePerGas: String? = nil, maxPriorityFeePerGas: String? = nil, data: String = "") -> String {
        var request: [String: Any] = [
            "chain": "ethereum",
            "recipient": recipient,
            "amount_wei": amountWei,
            "chain_id": chainId,
            "sender_key": senderKey,
            "nonce": nonce,
            "gas_limit": gasLimit
        ]
        
        if let gasPrice = gasPrice {
            request["gas_price"] = gasPrice
        }
        if let maxFee = maxFeePerGas {
            request["max_fee_per_gas"] = maxFee
        }
        if let priorityFee = maxPriorityFeePerGas {
            request["max_priority_fee_per_gas"] = priorityFee
        }
        if !data.isEmpty {
            request["data"] = data
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    /// Sign a Solana transaction
    func signSolana(recipient: String, amountSol: Double, recentBlockhash: String, senderBase58: String) -> String {
        let request: [String: Any] = [
            "chain": "solana",
            "recipient": recipient,
            "amount_sol": amountSol,
            "recent_blockhash": recentBlockhash,
            "sender_base58": senderBase58
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    /// Sign a Monero transaction
    func signMonero(recipient: String, amountXmr: Double, senderSpendHex: String, senderViewHex: String) -> String {
        let request: [String: Any] = [
            "chain": "monero",
            "recipient": recipient,
            "amount_xmr": amountXmr,
            "sender_spend_hex": senderSpendHex,
            "sender_view_hex": senderViewHex
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    /// Sign an XRP transaction
    func signXRP(recipient: String, amountDrops: UInt64, senderSeedHex: String, sequence: UInt32, destinationTag: UInt32? = nil) -> String {
        var request: [String: Any] = [
            "chain": "xrp",
            "recipient": recipient,
            "amount_drops": amountDrops,
            "sender_seed_hex": senderSeedHex,
            "sequence": sequence
        ]
        
        if let tag = destinationTag {
            request["destination_tag"] = tag
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    /// Sign a Litecoin transaction
    func signLitecoin(recipient: String, amountLits: UInt64, feeRate: UInt64, senderWIF: String, senderAddress: String, utxos: [[String: Any]]? = nil) -> String {
        var request: [String: Any] = [
            "chain": "litecoin",
            "recipient": recipient,
            "amount_lits": amountLits,
            "fee_rate": feeRate,
            "sender_wif": senderWIF,
            "sender_address": senderAddress
        ]
        
        if let utxos = utxos {
            request["utxos"] = utxos
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        return signTransaction(jsonInput: jsonString)
    }
    
    // MARK: - Key Generation (FFI-based)
    
    /// Generate wallet keys from mnemonic
    func generateKeysFromMnemonic(mnemonic: String) -> String {
        let request: [String: Any] = [
            "mnemonic": mnemonic,
            "passphrase": ""
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let inputCString = jsonString.cString(using: .utf8) else {
            return "{\"success\": false, \"error\": {\"code\": \"invalid_input\", \"message\": \"Failed to encode request\"}}"
        }
        
        guard let outputCString = hawala_restore_wallet(inputCString) else {
            return "{\"success\": false, \"error\": {\"code\": \"ffi_error\", \"message\": \"FFI returned null\"}}"
        }
        
        let swiftString = String(cString: outputCString)
        hawala_free_string(UnsafeMutablePointer(mutating: outputCString))
        
        return swiftString
    }
    
    // MARK: - Throwing Variants (match legacy API signatures)
    
    /// Sign a Bitcoin transaction (throwing variant)
    func signBitcoinThrowing(recipient: String, amountSats: UInt64, feeRate: UInt64, senderWIF: String, utxos: [RustUTXO]? = nil) throws -> String {
        // Convert RustUTXO to dictionary format
        var utxoDicts: [[String: Any]]? = nil
        if let utxos = utxos {
            utxoDicts = utxos.map { utxo in
                var dict: [String: Any] = [
                    "txid": utxo.txid,
                    "vout": utxo.vout,
                    "value": utxo.value
                ]
                var status: [String: Any] = ["confirmed": utxo.status.confirmed]
                if let height = utxo.status.block_height { status["block_height"] = height }
                if let hash = utxo.status.block_hash { status["block_hash"] = hash }
                if let time = utxo.status.block_time { status["block_time"] = time }
                dict["status"] = status
                return dict
            }
        }
        
        let result = signBitcoin(recipient: recipient, amountSats: amountSats, feeRate: feeRate, senderWIF: senderWIF, utxos: utxoDicts)
        return try extractSignedTx(result)
    }
    
    /// Sign an Ethereum transaction (throwing variant)
    func signEthereumThrowing(recipient: String, amountWei: String, chainId: UInt64, senderKey: String, nonce: UInt64, gasLimit: UInt64, gasPrice: String? = nil, maxFeePerGas: String? = nil, maxPriorityFeePerGas: String? = nil, data: String = "") throws -> String {
        let result = signEthereum(recipient: recipient, amountWei: amountWei, chainId: chainId, senderKey: senderKey, nonce: nonce, gasLimit: gasLimit, gasPrice: gasPrice, maxFeePerGas: maxFeePerGas, maxPriorityFeePerGas: maxPriorityFeePerGas, data: data)
        return try extractSignedTx(result)
    }
    
    /// Sign a Solana transaction (throwing variant)
    func signSolanaThrowing(recipient: String, amountSol: Double, recentBlockhash: String, senderBase58: String) throws -> String {
        let result = signSolana(recipient: recipient, amountSol: amountSol, recentBlockhash: recentBlockhash, senderBase58: senderBase58)
        return try extractSignedTx(result)
    }
    
    /// Sign a Monero transaction (throwing variant)
    func signMoneroThrowing(recipient: String, amountXmr: Double, senderSpendHex: String, senderViewHex: String) throws -> String {
        let result = signMonero(recipient: recipient, amountXmr: amountXmr, senderSpendHex: senderSpendHex, senderViewHex: senderViewHex)
        return try extractSignedTx(result)
    }
    
    /// Sign an XRP transaction (throwing variant)
    func signXRPThrowing(recipient: String, amountDrops: UInt64, senderSeedHex: String, sequence: UInt32, destinationTag: UInt32? = nil) throws -> String {
        let result = signXRP(recipient: recipient, amountDrops: amountDrops, senderSeedHex: senderSeedHex, sequence: sequence, destinationTag: destinationTag)
        return try extractSignedTx(result)
    }
    
    /// Sign a Litecoin transaction (throwing variant)
    func signLitecoinThrowing(recipient: String, amountLits: UInt64, feeRate: UInt64, senderWIF: String, senderAddress: String, utxos: [RustUTXO]? = nil) throws -> String {
        // Convert RustUTXO to dictionary format
        var utxoDicts: [[String: Any]]? = nil
        if let utxos = utxos {
            utxoDicts = utxos.map { utxo in
                var dict: [String: Any] = [
                    "txid": utxo.txid,
                    "vout": utxo.vout,
                    "value": utxo.value
                ]
                var status: [String: Any] = ["confirmed": utxo.status.confirmed]
                if let height = utxo.status.block_height { status["block_height"] = height }
                if let hash = utxo.status.block_hash { status["block_hash"] = hash }
                if let time = utxo.status.block_time { status["block_time"] = time }
                dict["status"] = status
                return dict
            }
        }
        
        let result = signLitecoin(recipient: recipient, amountLits: amountLits, feeRate: feeRate, senderWIF: senderWIF, senderAddress: senderAddress, utxos: utxoDicts)
        return try extractSignedTx(result)
    }
}

// MARK: - UTXO Types (shared with legacy bridge)

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
