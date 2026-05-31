#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Checking production guardrails..."

if rg -n --glob '!docs/**' \
  --glob '!rust-app/src/dex/**' \
  --glob '!rust-app/src/bridge/**' \
  --glob '!rust-app/src/ibc/**' \
  --glob '!rust-app/src/lightning/**' \
  --glob '!rust-app/src/ordinals/**' \
  --glob '!rust-app/src/onramp/**' \
  --glob '!rust-app/src/thorchain_swap.rs' \
  --glob '!rust-app/src/mina_wallet.rs' \
  --glob '!rust-app/src/monero_wallet.rs' \
  --glob '!swift-app/Sources/swift-app/Services/Swap/**' \
  --glob '!swift-app/Sources/swift-app/Services/Bridge/**' \
  --glob '!**/tests/**' --glob '!**/*Tests/**' --glob '!**/*tests.rs' --glob '!**/*.bak' \
  'mock quote|mock bridge|mock fallback|generateMockTxHash|mock_monero_tx_hex|placeholder public key|return mock|mock implementation' \
  rust-app/src swift-app/Sources; then
  cat <<'MESSAGE'

Production guard failed.

Mock or placeholder execution paths were found in launch-scope source areas.
Move them behind explicit development-only gates, replace them with real
provider/protocol implementations, or restrict them to tests/previews/docs
before shipping.
MESSAGE
  exit 1
fi

if find swift-app/Sources -name '*.swift' -not -name '*.bak' -print0 |
  xargs -0 awk '
    /^[[:space:]]*#if[[:space:]]+DEBUG/ { debug_depth += 1 }
    /^[[:space:]]*#endif/ { if (debug_depth > 0) debug_depth -= 1 }
    debug_depth == 0 && /^[[:space:]]*print\(/ && tolower($0) ~ /(private|secret|seed|mnemonic|wif|passphrase)/ {
      printf "%s:%d:%s\n", FILENAME, FNR, $0
      found = 1
    }
    END { exit found ? 1 : 0 }
  '; then
  :
else
  cat <<'MESSAGE'

Production guard failed.

Potential sensitive print statements were found. Use HawalaLogger redaction or
DEBUG-only logging, and never log secrets or recovery material.
MESSAGE
  exit 1
fi

echo "Production guardrails passed."
