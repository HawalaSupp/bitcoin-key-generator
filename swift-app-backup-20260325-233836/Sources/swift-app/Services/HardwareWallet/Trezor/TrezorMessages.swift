//
//  TrezorMessages.swift
//  Hawala
//
//  Trezor Protobuf Message Structures
//
//  Defines the message structures for Trezor communication.
//  In production, these would be generated from trezor-common protobuf definitions.
//

import Foundation

// MARK: - Message Protocol

/// Protocol for Trezor messages that can be encoded/decoded
public protocol TrezorMessage: Sendable {
    /// The message type ID
    static var messageType: TrezorMessageType { get }
    
    /// Encode the message to protobuf wire format
    func encode() -> Data
    
    /// Decode from protobuf wire format
    static func decode(from data: Data) throws -> Self
}

// MARK: - Core Messages

/// Initialize message - sent to start a session
public struct TrezorInitialize: TrezorMessage {
    public static let messageType: TrezorMessageType = .initialize
    
    public let sessionId: Data?
    public let derivationCardanoIcarusFromLedger: Bool?
    
    public init(sessionId: Data? = nil, derivationCardanoIcarusFromLedger: Bool? = nil) {
        self.sessionId = sessionId
        self.derivationCardanoIcarusFromLedger = derivationCardanoIcarusFromLedger
    }
    
    public func encode() -> Data {
        var data = Data()
        // Field 1: session_id (bytes)
        if let sessionId = sessionId {
            data.append(contentsOf: encodeBytes(fieldNumber: 1, value: sessionId))
        }
        // Field 3: derive_cardano_icarus_from_ledger (bool)
        if let derive = derivationCardanoIcarusFromLedger, derive {
            data.append(contentsOf: encodeBool(fieldNumber: 3, value: derive))
        }
        return data
    }
    
    public static func decode(from data: Data) throws -> TrezorInitialize {
        return TrezorInitialize()
    }
}

/// Features message - response with device capabilities
public struct TrezorFeatures: TrezorMessage {
    public static let messageType: TrezorMessageType = .features
    
    public let vendor: String?
    public let majorVersion: UInt32?
    public let minorVersion: UInt32?
    public let patchVersion: UInt32?
    public let bootloaderMode: Bool?
    public let deviceId: String?
    public let pinProtection: Bool?
    public let passphraseProtection: Bool?
    public let language: String?
    public let label: String?
    public let initialized: Bool?
    public let revision: Data?
    public let unlocked: Bool?
    public let needsBackup: Bool?
    public let model: String?
    
    public init(
        vendor: String? = nil,
        majorVersion: UInt32? = nil,
        minorVersion: UInt32? = nil,
        patchVersion: UInt32? = nil,
        bootloaderMode: Bool? = nil,
        deviceId: String? = nil,
        pinProtection: Bool? = nil,
        passphraseProtection: Bool? = nil,
        language: String? = nil,
        label: String? = nil,
        initialized: Bool? = nil,
        revision: Data? = nil,
        unlocked: Bool? = nil,
        needsBackup: Bool? = nil,
        model: String? = nil
    ) {
        self.vendor = vendor
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.patchVersion = patchVersion
        self.bootloaderMode = bootloaderMode
        self.deviceId = deviceId
        self.pinProtection = pinProtection
        self.passphraseProtection = passphraseProtection
        self.language = language
        self.label = label
        self.initialized = initialized
        self.revision = revision
        self.unlocked = unlocked
        self.needsBackup = needsBackup
        self.model = model
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorFeatures {
        var features = TrezorFeatures()
        var offset = 0
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: data, offset: offset)
            offset = newOffset
            
            switch (fieldNumber, wireType) {
            case (1, 2): // vendor
                let (value, nextOffset) = try decodeString(data: data, offset: offset)
                features = TrezorFeatures(
                    vendor: value,
                    majorVersion: features.majorVersion,
                    minorVersion: features.minorVersion,
                    patchVersion: features.patchVersion,
                    bootloaderMode: features.bootloaderMode,
                    deviceId: features.deviceId,
                    pinProtection: features.pinProtection,
                    passphraseProtection: features.passphraseProtection,
                    language: features.language,
                    label: features.label,
                    initialized: features.initialized,
                    revision: features.revision,
                    unlocked: features.unlocked,
                    needsBackup: features.needsBackup,
                    model: features.model
                )
                offset = nextOffset
            case (2, 0): // major_version
                let (value, nextOffset) = decodeVarint(data: data, offset: offset)
                features = TrezorFeatures(
                    vendor: features.vendor,
                    majorVersion: UInt32(value),
                    minorVersion: features.minorVersion,
                    patchVersion: features.patchVersion,
                    bootloaderMode: features.bootloaderMode,
                    deviceId: features.deviceId,
                    pinProtection: features.pinProtection,
                    passphraseProtection: features.passphraseProtection,
                    language: features.language,
                    label: features.label,
                    initialized: features.initialized,
                    revision: features.revision,
                    unlocked: features.unlocked,
                    needsBackup: features.needsBackup,
                    model: features.model
                )
                offset = nextOffset
            case (3, 0): // minor_version
                let (value, nextOffset) = decodeVarint(data: data, offset: offset)
                features = TrezorFeatures(
                    vendor: features.vendor,
                    majorVersion: features.majorVersion,
                    minorVersion: UInt32(value),
                    patchVersion: features.patchVersion,
                    bootloaderMode: features.bootloaderMode,
                    deviceId: features.deviceId,
                    pinProtection: features.pinProtection,
                    passphraseProtection: features.passphraseProtection,
                    language: features.language,
                    label: features.label,
                    initialized: features.initialized,
                    revision: features.revision,
                    unlocked: features.unlocked,
                    needsBackup: features.needsBackup,
                    model: features.model
                )
                offset = nextOffset
            case (4, 0): // patch_version
                let (value, nextOffset) = decodeVarint(data: data, offset: offset)
                features = TrezorFeatures(
                    vendor: features.vendor,
                    majorVersion: features.majorVersion,
                    minorVersion: features.minorVersion,
                    patchVersion: UInt32(value),
                    bootloaderMode: features.bootloaderMode,
                    deviceId: features.deviceId,
                    pinProtection: features.pinProtection,
                    passphraseProtection: features.passphraseProtection,
                    language: features.language,
                    label: features.label,
                    initialized: features.initialized,
                    revision: features.revision,
                    unlocked: features.unlocked,
                    needsBackup: features.needsBackup,
                    model: features.model
                )
                offset = nextOffset
            default:
                // Skip unknown fields
                offset = skipField(data: data, offset: offset, wireType: wireType)
            }
        }
        
        return features
    }
}

/// Ping message
public struct TrezorPing: TrezorMessage {
    public static let messageType: TrezorMessageType = .ping
    
    public let message: String?
    public let buttonProtection: Bool?
    
    public init(message: String? = nil, buttonProtection: Bool? = nil) {
        self.message = message
        self.buttonProtection = buttonProtection
    }
    
    public func encode() -> Data {
        var data = Data()
        if let message = message {
            data.append(contentsOf: encodeString(fieldNumber: 1, value: message))
        }
        if let buttonProtection = buttonProtection, buttonProtection {
            data.append(contentsOf: encodeBool(fieldNumber: 2, value: buttonProtection))
        }
        return data
    }
    
    public static func decode(from data: Data) throws -> TrezorPing {
        return TrezorPing()
    }
}

/// Success message
public struct TrezorSuccess: TrezorMessage {
    public static let messageType: TrezorMessageType = .success
    
    public let message: String?
    
    public init(message: String? = nil) {
        self.message = message
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorSuccess {
        var message: String?
        var offset = 0
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: data, offset: offset)
            offset = newOffset
            
            if fieldNumber == 1 && wireType == 2 {
                let (value, nextOffset) = try decodeString(data: data, offset: offset)
                message = value
                offset = nextOffset
            } else {
                offset = skipField(data: data, offset: offset, wireType: wireType)
            }
        }
        
        return TrezorSuccess(message: message)
    }
}

/// Failure message
public struct TrezorFailure: TrezorMessage {
    public static let messageType: TrezorMessageType = .failure
    
    public let code: UInt32?
    public let message: String?
    
    public init(code: UInt32? = nil, message: String? = nil) {
        self.code = code
        self.message = message
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorFailure {
        var code: UInt32?
        var message: String?
        var offset = 0
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: data, offset: offset)
            offset = newOffset
            
            switch (fieldNumber, wireType) {
            case (1, 0):
                let (value, nextOffset) = decodeVarint(data: data, offset: offset)
                code = UInt32(value)
                offset = nextOffset
            case (2, 2):
                let (value, nextOffset) = try decodeString(data: data, offset: offset)
                message = value
                offset = nextOffset
            default:
                offset = skipField(data: data, offset: offset, wireType: wireType)
            }
        }
        
        return TrezorFailure(code: code, message: message)
    }
}

/// Button request
public struct TrezorButtonRequest: TrezorMessage {
    public static let messageType: TrezorMessageType = .buttonRequest
    
    public let code: UInt32?
    
    public init(code: UInt32? = nil) {
        self.code = code
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorButtonRequest {
        return TrezorButtonRequest()
    }
}

/// Button acknowledgment
public struct TrezorButtonAck: TrezorMessage {
    public static let messageType: TrezorMessageType = .buttonAck
    
    public init() {}
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorButtonAck {
        return TrezorButtonAck()
    }
}

/// PIN matrix request
public struct TrezorPinMatrixRequest: TrezorMessage {
    public static let messageType: TrezorMessageType = .pinMatrixRequest
    
    public let type: UInt32?
    
    public init(type: UInt32? = nil) {
        self.type = type
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorPinMatrixRequest {
        return TrezorPinMatrixRequest()
    }
}

/// PIN matrix acknowledgment
public struct TrezorPinMatrixAck: TrezorMessage {
    public static let messageType: TrezorMessageType = .pinMatrixAck
    
    public let pin: String
    
    public init(pin: String) {
        self.pin = pin
    }
    
    public func encode() -> Data {
        return encodeString(fieldNumber: 1, value: pin)
    }
    
    public static func decode(from data: Data) throws -> TrezorPinMatrixAck {
        return TrezorPinMatrixAck(pin: "")
    }
}

/// Passphrase request
public struct TrezorPassphraseRequest: TrezorMessage {
    public static let messageType: TrezorMessageType = .passphraseRequest
    
    public let onDevice: Bool?
    
    public init(onDevice: Bool? = nil) {
        self.onDevice = onDevice
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorPassphraseRequest {
        return TrezorPassphraseRequest()
    }
}

/// Passphrase acknowledgment
public struct TrezorPassphraseAck: TrezorMessage {
    public static let messageType: TrezorMessageType = .passphraseAck
    
    public let passphrase: String?
    public let onDevice: Bool?
    
    public init(passphrase: String? = nil, onDevice: Bool? = nil) {
        self.passphrase = passphrase
        self.onDevice = onDevice
    }
    
    public func encode() -> Data {
        var data = Data()
        if let passphrase = passphrase {
            data.append(contentsOf: encodeString(fieldNumber: 1, value: passphrase))
        }
        if let onDevice = onDevice {
            data.append(contentsOf: encodeBool(fieldNumber: 3, value: onDevice))
        }
        return data
    }
    
    public static func decode(from data: Data) throws -> TrezorPassphraseAck {
        return TrezorPassphraseAck()
    }
}

// MARK: - Crypto Messages

/// Get public key request
public struct TrezorGetPublicKey: TrezorMessage {
    public static let messageType: TrezorMessageType = .getPublicKey
    
    public let addressN: [UInt32]
    public let ecdsaCurveName: String?
    public let showDisplay: Bool?
    public let coinName: String?
    public let scriptType: UInt32?
    
    public init(
        addressN: [UInt32],
        ecdsaCurveName: String? = nil,
        showDisplay: Bool? = nil,
        coinName: String? = nil,
        scriptType: UInt32? = nil
    ) {
        self.addressN = addressN
        self.ecdsaCurveName = ecdsaCurveName
        self.showDisplay = showDisplay
        self.coinName = coinName
        self.scriptType = scriptType
    }
    
    public func encode() -> Data {
        var data = Data()
        
        // Field 1: address_n (repeated uint32)
        for n in addressN {
            data.append(contentsOf: encodeVarintField(fieldNumber: 1, value: UInt64(n)))
        }
        
        // Field 2: ecdsa_curve_name (string)
        if let curve = ecdsaCurveName {
            data.append(contentsOf: encodeString(fieldNumber: 2, value: curve))
        }
        
        // Field 3: show_display (bool)
        if let show = showDisplay, show {
            data.append(contentsOf: encodeBool(fieldNumber: 3, value: show))
        }
        
        // Field 5: coin_name (string)
        if let coin = coinName {
            data.append(contentsOf: encodeString(fieldNumber: 5, value: coin))
        }
        
        // Field 6: script_type (enum)
        if let script = scriptType {
            data.append(contentsOf: encodeVarintField(fieldNumber: 6, value: UInt64(script)))
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> TrezorGetPublicKey {
        return TrezorGetPublicKey(addressN: [])
    }
}

/// Public key response
public struct TrezorPublicKey: TrezorMessage {
    public static let messageType: TrezorMessageType = .publicKey
    
    public let xpub: String?
    public let node: HDNodeType?
    public let rootFingerprint: UInt32?
    
    public struct HDNodeType: Sendable {
        public let depth: UInt32?
        public let fingerprint: UInt32?
        public let childNum: UInt32?
        public let chainCode: Data?
        public let publicKey: Data?
    }
    
    public init(xpub: String? = nil, node: HDNodeType? = nil, rootFingerprint: UInt32? = nil) {
        self.xpub = xpub
        self.node = node
        self.rootFingerprint = rootFingerprint
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorPublicKey {
        var xpub: String?
        var publicKey: Data?
        var chainCode: Data?
        var offset = 0
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: data, offset: offset)
            offset = newOffset
            
            switch (fieldNumber, wireType) {
            case (1, 2): // node
                let (length, nextOffset) = decodeVarint(data: data, offset: offset)
                // Parse nested HDNodeType - simplified, just extract public_key and chain_code
                let nodeEnd = nextOffset + Int(length)
                var nodeOffset = nextOffset
                while nodeOffset < nodeEnd {
                    let (nodeField, nodeWireType, nodeNewOffset) = decodeTag(data: data, offset: nodeOffset)
                    nodeOffset = nodeNewOffset
                    
                    switch (nodeField, nodeWireType) {
                    case (4, 2): // chain_code
                        let (bytes, bytesEnd) = try decodeBytes(data: data, offset: nodeOffset)
                        chainCode = bytes
                        nodeOffset = bytesEnd
                    case (5, 2): // public_key
                        let (bytes, bytesEnd) = try decodeBytes(data: data, offset: nodeOffset)
                        publicKey = bytes
                        nodeOffset = bytesEnd
                    default:
                        nodeOffset = skipField(data: data, offset: nodeOffset, wireType: nodeWireType)
                    }
                }
                offset = nodeEnd
            case (2, 2): // xpub
                let (value, nextOffset) = try decodeString(data: data, offset: offset)
                xpub = value
                offset = nextOffset
            default:
                offset = skipField(data: data, offset: offset, wireType: wireType)
            }
        }
        
        let node = HDNodeType(
            depth: nil,
            fingerprint: nil,
            childNum: nil,
            chainCode: chainCode,
            publicKey: publicKey
        )
        
        return TrezorPublicKey(xpub: xpub, node: node)
    }
}

/// Sign message request
public struct TrezorSignMessage: TrezorMessage {
    public static let messageType: TrezorMessageType = .signMessage
    
    public let addressN: [UInt32]
    public let message: Data
    public let coinName: String?
    public let scriptType: UInt32?
    public let noScriptType: Bool?
    
    public init(
        addressN: [UInt32],
        message: Data,
        coinName: String? = nil,
        scriptType: UInt32? = nil,
        noScriptType: Bool? = nil
    ) {
        self.addressN = addressN
        self.message = message
        self.coinName = coinName
        self.scriptType = scriptType
        self.noScriptType = noScriptType
    }
    
    public func encode() -> Data {
        var data = Data()
        
        for n in addressN {
            data.append(contentsOf: encodeVarintField(fieldNumber: 1, value: UInt64(n)))
        }
        
        data.append(contentsOf: encodeBytes(fieldNumber: 2, value: message))
        
        if let coin = coinName {
            data.append(contentsOf: encodeString(fieldNumber: 3, value: coin))
        }
        
        if let script = scriptType {
            data.append(contentsOf: encodeVarintField(fieldNumber: 4, value: UInt64(script)))
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> TrezorSignMessage {
        return TrezorSignMessage(addressN: [], message: Data())
    }
}

/// Message signature response
public struct TrezorMessageSignature: TrezorMessage {
    public static let messageType: TrezorMessageType = .messageSignature
    
    public let address: String?
    public let signature: Data?
    
    public init(address: String? = nil, signature: Data? = nil) {
        self.address = address
        self.signature = signature
    }
    
    public func encode() -> Data { Data() }
    
    public static func decode(from data: Data) throws -> TrezorMessageSignature {
        var address: String?
        var signature: Data?
        var offset = 0
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: data, offset: offset)
            offset = newOffset
            
            switch (fieldNumber, wireType) {
            case (1, 2): // address
                let (value, nextOffset) = try decodeString(data: data, offset: offset)
                address = value
                offset = nextOffset
            case (2, 2): // signature
                let (value, nextOffset) = try decodeBytes(data: data, offset: offset)
                signature = value
                offset = nextOffset
            default:
                offset = skipField(data: data, offset: offset, wireType: wireType)
            }
        }
        
        return TrezorMessageSignature(address: address, signature: signature)
    }
}

// MARK: - Protobuf Encoding Helpers

private func encodeTag(fieldNumber: Int, wireType: Int) -> Data {
    let tag = (fieldNumber << 3) | wireType
    return encodeVarint(UInt64(tag))
}

private func encodeVarint(_ value: UInt64) -> Data {
    var data = Data()
    var v = value
    while v > 0x7F {
        data.append(UInt8((v & 0x7F) | 0x80))
        v >>= 7
    }
    data.append(UInt8(v))
    return data
}

private func encodeVarintField(fieldNumber: Int, value: UInt64) -> Data {
    var data = encodeTag(fieldNumber: fieldNumber, wireType: 0)
    data.append(contentsOf: encodeVarint(value))
    return data
}

private func encodeString(fieldNumber: Int, value: String) -> Data {
    let bytes = value.data(using: .utf8) ?? Data()
    return encodeBytes(fieldNumber: fieldNumber, value: bytes)
}

private func encodeBytes(fieldNumber: Int, value: Data) -> Data {
    var data = encodeTag(fieldNumber: fieldNumber, wireType: 2)
    data.append(contentsOf: encodeVarint(UInt64(value.count)))
    data.append(value)
    return data
}

private func encodeBool(fieldNumber: Int, value: Bool) -> Data {
    return encodeVarintField(fieldNumber: fieldNumber, value: value ? 1 : 0)
}

// MARK: - Protobuf Decoding Helpers

private func decodeTag(data: Data, offset: Int) -> (fieldNumber: Int, wireType: Int, newOffset: Int) {
    let (tag, newOffset) = decodeVarint(data: data, offset: offset)
    let fieldNumber = Int(tag >> 3)
    let wireType = Int(tag & 0x07)
    return (fieldNumber, wireType, newOffset)
}

private func decodeVarint(data: Data, offset: Int) -> (value: UInt64, newOffset: Int) {
    var result: UInt64 = 0
    var shift = 0
    var pos = offset
    
    while pos < data.count {
        let byte = data[pos]
        result |= UInt64(byte & 0x7F) << shift
        pos += 1
        if byte & 0x80 == 0 {
            break
        }
        shift += 7
    }
    
    return (result, pos)
}

private func decodeString(data: Data, offset: Int) throws -> (value: String, newOffset: Int) {
    let (length, nextOffset) = decodeVarint(data: data, offset: offset)
    let end = nextOffset + Int(length)
    guard end <= data.count else {
        throw HWError.invalidResponse("String extends beyond data")
    }
    
    let stringData = data[nextOffset..<end]
    guard let string = String(data: stringData, encoding: .utf8) else {
        throw HWError.invalidResponse("Invalid UTF-8 string")
    }
    
    return (string, end)
}

private func decodeBytes(data: Data, offset: Int) throws -> (value: Data, newOffset: Int) {
    let (length, nextOffset) = decodeVarint(data: data, offset: offset)
    let end = nextOffset + Int(length)
    guard end <= data.count else {
        throw HWError.invalidResponse("Bytes extend beyond data")
    }
    
    return (Data(data[nextOffset..<end]), end)
}

private func skipField(data: Data, offset: Int, wireType: Int) -> Int {
    switch wireType {
    case 0: // Varint
        let (_, newOffset) = decodeVarint(data: data, offset: offset)
        return newOffset
    case 1: // 64-bit
        return offset + 8
    case 2: // Length-delimited
        let (length, nextOffset) = decodeVarint(data: data, offset: offset)
        return nextOffset + Int(length)
    case 5: // 32-bit
        return offset + 4
    default:
        return offset + 1
    }
}
