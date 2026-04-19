//
//  LedgerTransport.swift
//  Hawala
//
//  Ledger Hardware Wallet Transport Layer
//
//  Implements low-level USB HID and Bluetooth communication with Ledger devices.
//  Uses APDU (Application Protocol Data Unit) framing over HID frames.
//

import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid
@preconcurrency import CoreBluetooth

// MARK: - Ledger Transport Protocol

/// Protocol for Ledger device transport (USB or Bluetooth)
public protocol LedgerTransportProtocol: AnyObject, Sendable {
    /// Whether the transport is connected
    var isConnected: Bool { get async }
    
    /// Open the transport connection
    func open() async throws
    
    /// Close the transport connection
    func close() async throws
    
    /// Exchange APDU command/response
    /// - Parameter apdu: APDU command bytes
    /// - Returns: Response bytes (without status word for errors)
    func exchange(_ apdu: Data) async throws -> Data
}

// MARK: - Ledger APDU Protocol

/// Ledger APDU command structure (V2 - renamed to avoid conflict)
public struct LedgerAPDUCommand: Sendable {
    // Class bytes for different apps
    public static let claCommon: UInt8 = 0xB0
    public static let claBitcoin: UInt8 = 0xE0
    public static let claEthereum: UInt8 = 0xE0
    public static let claSolana: UInt8 = 0xE0
    public static let claCosmos: UInt8 = 0x55
    
    /// Build an APDU command
    /// - Parameters:
    ///   - cla: Class byte
    ///   - ins: Instruction byte
    ///   - p1: Parameter 1
    ///   - p2: Parameter 2
    ///   - data: Optional data payload
    ///   - le: Expected response length (0 = variable)
    /// - Returns: Complete APDU bytes
    public static func build(cla: UInt8, ins: UInt8, p1: UInt8 = 0, p2: UInt8 = 0, data: Data? = nil, le: UInt8? = nil) -> Data {
        var apdu = Data([cla, ins, p1, p2])
        
        if let data = data {
            if data.count <= 255 {
                apdu.append(UInt8(data.count))
            } else {
                // Extended length encoding
                apdu.append(0x00)
                apdu.append(UInt8((data.count >> 8) & 0xFF))
                apdu.append(UInt8(data.count & 0xFF))
            }
            apdu.append(data)
        } else if le != nil {
            apdu.append(0x00) // No data, just Le
        }
        
        if let le = le {
            apdu.append(le)
        }
        
        return apdu
    }
    
    /// Parse APDU response to extract data and status word
    public static func parseResponse(_ response: Data) -> (data: Data, statusWord: UInt16)? {
        guard response.count >= 2 else { return nil }
        
        let sw1 = response[response.count - 2]
        let sw2 = response[response.count - 1]
        let statusWord = UInt16(sw1) << 8 | UInt16(sw2)
        let data = response.dropLast(2)
        
        return (Data(data), statusWord)
    }
}

// MARK: - USB HID Transport

/// USB HID transport for Ledger devices
public actor LedgerUSBTransport: LedgerTransportProtocol {
    // HID framing constants
    private static let hidPacketSize = 64
    private static let channelId: UInt16 = 0x0101
    private static let tagAPDU: UInt8 = 0x05
    
    // Device reference
    private var device: IOHIDDevice?
    private let deviceInfo: DiscoveredDevice
    
    // Communication state
    private var isOpen = false
    private var sequenceNumber: UInt16 = 0
    
    // Response handling
    private var pendingResponse: CheckedContinuation<Data, Error>?
    private var responseBuffer = Data()
    private var expectedLength: Int = 0
    
    // Timeout
    private let timeout: TimeInterval = 30.0
    
    public var isConnected: Bool {
        isOpen && device != nil
    }
    
    public init(deviceInfo: DiscoveredDevice) {
        self.deviceInfo = deviceInfo
    }
    
    public func open() async throws {
        guard !isOpen else { return }
        
        // Find and open the HID device
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Build matching dictionary
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
        
        // Get matching devices
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let foundDevice = deviceSet.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HWError.deviceNotFound
        }
        
        device = foundDevice
        isOpen = true
        
        // Set up input report callback
        setupInputCallback()
    }
    
    public func close() async throws {
        guard isOpen else { return }
        
        device = nil
        isOpen = false
        sequenceNumber = 0
    }
    
    public func exchange(_ apdu: Data) async throws -> Data {
        guard isOpen, let device = device else {
            throw HWError.deviceDisconnected
        }
        
        // Reset state
        responseBuffer = Data()
        expectedLength = 0
        sequenceNumber = 0
        
        // Frame and send the APDU
        let frames = frameAPDU(apdu)
        
        for frame in frames {
            try sendFrame(frame, to: device)
        }
        
        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingResponse = continuation
            
            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.pendingResponse {
                    self.pendingResponse = nil
                    pending.resume(throwing: HWError.timeout)
                }
            }
        }
    }
    
    // MARK: - HID Framing
    
    /// Frame APDU into HID packets
    private func frameAPDU(_ apdu: Data) -> [Data] {
        var frames: [Data] = []
        var offset = 0
        var seq: UInt16 = 0
        
        while offset < apdu.count {
            var frame = Data(count: Self.hidPacketSize)
            var frameOffset = 0
            
            // Channel ID (2 bytes, big endian)
            frame[frameOffset] = UInt8((Self.channelId >> 8) & 0xFF)
            frame[frameOffset + 1] = UInt8(Self.channelId & 0xFF)
            frameOffset += 2
            
            // Tag
            frame[frameOffset] = Self.tagAPDU
            frameOffset += 1
            
            // Sequence number (2 bytes, big endian)
            frame[frameOffset] = UInt8((seq >> 8) & 0xFF)
            frame[frameOffset + 1] = UInt8(seq & 0xFF)
            frameOffset += 2
            
            if seq == 0 {
                // First frame: include length (2 bytes)
                frame[frameOffset] = UInt8((apdu.count >> 8) & 0xFF)
                frame[frameOffset + 1] = UInt8(apdu.count & 0xFF)
                frameOffset += 2
            }
            
            // Fill with data
            let remainingFrame = Self.hidPacketSize - frameOffset
            let dataLen = min(remainingFrame, apdu.count - offset)
            
            for i in 0..<dataLen {
                frame[frameOffset + i] = apdu[offset + i]
            }
            
            offset += dataLen
            seq += 1
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
        guard frame.count >= 7 else { return }
        
        // Parse header
        let channelId = UInt16(frame[0]) << 8 | UInt16(frame[1])
        guard channelId == Self.channelId else { return }
        
        let tag = frame[2]
        guard tag == Self.tagAPDU else { return }
        
        let seq = UInt16(frame[3]) << 8 | UInt16(frame[4])
        var dataOffset = 5
        
        if seq == 0 {
            // First frame: read length
            expectedLength = Int(frame[5]) << 8 | Int(frame[6])
            dataOffset = 7
        }
        
        // Append data
        let dataEnd = min(frame.count, dataOffset + expectedLength - responseBuffer.count)
        responseBuffer.append(frame[dataOffset..<dataEnd])
        
        // Check if complete
        if responseBuffer.count >= expectedLength {
            if let pending = pendingResponse {
                pendingResponse = nil
                pending.resume(returning: responseBuffer)
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
                let transport = Unmanaged<LedgerUSBTransport>.fromOpaque(context).takeUnretainedValue()
                
                let data = Data(bytes: report, count: reportLength)
                Task {
                    await transport.handleFrame(data)
                }
            },
            context
        )
    }
}

// MARK: - Bluetooth Transport

/// Bluetooth LE transport for Ledger Nano X
public final class LedgerBluetoothTransport: NSObject, LedgerTransportProtocol, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    // Ledger BLE UUIDs - stored in instance to avoid static mutable state
    private let serviceUUID = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")
    private let writeUUID = CBUUID(string: "13D63400-2C97-0004-0002-4C6564676572")
    private let notifyUUID = CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572")
    
    // BLE state
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    // Connection state (protected by MainActor)
    private var _isConnected = false
    
    // Response handling
    private var responseBuffer = Data()
    private var expectedLength = 0
    private var pendingResponse: CheckedContinuation<Data, Error>?
    
    // MTU for BLE communication
    private var mtu: Int = 20
    
    private let deviceInfo: DiscoveredDevice
    private let timeout: TimeInterval = 30.0
    
    public var isConnected: Bool {
        get async {
            return _isConnected
        }
    }
    
    public init(deviceInfo: DiscoveredDevice) {
        self.deviceInfo = deviceInfo
        super.init()
    }
    
    public func open() async throws {
        centralManager = CBCentralManager(delegate: self, queue: .main)
        
        // Wait for Bluetooth to be ready and connect
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Connection will be handled in delegate callbacks
            // For now, we'll need to track connection state
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self else { return }
                if !self._isConnected {
                    continuation.resume(throwing: HWError.timeout)
                }
            }
        }
    }
    
    public func close() async throws {
        if let peripheral = peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        _isConnected = false
        
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }
    
    public func exchange(_ apdu: Data) async throws -> Data {
        guard let write = writeCharacteristic, let peripheral = peripheral else {
            throw HWError.deviceDisconnected
        }
        
        responseBuffer = Data()
        expectedLength = 0
        
        // Frame APDU for BLE (similar to USB but smaller MTU)
        let frames = frameAPDU(apdu, mtu: mtu)
        
        for frame in frames {
            peripheral.writeValue(frame, for: write, type: .withResponse)
        }
        
        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingResponse = continuation
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if let pending = self?.pendingResponse {
                    self?.pendingResponse = nil
                    pending.resume(throwing: HWError.timeout)
                }
            }
        }
    }
    
    /// Frame APDU for BLE
    private func frameAPDU(_ apdu: Data, mtu: Int) -> [Data] {
        var frames: [Data] = []
        var offset = 0
        var seq: UInt16 = 0
        
        while offset < apdu.count {
            var frame = Data()
            
            // Add sequence number
            frame.append(UInt8((seq >> 8) & 0xFF))
            frame.append(UInt8(seq & 0xFF))
            
            if seq == 0 {
                // First frame: include total length
                frame.append(UInt8((apdu.count >> 8) & 0xFF))
                frame.append(UInt8(apdu.count & 0xFF))
            }
            
            // Calculate available space
            let headerSize = seq == 0 ? 4 : 2
            let available = mtu - headerSize
            let dataLen = min(available, apdu.count - offset)
            
            frame.append(apdu[offset..<(offset + dataLen)])
            
            offset += dataLen
            seq += 1
            frames.append(frame)
        }
        
        return frames
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        pendingResponse?.resume(throwing: HWError.connectionFailed(error?.localizedDescription ?? "Unknown"))
        pendingResponse = nil
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            if char.uuid == writeUUID {
                writeCharacteristic = char
            } else if char.uuid == notifyUUID {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        // Negotiate MTU
        mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        
        _isConnected = true
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyUUID, let value = characteristic.value else { return }
        
        handleFrame(value)
    }
    
    private func handleFrame(_ frame: Data) {
        guard frame.count >= 2 else { return }
        
        let seq = UInt16(frame[0]) << 8 | UInt16(frame[1])
        var dataOffset = 2
        
        if seq == 0 && frame.count >= 4 {
            expectedLength = Int(frame[2]) << 8 | Int(frame[3])
            dataOffset = 4
        }
        
        responseBuffer.append(frame[dataOffset...])
        
        if responseBuffer.count >= expectedLength {
            if let pending = pendingResponse {
                pendingResponse = nil
                pending.resume(returning: responseBuffer)
            }
        }
    }
}

// MARK: - Transport Factory

/// Factory for creating appropriate Ledger transport
public enum LedgerTransportFactory {
    /// Create a transport for the given device
    public static func create(for device: DiscoveredDevice) -> LedgerTransportProtocol {
        switch device.connectionType {
        case .usb:
            return LedgerUSBTransport(deviceInfo: device)
        case .bluetooth:
            return LedgerBluetoothTransport(deviceInfo: device)
        }
    }
}
