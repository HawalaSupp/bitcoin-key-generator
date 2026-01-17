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