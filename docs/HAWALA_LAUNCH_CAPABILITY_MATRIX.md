# Hawala Launch Capability Matrix

This is the Phase 0 source of truth for what Hawala should treat as launch scope, internal-only scope, and deferred scope.

Rules:
- `Launch` means the chain should appear in the main product experience once the listed capabilities are reliable.
- `Internal/Test` means the code may exist, but the chain should not be marketed or broadly exposed until the missing capabilities are complete.
- `Deferred` means not part of the current launch promise.
- A chain is not launch-ready if send is present but history, sync, and failure handling are weak.

Asset classes in scope:
- native coins
- fungible tokens
- staking positions
- bridge transfers
- WalletConnect-connected assets

Asset classes out of scope:
- non-fungible assets
- collectible galleries
- inscription-specific views

## Capability Definitions

- `Send`: user can prepare, review, and broadcast a transaction safely.
- `Receive`: user can show an address and receive funds on that chain.
- `History/Sync`: balances and transaction history can refresh reliably.
- `Swap`: chain participates in the in-app swap flow.
- `Bridge`: chain participates in the in-app bridge flow.
- `Stake`: chain has meaningful in-app staking support.
- `WalletConnect`: chain can be used safely in dApp connection flows.
- `Alerts`: price or activity alert coverage exists for the chain or its major assets.

## Proposed Launch Matrix

| Chain | Launch Status | Send | Receive | History/Sync | Swap | Bridge | Stake | WalletConnect | Alerts | Notes |
|:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| Bitcoin | Launch | Yes | Yes | Yes | No | No | No | No | Yes | Core UTXO chain with real sync support |
| Litecoin | Launch | Yes | Yes | Yes | No | No | No | No | Yes | Keep scope simple and reliable |
| Ethereum Mainnet | Launch | Yes | Yes | Yes | Yes | Yes | Partial | Yes | Yes | Highest-value smart-contract chain |
| Solana Mainnet | Launch | Yes | Yes | Yes | Partial | Partial | Partial | Partial | Yes | Keep launch scope conservative until staking execution is real |
| XRP Mainnet | Launch | Yes | Yes | Yes | No | No | No | No | Yes | Send and sync exist; keep advanced scope narrow |
| Polygon | Internal/Test | Yes | Yes | Partial | Yes | Yes | No | Yes | Yes | Do not market until sync/history is reliable |
| Arbitrum | Internal/Test | Yes | Yes | Partial | Yes | Yes | No | Yes | Yes | Strong candidate after Ethereum core hardening |
| Optimism | Internal/Test | Yes | Yes | Partial | Yes | Yes | No | Yes | Partial | Same gating as Arbitrum |
| Base | Internal/Test | Yes | Yes | Partial | Yes | Yes | No | Yes | Partial | Same gating as other EVM L2s |
| Avalanche | Internal/Test | Yes | Yes | Partial | Partial | Partial | No | Partial | Partial | Keep internal until history and provider quality improve |
| BNB Chain | Internal/Test | Yes | Yes | Partial | Partial | Partial | No | Partial | Partial | Avoid broad launch claims until provider paths are stable |
| Fantom | Deferred | Yes | Yes | Partial | Partial | Partial | No | Partial | No | Not part of first launch promise |
| Gnosis | Deferred | Yes | Yes | Partial | Partial | Partial | No | Partial | No | Not part of first launch promise |
| Scroll | Deferred | Yes | Yes | Partial | Partial | Partial | No | Partial | No | Not part of first launch promise |
| Ethereum Sepolia | Internal/Test | Yes | Yes | Yes | Internal | Internal | No | Internal | No | Engineering/test only |
| Bitcoin Testnet | Internal/Test | Yes | Yes | Yes | No | No | No | No | No | Engineering/test only |
| XRP Testnet | Internal/Test | Yes | Yes | Partial | No | No | No | No | No | Engineering/test only |

## Launch Rules By Capability

### Rule 1: Send is not enough

Do not expose a chain publicly just because `SendFlowHelper` allows sending.

Public exposure requires:
- send reliability
- receive support
- working balance/history refresh
- recoverable error handling

### Rule 2: Mainnet and testnet must be separated in product scope

Testnets may remain in code for development, but they are not launch features.

### Rule 3: Swap and bridge should be launch-scoped only on chains with real quote and execution paths

If a chain depends on mock fallback or weak provider quality, keep it internal.

### Rule 4: Staking is launch-scoped per chain, not globally

Do not claim “staking support” broadly until at least one chain has fully working stake lifecycle support.

## Immediate Follow-Up Tasks

1. Convert this matrix into a code-owned capability registry later.
2. Make UI exposure depend on the matrix, not scattered string checks.
3. Remove launch claims that exceed this matrix.
4. Revisit the `Internal/Test` rows after Phase 1 through Phase 6 work is done.
