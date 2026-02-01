#ifndef RustBridge_h
#define RustBridge_h

#include <stdint.h>
#include <stdbool.h>

// ============================================================================
// HAWALA CORE FFI - Unified Rust Backend API
// All functions return JSON with ApiResponse<T> format:
// {"success": true/false, "data": {...}, "error": {...}}
// ============================================================================

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------
void hawala_free_string(char* s);

// ----------------------------------------------------------------------------
// Wallet Operations
// ----------------------------------------------------------------------------
const char* hawala_generate_wallet(void);
const char* hawala_restore_wallet(const char* json_input);
const char* hawala_validate_mnemonic(const char* json_input);
const char* hawala_validate_address(const char* json_input);
const char* hawala_derive_address_from_key(const char* json_input);

// ----------------------------------------------------------------------------
// Transaction Pipeline (Phase 2)
// ----------------------------------------------------------------------------
const char* hawala_prepare_transaction(const char* json_input);
const char* hawala_sign_transaction(const char* json_input);
const char* hawala_broadcast_transaction(const char* json_input);

// ----------------------------------------------------------------------------
// Fee Estimation (Phase 3)
// ----------------------------------------------------------------------------
const char* hawala_estimate_fees(const char* json_input);
const char* hawala_estimate_gas(const char* json_input);
const char* hawala_analyze_fees(const char* json_input);

// ----------------------------------------------------------------------------
// Transaction Cancellation (Phase 4)
// ----------------------------------------------------------------------------
const char* hawala_cancel_bitcoin(const char* json_input);
const char* hawala_speedup_bitcoin(const char* json_input);
const char* hawala_cancel_evm(const char* json_input);
const char* hawala_speedup_evm(const char* json_input);

// ----------------------------------------------------------------------------
// Transaction Tracking (Phase 4)
// ----------------------------------------------------------------------------
const char* hawala_track_transaction(const char* json_input);
const char* hawala_get_confirmations(const char* json_input);
const char* hawala_get_tx_status(const char* json_input);

// ----------------------------------------------------------------------------
// History Operations (Phase 5)
// ----------------------------------------------------------------------------
const char* hawala_fetch_history(const char* json_input);
const char* hawala_fetch_chain_history(const char* json_input);

// ----------------------------------------------------------------------------
// Balance Operations (Phase 5)
// ----------------------------------------------------------------------------
const char* hawala_fetch_balances(const char* json_input);
const char* hawala_fetch_balance(const char* json_input);
const char* hawala_fetch_token_balance(const char* json_input);
const char* hawala_fetch_spl_balance(const char* json_input);

// ----------------------------------------------------------------------------
// UTXO Management (Phase 6)
// ----------------------------------------------------------------------------
const char* hawala_fetch_utxos(const char* json_input);
const char* hawala_select_utxos(const char* json_input);
const char* hawala_set_utxo_metadata(const char* json_input);

// ----------------------------------------------------------------------------
// Nonce Management (Phase 6)
// ----------------------------------------------------------------------------
const char* hawala_get_nonce(const char* json_input);
const char* hawala_reserve_nonce(const char* json_input);
const char* hawala_confirm_nonce(const char* json_input);
const char* hawala_detect_nonce_gaps(const char* json_input);

// ----------------------------------------------------------------------------
// Security Operations (Phase 5 - Security Hardening)
// ----------------------------------------------------------------------------

// Threat Detection
const char* hawala_assess_threat(const char* json_input);
const char* hawala_blacklist_address(const char* json_input);
const char* hawala_whitelist_address(const char* json_input);

// Transaction Policies
const char* hawala_check_policy(const char* json_input);
const char* hawala_set_spending_limits(const char* json_input);

// Authentication & Verification
const char* hawala_create_challenge(const char* json_input);
const char* hawala_verify_challenge(const char* json_input);

// Key Rotation
const char* hawala_register_key_version(const char* json_input);
const char* hawala_check_key_rotation(const char* json_input);

// Secure Memory Utilities
const char* hawala_secure_compare(const char* json_input);
const char* hawala_redact(const char* json_input);

// ----------------------------------------------------------------------------
// EIP-712 Typed Data Signing (Advanced Signing & Security)
// ----------------------------------------------------------------------------
const char* hawala_eip712_hash(const char* json_input);
const char* hawala_eip712_sign(const char* json_input);
const char* hawala_eip712_verify(const char* json_input);
const char* hawala_eip712_recover(const char* json_input);

// ----------------------------------------------------------------------------
// Message Signing (Personal Sign / EIP-191)
// ----------------------------------------------------------------------------
const char* hawala_personal_sign(const char* json_input);
const char* hawala_personal_verify(const char* json_input);
const char* hawala_personal_recover(const char* json_input);
const char* hawala_solana_sign_message(const char* json_input);
const char* hawala_solana_verify_message(const char* json_input);
const char* hawala_cosmos_sign_arbitrary(const char* json_input);
const char* hawala_tezos_sign_message(const char* json_input);

// ----------------------------------------------------------------------------
// EIP-7702 Account Delegation (Advanced Signing & Security)
// ----------------------------------------------------------------------------
const char* hawala_eip7702_sign_authorization(const char* json_input);
const char* hawala_eip7702_sign_transaction(const char* json_input);
const char* hawala_eip7702_recover_authorization_signer(const char* json_input);

// ----------------------------------------------------------------------------
// External Signature Compilation (Hardware Wallet / Air-Gapped Signing)
// ----------------------------------------------------------------------------
// Pre-image hash generation
const char* hawala_get_bitcoin_sighashes(const char* json_input);
const char* hawala_get_ethereum_signing_hash(const char* json_input);
const char* hawala_get_cosmos_sign_doc_hash(const char* json_input);
const char* hawala_get_solana_message_hash(const char* json_input);

// Transaction compilation with external signatures
const char* hawala_compile_bitcoin_transaction(const char* json_input);
const char* hawala_compile_ethereum_transaction(const char* json_input);
const char* hawala_compile_cosmos_transaction(const char* json_input);
const char* hawala_compile_solana_transaction(const char* json_input);

// ----------------------------------------------------------------------------
// BIP-340 Schnorr Signatures (Bitcoin Taproot)
// ----------------------------------------------------------------------------
const char* hawala_schnorr_sign(const char* json_input);
const char* hawala_schnorr_verify(const char* json_input);
const char* hawala_taproot_tweak_pubkey(const char* json_input);
const char* hawala_taproot_sign_key_path(const char* json_input);
const char* hawala_taproot_leaf_hash(const char* json_input);
const char* hawala_taproot_merkle_root(const char* json_input);

// ----------------------------------------------------------------------------
// Multi-Curve Cryptography (secp256k1, ed25519, sr25519, secp256r1)
// ----------------------------------------------------------------------------
const char* hawala_curve_generate_keypair(const char* json_input);
const char* hawala_curve_public_key(const char* json_input);
const char* hawala_curve_sign(const char* json_input);
const char* hawala_curve_verify(const char* json_input);
const char* hawala_curve_info(const char* json_input);

// ----------------------------------------------------------------------------
// QR Code Encoding/Decoding (Air-Gapped Signing, UR Format)
// ----------------------------------------------------------------------------
const char* hawala_qr_encode_ur(const char* json_input);
const char* hawala_qr_encode_simple(const char* json_input);
const char* hawala_qr_decode_ur(const char* json_input);
const char* hawala_qr_decoder_create(void);
const char* hawala_qr_supported_types(void);

// ----------------------------------------------------------------------------
// HD Key Derivation (BIP-32 / SLIP-0010)
// ----------------------------------------------------------------------------
const char* hawala_derive_key(const char* json_input);

// ----------------------------------------------------------------------------
// DEX Aggregator (1inch, 0x, THORChain)
// ----------------------------------------------------------------------------
const char* hawala_dex_get_quotes(const char* json_input);
const char* hawala_dex_get_best_quote(const char* json_input);
const char* hawala_dex_get_providers(const char* json_input);

// ----------------------------------------------------------------------------
// Cross-Chain Bridge (Wormhole, LayerZero, Stargate)
// ----------------------------------------------------------------------------
const char* hawala_bridge_get_quotes(const char* json_input);
const char* hawala_bridge_get_best_quote(const char* json_input);
const char* hawala_bridge_get_providers(const char* json_input);
const char* hawala_bridge_track_transfer(const char* json_input);

// ----------------------------------------------------------------------------
// IBC (Inter-Blockchain Communication) for Cosmos SDK Chains
// ----------------------------------------------------------------------------
const char* hawala_ibc_build_transfer(const char* json_input);
const char* hawala_ibc_get_channel(const char* json_input);
const char* hawala_ibc_get_supported_chains(const char* json_input);
const char* hawala_ibc_sign_transfer(const char* json_input);

// ----------------------------------------------------------------------------
// Shamir's Secret Sharing (Social Recovery)
// ----------------------------------------------------------------------------
const char* hawala_shamir_create_shares(const char* json_input);
const char* hawala_shamir_recover(const char* json_input);
const char* hawala_shamir_validate_share(const char* json_input);

// ----------------------------------------------------------------------------
// Staking Operations (Solana, Cosmos, Polkadot)
// ----------------------------------------------------------------------------
const char* hawala_staking_get_info(const char* json_input);
const char* hawala_staking_get_validators(const char* json_input);
const char* hawala_staking_prepare_tx(const char* json_input);

// ----------------------------------------------------------------------------
// Phase 2: Security & Trust Features
// ----------------------------------------------------------------------------

// Transaction Simulation
const char* hawala_simulate_transaction(const char* json_input);
const char* hawala_analyze_risk(const char* json_input);

// Token Approval Management
const char* hawala_get_approvals(const char* json_input);
const char* hawala_revoke_approval(const char* json_input);
const char* hawala_batch_revoke(const char* json_input);

// Phishing & Scam Detection
const char* hawala_check_phishing_address(const char* json_input);
const char* hawala_check_phishing_domain(const char* json_input);

// Address Whitelisting
const char* hawala_whitelist_add(const char* json_input);
const char* hawala_whitelist_remove(const char* json_input);
const char* hawala_whitelist_check(const char* json_input);
const char* hawala_whitelist_get_all(const char* json_input);
const char* hawala_whitelist_configure(const char* json_input);

// Combined Security Check
const char* hawala_security_check(const char* json_input);

// ----------------------------------------------------------------------------
// Phase 3: User Experience Features
// ----------------------------------------------------------------------------

// L2 Balance Aggregation
const char* hawala_aggregate_balances(const char* json_input);
const char* hawala_suggest_chain(const char* json_input);

// Payment Request Links
const char* hawala_create_payment_link(const char* json_input);
const char* hawala_parse_payment_link(const char* json_input);
const char* hawala_create_bip21_link(const char* json_input);
const char* hawala_create_eip681_link(const char* json_input);

// Transaction Notes
const char* hawala_add_note(const char* json_input);
const char* hawala_search_notes(const char* json_input);
const char* hawala_export_notes(const char* json_input);

// Fiat Off-Ramp
const char* hawala_offramp_quote(const char* json_input);
const char* hawala_offramp_compare(const char* json_input);
const char* hawala_offramp_currencies(const char* json_input);
const char* hawala_offramp_cryptos(const char* json_input);

// Price Alerts
const char* hawala_create_alert(const char* json_input);
const char* hawala_get_price(const char* json_input);
const char* hawala_alert_stats(void);

// ============================================================================
// LEGACY API - Backward compatibility (deprecated, will be removed)
// ============================================================================
const char* generate_keys_ffi(void);
const char* fetch_balances_ffi(const char* json_input);
const char* fetch_bitcoin_history_ffi(const char* address);
const char* prepare_transaction_ffi(const char* json_input);
const char* prepare_ethereum_transaction_ffi(const char* json_input);
const char* restore_wallet_ffi(const char* mnemonic);
bool validate_mnemonic_ffi(const char* mnemonic);
bool validate_ethereum_address_ffi(const char* address);
void keccak256_ffi(const uint8_t* data, size_t len, uint8_t* output);
const char* prepare_taproot_transaction_ffi(const char* json_input);
const char* derive_taproot_address_ffi(const char* wif);
void free_string(char* s);

#endif /* RustBridge_h */