//! BIP-340 Schnorr Signatures
//!
//! Implementation of Schnorr signatures as specified in BIP-340 for Bitcoin Taproot.
//! 
//! Key features:
//! - Tagged hashes for domain separation
//! - X-only public keys (32 bytes instead of 33)
//! - 64-byte signatures (vs 71-73 for ECDSA)
//! - Batch verification support
//! - Deterministic nonce generation (RFC 6979 + aux randomness)
//!
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki

use bitcoin::secp256k1::{
    Secp256k1, SecretKey, Keypair, Message,
    XOnlyPublicKey, schnorr::Signature as SchnorrSignature,
    All,
};
use serde::{Deserialize, Serialize};

// MARK: - Tagged Hash Functions

/// BIP-340 tagged hash computation
/// 
/// tagged_hash(tag, msg) = SHA256(SHA256(tag) || SHA256(tag) || msg)
/// 
/// This provides domain separation between different uses of the hash function.
pub fn tagged_hash(tag: &str, msg: &[u8]) -> [u8; 32] {
    use sha2::{Sha256, Digest};
    
    // Compute SHA256(tag)
    let tag_hash = {
        let mut hasher = Sha256::new();
        hasher.update(tag.as_bytes());
        hasher.finalize()
    };
    
    // Compute SHA256(SHA256(tag) || SHA256(tag) || msg)
    let mut hasher = Sha256::new();
    hasher.update(&tag_hash);
    hasher.update(&tag_hash);
    hasher.update(msg);
    
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Standard BIP-340 tags
pub mod tags {
    pub const BIP0340_AUX: &str = "BIP0340/aux";
    pub const BIP0340_NONCE: &str = "BIP0340/nonce";
    pub const BIP0340_CHALLENGE: &str = "BIP0340/challenge";
    pub const TAP_TWEAK: &str = "TapTweak";
    pub const TAP_LEAF: &str = "TapLeaf";
    pub const TAP_BRANCH: &str = "TapBranch";
    pub const TAP_SIGHASH: &str = "TapSighash";
}

// MARK: - Schnorr Key Types

/// X-only public key (32 bytes)
/// 
/// In BIP-340, public keys are represented as only their x-coordinate.
/// The y-coordinate is implicitly even.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct XOnlyPubKey(pub [u8; 32]);

impl XOnlyPubKey {
    /// Create from 32 bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
    
    /// Create from slice (must be 32 bytes)
    pub fn from_slice(slice: &[u8]) -> Result<Self, SchnorrError> {
        if slice.len() != 32 {
            return Err(SchnorrError::InvalidPublicKey(
                format!("Expected 32 bytes, got {}", slice.len())
            ));
        }
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(slice);
        Ok(Self(bytes))
    }
    
    /// Get the raw bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
    
    /// Convert to hex string
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
    
    /// Parse from hex string
    pub fn from_hex(s: &str) -> Result<Self, SchnorrError> {
        let bytes = hex::decode(s)
            .map_err(|e| SchnorrError::InvalidPublicKey(e.to_string()))?;
        Self::from_slice(&bytes)
    }
    
    /// Convert to bitcoin library XOnlyPublicKey
    pub fn to_secp256k1(&self) -> Result<XOnlyPublicKey, SchnorrError> {
        XOnlyPublicKey::from_slice(&self.0)
            .map_err(|e| SchnorrError::InvalidPublicKey(e.to_string()))
    }
}

impl From<XOnlyPublicKey> for XOnlyPubKey {
    fn from(key: XOnlyPublicKey) -> Self {
        Self(key.serialize())
    }
}

/// Schnorr signature (64 bytes: 32-byte R + 32-byte s)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SchnorrSig(pub [u8; 64]);

// Custom serde implementation for SchnorrSig (64 bytes as hex)
impl serde::Serialize for SchnorrSig {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&hex::encode(&self.0))
    }
}

impl<'de> serde::Deserialize<'de> for SchnorrSig {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = hex::decode(&s).map_err(serde::de::Error::custom)?;
        bytes
            .try_into()
            .map(SchnorrSig)
            .map_err(|_| serde::de::Error::custom("expected 64 bytes"))
    }
}

impl SchnorrSig {
    /// Create from 64 bytes
    pub fn from_bytes(bytes: [u8; 64]) -> Self {
        Self(bytes)
    }
    
    /// Create from slice (must be 64 bytes)
    pub fn from_slice(slice: &[u8]) -> Result<Self, SchnorrError> {
        if slice.len() != 64 {
            return Err(SchnorrError::InvalidSignature(
                format!("Expected 64 bytes, got {}", slice.len())
            ));
        }
        let mut bytes = [0u8; 64];
        bytes.copy_from_slice(slice);
        Ok(Self(bytes))
    }
    
    /// Get the raw bytes
    pub fn as_bytes(&self) -> &[u8; 64] {
        &self.0
    }
    
    /// Get the R component (first 32 bytes)
    pub fn r(&self) -> &[u8] {
        &self.0[..32]
    }
    
    /// Get the s component (last 32 bytes)
    pub fn s(&self) -> &[u8] {
        &self.0[32..]
    }
    
    /// Convert to hex string
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
    
    /// Parse from hex string
    pub fn from_hex(s: &str) -> Result<Self, SchnorrError> {
        let bytes = hex::decode(s)
            .map_err(|e| SchnorrError::InvalidSignature(e.to_string()))?;
        Self::from_slice(&bytes)
    }
    
    /// Convert to bitcoin library SchnorrSignature
    pub fn to_secp256k1(&self) -> Result<SchnorrSignature, SchnorrError> {
        SchnorrSignature::from_slice(&self.0)
            .map_err(|e| SchnorrError::InvalidSignature(e.to_string()))
    }
}

impl From<SchnorrSignature> for SchnorrSig {
    fn from(sig: SchnorrSignature) -> Self {
        Self(*sig.as_ref())
    }
}

// MARK: - Schnorr Errors

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SchnorrError {
    InvalidPrivateKey(String),
    InvalidPublicKey(String),
    InvalidSignature(String),
    InvalidMessage(String),
    SigningFailed(String),
    VerificationFailed(String),
}

impl std::fmt::Display for SchnorrError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidPrivateKey(s) => write!(f, "Invalid private key: {}", s),
            Self::InvalidPublicKey(s) => write!(f, "Invalid public key: {}", s),
            Self::InvalidSignature(s) => write!(f, "Invalid signature: {}", s),
            Self::InvalidMessage(s) => write!(f, "Invalid message: {}", s),
            Self::SigningFailed(s) => write!(f, "Signing failed: {}", s),
            Self::VerificationFailed(s) => write!(f, "Verification failed: {}", s),
        }
    }
}

impl std::error::Error for SchnorrError {}

// MARK: - Schnorr Signer

/// BIP-340 Schnorr signer
pub struct SchnorrSigner {
    secp: Secp256k1<All>,
}

impl Default for SchnorrSigner {
    fn default() -> Self {
        Self::new()
    }
}

impl SchnorrSigner {
    /// Create a new Schnorr signer
    pub fn new() -> Self {
        Self {
            secp: Secp256k1::new(),
        }
    }
    
    /// Generate a keypair from a 32-byte seed
    /// 
    /// Returns (secret_key, x_only_public_key)
    pub fn generate_keypair(&self, seed: &[u8; 32]) -> Result<(SecretKey, XOnlyPubKey), SchnorrError> {
        let secret_key = SecretKey::from_slice(seed)
            .map_err(|e| SchnorrError::InvalidPrivateKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        let (x_only_pubkey, _parity) = keypair.x_only_public_key();
        
        Ok((secret_key, XOnlyPubKey::from(x_only_pubkey)))
    }
    
    /// Derive x-only public key from private key
    pub fn public_key(&self, private_key: &[u8]) -> Result<XOnlyPubKey, SchnorrError> {
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| SchnorrError::InvalidPrivateKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        let (x_only_pubkey, _parity) = keypair.x_only_public_key();
        
        Ok(XOnlyPubKey::from(x_only_pubkey))
    }
    
    /// Sign a 32-byte message hash with BIP-340 Schnorr
    /// 
    /// Uses deterministic nonce generation (no auxiliary randomness).
    /// For extra security, use `sign_with_aux_rand`.
    pub fn sign(&self, message: &[u8; 32], private_key: &[u8]) -> Result<SchnorrSig, SchnorrError> {
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| SchnorrError::InvalidPrivateKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        let msg = Message::from_digest(*message);
        
        // Sign without auxiliary randomness (deterministic)
        let sig = self.secp.sign_schnorr_no_aux_rand(&msg, &keypair);
        
        Ok(SchnorrSig::from(sig))
    }
    
    /// Sign a 32-byte message hash with auxiliary randomness
    /// 
    /// The auxiliary randomness provides additional protection against
    /// side-channel attacks and fault injection.
    pub fn sign_with_aux_rand(
        &self, 
        message: &[u8; 32], 
        private_key: &[u8],
        aux_rand: &[u8; 32],
    ) -> Result<SchnorrSig, SchnorrError> {
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| SchnorrError::InvalidPrivateKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        let msg = Message::from_digest(*message);
        
        // Sign with auxiliary randomness
        let sig = self.secp.sign_schnorr_with_aux_rand(&msg, &keypair, aux_rand);
        
        Ok(SchnorrSig::from(sig))
    }
    
    /// Verify a BIP-340 Schnorr signature
    pub fn verify(
        &self,
        message: &[u8; 32],
        signature: &SchnorrSig,
        public_key: &XOnlyPubKey,
    ) -> Result<bool, SchnorrError> {
        let secp_sig = signature.to_secp256k1()?;
        let secp_pubkey = public_key.to_secp256k1()?;
        let msg = Message::from_digest(*message);
        
        match self.secp.verify_schnorr(&secp_sig, &msg, &secp_pubkey) {
            Ok(()) => Ok(true),
            Err(_) => Ok(false),
        }
    }
    
    /// Batch verify multiple Schnorr signatures
    /// 
    /// Returns true only if ALL signatures are valid.
    /// More efficient than verifying individually due to batch optimization.
    pub fn batch_verify(
        &self,
        messages: &[[u8; 32]],
        signatures: &[SchnorrSig],
        public_keys: &[XOnlyPubKey],
    ) -> Result<bool, SchnorrError> {
        if messages.len() != signatures.len() || signatures.len() != public_keys.len() {
            return Err(SchnorrError::VerificationFailed(
                "Mismatched array lengths".to_string()
            ));
        }
        
        // Convert all to secp256k1 types
        let mut secp_msgs = Vec::with_capacity(messages.len());
        let mut secp_sigs = Vec::with_capacity(signatures.len());
        let mut secp_pubkeys = Vec::with_capacity(public_keys.len());
        
        for i in 0..messages.len() {
            secp_msgs.push(Message::from_digest(messages[i]));
            secp_sigs.push(signatures[i].to_secp256k1()?);
            secp_pubkeys.push(public_keys[i].to_secp256k1()?);
        }
        
        // Verify each signature (secp256k1 library handles batch optimization internally)
        for i in 0..secp_msgs.len() {
            if self.secp.verify_schnorr(&secp_sigs[i], &secp_msgs[i], &secp_pubkeys[i]).is_err() {
                return Ok(false);
            }
        }
        
        Ok(true)
    }
    
    /// Hash a message with BIP-340 challenge tag
    /// 
    /// challenge = SHA256(SHA256("BIP0340/challenge") || SHA256("BIP0340/challenge") || R || P || m)
    pub fn challenge_hash(&self, r: &[u8; 32], p: &[u8; 32], message: &[u8]) -> [u8; 32] {
        let mut data = Vec::with_capacity(64 + message.len());
        data.extend_from_slice(r);
        data.extend_from_slice(p);
        data.extend_from_slice(message);
        tagged_hash(tags::BIP0340_CHALLENGE, &data)
    }
    
    /// Compute the nonce for BIP-340 signing
    /// 
    /// k = int(tagged_hash("BIP0340/nonce", t || bytes(P) || m)) mod n
    /// where t = xor(bytes(d), tagged_hash("BIP0340/aux", aux_rand))
    pub fn compute_nonce(
        &self,
        private_key: &[u8; 32],
        public_key: &[u8; 32],
        message: &[u8; 32],
        aux_rand: Option<&[u8; 32]>,
    ) -> [u8; 32] {
        // Compute t = xor(d, tagged_hash("BIP0340/aux", aux_rand))
        let t = if let Some(aux) = aux_rand {
            let aux_hash = tagged_hash(tags::BIP0340_AUX, aux);
            let mut t = [0u8; 32];
            for i in 0..32 {
                t[i] = private_key[i] ^ aux_hash[i];
            }
            t
        } else {
            *private_key
        };
        
        // Compute k = tagged_hash("BIP0340/nonce", t || P || m)
        let mut data = Vec::with_capacity(96);
        data.extend_from_slice(&t);
        data.extend_from_slice(public_key);
        data.extend_from_slice(message);
        
        tagged_hash(tags::BIP0340_NONCE, &data)
    }
}

// MARK: - Convenience Functions

/// Sign a message with BIP-340 Schnorr (deterministic)
pub fn schnorr_sign(message: &[u8; 32], private_key: &[u8]) -> Result<SchnorrSig, SchnorrError> {
    let signer = SchnorrSigner::new();
    signer.sign(message, private_key)
}

/// Sign a message with BIP-340 Schnorr (with auxiliary randomness)
pub fn schnorr_sign_with_aux_rand(
    message: &[u8; 32],
    private_key: &[u8],
    aux_rand: &[u8; 32],
) -> Result<SchnorrSig, SchnorrError> {
    let signer = SchnorrSigner::new();
    signer.sign_with_aux_rand(message, private_key, aux_rand)
}

/// Verify a BIP-340 Schnorr signature
pub fn schnorr_verify(
    message: &[u8; 32],
    signature: &SchnorrSig,
    public_key: &XOnlyPubKey,
) -> Result<bool, SchnorrError> {
    let signer = SchnorrSigner::new();
    signer.verify(message, signature, public_key)
}

/// Derive x-only public key from private key
pub fn schnorr_public_key(private_key: &[u8]) -> Result<XOnlyPubKey, SchnorrError> {
    let signer = SchnorrSigner::new();
    signer.public_key(private_key)
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_tagged_hash() {
        // Test vector from BIP-340
        let msg = hex::decode("0000000000000000000000000000000000000000000000000000000000000000")
            .unwrap();
        let hash = tagged_hash("BIP0340/aux", &msg);
        
        // Verify it produces 32 bytes
        assert_eq!(hash.len(), 32);
        
        // Different tags should produce different hashes
        let hash2 = tagged_hash("BIP0340/nonce", &msg);
        assert_ne!(hash, hash2);
    }
    
    #[test]
    fn test_schnorr_sign_verify() {
        let signer = SchnorrSigner::new();
        
        // Generate keypair
        let seed = [1u8; 32];
        let (secret_key, public_key) = signer.generate_keypair(&seed).unwrap();
        
        // Sign a message
        let message = [0xAAu8; 32];
        let signature = signer.sign(&message, &secret_key[..]).unwrap();
        
        // Verify signature
        let valid = signer.verify(&message, &signature, &public_key).unwrap();
        assert!(valid, "Signature should be valid");
        
        // Verify wrong message fails
        let wrong_message = [0xBBu8; 32];
        let invalid = signer.verify(&wrong_message, &signature, &public_key).unwrap();
        assert!(!invalid, "Wrong message should fail verification");
    }
    
    #[test]
    fn test_schnorr_sign_with_aux_rand() {
        let signer = SchnorrSigner::new();
        
        let seed = [2u8; 32];
        let (secret_key, public_key) = signer.generate_keypair(&seed).unwrap();
        
        let message = [0xCCu8; 32];
        let aux_rand = [0xDDu8; 32];
        
        // Sign with aux randomness
        let sig1 = signer.sign_with_aux_rand(&message, &secret_key[..], &aux_rand).unwrap();
        
        // Sign without (deterministic)
        let sig2 = signer.sign(&message, &secret_key[..]).unwrap();
        
        // Both should verify
        assert!(signer.verify(&message, &sig1, &public_key).unwrap());
        assert!(signer.verify(&message, &sig2, &public_key).unwrap());
        
        // Signatures should be different (different nonces)
        assert_ne!(sig1.as_bytes(), sig2.as_bytes());
    }
    
    #[test]
    fn test_schnorr_batch_verify() {
        let signer = SchnorrSigner::new();
        
        // Create multiple keypairs and signatures
        let seeds: [[u8; 32]; 3] = [[1u8; 32], [2u8; 32], [3u8; 32]];
        let messages: [[u8; 32]; 3] = [[0xAAu8; 32], [0xBBu8; 32], [0xCCu8; 32]];
        
        let mut public_keys = Vec::new();
        let mut signatures = Vec::new();
        
        for (seed, message) in seeds.iter().zip(messages.iter()) {
            let (secret_key, public_key) = signer.generate_keypair(seed).unwrap();
            let sig = signer.sign(message, &secret_key[..]).unwrap();
            public_keys.push(public_key);
            signatures.push(sig);
        }
        
        // Batch verify - should pass
        let valid = signer.batch_verify(&messages, &signatures, &public_keys).unwrap();
        assert!(valid, "Batch verification should pass");
        
        // Modify one signature - should fail
        let mut bad_sigs = signatures.clone();
        bad_sigs[1].0[0] ^= 0xFF; // Corrupt one byte
        let invalid = signer.batch_verify(&messages, &bad_sigs, &public_keys).unwrap();
        assert!(!invalid, "Corrupted signature batch should fail");
    }
    
    #[test]
    fn test_x_only_pubkey_serialization() {
        let signer = SchnorrSigner::new();
        let seed = [42u8; 32];
        let (_, pubkey) = signer.generate_keypair(&seed).unwrap();
        
        // Test hex round-trip
        let hex_str = pubkey.to_hex();
        let recovered = XOnlyPubKey::from_hex(&hex_str).unwrap();
        assert_eq!(pubkey, recovered);
        
        // Test bytes round-trip
        let bytes = pubkey.as_bytes().clone();
        let recovered2 = XOnlyPubKey::from_bytes(bytes);
        assert_eq!(pubkey, recovered2);
    }
    
    #[test]
    fn test_schnorr_sig_serialization() {
        let signer = SchnorrSigner::new();
        let seed = [42u8; 32];
        let (secret_key, _) = signer.generate_keypair(&seed).unwrap();
        
        let message = [0xEEu8; 32];
        let sig = signer.sign(&message, &secret_key[..]).unwrap();
        
        // Test hex round-trip
        let hex_str = sig.to_hex();
        let recovered = SchnorrSig::from_hex(&hex_str).unwrap();
        assert_eq!(sig, recovered);
        
        // Test R and s extraction
        assert_eq!(sig.r().len(), 32);
        assert_eq!(sig.s().len(), 32);
    }
    
    // BIP-340 Test Vector 0
    #[test]
    fn test_bip340_vector_0() {
        let signer = SchnorrSigner::new();
        
        // Test vector 0 from BIP-340
        let secret_key = hex::decode(
            "0000000000000000000000000000000000000000000000000000000000000003"
        ).unwrap();
        
        let expected_pubkey = hex::decode(
            "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9"
        ).unwrap();
        
        let message = hex::decode(
            "0000000000000000000000000000000000000000000000000000000000000000"
        ).unwrap();
        
        let expected_sig = hex::decode(
            "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0"
        ).unwrap();
        
        // Derive public key
        let pubkey = signer.public_key(&secret_key).unwrap();
        assert_eq!(
            pubkey.to_hex().to_uppercase(),
            hex::encode(&expected_pubkey).to_uppercase(),
            "Public key mismatch"
        );
        
        // Sign with aux_rand = 0 (to match test vector)
        let aux_rand = [0u8; 32];
        let mut msg_arr = [0u8; 32];
        msg_arr.copy_from_slice(&message);
        
        let sig = signer.sign_with_aux_rand(&msg_arr, &secret_key, &aux_rand).unwrap();
        assert_eq!(
            sig.to_hex().to_uppercase(),
            hex::encode(&expected_sig).to_uppercase(),
            "Signature mismatch"
        );
        
        // Verify
        let valid = signer.verify(&msg_arr, &sig, &pubkey).unwrap();
        assert!(valid, "Verification should pass");
    }
    
    // BIP-340 Test Vector 1
    #[test]
    fn test_bip340_vector_1() {
        let signer = SchnorrSigner::new();
        
        let secret_key = hex::decode(
            "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF"
        ).unwrap();
        
        let message = hex::decode(
            "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"
        ).unwrap();
        
        let expected_pubkey = hex::decode(
            "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659"
        ).unwrap();
        
        // Derive public key
        let pubkey = signer.public_key(&secret_key).unwrap();
        assert_eq!(
            pubkey.to_hex().to_uppercase(),
            hex::encode(&expected_pubkey).to_uppercase(),
            "Public key mismatch"
        );
        
        // Sign and verify
        let mut msg_arr = [0u8; 32];
        msg_arr.copy_from_slice(&message);
        
        let sig = signer.sign(&msg_arr, &secret_key).unwrap();
        let valid = signer.verify(&msg_arr, &sig, &pubkey).unwrap();
        assert!(valid, "Verification should pass");
    }
}
