import Foundation
import RustBridge

final class RustService: @unchecked Sendable {
    static let shared = RustService()
    
    private init() {}
    
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
}
