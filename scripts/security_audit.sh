#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ACCEPTED_RUSTSEC_IDS=(
  "RUSTSEC-2024-0344" # Solana transitive curve25519-dalek 3.x; launch use limited and tracked in docs.
  "RUSTSEC-2022-0093" # Solana transitive ed25519-dalek 1.x; direct app dependency already uses 2.x.
  "RUSTSEC-2024-0398" # sharks has no patched release; Shamir feature remains non-launch/internal.
)

echo "Running Hawala Phase 2 security audit..."

echo "Checking production guardrails..."
scripts/check_production_guards.sh

echo "Checking Rust dependency advisories..."
audit_args=(--file rust-app/Cargo.lock)
for id in "${ACCEPTED_RUSTSEC_IDS[@]}"; do
  audit_args+=(--ignore "$id")
done
cargo audit "${audit_args[@]}"

echo "Checking dependency policy with cargo-deny..."
if command -v cargo-deny >/dev/null 2>&1; then
  cargo deny --manifest-path rust-app/Cargo.toml check --config deny.toml licenses bans sources
else
  echo "cargo-deny is not installed; install it with: cargo install cargo-deny --locked"
  echo "Skipping local cargo-deny policy check."
fi

echo "Checking release panic boundary..."
if ! awk '
  /^\[profile\.release\]/ { in_release = 1; next }
  /^\[/ && in_release { in_release = 0 }
  in_release && /^[[:space:]]*panic[[:space:]]*=[[:space:]]*"abort"/ { found = 1 }
  END { exit found ? 0 : 1 }
' rust-app/Cargo.toml; then
  echo "Release profile must set panic = \"abort\" so Rust panics cannot unwind across FFI." >&2
  exit 1
fi

echo "Scanning source for high-risk secret patterns..."
SECRET_SCAN_EXCLUDES=(
  ':(exclude)docs/**'
  ':(exclude)*_ROADMAP.md'
  ':(exclude)swift-app-backup-*/**'
  ':(exclude)swift-app/Tests/**'
  ':(exclude)rust-app/tests/**'
  ':(exclude)**/Package.resolved'
  ':(exclude)**/Cargo.lock'
)

if git grep -n -I -E \
  '(-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{36,}|(api[_-]?key|secret|private[_-]?key|mnemonic|seed|passcode).{0,40}(sk_live|pk_live|AKIA|-----BEGIN|[0-9a-fA-F]{64}))' \
  -- . "${SECRET_SCAN_EXCLUDES[@]}"; then
  echo "Potential hardcoded secret found. Remove it or add a narrowly scoped scanner exception with rationale." >&2
  exit 1
fi

if command -v gitleaks >/dev/null 2>&1; then
  echo "Running gitleaks..."
  gitleaks detect --source "$ROOT_DIR" --no-banner --redact
else
  echo "gitleaks is not installed; regex secret scan completed as fallback."
fi

echo "Security audit completed."
