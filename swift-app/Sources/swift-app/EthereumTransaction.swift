import Foundation
import CryptoKit
import P256K

// MARK: - Ethereum Transaction Builder

struct EthereumTransaction {
    
    // Build and sign an Ethereum transaction
    static func buildAndSign(
        to recipient: String,
        value: String, // in Wei (as hex string or decimal)
        gasLimit: Int,
        gasPrice: String, // in Wei (as hex string)
        nonce: Int,
        chainId: Int = 1, // 1 = mainnet, 11155111 = sepolia
        privateKeyHex: String,
        data: String = "0x" // For ETH transfers, empty. For ERC-20, encoded function call
    ) throws -> String {
        
        // Construct JSON for Rust FFI
        let request: [String: Any] = [
            "recipient": recipient,
            "amount": value,
            "chain_id": chainId,
            "sender_key_hex": privateKeyHex,
            "nonce": nonce,
            "gas_limit": gasLimit,
            "gas_price": gasPrice,
            "data": data
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let _ = String(data: jsonData, encoding: .utf8) else {
            throw EthereumError.encodingFailed
        }
        
        // Call Rust CLI
        let signedHex = try RustCLIBridge.shared.signEthereum(
            recipient: recipient,
            amountWei: value,
            chainId: UInt64(chainId),
            senderKey: privateKeyHex,
            nonce: UInt64(nonce),
            gasLimit: UInt64(gasLimit),
            gasPrice: gasPrice,
            data: data
        )
        
        return signedHex
    }
    
    // Build and sign ERC-20 token transfer
    static func buildAndSignERC20Transfer(
        tokenContract: String,
        to recipient: String,
        amount: String, // in smallest unit (e.g., for USDT with 6 decimals, "1000000" = 1 USDT)
        gasLimit: Int,
        gasPrice: String,
        nonce: Int,
        chainId: Int = 1,
        privateKeyHex: String
    ) throws -> String {
        
        // ERC-20 transfer function signature: transfer(address,uint256)
        // Function selector: 0xa9059cbb
        let functionSelector = "a9059cbb"
        
        // Encode recipient address (32 bytes, left-padded)
        let recipientAddress = recipient.hasPrefix("0x") ? String(recipient.dropFirst(2)) : recipient
        let paddedRecipient = String(repeating: "0", count: 64 - recipientAddress.count) + recipientAddress
        
        // Encode amount (32 bytes, left-padded)
        let amountBigInt = try parseWei(amount)
        let amountHex = String(amountBigInt, radix: 16)
        let paddedAmount = String(repeating: "0", count: 64 - amountHex.count) + amountHex
        
        // Combine into data field
        let data = "0x" + functionSelector + paddedRecipient + paddedAmount
        
        // Build transaction with value = 0 (we're not sending ETH, just calling contract)
        return try buildAndSign(
            to: tokenContract,
            value: "0",
            gasLimit: gasLimit,
            gasPrice: gasPrice,
            nonce: nonce,
            chainId: chainId,
            privateKeyHex: privateKeyHex,
            data: data
        )
    }
    
    // MARK: - Private Helpers
    
    private static func parseWei(_ value: String) throws -> UInt64 {
        let cleaned = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
        
        if cleaned.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) {
            // Hex string
            guard let wei = UInt64(cleaned, radix: 16) else {
                throw EthereumError.invalidAmount
            }
            return wei
        } else {
            // Decimal string
            guard let wei = UInt64(cleaned) else {
                throw EthereumError.invalidAmount
            }
            return wei
        }
    }
    
    private static func buildTransactionData(
        nonce: Int,
        gasPrice: UInt64,
        gasLimit: Int,
        to: String,
        value: UInt64,
        data: String,
        chainId: Int
    ) throws -> Data {
        
        // For EIP-155 (replay protection), we include chainId, 0, 0 in the signing hash
        let items: [RLPItem] = [
            .uint(UInt64(nonce)),
            .uint(gasPrice),
            .uint(UInt64(gasLimit)),
            .address(to),
            .uint(value),
            .data(data),
            .uint(UInt64(chainId)), // EIP-155
            .uint(0),
            .uint(0)
        ]
        
        return try rlpEncode(items)
    }
    
    private static func signTransaction(txData: Data, privateKeyHex: String, chainId: Int) throws -> String {
        // Hash the transaction data
        let hash = SHA256.hash(data: txData)
        let messageHash = Data(hash)
        
        // Parse private key
        let privKeyData = try hexToData(privateKeyHex)
        guard privKeyData.count == 32 else {
            throw EthereumError.invalidPrivateKey
        }
        
        // Sign using P256 (placeholder for secp256k1)
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privKeyData)
        let signature = try privateKey.signature(for: messageHash)
        
        // Extract r, s, v from signature
        let rawSig = signature.rawRepresentation
        guard rawSig.count == 64 else {
            throw EthereumError.signingFailed
        }
        
        let r = rawSig[0..<32]
        let s = rawSig[32..<64]
        
        // Calculate v for EIP-155: v = chainId * 2 + 35 + {0,1}
        // We need to determine recovery ID (0 or 1)
        let v = UInt64(chainId * 2 + 35) // Simplified - assume recovery ID 0
        
        // Build final signed transaction with r, s, v
        // Note: signedItems is computed for future use when full RLP encoding is implemented
        _ = [
            RLPItem.uint(UInt64(txData.count)), // nonce (placeholder, need to extract from txData)
            RLPItem.data("0x" + String(v, radix: 16)),
            RLPItem.data("0x" + r.hexString),
            RLPItem.data("0x" + s.hexString)
        ]
        
        // For now, return hex-encoded signature components
        // TODO: Properly encode the full signed transaction with RLP
        return "0x" + r.hexString + s.hexString + String(v, radix: 16)
    }
    
    private static func hexToData(_ hex: String) throws -> Data {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleaned.count % 2 == 0 else {
            throw EthereumError.invalidHex
        }
        
        var data = Data()
        var index = cleaned.startIndex
        
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw EthereumError.invalidHex
            }
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
}

// MARK: - RLP Encoding

private enum RLPItem {
    case uint(UInt64)
    case data(String)
    case address(String)
    case list([RLPItem])
}

private func rlpEncode(_ items: [RLPItem]) throws -> Data {
    var encoded = Data()
    
    for item in items {
        switch item {
        case .uint(let value):
            encoded.append(encodeUInt(value))
        case .data(let hex):
            encoded.append(try encodeData(hex))
        case .address(let addr):
            encoded.append(try encodeAddress(addr))
        case .list(let subItems):
            let listData = try rlpEncode(subItems)
            encoded.append(encodeLength(listData.count, offset: 0xc0))
            encoded.append(listData)
        }
    }
    
    return encoded
}

private func encodeUInt(_ value: UInt64) -> Data {
    if value == 0 {
        return Data([0x80])
    }
    
    var bytes: [UInt8] = []
    var val = value
    
    while val > 0 {
        bytes.insert(UInt8(val & 0xFF), at: 0)
        val >>= 8
    }
    
    if bytes.count == 1 && bytes[0] < 0x80 {
        return Data(bytes)
    }
    
    var result = Data()
    result.append(0x80 + UInt8(bytes.count))
    result.append(contentsOf: bytes)
    return result
}

private func encodeData(_ hex: String) throws -> Data {
    let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    
    if cleaned.isEmpty {
        return Data([0x80])
    }
    
    var data = Data()
    var index = cleaned.startIndex
    
    while index < cleaned.endIndex {
        let nextIndex = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
        let byteString = cleaned[index..<nextIndex]
        guard let byte = UInt8(byteString, radix: 16) else {
            throw EthereumError.invalidHex
        }
        data.append(byte)
        index = nextIndex
    }
    
    return encodeBytes(data)
}

private func encodeAddress(_ address: String) throws -> Data {
    let cleaned = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
    guard cleaned.count == 40 else {
        throw EthereumError.invalidAddress
    }
    
    return try encodeData(cleaned)
}

private func encodeBytes(_ bytes: Data) -> Data {
    if bytes.count == 1 && bytes[0] < 0x80 {
        return bytes
    }
    
    var result = Data()
    result.append(encodeLength(bytes.count, offset: 0x80))
    result.append(bytes)
    return result
}

private func encodeLength(_ length: Int, offset: UInt8) -> Data {
    if length < 56 {
        return Data([offset + UInt8(length)])
    }
    
    var lengthBytes: [UInt8] = []
    var len = length
    
    while len > 0 {
        lengthBytes.insert(UInt8(len & 0xFF), at: 0)
        len >>= 8
    }
    
    var result = Data()
    result.append(offset + 55 + UInt8(lengthBytes.count))
    result.append(contentsOf: lengthBytes)
    return result
}

// MARK: - Errors

enum EthereumError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidPrivateKey
    case invalidHex
    case encodingFailed
    case signingFailed
    case insufficientBalance
    case gasEstimationFailed
    case broadcastFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid Ethereum address format"
        case .invalidAmount:
            return "Invalid amount format"
        case .invalidPrivateKey:
            return "Invalid private key"
        case .invalidHex:
            return "Invalid hexadecimal string"
        case .encodingFailed:
            return "Failed to encode transaction data"
        case .signingFailed:
            return "Failed to sign transaction"
        case .insufficientBalance:
            return "Insufficient balance for transaction + gas"
        case .gasEstimationFailed:
            return "Failed to estimate gas"
        case .broadcastFailed(let msg):
            return "Failed to broadcast transaction: \(msg)"
        }
    }
}

// MARK: - Helpers
// Note: hexString extension for Data is defined in BitcoinTransaction.swift
