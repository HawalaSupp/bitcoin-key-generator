#ifndef RustBridge_h
#define RustBridge_h

#include <stdint.h>
#include <stdbool.h>

// Generates keys for all supported chains and returns a JSON string.
// The caller is responsible for freeing the returned string using free_string.
const char* generate_keys_ffi(void);
const char* fetch_balances_ffi(const char* json_input);
const char* fetch_bitcoin_history_ffi(const char* address);
const char* prepare_transaction_ffi(const char* json_input);
const char* prepare_ethereum_transaction_ffi(const char* json_input);
const char* restore_wallet_ffi(const char* mnemonic);
bool validate_mnemonic_ffi(const char* mnemonic);
// Frees a string allocated by Rust.
void free_string(char* s);

#endif /* RustBridge_h */
