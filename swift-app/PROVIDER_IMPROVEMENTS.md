# Blockchain Data Provider Improvements

## Overview

Added enterprise-grade blockchain data providers to improve reliability for transaction histories and balance fetching. The new providers are used by major wallet apps like Trust Wallet, Exodus, and MetaMask.

## New Providers Added

### 1. Moralis (Primary Provider)
- **Used by**: Trust Wallet, Exodus, MetaMask, Ledger, Kraken
- **Free tier**: 40,000 CU/day (compute units)
- **Supported chains**: 30+ EVM chains + Solana
- **Features**:
  - Native balance fetching
  - Token balances (ERC-20, SPL)
  - Transaction history with full details
  - Token transfers tracking
  - Price API
- **API Key**: Get free at [moralis.io](https://moralis.io)

### 2. Tatum (Prepared for Future)
- **Supported chains**: 130+ blockchain networks
- **Free tier**: 5 requests/second
- **Features**:
  - Universal API for all chains
  - Transaction broadcasting
  - Balance queries
  - NFT support
- **API Key**: Get free at [tatum.io](https://tatum.io)

### 3. Unified Blockchain Provider
A new service that intelligently routes requests through available providers with automatic fallback:

```
Priority Order:
1. Moralis (if API key configured)
2. Alchemy (for EVM chains)
3. Tatum (if API key configured)
4. Public APIs (Mempool.space, Etherscan, etc.)
```

## Files Created/Modified

### New Files
- `swift-app/Sources/swift-app/Services/MoralisAPI.swift` - Full Moralis API client
- `swift-app/Sources/swift-app/Services/UnifiedBlockchainProvider.swift` - Unified provider service

### Modified Files
- `APIKeys.swift` - Added Moralis and Tatum key storage
- `MultiProviderAPI.swift` - Added Moralis as primary price provider
- `ProviderHealthManager.swift` - Added Moralis and Tatum provider types
- `ProviderSettingsView.swift` - Added UI for Moralis and Tatum API keys

## Provider Fallback Chain

### Price Data
1. **Moralis** (if API key) - Used by Trust Wallet
2. **CoinCap** - Free, no API key
3. **CryptoCompare** - Free tier
4. **CoinGecko** - Often rate limited

### Balance/Transaction Data
1. **Moralis** (EVM + Solana) - if API key
2. **Alchemy** (EVM + Solana) - if API key  
3. **Tatum** (130+ chains) - if API key
4. **Public APIs**:
   - Mempool.space (Bitcoin)
   - Etherscan (Ethereum)
   - Blockcypher (Litecoin)
   - Solana RPC (Solana)
   - XRP RPC (XRP)
   - BscScan (BNB)

## How to Configure

### Option 1: Settings UI
1. Open Hawala app
2. Go to Settings → Provider Settings
3. Click "Add" next to Moralis API Key
4. Enter your API key from moralis.io
5. Click Save

### Option 2: Environment Variable
```bash
export MORALIS_API_KEY="your-api-key-here"
export TATUM_API_KEY="your-api-key-here"
```

## Benefits

1. **Higher Reliability**: Multiple fallback providers ensure data is always available
2. **Better Coverage**: Support for 130+ blockchains via Tatum
3. **Industry Standard**: Same providers used by Trust Wallet, Exodus, MetaMask
4. **Smart Routing**: Automatic selection of best available provider
5. **Rate Limit Protection**: Built-in rate limiting with backoff
6. **Graceful Degradation**: Falls back to public APIs if premium providers fail

## Known Issues Fixed

- **CoinCap Unavailability**: CoinCap frequently returns "server not found" errors
  - Solution: Moralis now used as primary, CoinCap demoted to fallback
- **Rate Limiting**: CoinGecko aggressive rate limiting
  - Solution: Added multiple providers, intelligent retry with backoff

## Testing

Run the app and check the debug console for provider health:
```
📊 Trying Moralis for prices...
✅ Moralis returned 7 prices
🔍 [Provider] Provider Moralis marked healthy
```

Or without Moralis key:
```
📊 Trying CoinCap for prices...
⚠️ CoinCap failed: A server with the specified hostname could not be found.
📊 Trying CryptoCompare for prices...
✅ CryptoCompare returned 7 prices
```
