# Trust Wallet Core Integration Guide for Hawala (macOS)

## ✅ Integration Complete!

We've integrated the **highest-value features** from Trust Wallet's wallet-core directly into Hawala's Rust backend. This gives you battle-tested blockchain implementations without the complexity of building the full C++ library.

### New Chains Added

| Chain | Module | Features |
|-------|--------|----------|
| **TON** | `ton_wallet.rs` | Address generation (v4r2), transfers, Jetton tokens |
| **Aptos** | `aptos_wallet.rs` | Account derivation, APT/coin transfers, Move calls |
| **Sui** | `sui_wallet.rs` | Address derivation, SUI/object transfers, Move calls |
| **Polkadot** | `polkadot_wallet.rs` | SS58 addresses, DOT/KSM, staking, balance transfers |
| **THORChain** | `thorchain_swap.rs` | Cross-chain swaps (BTC↔ETH, etc.), liquidity pools |

### New Files Created

```
rust-app/src/
├── ton_wallet.rs       # TON blockchain support
├── aptos_wallet.rs     # Aptos blockchain support  
├── sui_wallet.rs       # Sui blockchain support
├── polkadot_wallet.rs  # Polkadot/Kusama support
├── thorchain_swap.rs   # Cross-chain swap protocol
└── serde_bytes.rs      # Shared serialization helpers
```

---

## Usage Examples

### TON Wallet

```rust
use rust_app::ton_wallet::{TonKeyPair, TonTransaction, TonAddress};

// Create key pair from seed
let key_pair = TonKeyPair::from_mnemonic_index(&seed, 0)?;
println!("TON Address: {}", key_pair.address);

// Create and sign a transfer
let tx = TonTransaction::transfer(
    TonAddress::from_string("EQ...")?,
    1_000_000_000, // 1 TON in nanoTON
    seqno,
);
let signed = tx.sign(&key_pair)?;
```

### Aptos Wallet

```rust
use rust_app::aptos_wallet::{AptosKeyPair, AptosTransaction, AptosAddress};

// Create key pair
let key_pair = AptosKeyPair::from_mnemonic_seed(&seed, 0)?;
println!("Aptos Address: {}", key_pair.address);

// APT transfer
let tx = AptosTransaction::transfer(
    key_pair.address.clone(),
    AptosAddress::from_string("0x...")?,
    100_000_000, // 1 APT in octas
    sequence_number,
);
let signed = tx.sign(&key_pair)?;
```

### Sui Wallet

```rust
use rust_app::sui_wallet::{SuiKeyPair, SuiTransaction, SuiAddress, ObjectRef};

// Create key pair
let key_pair = SuiKeyPair::from_mnemonic_seed(&seed, 0)?;
println!("Sui Address: {}", key_pair.address);

// SUI transfer
let tx = SuiTransaction::transfer_sui(
    key_pair.address.clone(),
    SuiAddress::from_string("0x...")?,
    1_000_000_000, // 1 SUI in MIST
    gas_object,
    10_000_000, // gas budget
);
let signed = tx.sign(&key_pair)?;
```

### Polkadot/Kusama Wallet

```rust
use rust_app::polkadot_wallet::{SubstrateKeyPair, SubstrateExtrinsic, Ss58Network};

// Create Polkadot key pair
let key_pair = SubstrateKeyPair::from_mnemonic_seed(
    &seed, 0, Ss58Network::Polkadot
)?;
println!("DOT Address: {}", key_pair.address);

// Balance transfer
let tx = SubstrateExtrinsic::transfer(
    SubstrateAddress::from_string("1...")?,
    10_000_000_000, // 1 DOT in planck
    nonce,
    genesis_hash,
    spec_version,
    tx_version,
);
let signed = tx.sign(&key_pair)?;
```

### THORChain Cross-Chain Swaps

```rust
use rust_app::thorchain_swap::{ThorSwap, SwapRequest, ThorAsset, ThorChain};

// Initialize swap service
let swap = ThorSwap::mainnet();

// Create swap request: BTC -> ETH
let request = SwapRequest::new(
    ThorAsset::native(ThorChain::Bitcoin),
    ThorAsset::native(ThorChain::Ethereum),
    "bc1q...",  // BTC address
    "0x...",   // ETH address
    100_000_000, // 1 BTC in satoshis
)
.with_slippage(300); // 3%

// Get quote
let quote = swap.get_quote(&request)?;
println!("Expected output: {} ETH", quote.expected_amount_out);
println!("Vault address: {}", quote.inbound_address);
println!("Memo: {}", quote.memo);
```

---
