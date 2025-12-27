import Foundation

// MARK: - Keccak-256 Hash

/// Keccak-256 hash implementation for Ethereum-compatible hashing
/// Note: Keccak-256 is NOT the same as SHA3-256 (different padding)
enum Keccak256 {
    
    /// Compute Keccak-256 hash of data
    static func hash(data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rateInBytes = 136 // (1600 - 256 * 2) / 8
        
        var input = data
        // Keccak padding (different from SHA3!)
        input.append(0x01)
        while input.count % rateInBytes != rateInBytes - 1 {
            input.append(0x00)
        }
        input.append(0x80)
        
        // Process blocks
        for blockStart in stride(from: 0, to: input.count, by: rateInBytes) {
            for i in 0..<(rateInBytes / 8) {
                let offset = blockStart + i * 8
                if offset + 8 <= input.count {
                    var value: UInt64 = 0
                    for j in 0..<8 {
                        value |= UInt64(input[offset + j]) << (j * 8)
                    }
                    state[i] ^= value
                }
            }
            keccakF1600(&state)
        }
        
        // Extract 32-byte output
        var output = Data()
        for i in 0..<4 {
            var value = state[i]
            for _ in 0..<8 {
                output.append(UInt8(value & 0xff))
                value >>= 8
            }
        }
        
        return output
    }
    
    /// Compute Keccak-256 hash of string (UTF-8 encoded)
    static func hash(string: String) -> Data {
        hash(data: Data(string.utf8))
    }
    
    /// Compute Keccak-256 hash and return as hex string
    static func hashHex(data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Keccak-f[1600] Permutation
    
    private static func keccakF1600(_ state: inout [UInt64]) {
        let roundConstants: [UInt64] = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
            0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
            0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
            0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
            0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
        ]
        
        let rotations: [[Int]] = [
            [0, 36, 3, 41, 18],
            [1, 44, 10, 45, 2],
            [62, 6, 43, 15, 61],
            [28, 55, 25, 21, 56],
            [27, 20, 39, 8, 14]
        ]
        
        for round in 0..<24 {
            // θ (theta)
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotateLeft(c[(x + 1) % 5], by: 1)
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + y * 5] ^= d[x]
                }
            }
            
            // ρ (rho) and π (pi)
            var temp = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    let newX = y
                    let newY = (2 * x + 3 * y) % 5
                    temp[newX + newY * 5] = rotateLeft(state[x + y * 5], by: rotations[y][x])
                }
            }
            state = temp
            
            // χ (chi)
            for y in 0..<5 {
                var row = [UInt64](repeating: 0, count: 5)
                for x in 0..<5 {
                    row[x] = state[x + y * 5]
                }
                for x in 0..<5 {
                    state[x + y * 5] = row[x] ^ ((~row[(x + 1) % 5]) & row[(x + 2) % 5])
                }
            }
            
            // ι (iota)
            state[0] ^= roundConstants[round]
        }
    }
    
    private static func rotateLeft(_ value: UInt64, by count: Int) -> UInt64 {
        let count = count % 64
        return (value << count) | (value >> (64 - count))
    }
}
