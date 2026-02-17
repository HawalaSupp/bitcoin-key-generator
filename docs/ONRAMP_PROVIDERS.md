# Hawala — Fiat On-Ramp / Off-Ramp Providers (Commission Programs)

> **Purpose:** Reference list of providers to sign up with before app launch.  
> Each provider offers an affiliate/revenue-share program where Hawala earns a commission on every buy/sell transaction routed through their widget.  
> **Status:** UI is built in `BuySellView.swift`. Wire API keys into `OnRampService.swift` when ready.

---

## Tier 1 — Already Integrated (widget URL generation ready)

| # | Provider | Signup URL | Fee | Commission Model | Cryptos | Countries | Buy | Sell |
|---|----------|-----------|-----|-----------------|---------|-----------|-----|------|
| 1 | **MoonPay** | https://dashboard.moonpay.com/register | 4.5% | Revenue share **up to 50%** of fees | 100+ | 160+ | ✅ | ✅ |
| 2 | **Transak** | https://transak.com/partner | 5.0% | Revenue share **10–50%** of fees | 170+ | 170+ | ✅ | ✅ |
| 3 | **Ramp Network** | https://ramp.network/partner | 2.5% | Revenue share **up to 70%** of fees | 90+ | 150+ | ✅ | ✅ |

## Tier 2 — Ready to Integrate (sign up → get API key → add to `OnRampService`)

| # | Provider | Signup URL | Fee | Commission Model | Cryptos | Countries | Buy | Sell |
|---|----------|-----------|-----|-----------------|---------|-----------|-----|------|
| 4 | **Banxa** | https://banxa.com/partner | 2.0% | Revenue share per transaction | 50+ | 180+ | ✅ | ✅ |
| 5 | **Simplex (Nuvei)** | https://dashboard.simplex.com/register | 5.0% | Revenue share on transaction fees | 50+ | 180+ | ✅ | ❌ |
| 6 | **Sardine** | https://sardine.ai/contact | 1.5% | Customizable revenue share | 40+ | 50+ | ✅ | ✅ |
| 7 | **Mercuryo** | https://mercuryo.io/partners | 3.95% | Revenue share **25–50%** of fees | 30+ | 100+ | ✅ | ✅ |
| 8 | **Onramper** *(aggregator)* | https://onramper.com/partner | 1.0% | Revenue share on aggregated volume | 200+ | 180+ | ✅ | ✅ |
| 9 | **Alchemy Pay** | https://alchemypay.org/partner | 3.5% | Commission per transaction | 300+ | 173+ | ✅ | ✅ |
| 10 | **Topper (Uphold)** | https://topper.dev | 3.0% | Revenue share per transaction | 70+ | 130+ | ✅ | ✅ |
| 11 | **Guardarian** | https://guardarian.com/for-partners | 3.5% | Revenue share on fees | 400+ | 170+ | ✅ | ✅ |
| 12 | **Paybis** | https://paybis.com/affiliate-program | 2.49% | Revenue share **up to 25%** | 100+ | 180+ | ✅ | ✅ |
| 13 | **Utorg** | https://utorg.pro/partners | 4.0% | Revenue share per trade | 200+ | 187+ | ✅ | ✅ |
| 14 | **Swipelux** | https://swipelux.com/for-business | 3.5% | Revenue share per transaction | 300+ | 150+ | ✅ | ✅ |
| 15 | **Kado** | https://kado.money/partners | 1.5% | Revenue share on volume | 20+ | 50+ | ✅ | ✅ |
| 16 | **Robinhood Connect** | https://robinhood.com/connect | 1.5% | Per-transaction referral fee | 15+ | US only | ✅ | ❌ |
| 17 | **Coinbase Onramp** | https://www.coinbase.com/cloud/products/onramp | 1.0% | Revenue share via Coinbase Commerce | 100+ | 100+ | ✅ | ✅ |

---

## Recommended Signup Priority

1. **Ramp Network** — Highest rev share (70%), lowest base fees (2.5%)
2. **MoonPay** — Widest brand recognition, 50% rev share
3. **Onramper** — Aggregator that auto-compares 15+ providers for best rate
4. **Sardine** — Instant ACH, great for US users, customizable rev share
5. **Banxa** — Regulated, competitive spreads, global coverage

## API Key Configuration

API keys are loaded from environment variables in `OnRampService.swift`:

```
MOONPAY_API_KEY=pk_live_xxx
TRANSAK_API_KEY=xxx
RAMP_API_KEY=xxx
```

For production, migrate to Keychain storage via `SecurityManager`.

---

*Last updated: 2026-02-15*
