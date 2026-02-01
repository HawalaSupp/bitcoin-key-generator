//! Taproot Key Tweaking and Script Trees (BIP-341)
//!
//! Implementation of Taproot key tweaking, script tree construction,
//! and control block generation as specified in BIP-341.
//!
//! Key features:
//! - Internal key to output key tweaking
//! - Script tree Merkle root calculation
//! - Control block construction for script-path spends
//! - TapLeaf and TapBranch tagged hashes
//!
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki

use crate::crypto::schnorr::{tagged_hash, tags, XOnlyPubKey, SchnorrSig, SchnorrError, SchnorrSigner};
use bitcoin::secp256k1::{Secp256k1, SecretKey, Keypair, Parity};
use bitcoin::key::TapTweak;
use serde::{Deserialize, Serialize};

// MARK: - Taproot Constants

/// Default TapScript leaf version (0xc0)
pub const TAPSCRIPT_LEAF_VERSION: u8 = 0xc0;

// MARK: - Taproot Types

/// Taproot output key (tweaked public key)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaprootOutputKey {
    /// The x-only output public key
    pub output_key: XOnlyPubKey,
    /// Parity of the output key (needed for script-path spending)
    pub parity: bool,
}

/// Taproot internal key (untweaked public key)
pub type TaprootInternalKey = XOnlyPubKey;

/// Merkle root of the script tree (32 bytes)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TapMerkleRoot(pub [u8; 32]);

impl TapMerkleRoot {
    /// Create empty merkle root (key-path only spend)
    pub fn empty() -> Self {
        Self([0u8; 32])
    }
    
    /// Create from 32 bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
    
    /// Create from slice
    pub fn from_slice(slice: &[u8]) -> Result<Self, TaprootError> {
        if slice.len() != 32 {
            return Err(TaprootError::InvalidMerkleRoot(
                format!("Expected 32 bytes, got {}", slice.len())
            ));
        }
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(slice);
        Ok(Self(bytes))
    }
    
    /// Get raw bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
    
    /// Check if empty (no script tree)
    pub fn is_empty(&self) -> bool {
        self.0 == [0u8; 32]
    }
    
    /// Convert to hex
    pub fn to_hex(&self) -> String {
        hex::encode(&self.0)
    }
}

/// TapLeaf - a single script in the tree
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TapLeaf {
    /// Leaf version (default 0xc0 for TapScript)
    pub version: u8,
    /// The script bytes
    pub script: Vec<u8>,
}

impl TapLeaf {
    /// Create a new TapLeaf with default version
    pub fn new(script: Vec<u8>) -> Self {
        Self {
            version: TAPSCRIPT_LEAF_VERSION,
            script,
        }
    }
    
    /// Create with custom version
    pub fn with_version(version: u8, script: Vec<u8>) -> Self {
        Self { version, script }
    }
    
    /// Calculate the leaf hash
    /// 
    /// TapLeaf hash = tagged_hash("TapLeaf", version || compact_size(script) || script)
    pub fn hash(&self) -> [u8; 32] {
        let mut data = Vec::with_capacity(1 + 8 + self.script.len());
        data.push(self.version);
        
        // Compact size encoding
        if self.script.len() < 253 {
            data.push(self.script.len() as u8);
        } else if self.script.len() <= 0xFFFF {
            data.push(253);
            data.extend_from_slice(&(self.script.len() as u16).to_le_bytes());
        } else {
            data.push(254);
            data.extend_from_slice(&(self.script.len() as u32).to_le_bytes());
        }
        
        data.extend_from_slice(&self.script);
        
        tagged_hash(tags::TAP_LEAF, &data)
    }
}

/// TapBranch - a branch in the script tree
#[derive(Debug, Clone)]
pub enum TapNode {
    /// A leaf node (script)
    Leaf(TapLeaf),
    /// A branch node (two children)
    Branch(Box<TapNode>, Box<TapNode>),
}

impl TapNode {
    /// Calculate the hash of this node
    pub fn hash(&self) -> [u8; 32] {
        match self {
            TapNode::Leaf(leaf) => leaf.hash(),
            TapNode::Branch(left, right) => {
                let left_hash = left.hash();
                let right_hash = right.hash();
                tap_branch_hash(&left_hash, &right_hash)
            }
        }
    }
    
    /// Create a branch from two nodes
    pub fn branch(left: TapNode, right: TapNode) -> Self {
        TapNode::Branch(Box::new(left), Box::new(right))
    }
}

/// Control block for script-path spending
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlBlock {
    /// Leaf version with parity bit
    pub leaf_version_with_parity: u8,
    /// Internal public key (32 bytes)
    pub internal_key: XOnlyPubKey,
    /// Merkle path (each element is 32 bytes)
    pub merkle_path: Vec<[u8; 32]>,
}

impl ControlBlock {
    /// Create a new control block
    pub fn new(
        leaf_version: u8,
        output_key_parity: bool,
        internal_key: XOnlyPubKey,
        merkle_path: Vec<[u8; 32]>,
    ) -> Self {
        // Combine leaf version with parity bit
        let leaf_version_with_parity = leaf_version | if output_key_parity { 0x01 } else { 0x00 };
        
        Self {
            leaf_version_with_parity,
            internal_key,
            merkle_path,
        }
    }
    
    /// Serialize to bytes
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::with_capacity(1 + 32 + self.merkle_path.len() * 32);
        data.push(self.leaf_version_with_parity);
        data.extend_from_slice(self.internal_key.as_bytes());
        for hash in &self.merkle_path {
            data.extend_from_slice(hash);
        }
        data
    }
    
    /// Get the parity bit
    pub fn parity(&self) -> bool {
        (self.leaf_version_with_parity & 0x01) != 0
    }
    
    /// Get the leaf version (without parity bit)
    pub fn leaf_version(&self) -> u8 {
        self.leaf_version_with_parity & 0xFE
    }
}

// MARK: - Taproot Errors

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TaprootError {
    InvalidInternalKey(String),
    InvalidTweak(String),
    InvalidMerkleRoot(String),
    TweakFailed(String),
    SchnorrError(String),
}

impl std::fmt::Display for TaprootError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInternalKey(s) => write!(f, "Invalid internal key: {}", s),
            Self::InvalidTweak(s) => write!(f, "Invalid tweak: {}", s),
            Self::InvalidMerkleRoot(s) => write!(f, "Invalid merkle root: {}", s),
            Self::TweakFailed(s) => write!(f, "Tweak failed: {}", s),
            Self::SchnorrError(s) => write!(f, "Schnorr error: {}", s),
        }
    }
}

impl std::error::Error for TaprootError {}

impl From<SchnorrError> for TaprootError {
    fn from(e: SchnorrError) -> Self {
        TaprootError::SchnorrError(e.to_string())
    }
}

// MARK: - Taproot Functions

/// Calculate TapBranch hash from two child hashes
/// 
/// The children are sorted lexicographically before hashing.
pub fn tap_branch_hash(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    // Sort children lexicographically
    let (first, second) = if left < right {
        (left, right)
    } else {
        (right, left)
    };
    
    let mut data = [0u8; 64];
    data[..32].copy_from_slice(first);
    data[32..].copy_from_slice(second);
    
    tagged_hash(tags::TAP_BRANCH, &data)
}

/// Calculate the tweak hash
/// 
/// tweak = tagged_hash("TapTweak", internal_key || merkle_root)
/// 
/// If merkle_root is empty (key-path only), use:
/// tweak = tagged_hash("TapTweak", internal_key)
pub fn tap_tweak_hash(internal_key: &XOnlyPubKey, merkle_root: Option<&TapMerkleRoot>) -> [u8; 32] {
    match merkle_root {
        Some(root) if !root.is_empty() => {
            let mut data = [0u8; 64];
            data[..32].copy_from_slice(internal_key.as_bytes());
            data[32..].copy_from_slice(root.as_bytes());
            tagged_hash(tags::TAP_TWEAK, &data)
        }
        _ => {
            tagged_hash(tags::TAP_TWEAK, internal_key.as_bytes())
        }
    }
}

/// Taproot key tweaker
pub struct TaprootTweaker {
    secp: Secp256k1<bitcoin::secp256k1::All>,
}

impl Default for TaprootTweaker {
    fn default() -> Self {
        Self::new()
    }
}

impl TaprootTweaker {
    /// Create a new Taproot tweaker
    pub fn new() -> Self {
        Self {
            secp: Secp256k1::new(),
        }
    }
    
    /// Tweak an internal public key to create the output key
    /// 
    /// output_key = internal_key + tweak * G
    pub fn tweak_public_key(
        &self,
        internal_key: &XOnlyPubKey,
        merkle_root: Option<&TapMerkleRoot>,
    ) -> Result<TaprootOutputKey, TaprootError> {
        let secp_internal_key = internal_key.to_secp256k1()
            .map_err(|e| TaprootError::InvalidInternalKey(e.to_string()))?;
        
        // Use bitcoin library's TapTweak trait
        let merkle_root_bytes = merkle_root.and_then(|r| {
            if r.is_empty() {
                None
            } else {
                Some(bitcoin::taproot::TapNodeHash::assume_hidden(r.0))
            }
        });
        
        let (output_key, parity) = secp_internal_key.tap_tweak(&self.secp, merkle_root_bytes);
        
        Ok(TaprootOutputKey {
            output_key: XOnlyPubKey::from(output_key.to_x_only_public_key()),
            parity: parity == Parity::Odd,
        })
    }
    
    /// Tweak a private key for key-path spending
    /// 
    /// tweaked_key = private_key + tweak (mod n)
    pub fn tweak_private_key(
        &self,
        private_key: &[u8],
        merkle_root: Option<&TapMerkleRoot>,
    ) -> Result<SecretKey, TaprootError> {
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| TaprootError::InvalidInternalKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        
        let merkle_root_bytes = merkle_root.and_then(|r| {
            if r.is_empty() {
                None
            } else {
                Some(bitcoin::taproot::TapNodeHash::assume_hidden(r.0))
            }
        });
        
        let tweaked_keypair = keypair.tap_tweak(&self.secp, merkle_root_bytes);
        
        Ok(SecretKey::from_keypair(&tweaked_keypair.to_keypair()))
    }
    
    /// Generate a Taproot output key from a private key
    pub fn create_output_key(
        &self,
        private_key: &[u8],
        merkle_root: Option<&TapMerkleRoot>,
    ) -> Result<TaprootOutputKey, TaprootError> {
        // First get the internal key
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| TaprootError::InvalidInternalKey(e.to_string()))?;
        
        let keypair = Keypair::from_secret_key(&self.secp, &secret_key);
        let (internal_key, _parity) = keypair.x_only_public_key();
        
        // Then tweak it
        self.tweak_public_key(&XOnlyPubKey::from(internal_key), merkle_root)
    }
    
    /// Build a Merkle root from a list of TapLeaves
    /// 
    /// Creates a balanced binary tree from the leaves.
    pub fn build_merkle_root(&self, leaves: &[TapLeaf]) -> Result<TapMerkleRoot, TaprootError> {
        if leaves.is_empty() {
            return Ok(TapMerkleRoot::empty());
        }
        
        if leaves.len() == 1 {
            return Ok(TapMerkleRoot::from_bytes(leaves[0].hash()));
        }
        
        // Build tree from leaves
        let mut hashes: Vec<[u8; 32]> = leaves.iter().map(|l| l.hash()).collect();
        
        while hashes.len() > 1 {
            let mut new_hashes = Vec::new();
            
            for i in (0..hashes.len()).step_by(2) {
                if i + 1 < hashes.len() {
                    new_hashes.push(tap_branch_hash(&hashes[i], &hashes[i + 1]));
                } else {
                    // Odd number of nodes - promote the last one
                    new_hashes.push(hashes[i]);
                }
            }
            
            hashes = new_hashes;
        }
        
        Ok(TapMerkleRoot::from_bytes(hashes[0]))
    }
    
    /// Create a control block for script-path spending
    pub fn create_control_block(
        &self,
        internal_key: &XOnlyPubKey,
        output_key_parity: bool,
        leaf: &TapLeaf,
        merkle_path: Vec<[u8; 32]>,
    ) -> ControlBlock {
        ControlBlock::new(
            leaf.version,
            output_key_parity,
            internal_key.clone(),
            merkle_path,
        )
    }
}

// MARK: - Taproot Signer

/// Sign a message for Taproot key-path spending
pub struct TaprootSigner {
    schnorr_signer: SchnorrSigner,
    tweaker: TaprootTweaker,
}

impl Default for TaprootSigner {
    fn default() -> Self {
        Self::new()
    }
}

impl TaprootSigner {
    /// Create a new Taproot signer
    pub fn new() -> Self {
        Self {
            schnorr_signer: SchnorrSigner::new(),
            tweaker: TaprootTweaker::new(),
        }
    }
    
    /// Sign a sighash for key-path spending
    /// 
    /// The private key is automatically tweaked before signing.
    pub fn sign_key_path(
        &self,
        sighash: &[u8; 32],
        private_key: &[u8],
        merkle_root: Option<&TapMerkleRoot>,
    ) -> Result<SchnorrSig, TaprootError> {
        // Tweak the private key
        let tweaked_key = self.tweaker.tweak_private_key(private_key, merkle_root)?;
        
        // Sign with the tweaked key
        let sig = self.schnorr_signer.sign(sighash, &tweaked_key[..])?;
        
        Ok(sig)
    }
    
    /// Sign a sighash for script-path spending
    /// 
    /// No key tweaking is needed for script-path.
    pub fn sign_script_path(
        &self,
        sighash: &[u8; 32],
        private_key: &[u8],
    ) -> Result<SchnorrSig, TaprootError> {
        let sig = self.schnorr_signer.sign(sighash, private_key)?;
        Ok(sig)
    }
    
    /// Get the output key for a given private key and merkle root
    pub fn get_output_key(
        &self,
        private_key: &[u8],
        merkle_root: Option<&TapMerkleRoot>,
    ) -> Result<TaprootOutputKey, TaprootError> {
        self.tweaker.create_output_key(private_key, merkle_root)
    }
    
    /// Get the internal key (x-only public key) for a private key
    pub fn get_internal_key(&self, private_key: &[u8]) -> Result<XOnlyPubKey, TaprootError> {
        Ok(self.schnorr_signer.public_key(private_key)?)
    }
}

// MARK: - Convenience Functions

/// Tweak an internal key to create output key (key-path only)
pub fn taproot_tweak_key_only(internal_key: &XOnlyPubKey) -> Result<TaprootOutputKey, TaprootError> {
    let tweaker = TaprootTweaker::new();
    tweaker.tweak_public_key(internal_key, None)
}

/// Tweak an internal key with merkle root
pub fn taproot_tweak_with_merkle(
    internal_key: &XOnlyPubKey,
    merkle_root: &TapMerkleRoot,
) -> Result<TaprootOutputKey, TaprootError> {
    let tweaker = TaprootTweaker::new();
    tweaker.tweak_public_key(internal_key, Some(merkle_root))
}

/// Sign for key-path spending
pub fn taproot_sign_key_path(
    sighash: &[u8; 32],
    private_key: &[u8],
    merkle_root: Option<&TapMerkleRoot>,
) -> Result<SchnorrSig, TaprootError> {
    let signer = TaprootSigner::new();
    signer.sign_key_path(sighash, private_key, merkle_root)
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_tap_leaf_hash() {
        // Simple script: OP_TRUE (0x51)
        let script = vec![0x51];
        let leaf = TapLeaf::new(script);
        
        let hash = leaf.hash();
        assert_eq!(hash.len(), 32);
        
        // Different scripts should produce different hashes
        let leaf2 = TapLeaf::new(vec![0x00]);
        assert_ne!(leaf.hash(), leaf2.hash());
    }
    
    #[test]
    fn test_tap_branch_hash() {
        let left = [1u8; 32];
        let right = [2u8; 32];
        
        let hash1 = tap_branch_hash(&left, &right);
        let hash2 = tap_branch_hash(&right, &left);
        
        // Branch hash should be the same regardless of order (sorted internally)
        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 32);
    }
    
    #[test]
    fn test_tap_tweak_hash() {
        let internal_key = XOnlyPubKey([0xAB; 32]);
        
        // Key-only tweak (no merkle root)
        let tweak1 = tap_tweak_hash(&internal_key, None);
        let tweak2 = tap_tweak_hash(&internal_key, Some(&TapMerkleRoot::empty()));
        
        // Both should be the same
        assert_eq!(tweak1, tweak2);
        
        // With merkle root should be different
        let merkle_root = TapMerkleRoot([0xCD; 32]);
        let tweak3 = tap_tweak_hash(&internal_key, Some(&merkle_root));
        assert_ne!(tweak1, tweak3);
    }
    
    #[test]
    fn test_tweak_public_key() {
        let tweaker = TaprootTweaker::new();
        let signer = SchnorrSigner::new();
        
        // Generate keypair
        let seed = [42u8; 32];
        let (_, internal_key) = signer.generate_keypair(&seed).unwrap();
        
        // Tweak (key-only)
        let output = tweaker.tweak_public_key(&internal_key, None).unwrap();
        
        // Output key should be different from internal key
        assert_ne!(output.output_key.as_bytes(), internal_key.as_bytes());
    }
    
    #[test]
    fn test_tweak_private_key_and_sign() {
        let _tweaker = TaprootTweaker::new();
        let signer = TaprootSigner::new();
        
        let private_key = [42u8; 32];
        let message = [0xFFu8; 32];
        
        // Sign with key-path
        let sig = signer.sign_key_path(&message, &private_key, None).unwrap();
        
        // Get output key
        let output = signer.get_output_key(&private_key, None).unwrap();
        
        // Verify signature with output key
        let schnorr_signer = SchnorrSigner::new();
        let valid = schnorr_signer.verify(&message, &sig, &output.output_key).unwrap();
        assert!(valid, "Key-path signature should verify against output key");
    }
    
    #[test]
    fn test_build_merkle_root_single() {
        let tweaker = TaprootTweaker::new();
        
        let leaf = TapLeaf::new(vec![0x51]); // OP_TRUE
        let root = tweaker.build_merkle_root(&[leaf.clone()]).unwrap();
        
        // Single leaf merkle root = leaf hash
        assert_eq!(root.as_bytes(), &leaf.hash());
    }
    
    #[test]
    fn test_build_merkle_root_multiple() {
        let tweaker = TaprootTweaker::new();
        
        let leaf1 = TapLeaf::new(vec![0x51]); // OP_TRUE
        let leaf2 = TapLeaf::new(vec![0x00]); // OP_FALSE
        
        let root = tweaker.build_merkle_root(&[leaf1.clone(), leaf2.clone()]).unwrap();
        
        // Manual calculation
        let expected = tap_branch_hash(&leaf1.hash(), &leaf2.hash());
        assert_eq!(root.as_bytes(), &expected);
    }
    
    #[test]
    fn test_control_block() {
        let internal_key = XOnlyPubKey([0xAB; 32]);
        let merkle_path = vec![[0xCD; 32], [0xEF; 32]];
        
        let cb = ControlBlock::new(
            TAPSCRIPT_LEAF_VERSION,
            true, // odd parity
            internal_key.clone(),
            merkle_path.clone(),
        );
        
        // Check serialization
        let serialized = cb.serialize();
        assert_eq!(serialized.len(), 1 + 32 + 64); // version+parity, internal key, 2 path elements
        
        // Check parity bit
        assert!(cb.parity());
        assert_eq!(cb.leaf_version(), TAPSCRIPT_LEAF_VERSION);
    }
    
    #[test]
    fn test_merkle_root_empty() {
        let root = TapMerkleRoot::empty();
        assert!(root.is_empty());
        
        let non_empty = TapMerkleRoot([1u8; 32]);
        assert!(!non_empty.is_empty());
    }
}
