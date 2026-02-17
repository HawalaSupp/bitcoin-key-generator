# Hawala — Crypto Swap Providers (Commission Programs)

> **Purpose:** Reference list of swap providers to sign up with before app launch.  
> Each provider offers affiliate/revenue-share or configurable fee parameters where Hawala earns on every swap routed through their API/widget.  
> **Status:** UI is built in `SwapCryptoView.swift`. Existing `SwapService.swift` has Changelly, ChangeNOW, SimpleSwap, Exolix stubs. `DEXAggregatorService.swift` has 1inch, 0x, THORChain, Osmosis, Uniswap, ParaSwap stubs.

---

## Cross-Chain Swap Providers (Non-Custodial Exchanges)

These handle swaps between different blockchains (e.g. BTC → ETH). No user registration required.

| # | Provider | Signup URL | Fee | Commission Model | Pairs | Est. Time |
|---|----------|-----------|-----|-----------------|-------|-----------|
| 1 | **Changelly** | https://changelly.com/for-partners | 0.25% | Revenue share **50%** of fees | 500+ | 5–30 min |
| 2 | **ChangeNOW** | https://changenow.io/affiliate | 0.50% | Revenue share **50%** of fees | 900+ | 5–30 min |
| 3 | **SimpleSwap** | https://simpleswap.io/affiliate | 0.50% | Revenue share **50%** of swaps | 1500+ | 10–40 min |
| 4 | **Exolix** | https://exolix.com/affiliate | 0.30% | Revenue share per swap | 500+ | 5–20 min |
| 5 | **SideShift.ai** | https://sideshift.ai/affiliate | 0.50% | Revenue share via affiliate ID | 100+ | 5–15 min |
| 6 | **THORSwap** | https://docs.thorswap.net/aggregation-api | 0.30% | Affiliate fee embedded in swap TX (configurable bps) | 5000+ | 10–60 min |
| 7 | **StealthEX** | https://stealthex.io/affiliate | 0.40% | Revenue share **up to 50%** | 1400+ | 10–30 min |
| 8 | **LetsExchange** | https://letsexchange.io/affiliate-program | 0.35% | Revenue share **50%** of fees | 4800+ | 5–30 min |
| 9 | **Swapzone** *(aggregator)* | https://swapzone.io/partnership | 0.00% | Revenue share on aggregated swaps | 1600+ | 5–30 min |

## DEX Aggregator Providers (On-Chain Swaps)

These route swaps through decentralized exchanges on the same chain. Commission is via configurable fee parameters (basis points) on each swap.

| # | Provider | Signup URL | Fee | Commission Model | Pairs | Est. Time |
|---|----------|-----------|-----|-----------------|-------|-----------|
| 1 | **1inch Fusion** | https://portal.1inch.dev | 0.00% | Referral fee via swap surplus (positive slippage) | 10K+ | < 1 min |
| 2 | **0x Protocol** | https://0x.org/docs/developer-resources/signup | 0.00% | Affiliate fee (configurable bps on each swap) | 5K+ | < 1 min |
| 3 | **ParaSwap** | https://developers.paraswap.network | 0.00% | Revenue share via partner fee (configurable bps) | 8K+ | < 1 min |
| 4 | **Jupiter** *(Solana)* | https://station.jup.ag/docs/apis | 0.00% | Referral fee via platform fee parameter | 3K+ | < 10 sec |
| 5 | **Uniswap** | https://docs.uniswap.org/sdk/v3/overview | 0.30% | Interface fee (front-end referral) | 15K+ | < 1 min |
| 6 | **KyberSwap** | https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator | 0.00% | Partner commission via referral program | 6K+ | < 1 min |
| 7 | **Odos** | https://docs.odos.xyz | 0.00% | Referral fee (configurable bps) | 4K+ | < 1 min |
| 8 | **LI.FI** *(cross-chain DEX)* | https://docs.li.fi/integrate-li.fi-sdk | 0.00% | Integrator fee (configurable bps, up to 100% yours) | 10K+ | 1–10 min |

---

## Recommended Signup Priority

### Cross-Chain Swaps
1. **Changelly** — Industry standard, 50% rev share, widget ready
2. **ChangeNOW** — 900+ coins, 50% rev share, simple API
3. **Swapzone** — Aggregator that auto-compares all providers
4. **THORSwap** — Native DEX, configurable affiliate bps in TX

### DEX Aggregators
1. **LI.FI** — Cross-chain + DEX in one, configurable integrator fee
2. **0x Protocol** — Professional API, configurable affiliate bps
3. **1inch** — Largest DEX aggregator, surplus sharing
4. **Jupiter** — Essential for Solana swaps

---

## Integration Notes

### Cross-chain providers (SwapService.swift)
Each provider has a widget URL and an API. The widget approach is simplest:
1. Get API key from provider
2. Build widget URL with `affiliateId` / `refId` parameter  
3. Open in WebView or browser
4. Commission is tracked automatically via your affiliate ID

### DEX aggregators (DEXAggregatorService.swift)
DEX aggregators use on-chain transactions:
1. Get API key / register as integrator
2. When building the swap TX, include the `referrerAddress` + `fee` (in basis points)
3. The fee is taken from the swap output and sent to your address on-chain
4. Example: 0x API → set `affiliateAddress` and `buyTokenPercentageFee` (0.01 = 1%)

### API Key Configuration
```
CHANGELLY_API_KEY=xxx
CHANGENOW_API_KEY=xxx
SIMPLESWAP_API_KEY=xxx
EXOLIX_API_KEY=xxx
ONEINCH_API_KEY=xxx
ZEROX_API_KEY=xxx
LIFI_INTEGRATOR_ID=hawala
```

---

*Last updated: 2026-02-15*
