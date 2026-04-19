import Foundation
import CryptoKit
import P256K

// MARK: - Ethereum Transaction Builder
//
// NOTE: All Ethereum signing is done through RustService.signEthereumThrowing() which
// uses the ethers-core library for proper EIP-1559 and legacy transaction encoding.
// The private helper functions below are NOT used and are kept for reference only.
// DO NOT use nativeSign() - it has incomplete RLP encoding.

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
        
        // Call Rust FFI
        let signedHex = try RustService.shared.signEthereumThrowing(
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
    
    /// DEPRECATED: This function has incomplete RLP encoding and should NOT be used.
    /// All Ethereum signing must go through RustService.signEthereumThrowing() which uses
    /// ethers-core for proper EIP-155/EIP-1559 transaction encoding.
    @available(*, deprecated, message: "Use RustService.signEthereumThrowing instead")
    private static func signTransaction(txData: Data, privateKeyHex: String, chainId: Int) throws -> String {
        // SECURITY WARNING: This implementation is incomplete and will produce invalid transactions.
        // The Rust FFI bridge handles all signing - this code is never called.
        fatalError("signTransaction is deprecated - use RustService.signEthereumThrowing")
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
