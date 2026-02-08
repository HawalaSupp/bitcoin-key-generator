import Foundation
import CryptoKit
import P256K

/// Handles WalletConnect message and transaction signing.
///
/// Pure logic — no UI references. Receives keys as parameters and returns
/// hex-encoded Ethereum signatures.
@MainActor
final class WalletConnectSigningService: ObservableObject {
    static let shared = WalletConnectSigningService()
    private init() {}

    // MARK: - EVM account helpers

    /// Build CAIP-10 account identifiers from the wallet's key set.
    func evmAccounts(from keys: AllKeys) -> [String] {
        var accounts: [String] = []

        // Ethereum mainnet
        if !keys.ethereum.address.isEmpty {
            accounts.append("eip155:1:\(keys.ethereum.address)")
        }

        // Ethereum Sepolia testnet
        if !keys.ethereumSepolia.address.isEmpty {
            accounts.append("eip155:11155111:\(keys.ethereumSepolia.address)")
        }

        // BSC (BNB Chain)
        if !keys.bnb.address.isEmpty {
            accounts.append("eip155:56:\(keys.bnb.address)")
        }

        // Additional EVM chains sharing the same address
        let evmAddress = keys.ethereum.address.isEmpty ? keys.ethereumSepolia.address : keys.ethereum.address
        if !evmAddress.isEmpty {
            accounts.append("eip155:137:\(evmAddress)")   // Polygon
            accounts.append("eip155:42161:\(evmAddress)") // Arbitrum
            accounts.append("eip155:10:\(evmAddress)")    // Optimism
            accounts.append("eip155:43114:\(evmAddress)") // Avalanche
        }

        return accounts
    }

    // MARK: - Request dispatch

    /// Route a WalletConnect session request to the appropriate signing handler.
    func handleSign(_ request: WCSessionRequest, keys: AllKeys) async throws -> String {
        switch request.method {
        case "personal_sign", "eth_sign":
            return try await signPersonalMessage(request, keys: keys)

        case "eth_signTypedData", "eth_signTypedData_v3", "eth_signTypedData_v4":
            return try await signTypedData(request, keys: keys)

        case "eth_sendTransaction", "eth_signTransaction":
            return try await signTransaction(request, keys: keys)

        default:
            throw WCError.userRejected
        }
    }

    // MARK: - Personal sign (eth_sign / personal_sign)

    private func signPersonalMessage(_ request: WCSessionRequest, keys: AllKeys) async throws -> String {
        guard let params = request.params as? [Any],
              params.count >= 2,
              let message = params[1] as? String else {
            throw WCError.requestTimeout
        }

        let privateKeyHex = resolvePrivateKey(from: keys)
        guard !privateKeyHex.isEmpty else { throw WCError.userRejected }

        #if DEBUG
        print("📝 WalletConnect: Personal sign request for message: \(message)")
        #endif

        // Decode message (could be hex or plain text)
        let messageBytes: Data
        if message.hasPrefix("0x") {
            messageBytes = hexToData(String(message.dropFirst(2)))
        } else {
            messageBytes = Data(message.utf8)
        }

        // Ethereum signed message hash: keccak256("\x19Ethereum Signed Message:\n" + len + message)
        let prefix = "\u{19}Ethereum Signed Message:\n\(messageBytes.count)"
        var prefixedMessage = Data(prefix.utf8)
        prefixedMessage.append(messageBytes)

        let messageHash = Keccak256.hash(data: prefixedMessage)
        return try signWithSecp256k1(hash: messageHash, privateKeyHex: privateKeyHex)
    }

    // MARK: - Typed data (EIP-712)

    private func signTypedData(_ request: WCSessionRequest, keys: AllKeys) async throws -> String {
        guard let params = request.params as? [Any],
              params.count >= 2 else {
            throw WCError.requestTimeout
        }

        let privateKeyHex = resolvePrivateKey(from: keys)
        guard !privateKeyHex.isEmpty else { throw WCError.userRejected }

        #if DEBUG
        print("📝 WalletConnect: Typed data sign request (EIP-712 spec-compliant)")
        #endif

        let typedDataJSON: String
        if let jsonStr = params[1] as? String {
            typedDataJSON = jsonStr
        } else if let jsonDict = params[1] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
                  let str = String(data: jsonData, encoding: .utf8) {
            typedDataJSON = str
        } else {
            throw WCError.requestTimeout
        }

        // EIP-712 spec-compliant: parse typed data, compute domain separator + struct hash via Rust FFI
        do {
            let typedData = try EIP712TypedData.fromJSON(typedDataJSON)
            let cleanHex = privateKeyHex.hasPrefix("0x") ? String(privateKeyHex.dropFirst(2)) : privateKeyHex
            let privKeyData = hexToData(cleanHex)
            guard privKeyData.count == 32 else { throw WCError.userRejected }

            let signature = try await EIP712Signer.shared.signTypedData(typedData, privateKey: privKeyData)
            return signature.hexSignature
        } catch let error as EIP712Error {
            #if DEBUG
            print("⚠️ WalletConnect: EIP-712 spec signing failed (\(error.localizedDescription)), falling back to hash-based signing")
            #endif
            // Fallback for malformed typed data: prefix + keccak256 of JSON
            let prefix = "\u{19}Ethereum Signed Message:\n\(typedDataJSON.count)"
            var prefixedMessage = Data(prefix.utf8)
            prefixedMessage.append(Data(typedDataJSON.utf8))
            let hash = Keccak256.hash(data: prefixedMessage)
            return try signWithSecp256k1(hash: hash, privateKeyHex: privateKeyHex)
        }
    }

    // MARK: - Transaction signing

    private func signTransaction(_ request: WCSessionRequest, keys: AllKeys) async throws -> String {
        guard let params = request.params as? [[String: Any]],
              let txParams = params.first else {
            throw WCError.requestTimeout
        }

        #if DEBUG
        print("📝 WalletConnect: Transaction sign request")
        print("   From: \(txParams["from"] ?? "unknown")")
        print("   To: \(txParams["to"] ?? "unknown")")
        print("   Value: \(txParams["value"] ?? "0")")
        print("   Data: \(txParams["data"] ?? "0x")")
        #endif

        // For transaction signing, user should use app's send UI
        throw WCError.userRejected
    }

    // MARK: - Core secp256k1 signing

    /// Sign a hash using secp256k1 and return an Ethereum-compatible signature.
    func signWithSecp256k1(hash: Data, privateKeyHex: String) throws -> String {
        let cleanHex = privateKeyHex.hasPrefix("0x") ? String(privateKeyHex.dropFirst(2)) : privateKeyHex
        let privKeyData = hexToData(cleanHex)

        guard privKeyData.count == 32 else {
            throw WCError.userRejected
        }

        let privKey = try P256K.Signing.PrivateKey(dataRepresentation: privKeyData)
        let digest = HashDigest(Array(hash))
        let signature = try privKey.signature(for: digest)
        let derSig = try signature.derRepresentation

        // Parse DER: 0x30 [total] 0x02 [rLen] [r] 0x02 [sLen] [s]
        guard derSig.count >= 8, derSig[0] == 0x30, derSig[2] == 0x02 else {
            throw WCError.userRejected
        }

        let rLength = Int(derSig[3])
        let rStart = 4
        var rData = Data(derSig[rStart..<(rStart + rLength)])

        let sLengthIndex = rStart + rLength + 1
        guard derSig.count > sLengthIndex else { throw WCError.userRejected }
        let sLength = Int(derSig[sLengthIndex])
        let sStart = sLengthIndex + 1
        var sData = Data(derSig[sStart..<(sStart + sLength)])

        // Strip leading zero padding
        if rData.count == 33 && rData[0] == 0x00 { rData = Data(rData.dropFirst()) }
        if sData.count == 33 && sData[0] == 0x00 { sData = Data(sData.dropFirst()) }

        // Pad to 32 bytes
        while rData.count < 32 { rData.insert(0x00, at: 0) }
        while sData.count < 32 { sData.insert(0x00, at: 0) }

        // Recovery ID (v) – typically 27 or 28 for Ethereum
        let v: UInt8 = 27

        return "0x" + rData.map { String(format: "%02x", $0) }.joined()
             + sData.map { String(format: "%02x", $0) }.joined()
             + String(format: "%02x", v)
    }

    // MARK: - Helpers

    private func resolvePrivateKey(from keys: AllKeys) -> String {
        keys.ethereum.privateHex.isEmpty ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
    }

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
}
