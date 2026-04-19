import Foundation

// MARK: - Secure Memory Buffer

/// A buffer that securely holds sensitive data and zeros memory on deallocation.
/// Use this for temporarily holding seeds, private keys, and passphrases.
///
/// Features:
/// - Automatic memory zeroing on deallocation
/// - Redacted debug/print output
/// - Prevents accidental logging of secrets
final class SecureMemoryBuffer: @unchecked Sendable {
    
    /// The underlying data storage
    private var storage: Data
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Whether the buffer has been zeroed
    private var isZeroed = false
    
    // MARK: - Initialization
    
    /// Create a buffer with the given data
    init(data: Data) {
        self.storage = data
    }
    
    /// Create a buffer from a string (UTF-8 encoded)
    init?(string: String) {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        self.storage = data
    }
    
    /// Create an empty buffer of specified size
    init(size: Int) {
        self.storage = Data(count: size)
    }
    
    deinit {
        zeroMemory()
    }
    
    // MARK: - Access
    
    /// Access the data safely
    /// - Parameter body: Closure that receives the data
    /// - Returns: Result of the closure
    func withData<T>(_ body: (Data) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isZeroed else {
            return try body(Data())
        }
        
        return try body(storage)
    }
    
    /// Access the bytes safely
    /// - Parameter body: Closure that receives the bytes
    /// - Returns: Result of the closure
    func withBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isZeroed else {
            return try Data().withUnsafeBytes(body)
        }
        
        return try storage.withUnsafeBytes(body)
    }
    
    /// Get data as string (UTF-8)
    func asString() -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isZeroed else { return nil }
        return String(data: storage, encoding: .utf8)
    }
    
    /// Get the size of the buffer
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
    
    // MARK: - Memory Management
    
    /// Zero out the memory immediately
    func zeroMemory() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isZeroed else { return }
        
        // Zero each byte
        storage.withUnsafeMutableBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                memset(baseAddress, 0, bytes.count)
            }
        }
        
        // Replace with empty data
        storage = Data()
        isZeroed = true
    }
    
    /// Check if the buffer has been zeroed
    var isCleared: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isZeroed
    }
}

// MARK: - CustomStringConvertible (Redacted)

extension SecureMemoryBuffer: CustomStringConvertible {
    var description: String {
        "[REDACTED SecureMemoryBuffer: \(count) bytes]"
    }
}

// MARK: - CustomDebugStringConvertible (Redacted)

extension SecureMemoryBuffer: CustomDebugStringConvertible {
    var debugDescription: String {
        "[REDACTED SecureMemoryBuffer: \(count) bytes, zeroed: \(isZeroed)]"
    }
}

// MARK: - Secure String

/// A string wrapper that zeros memory on deallocation and redacts in logs.
/// Use for seed phrases, passwords, and other sensitive strings.
struct SecureString: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    
    /// The underlying secure buffer
    private let buffer: SecureMemoryBuffer
    
    /// Create from a string
    init(_ string: String) {
        self.buffer = SecureMemoryBuffer(string: string) ?? SecureMemoryBuffer(size: 0)
    }
    
    /// Get the string value (use sparingly)
    var value: String {
        buffer.asString() ?? ""
    }
    
    /// Zero the memory
    func clear() {
        buffer.zeroMemory()
    }
    
    /// Whether the string has been cleared
    var isCleared: Bool {
        buffer.isCleared
    }
    
    // Redacted output
    var description: String { "[REDACTED]" }
    var debugDescription: String { "[REDACTED SecureString]" }
}

// MARK: - Extensions for Sensitive Data

extension Data {
    /// Create a secure copy that will be zeroed when the buffer is deallocated
    func toSecureBuffer() -> SecureMemoryBuffer {
        SecureMemoryBuffer(data: self)
    }
}

extension String {
    /// Create a secure copy that will be zeroed when the buffer is deallocated
    func toSecureString() -> SecureString {
        SecureString(self)
    }
}
