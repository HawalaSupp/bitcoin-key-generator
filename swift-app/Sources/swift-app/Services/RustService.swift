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
    
    func restoreWallet(mnemonic: String) -> String {
        guard let inputCString = mnemonic.cString(using: .utf8) else {
            return "{}"
        }
        
        guard let outputCString = restore_wallet_ffi(inputCString) else {
            return "{}"
        }
        
        let swiftString = String(cString: outputCString)
        free_string(UnsafeMutablePointer(mutating: outputCString))
        
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
}
