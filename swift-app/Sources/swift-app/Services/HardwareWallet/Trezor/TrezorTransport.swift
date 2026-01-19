//
//  TrezorTransport.swift
//  Hawala
//
//  Trezor Hardware Wallet Transport Layer
//
//  Implements USB HID communication with Trezor devices using their
//  Protobuf-based message protocol.
//

import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

// MARK: - Trezor Transport Protocol

/// Protocol for Trezor device transport
public protocol TrezorTransportProtocol: AnyObject, Sendable {
    /// Whether the transport is connected
    var isConnected: Bool { get async }
    
    /// Open the transport connection
    func open() async throws
    
    /// Close the transport connection
    func close() async throws
    
    /// Exchange a Trezor message
    /// - Parameters:
    ///   - messageType: Trezor message type ID
    ///   - data: Serialized protobuf message data
    /// - Returns: Tuple of (response message type, response data)
    func exchange(messageType: UInt16, data: Data) async throws -> (messageType: UInt16, data: Data)
}

// MARK: - Trezor Message Types

/// Common Trezor message type IDs
public enum TrezorMessageType: UInt16, Sendable {
    // Core messages
    case initialize = 0
    case ping = 1
    case success = 2
    case failure = 3
    case changePin = 4
    case wipeDevice = 5
    case getEntropy = 9
    case entropy = 10
    case loadDevice = 13
    case resetDevice = 14
    case features = 17
    case pinMatrixRequest = 18
    case pinMatrixAck = 19
    case cancel = 20
    case applySettings = 25
    case buttonRequest = 26
    case buttonAck = 27
    case applyFlags = 28
    case getNextU2FCounter = 80
    case nextU2FCounter = 81
    case doPreauthorized = 84
    case preauthorizedRequest = 85
    case cancelAuthorization = 86
    
    // Crypto
    case getPublicKey = 11
    case publicKey = 12
    case signTx = 15
    case txRequest = 21
    case txAck = 22
    case signMessage = 38
    case verifyMessage = 39
    case messageSignature = 40
    
    // Ethereum
    case ethereumGetPublicKey = 450
    case ethereumPublicKey = 451
    case ethereumSignTx = 58
    case ethereumTxRequest = 59
    case ethereumSignMessage = 64
    case ethereumMessageSignature = 66
    case ethereumSignTypedData = 464
    case ethereumTypedDataStructRequest = 465
    case ethereumTypedDataStructAck = 466
    case ethereumTypedDataValueRequest = 467
    case ethereumTypedDataValueAck = 468
    case ethereumTypedDataSignature = 469
    case ethereumSignTypedHash = 470
    
    // Solana
    case solanaGetPublicKey = 512
    case solanaPublicKey = 513
    case solanaSignTx = 514
    case solanaSignedTx = 515
    case solanaGetAddress = 516
    case solanaAddress = 517
    
    // Cardano
    case cardanoGetPublicKey = 305
    case cardanoPublicKey = 306
    case cardanoSignTxInit = 307
    case cardanoSignTxFinished = 308
    
    // Passphrase
    case passphraseRequest = 41
    case passphraseAck = 42
    case passphraseSt0ateRequest = 77
    case passphraseStateAck = 78
    
    // Device info
    case getDeviceId = 55
    case deviceId = 56
}

// MARK: - Trezor USB Transport

/// USB HID transport for Trezor devices
public actor TrezorUSBTransport: TrezorTransportProtocol {
    // HID framing constants
    private static let hidPacketSize = 64
    private static let magicV1: [UInt8] = [0x23, 0x23] // "##"
    private static let magicV2: [UInt8] = [0x3F, 0x23, 0x23] // "?##"
    
    // Device reference
    private var device: IOHIDDevice?
    private let deviceInfo: DiscoveredDevice
    
    // Communication state
    private var isOpen = false
    private var usesV2Protocol: Bool
    
    // Response handling
    private var pendingResponse: CheckedContinuation<(messageType: UInt16, data: Data), Error>?
    private var responseBuffer = Data()
    private var expectedLength: Int = 0
    private var responseMessageType: UInt16 = 0
    
    // Timeout
    private let timeout: TimeInterval = 60.0 // Longer for user interaction
    
    public var isConnected: Bool {
        isOpen && device != nil
    }
    
    public init(deviceInfo: DiscoveredDevice) {
        self.deviceInfo = deviceInfo
        // Trezor Model T uses V2 protocol, Trezor One uses V1
        self.usesV2Protocol = deviceInfo.deviceType == .trezorModelT || deviceInfo.deviceType == .trezorSafe3
    }
    
    public func open() async throws {
        guard !isOpen else { return }
        
        // Perform HID setup (IOKit calls are sync and should work in any context)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Build matching dictionary for Trezor
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: deviceInfo.deviceType.vendorId,
            kIOHIDProductIDKey as String: deviceInfo.deviceType.productIds.first as Any
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HWError.connectionFailed("Failed to open HID manager: \(result)")
        }
        
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let foundDevice = deviceSet.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HWError.deviceNotFound
        }
        
        device = foundDevice
        isOpen = true
        
        setupInputCallback()
    }
    
    public func close() async throws {
        guard isOpen else { return }
        
        device = nil
        isOpen = false
    }
    
    public func exchange(messageType: UInt16, data: Data) async throws -> (messageType: UInt16, data: Data) {
        guard isOpen, let device = device else {
            throw HWError.deviceDisconnected
        }
        
        // Reset state
        responseBuffer = Data()
        expectedLength = 0
        responseMessageType = 0
        
        // Frame and send the message
        let frames = frameMessage(type: messageType, data: data)
        
        for frame in frames {
            try sendFrame(frame, to: device)
        }
        
        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingResponse = continuation
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.pendingResponse {
                    self.pendingResponse = nil
                    pending.resume(throwing: HWError.timeout)
                }
            }
        }
    }
    
    // MARK: - Message Framing
    
    /// Frame a Trezor message into HID packets
    private func frameMessage(type: UInt16, data: Data) -> [Data] {
        var frames: [Data] = []
        
        // Build message header
        var header = Data()
        if usesV2Protocol {
            header.append(0x3F) // Report ID for V2
        }
        header.append(contentsOf: [0x23, 0x23]) // "##" magic
        header.append(UInt8((type >> 8) & 0xFF))
        header.append(UInt8(type & 0xFF))
        
        // Message length (4 bytes, big-endian)
        let len = UInt32(data.count)
        header.append(UInt8((len >> 24) & 0xFF))
        header.append(UInt8((len >> 16) & 0xFF))
        header.append(UInt8((len >> 8) & 0xFF))
        header.append(UInt8(len & 0xFF))
        
        // Combine header and data
        var fullMessage = header
        fullMessage.append(data)
        
        // Split into frames
        var offset = 0
        while offset < fullMessage.count {
            var frame = Data(count: Self.hidPacketSize)
            
            let startIdx = usesV2Protocol ? 1 : 0
            if offset == 0 {
                // First frame contains the header
                let toCopy = min(fullMessage.count, Self.hidPacketSize - startIdx)
                for i in 0..<toCopy {
                    frame[startIdx + i] = fullMessage[i]
                }
                offset = toCopy
            } else {
                // Continuation frame
                if usesV2Protocol {
                    frame[0] = 0x3F // Report ID
                }
                frame[startIdx] = 0x3F // "?" for continuation
                
                let available = Self.hidPacketSize - startIdx - 1
                let remaining = fullMessage.count - offset
                let toCopy = min(available, remaining)
                
                for i in 0..<toCopy {
                    frame[startIdx + 1 + i] = fullMessage[offset + i]
                }
                offset += toCopy
            }
            
            frames.append(frame)
        }
        
        return frames
    }
    
    /// Send a single HID frame
    private func sendFrame(_ frame: Data, to device: IOHIDDevice) throws {
        let result = frame.withUnsafeBytes { ptr in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                frame.count
            )
        }
        
        guard result == kIOReturnSuccess else {
            throw HWError.communicationError("Failed to send HID report: \(result)")
        }
    }
    
    /// Handle received HID frame
    private func handleFrame(_ frame: Data) {
        let startIdx = usesV2Protocol ? 1 : 0
        
        guard frame.count > startIdx + 1 else { return }
        
        if frame[startIdx] == 0x23 && frame[startIdx + 1] == 0x23 {
            // First frame with header
            guard frame.count >= startIdx + 9 else { return }
            
            // Parse message type
            responseMessageType = UInt16(frame[startIdx + 2]) << 8 | UInt16(frame[startIdx + 3])
            
            // Parse length
            let len = UInt32(frame[startIdx + 4]) << 24 |
                      UInt32(frame[startIdx + 5]) << 16 |
                      UInt32(frame[startIdx + 6]) << 8 |
                      UInt32(frame[startIdx + 7])
            expectedLength = Int(len)
            
            // Extract data
            let dataStart = startIdx + 8
            let dataEnd = min(frame.count, dataStart + expectedLength)
            responseBuffer.append(frame[dataStart..<dataEnd])
            
        } else if frame[startIdx] == 0x3F {
            // Continuation frame
            let dataStart = startIdx + 1
            let remaining = expectedLength - responseBuffer.count
            let dataEnd = min(frame.count, dataStart + remaining)
            responseBuffer.append(frame[dataStart..<dataEnd])
        }
        
        // Check if complete
        if responseBuffer.count >= expectedLength && expectedLength > 0 {
            if let pending = pendingResponse {
                pendingResponse = nil
                pending.resume(returning: (messageType: responseMessageType, data: responseBuffer))
            }
        }
    }
    
    /// Set up HID input callback
    private func setupInputCallback() {
        guard let device = device else { return }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDDeviceRegisterInputReportCallback(
            device,
            UnsafeMutablePointer<UInt8>.allocate(capacity: Self.hidPacketSize),
            Self.hidPacketSize,
            { context, result, sender, type, reportId, report, reportLength in
                guard let context = context, result == kIOReturnSuccess else { return }
                let transport = Unmanaged<TrezorUSBTransport>.fromOpaque(context).takeUnretainedValue()
                
                let data = Data(bytes: report, count: reportLength)
                Task {
                    await transport.handleFrame(data)
                }
            },
            context
        )
    }
}

// MARK: - Transport Factory

/// Factory for creating Trezor transport
public enum TrezorTransportFactory {
    /// Create a transport for the given device
    public static func create(for device: DiscoveredDevice) -> TrezorTransportProtocol {
        return TrezorUSBTransport(deviceInfo: device)
    }
}
