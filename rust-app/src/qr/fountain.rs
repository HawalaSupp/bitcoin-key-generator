//! Fountain Codes for Reliable QR Transmission
//!
//! Implements LT (Luby Transform) fountain codes for robust data transmission
//! over animated QR codes. Fountain codes allow the receiver to reconstruct
//! the original message from any sufficiently large subset of encoded parts.
//!
//! # Algorithm
//! 1. Original message is split into K fragments
//! 2. Each encoded part is XOR of a random subset of fragments
//! 3. Receiver collects parts until K fragments can be recovered
//! 4. Gaussian elimination recovers original fragments
//!
//! # Advantages
//! - No need to receive specific parts (any K+ε parts work)
//! - Resilient to missed frames during scanning
//! - Efficient encoding and decoding

use super::{QrError, QrResult};
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha20Rng;

/// A single fountain-encoded part
#[derive(Debug, Clone)]
pub struct FountainPart {
    /// Indexes of source fragments XORed together
    pub indexes: Vec<usize>,
    /// XOR of the source fragments
    pub data: Vec<u8>,
}

/// Fountain code encoder
pub struct FountainEncoder {
    /// Original message fragments
    fragments: Vec<Vec<u8>>,
    /// Fragment size in bytes
    fragment_size: usize,
    /// Total message length
    message_len: usize,
    /// RNG for deterministic part generation
    rng_seed: u64,
}

impl FountainEncoder {
    /// Create a new fountain encoder
    pub fn new(message: &[u8], fragment_size: usize) -> Self {
        let fragment_count = (message.len() + fragment_size - 1) / fragment_size;
        
        // Split message into fragments, padding last fragment if needed
        let mut fragments = Vec::with_capacity(fragment_count);
        for i in 0..fragment_count {
            let start = i * fragment_size;
            let end = std::cmp::min(start + fragment_size, message.len());
            
            let mut fragment = vec![0u8; fragment_size];
            fragment[..end - start].copy_from_slice(&message[start..end]);
            fragments.push(fragment);
        }
        
        // Generate random seed
        let rng_seed: u64 = rand::thread_rng().gen();
        
        Self {
            fragments,
            fragment_size,
            message_len: message.len(),
            rng_seed,
        }
    }
    
    /// Number of fragments
    pub fn fragment_count(&self) -> usize {
        self.fragments.len()
    }
    
    /// Fragment size
    pub fn fragment_size(&self) -> usize {
        self.fragment_size
    }
    
    /// Message length
    pub fn message_len(&self) -> usize {
        self.message_len
    }
    
    /// Generate the next fountain-encoded part
    pub fn next_part(&self, seq: usize) -> FountainPart {
        // Create deterministic RNG for this sequence number
        let seed = self.rng_seed.wrapping_add(seq as u64);
        let mut rng = ChaCha20Rng::seed_from_u64(seed);
        
        // Choose which fragments to XOR together
        // Use robust soliton distribution for optimal performance
        let indexes = self.choose_fragments(&mut rng);
        
        // XOR the chosen fragments
        let mut data = vec![0u8; self.fragment_size];
        for &idx in &indexes {
            xor_bytes(&mut data, &self.fragments[idx]);
        }
        
        FountainPart { indexes, data }
    }
    
    /// Choose fragments to include using robust soliton distribution
    fn choose_fragments(&self, rng: &mut ChaCha20Rng) -> Vec<usize> {
        let k = self.fragments.len();
        
        // Simplified degree distribution
        // In practice, use robust soliton distribution for better performance
        let degree = self.sample_degree(rng, k);
        
        // Choose 'degree' random fragments without replacement
        let mut available: Vec<usize> = (0..k).collect();
        let mut chosen = Vec::with_capacity(degree);
        
        for _ in 0..degree {
            if available.is_empty() {
                break;
            }
            let idx = rng.gen_range(0..available.len());
            chosen.push(available.swap_remove(idx));
        }
        
        chosen.sort();
        chosen
    }
    
    /// Sample degree from simplified robust soliton distribution
    fn sample_degree(&self, rng: &mut ChaCha20Rng, k: usize) -> usize {
        // Simplified distribution: mostly degree 1-3
        let r: f64 = rng.gen();
        
        if r < 0.5 {
            1
        } else if r < 0.8 {
            2
        } else if r < 0.95 {
            3
        } else {
            std::cmp::min(rng.gen_range(4..=10), k)
        }
    }
}

/// Fountain code decoder using Gaussian elimination
#[allow(dead_code)]
pub struct FountainDecoder {
    /// Number of fragments
    fragment_count: usize,
    /// Fragment size
    fragment_size: usize,
    /// Original message length
    message_len: usize,
    /// Received parts
    parts: Vec<FountainPart>,
    /// Recovered fragments (Some if recovered)
    recovered: Vec<Option<Vec<u8>>>,
    /// Whether decoding is complete
    complete: bool,
}

impl FountainDecoder {
    /// Create a new fountain decoder
    pub fn new(fragment_count: usize, message_len: usize) -> Self {
        let fragment_size = (message_len + fragment_count - 1) / fragment_count;
        
        Self {
            fragment_count,
            fragment_size,
            message_len,
            parts: Vec::new(),
            recovered: vec![None; fragment_count],
            complete: false,
        }
    }
    
    /// Receive a fountain-encoded part
    pub fn receive_part(&mut self, part: FountainPart) -> QrResult<()> {
        if self.complete {
            return Ok(());
        }
        
        // Simplify part using already recovered fragments
        let simplified = self.simplify_part(part);
        
        if simplified.indexes.is_empty() {
            // Part is redundant
            return Ok(());
        }
        
        if simplified.indexes.len() == 1 {
            // Direct recovery of a fragment
            let idx = simplified.indexes[0];
            self.recovered[idx] = Some(simplified.data);
            self.propagate_recovery(idx);
        } else {
            // Store for later
            self.parts.push(simplified);
        }
        
        // Check if complete
        if self.recovered.iter().all(|r| r.is_some()) {
            self.complete = true;
        }
        
        Ok(())
    }
    
    /// Simplify a part by XORing out already recovered fragments
    fn simplify_part(&self, mut part: FountainPart) -> FountainPart {
        let mut new_indexes = Vec::new();
        
        for idx in part.indexes {
            if let Some(ref fragment) = self.recovered[idx] {
                // XOR out this fragment
                xor_bytes(&mut part.data, fragment);
            } else {
                new_indexes.push(idx);
            }
        }
        
        part.indexes = new_indexes;
        part
    }
    
    /// Propagate a newly recovered fragment through stored parts
    fn propagate_recovery(&mut self, recovered_idx: usize) {
        let fragment = self.recovered[recovered_idx].clone().unwrap();
        
        let mut i = 0;
        while i < self.parts.len() {
            if self.parts[i].indexes.contains(&recovered_idx) {
                // XOR out the recovered fragment
                xor_bytes(&mut self.parts[i].data, &fragment);
                self.parts[i].indexes.retain(|&x| x != recovered_idx);
                
                if self.parts[i].indexes.len() == 1 {
                    // This part now directly recovers a fragment
                    let part = self.parts.swap_remove(i);
                    let idx = part.indexes[0];
                    self.recovered[idx] = Some(part.data);
                    self.propagate_recovery(idx);
                    continue; // Don't increment i since we swapped
                } else if self.parts[i].indexes.is_empty() {
                    // Redundant part
                    self.parts.swap_remove(i);
                    continue;
                }
            }
            i += 1;
        }
    }
    
    /// Check if decoding is complete
    pub fn is_complete(&self) -> bool {
        self.complete
    }
    
    /// Check if decoding is possible (might need more parts)
    pub fn can_decode(&self) -> bool {
        let recovered_count = self.recovered.iter().filter(|r| r.is_some()).count();
        recovered_count == self.fragment_count
    }
    
    /// Get decoding progress (0.0 to 1.0)
    pub fn progress(&self) -> f32 {
        let recovered = self.recovered.iter().filter(|r| r.is_some()).count();
        recovered as f32 / self.fragment_count as f32
    }
    
    /// Get the decoded result
    pub fn result(&self) -> QrResult<Vec<u8>> {
        if !self.complete {
            return Err(QrError::DecodingIncomplete);
        }
        
        let mut message = Vec::with_capacity(self.message_len);
        
        for fragment in &self.recovered {
            let fragment = fragment.as_ref()
                .ok_or(QrError::DecodingIncomplete)?;
            message.extend_from_slice(fragment);
        }
        
        // Trim to original message length
        message.truncate(self.message_len);
        
        Ok(message)
    }
    
    /// Get statistics about the decoder state
    pub fn stats(&self) -> DecoderStats {
        let recovered = self.recovered.iter().filter(|r| r.is_some()).count();
        
        DecoderStats {
            fragment_count: self.fragment_count,
            recovered_count: recovered,
            pending_parts: self.parts.len(),
            is_complete: self.complete,
            progress: recovered as f32 / self.fragment_count as f32,
        }
    }
}

/// Decoder statistics
#[derive(Debug, Clone)]
pub struct DecoderStats {
    pub fragment_count: usize,
    pub recovered_count: usize,
    pub pending_parts: usize,
    pub is_complete: bool,
    pub progress: f32,
}

/// XOR bytes in place
fn xor_bytes(target: &mut [u8], source: &[u8]) {
    for (t, s) in target.iter_mut().zip(source.iter()) {
        *t ^= s;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_fountain_roundtrip() {
        let message = b"Hello, World! This is a test message for fountain codes.";
        let fragment_size = 10;
        
        let encoder = FountainEncoder::new(message, fragment_size);
        let mut decoder = FountainDecoder::new(
            encoder.fragment_count(),
            encoder.message_len(),
        );
        
        // Generate enough parts to decode
        for seq in 0..50 {
            let part = encoder.next_part(seq);
            decoder.receive_part(part).unwrap();
            
            if decoder.is_complete() {
                break;
            }
        }
        
        assert!(decoder.is_complete());
        
        let result = decoder.result().unwrap();
        assert_eq!(result, message.to_vec());
    }
    
    #[test]
    fn test_fountain_with_losses() {
        let message = b"Testing fountain codes with simulated packet loss";
        let fragment_size = 5;
        
        let encoder = FountainEncoder::new(message, fragment_size);
        let mut decoder = FountainDecoder::new(
            encoder.fragment_count(),
            encoder.message_len(),
        );
        
        // Skip every other part to simulate 50% loss
        for seq in 0..100 {
            if seq % 2 == 0 {
                continue; // Simulated loss
            }
            
            let part = encoder.next_part(seq);
            decoder.receive_part(part).unwrap();
            
            if decoder.is_complete() {
                break;
            }
        }
        
        assert!(decoder.is_complete());
        
        let result = decoder.result().unwrap();
        assert_eq!(result, message.to_vec());
    }
    
    #[test]
    fn test_decoder_stats() {
        let encoder = FountainEncoder::new(b"Test", 2);
        let decoder = FountainDecoder::new(
            encoder.fragment_count(),
            4,
        );
        
        let stats = decoder.stats();
        assert_eq!(stats.fragment_count, 2);
        assert_eq!(stats.recovered_count, 0);
        assert!(!stats.is_complete);
    }
    
    #[test]
    fn test_xor_bytes() {
        let mut a = vec![0xFF, 0x00, 0xAA];
        let b = vec![0xFF, 0xFF, 0x55];
        
        xor_bytes(&mut a, &b);
        
        assert_eq!(a, vec![0x00, 0xFF, 0xFF]);
    }
}
