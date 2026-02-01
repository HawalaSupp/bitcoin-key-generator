# Hawala 2.0 - Feature Gap Analysis

**Generated:** November 30, 2025  
**Purpose:** Comprehensive benchmark-driven review of missing features for release readiness

---

## Executive Summary

**Total Features Identified:** 65  
- **High Priority:** 12 (critical for release)  
- **Medium Priority:** 21 (competitive product)  
- **Low Priority:** 31 (future roadmap)  
- **Not Feasible:** 1 (Tor - App Store constraints)

---

## Critical Missing Features for Release

| # | Feature | Priority | Status |
|---|---------|----------|--------|
| 1 | Bitcoin RBF Transaction Cancellation | HIGH | ✅ Complete |
| 2 | Ethereum Transaction Cancellation | HIGH | ✅ Complete |
| 3 | WalletConnect v2 Integration | HIGH | ✅ Complete |
| 4 | EIP-1559 Transaction Support | HIGH | ✅ Complete |
| 5 | Gas Estimation for Contracts | HIGH | ✅ Complete |
| 6 | Biometric Confirmation for Transactions | HIGH | Missing |
| 7 | Terms of Service/Privacy Policy | HIGH | Missing |
| 8 | App Store Preparation | HIGH | Missing |

---

## Crypto Cancellation Feasibility Matrix

| Chain | Method | Feasibility | Time Window | Notes |
|-------|--------|-------------|-------------|-------|
| **Bitcoin** | RBF (BIP-125) | ✅ Possible | Minutes-hours | Requires UTXO tracking |
| **Ethereum** | Nonce replacement | ✅ Easy | ~12 seconds | Send 0 ETH to self, same nonce |
| **Litecoin** | RBF-like | ✅ Possible | Minutes | Similar to Bitcoin |
| **BNB Chain** | Nonce replacement | ✅ Easy | ~3 seconds | Same as Ethereum |
| **Solana** | N/A | ❌ Not feasible | ~400ms | Instant finality |
| **XRP** | N/A | ❌ Not practical | 3-5 seconds | Near-instant consensus |
| **Monero** | N/A | ❌ Not possible | N/A | No RBF mechanism |

---

## Complete Feature List (JSON)

```json
[
  {
    "feature_name": "Bitcoin Transaction Cancellation (RBF)",
    "description": "Allow users to cancel unconfirmed Bitcoin transactions by replacing them with a higher-fee transaction that sends funds back to themselves. BlueWallet's 'Bump fee' and 'Cancel' feature uses Replace-By-Fee (BIP-125) to either speed up or effectively cancel stuck transactions.",
    "inspired_by": "BlueWallet, Electrum, Sparrow Wallet",
    "research_notes": "The app already has SpeedUpTransactionSheet.swift with RBF sequence number (0xfffffffd) set in BitcoinTransaction.swift, but actual Bitcoin RBF implementation throws 'featureInProgress' error. Full implementation requires: 1) Storing original UTXOs used in pending transactions, 2) Rebuilding transaction with same inputs but recipient = self address, 3) Higher fee rate. Technical limitation: Must track pending UTXOs to prevent double-spend attempts.",
    "implementation_status": "complete",
    "priority": "high",
    "dependencies": ["UTXO tracking service", "Pending transaction storage with full input data"],
    "notes": "Implemented in rust-app/src/tx/cancellation.rs with cancel_bitcoin_rbf() and speed_up_bitcoin_rbf() functions. Swift integration via TransactionCancellationManager.swift and SpeedUpTransactionSheet.swift.",
    "examples": ["User sends BTC with low fee, transaction stuck for hours, clicks 'Cancel' to reclaim funds", "Replace stuck transaction with self-send at higher fee to invalidate original"]
  },
  {
    "feature_name": "Ethereum Transaction Cancellation",
    "description": "Cancel pending Ethereum transactions by sending a 0-value transaction to self with the same nonce but higher gas price. This replaces the pending transaction in the mempool.",
    "inspired_by": "MetaMask, Trust Wallet, Rainbow Wallet",
    "research_notes": "Implemented in rust-app/src/tx/cancellation.rs with cancel_evm_nonce() and speed_up_evm() functions. Swift integration via TransactionCancellationManager.swift. Supports both legacy and EIP-1559 fee bumping.",
    "implementation_status": "complete",
    "priority": "high",
    "dependencies": ["EIP-1559 transaction support"],
    "examples": ["User accidentally sends ETH to wrong address, quickly cancels before confirmation", "Cancel stuck transaction when gas prices drop"]
  },
  {
    "feature_name": "Multi-Chain Transaction Cancellation Matrix",
    "description": "Comprehensive cancellation support across all supported chains with clear UI indicating which chains support cancellation and which don't.",
    "inspired_by": "Trust Wallet, Exodus",
    "research_notes": "Chain-by-chain cancellation feasibility: BTC (RBF if enabled) ✓, ETH (nonce replacement) ✓, LTC (similar to BTC) ✓, SOL (transactions finalize in ~400ms - cancellation not feasible), XRP (transactions finalize in 3-5 seconds - very narrow window), BNB (nonce replacement like ETH) ✓, Monero (no RBF mechanism - not feasible). UI should clearly show which pending transactions can be cancelled.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["Bitcoin RBF implementation", "Ethereum cancellation"],
    "examples": ["Show 'Cancel' button only on chains that support it", "Display 'Cannot cancel - transaction finalizes instantly' for Solana"]
  },
  {
    "feature_name": "WalletConnect v2 Integration",
    "description": "Connect to dApps via WalletConnect protocol to sign transactions and messages from web3 applications without exposing private keys.",
    "inspired_by": "Trust Wallet, MetaMask, Rainbow Wallet, Coinbase Wallet",
    "research_notes": "Fully implemented in WalletConnectService.swift (613 lines). Features: WebSocket relay connection, session proposal/approval/rejection, request handling (eth_sendTransaction, personal_sign, eth_signTypedData_v4), session persistence, chain switching, error handling. UI in WalletConnectView.swift. Integrated in ContentView.swift with handleWalletConnectSign().",
    "implementation_status": "complete",
    "priority": "high",
    "dependencies": ["QR scanner (exists)", "Transaction signing (exists)", "Message signing"],
    "examples": ["Scan QR on Uniswap to connect wallet", "Approve swap transaction from dApp", "Sign message to prove wallet ownership"]
  },
  {
    "feature_name": "EIP-712 Typed Data Signing",
    "description": "Support signing structured typed data per EIP-712 standard, required for many DeFi protocols, NFT marketplaces, and dApp interactions.",
    "inspired_by": "MetaMask, Coinbase Wallet",
    "research_notes": "EIP-712 defines a standard for hashing and signing typed structured data. Required for OpenSea listings, Uniswap permits, and most modern dApps. Implementation requires: 1) Parsing domain separator, 2) Encoding types recursively, 3) Computing structHash, 4) Signing with eth_signTypedData_v4 compatibility.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["WalletConnect integration"],
    "examples": ["Sign permit for gasless token approvals", "List NFT on OpenSea", "Approve Uniswap v3 position"]
  },
  {
    "feature_name": "Personal Message Signing (eth_sign, personal_sign)",
    "description": "Sign arbitrary messages with Ethereum private key for authentication and verification purposes.",
    "inspired_by": "MetaMask, All Web3 wallets",
    "research_notes": "Two common methods: eth_sign (dangerous, signs raw hash) and personal_sign (prefixes message with '\\x19Ethereum Signed Message:\\n'). personal_sign is safer and more common. Implementation is straightforward using existing secp256k1 signing. Must show clear message preview to user.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Sign in to OpenSea with wallet", "Prove ownership for airdrops", "Authenticate to web3 services"]
  },
  {
    "feature_name": "EIP-1559 Transaction Support",
    "description": "Support EIP-1559 (Type 2) transactions with baseFee + maxPriorityFeePerGas for better fee estimation and faster inclusion on Ethereum.",
    "inspired_by": "MetaMask, All modern Ethereum wallets",
    "research_notes": "Fully implemented in rust-app/src/signing/preimage/ethereum.rs with get_eip1559_hash() and compile_eip1559_tx(). Supports maxFeePerGas, maxPriorityFeePerGas, accessList. FFI integration via hawala_sign_evm supports type 2 transactions.",
    "implementation_status": "complete",
    "priority": "high",
    "dependencies": [],
    "examples": ["Set max fee user is willing to pay", "Automatic fee adjustment based on network conditions"]
  },
  {
    "feature_name": "Gas Estimation Improvement",
    "description": "Accurate gas limit estimation for contract interactions, not just simple transfers. Currently hardcoded to 21000 for ETH transfers.",
    "inspired_by": "MetaMask, Trust Wallet",
    "research_notes": "Fully implemented in rust-app/src/fees/estimator.rs with estimate_gas_limit() calling eth_estimateGas RPC, and recommended_gas_limit() providing type-based defaults (21000 ETH, 65000 ERC20, 250000 Swap). 10-20% buffer applied automatically.",
    "implementation_status": "complete",
    "priority": "high",
    "dependencies": [],
    "examples": ["Correctly estimate gas for USDT transfer", "Estimate gas for Uniswap swap"]
  },
  {
    "feature_name": "Custom Token Addition",
    "description": "Allow users to add any ERC-20, BEP-20, or SPL token by entering contract address. Auto-fetch name, symbol, decimals, and logo.",
    "inspired_by": "MetaMask, Trust Wallet, Exodus",
    "research_notes": "Implementation requires: 1) Validate contract address, 2) Call name(), symbol(), decimals() on contract, 3) Fetch balance via balanceOf(), 4) Store in user's token list, 5) Optionally fetch logo from trust-wallet/assets GitHub repo.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Add obscure DeFi token not in default list", "Track airdropped tokens"]
  },
  {
    "feature_name": "Token Approval Management",
    "description": "View and revoke ERC-20 token approvals (allowances) that have been granted to smart contracts.",
    "inspired_by": "Revoke.cash, MetaMask Portfolio",
    "research_notes": "Critical security feature. Users often grant unlimited approvals to DeFi protocols. Implementation: 1) Query approval events for user's address, 2) Display list of contracts with approval amounts, 3) Allow revoking by setting allowance to 0. Can use Etherscan API or index events directly.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["Custom token support"],
    "examples": ["Revoke old Uniswap approval", "See all contracts that can spend your tokens"]
  },
  {
    "feature_name": "NFT Display and Management",
    "description": "Display owned NFTs (ERC-721, ERC-1155) with images, metadata, and ability to send.",
    "inspired_by": "MetaMask, Trust Wallet, Rainbow Wallet",
    "research_notes": "Implementation: 1) Query NFT balance via OpenSea/Alchemy/Moralis API or direct contract calls, 2) Fetch metadata from tokenURI, 3) Display images (handle IPFS URLs), 4) Support sending NFTs. Consider lazy loading for large collections.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Custom token support"],
    "examples": ["View NFT collection", "Send NFT to friend", "Display floor price"]
  },
  {
    "feature_name": "BIP-39 Passphrase (25th Word)",
    "description": "Support optional passphrase in addition to 12/24 word mnemonic for additional security layer creating hidden wallets.",
    "inspired_by": "Ledger, Trezor, Electrum",
    "research_notes": "BIP-39 allows optional passphrase that's combined with mnemonic during seed derivation. Different passphrase = completely different wallet. Provides plausible deniability and extra security. Already mentioned in ROADMAP.md Phase 9.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Create hidden wallet with passphrase", "Decoy wallet with no passphrase, real funds behind passphrase"]
  },
  {
    "feature_name": "iCloud/Keychain Encrypted Backup",
    "description": "Optionally backup encrypted wallet data to iCloud Keychain for seamless recovery across Apple devices.",
    "inspired_by": "Coinbase Wallet, Trust Wallet",
    "research_notes": "Use kSecAttrSynchronizable with Keychain to sync across devices. Must encrypt mnemonic with user password before storing. Show clear warnings about cloud storage risks. Make it opt-in with explicit user consent.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Restore wallet on new Mac automatically", "Sync wallet to iPhone"]
  },
  {
    "feature_name": "Social Recovery",
    "description": "Allow wallet recovery through trusted guardians who each hold a share of the recovery key (Shamir's Secret Sharing).",
    "inspired_by": "Argent, Loopring Wallet",
    "research_notes": "Fully implemented in rust-app/src/security/shamir.rs using the sharks crate. Supports M-of-N share creation (e.g., 2-of-3, 3-of-5), share recovery, and validation with checksums. Swift bridge in HawalaBridge.swift with createShamirShares(), recoverFromShares(), validateShare().",
    "implementation_status": "complete",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Split seed into 3 shares, need 2 to recover", "Send shares to trusted family members"]
  },
  {
    "feature_name": "Transaction Speed/Priority Presets",
    "description": "Clear presets for transaction speed: Slow (economy), Normal, Fast, Instant with estimated time and cost.",
    "inspired_by": "All major wallets",
    "research_notes": "FeeEstimationService.swift exists but UI needs clearer presets. Show: 1) Estimated confirmation time, 2) Fee in crypto and fiat, 3) Visual indicator of network congestion. Allow custom fee for advanced users.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Select 'Fast' for 10-minute confirmation", "See that 'Slow' saves $2 but takes 2 hours"]
  },
  {
    "feature_name": "Transaction Batching",
    "description": "Send to multiple recipients in a single transaction to save on fees (where supported).",
    "inspired_by": "Electrum, BlueWallet",
    "research_notes": "Bitcoin: Single transaction with multiple outputs. Ethereum: Requires batch contract or multiple sequential txs. Implementation for BTC straightforward - modify BitcoinTransactionBuilder to accept multiple Output structs.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Pay multiple employees in one transaction", "Distribute tokens to multiple addresses"]
  },
  {
    "feature_name": "Coin Control (UTXO Selection)",
    "description": "Allow advanced users to manually select which UTXOs to spend in Bitcoin transactions for privacy and fee optimization.",
    "inspired_by": "Electrum, Sparrow, BlueWallet Pro",
    "research_notes": "Privacy feature allowing users to avoid linking UTXOs. Implementation: 1) Display available UTXOs with amounts and ages, 2) Let user select which to include, 3) Calculate fee based on selection, 4) Warn about change output implications.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["UTXO tracking"],
    "examples": ["Select only coinjoined UTXOs for spending", "Avoid spending dust UTXOs with high fee ratio"]
  },
  {
    "feature_name": "Address Reuse Warning",
    "description": "Warn users when they're about to reuse a Bitcoin address that has already received funds, as this reduces privacy.",
    "inspired_by": "Wasabi Wallet, Sparrow",
    "research_notes": "BIP-32 HD wallets should generate new addresses for each receive. Track used addresses and warn if user shares a previously-used address. Can implement as soft warning, not blocking.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["'This address was used before. Generate new address for better privacy?'"]
  },
  {
    "feature_name": "Full Transaction Details View",
    "description": "Comprehensive transaction details showing inputs, outputs, fees, confirmations, block height, raw hex, and ability to decode.",
    "inspired_by": "Electrum, BlueWallet",
    "research_notes": "Current TransactionDetailView.swift exists but may not show all details. Should include: txid, block hash, confirmations, inputs/outputs breakdown, fee rate, size/vsize, RBF status, links to block explorer.",
    "implementation_status": "unknown",
    "priority": "medium",
    "dependencies": [],
    "examples": ["View all inputs and outputs", "Copy raw transaction hex", "See fee paid per vbyte"]
  },
  {
    "feature_name": "Push Notification for Transaction Confirmation",
    "description": "Send push notification when a pending transaction confirms on-chain.",
    "inspired_by": "Trust Wallet, Coinbase Wallet, Exodus",
    "research_notes": "NotificationManager.swift exists with transactionConfirmed type. Requires: 1) Background task to poll transaction status, 2) Or WebSocket subscription to mempool/block events, 3) Trigger local notification on confirmation. May need APNs for true push when app is closed.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["Background task scheduling"],
    "examples": ["Notification: 'Your 0.5 BTC transfer has confirmed!'"]
  },
  {
    "feature_name": "Address Book with ENS/Unstoppable Domains",
    "description": "Resolve human-readable names like vitalik.eth to addresses. ContactsManager exists but lacks name resolution.",
    "inspired_by": "MetaMask, Trust Wallet, Rainbow",
    "research_notes": "ENS resolution via ENS registry contract or public resolvers. Unstoppable Domains has API. Implementation: 1) Detect .eth, .crypto, .nft endings, 2) Resolve via appropriate service, 3) Show resolved address with name, 4) Cache resolutions.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Send to vitalik.eth instead of 0x...", "Save contact as 'Alice' with alice.crypto address"]
  },
  {
    "feature_name": "QR Code Payment Requests (BIP-21)",
    "description": "Generate QR codes with embedded amount and label following BIP-21 URI scheme.",
    "inspired_by": "All Bitcoin wallets",
    "research_notes": "BIP-21 format: bitcoin:address?amount=1.5&label=Payment. Extend to other chains. Current receive UI may only show address. Should allow: 1) Set requested amount, 2) Add label/message, 3) Generate QR with full URI.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Generate QR requesting exactly 0.01 BTC for coffee", "Merchant payment request with memo"]
  },
  {
    "feature_name": "Fiat On-Ramp Integration",
    "description": "Buy crypto directly in-app via integrated fiat on-ramp providers (MoonPay, Transak, Ramp, Banxa).",
    "inspired_by": "Trust Wallet, MetaMask, Exodus",
    "research_notes": "Integrate via WebView or deep link to partner's flow. Revenue share opportunity. Requires: 1) Partner API integration, 2) KYC flow handling, 3) Wallet address passing, 4) Transaction status tracking. Regulatory considerations vary by jurisdiction.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Buy $100 of BTC with credit card", "Apple Pay to crypto"]
  },
  {
    "feature_name": "Fiat Off-Ramp Integration",
    "description": "Sell crypto directly to bank account via integrated off-ramp providers.",
    "inspired_by": "Coinbase Wallet, Trust Wallet",
    "research_notes": "Similar to on-ramp but reverse flow. Fewer providers support this. May require more extensive KYC. Consider for future version after on-ramp is established.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Fiat on-ramp integration"],
    "examples": ["Sell ETH to USD, receive in bank account"]
  },
  {
    "feature_name": "In-App Token Swap (DEX Aggregator)",
    "description": "Swap tokens directly in-app by aggregating quotes from multiple DEXs (Uniswap, SushiSwap, 1inch, etc.).",
    "inspired_by": "MetaMask Swaps, Trust Wallet, Rainbow",
    "research_notes": "Use aggregator API like 1inch, 0x, or Paraswap. Implementation: 1) Get quotes from aggregator, 2) Show best route, 3) Build and sign swap transaction, 4) Handle approvals if needed. Revenue via affiliate fees.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["Token approval management", "Gas estimation"],
    "examples": ["Swap ETH to USDC at best rate", "Convert MATIC to ETH"]
  },
  {
    "feature_name": "Cross-Chain Bridge Integration",
    "description": "Bridge assets between chains (e.g., ETH mainnet to Polygon, BSC to Ethereum) via integrated bridge protocols.",
    "inspired_by": "Trust Wallet, MetaMask Portfolio",
    "research_notes": "Complex feature with security risks. Consider integrating established bridges like Hop, Across, Stargate via their APIs. Must clearly show fees, time estimates, and risks.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Multi-chain support", "In-app swap"],
    "examples": ["Bridge USDC from Ethereum to Polygon", "Move ETH from Arbitrum to mainnet"]
  },
  {
    "feature_name": "Staking Rewards Claiming",
    "description": "Claim staking rewards directly from wallet. StakingManager.swift exists but needs claiming functionality.",
    "inspired_by": "Exodus, Trust Wallet, Ledger Live",
    "research_notes": "StakingManager has validator fetching but createSolanaStakeTransaction throws notImplemented. Need: 1) Display claimable rewards, 2) Build claim transaction, 3) Sign and broadcast. Chain-specific implementations needed.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["Staking position tracking"],
    "examples": ["Claim 0.5 SOL staking rewards", "Compound rewards back to stake"]
  },
  {
    "feature_name": "Hardware Wallet Full Integration",
    "description": "Complete Ledger and Trezor integration for transaction signing. HardwareWalletManager.swift has structure but signing is incomplete.",
    "inspired_by": "Ledger Live, Trezor Suite, Sparrow",
    "research_notes": "Current implementation has HID setup and APDU command structure. Missing: 1) Full transaction signing flow, 2) App switching prompts, 3) Error handling for user rejection, 4) Multi-account derivation. Consider using official Ledger Swift SDK.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Sign BTC transaction on Ledger Nano", "Derive ETH address from Trezor"]
  },
  {
    "feature_name": "Multisig Transaction Signing",
    "description": "Complete PSBT signing flow for multisig wallets. MultisigManager.swift has structure but transaction signing incomplete.",
    "inspired_by": "BlueWallet, Sparrow, Nunchuk",
    "research_notes": "MultisigManager has wallet creation and public key collection. Missing: 1) PSBT creation, 2) Partial signature collection, 3) PSBT file export/import, 4) Signature aggregation, 5) Broadcast when threshold met.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["PSBT support"],
    "examples": ["Create 2-of-3 multisig", "Sign PSBT and share with co-signer"]
  },
  {
    "feature_name": "PSBT Support (BIP-174)",
    "description": "Full support for Partially Signed Bitcoin Transactions for hardware wallets, multisig, and air-gapped signing.",
    "inspired_by": "Sparrow, BlueWallet, Nunchuk",
    "research_notes": "PSBT is standard format for unsigned/partially-signed transactions. Implementation: 1) PSBT parsing, 2) PSBT creation, 3) Signature insertion, 4) Finalization, 5) File export/import. Essential for hardware and multisig workflows.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Export unsigned transaction as PSBT", "Import PSBT signed by hardware wallet"]
  },
  {
    "feature_name": "Localization (i18n)",
    "description": "Multi-language support for global users. All user-facing strings should be localizable.",
    "inspired_by": "All major wallets",
    "research_notes": "SwiftUI supports localization via String Catalogs or .strings files. Priority languages: Spanish, Chinese (Simplified/Traditional), Japanese, Korean, German, French, Portuguese, Russian, Arabic.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Spanish UI for Latin American users", "Japanese for Japan market"]
  },
  {
    "feature_name": "VoiceOver Accessibility",
    "description": "Full VoiceOver support for visually impaired users. Ensure all UI elements have proper accessibility labels.",
    "inspired_by": "Apple Human Interface Guidelines",
    "research_notes": "SwiftUI has built-in accessibility modifiers. Audit all views for: 1) accessibilityLabel, 2) accessibilityHint, 3) accessibilityValue, 4) Proper focus order, 5) Custom actions where needed.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["VoiceOver reads 'Bitcoin balance: 0.5 BTC, $50,000 USD'"]
  },
  {
    "feature_name": "Keyboard Navigation",
    "description": "Full keyboard navigation support for power users and accessibility. Tab through all interactive elements.",
    "inspired_by": "macOS accessibility standards",
    "research_notes": "Some keyboard shortcuts exist (Cmd+1-4, Cmd+R). Need comprehensive keyboard navigation: 1) Tab order through all elements, 2) Arrow key navigation in lists, 3) Enter to activate, 4) Escape to dismiss. Use .focusable() and @FocusState.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Tab through wallet cards", "Navigate transaction list with arrows"]
  },
  {
    "feature_name": "Biometric Confirmation for Transactions",
    "description": "Require Touch ID/Face ID confirmation before signing any transaction, not just app unlock.",
    "inspired_by": "Coinbase Wallet, Trust Wallet",
    "research_notes": "AutoLockManager handles app-level biometrics. Add transaction-level: 1) Before signing, prompt for biometric, 2) Fall back to passcode, 3) Make configurable in settings. Use LocalAuthentication framework.",
    "implementation_status": "missing",
    "priority": "high",
    "dependencies": [],
    "examples": ["Touch ID required before sending 1 BTC", "Face ID to confirm swap"]
  },
  {
    "feature_name": "Spending Limits",
    "description": "Set daily/weekly/monthly spending limits with alerts or hard blocks when exceeded.",
    "inspired_by": "Traditional banking apps, some institutional wallets",
    "research_notes": "User-configurable limits per asset or total portfolio. Implementation: 1) Track sent amounts over time periods, 2) Warn when approaching limit, 3) Optionally hard-block transactions exceeding limit, 4) Require additional auth to override.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Transaction history tracking"],
    "examples": ["Limit daily BTC sends to 0.1 BTC", "Alert when weekly spending exceeds $5000"]
  },
  {
    "feature_name": "Address Whitelisting",
    "description": "Maintain whitelist of approved addresses. Warn or block sends to non-whitelisted addresses.",
    "inspired_by": "Institutional wallets, exchange withdrawal whitelists",
    "research_notes": "Security feature to prevent sends to unknown addresses. Implementation: 1) Whitelist management UI, 2) Check recipient against whitelist before send, 3) Require delay for new whitelist additions (24-48 hours).",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Contact management"],
    "examples": ["Only allow sends to saved contacts", "24-hour delay before new address can receive"]
  },
  {
    "feature_name": "Transaction Simulation",
    "description": "Simulate transaction execution to preview token balance changes and detect potential scams before signing.",
    "inspired_by": "Blowfish, Pocket Universe, MetaMask Snaps",
    "research_notes": "Use services like Blowfish, Tenderly, or custom simulation. For Ethereum: 1) Call eth_call with transaction data, 2) Decode balance changes, 3) Flag suspicious patterns (draining approvals, unknown contracts). Critical for DeFi safety.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": ["WalletConnect integration"],
    "examples": ["Preview: 'This transaction will transfer all your NFTs'", "Warning: 'Unlimited token approval detected'"]
  },
  {
    "feature_name": "Scam/Phishing Detection",
    "description": "Warn users when interacting with known scam addresses or phishing contracts.",
    "inspired_by": "MetaMask, Trust Wallet",
    "research_notes": "Integrate with scam databases like ChainAbuse, Etherscan labels, or custom blacklist. Check: 1) Recipient addresses against blacklist, 2) Contract addresses before approval, 3) Domain names in WalletConnect requests.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Warning: 'This address has been reported as a scam'", "Block interaction with known phishing contract"]
  },
  {
    "feature_name": "Security Audit Trail",
    "description": "Log all security-relevant events: logins, transactions, settings changes with timestamps.",
    "inspired_by": "Enterprise wallets, banking apps",
    "research_notes": "Store locally encrypted log of: 1) App unlock events, 2) Transaction signatures, 3) Settings modifications, 4) Export operations. Allow export for user review. Helps identify compromised devices.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["View: 'Transaction signed at 2:30 PM from IP xxx'", "Alert: 'Multiple failed unlock attempts'"]
  },
  {
    "feature_name": "Network Fee Spike Alerts",
    "description": "Alert users when network fees are unusually high and suggest waiting.",
    "inspired_by": "Gas trackers, MetaMask",
    "research_notes": "FeeEstimationService already fetches fees. Add: 1) Historical fee comparison, 2) Alert when fees > 2x average, 3) Suggest optimal times based on historical patterns. Help users save on fees.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Fee estimation service"],
    "examples": ["'Gas prices are 3x normal. Consider waiting 2 hours.'", "Historical fee chart showing best times"]
  },
  {
    "feature_name": "Portfolio Value Change Notifications",
    "description": "Notify users of significant portfolio value changes (daily digest or threshold alerts).",
    "inspired_by": "Coinbase, Delta, Blockfolio",
    "research_notes": "NotificationManager has priceAlert type. Extend for portfolio-level: 1) Track portfolio value over time, 2) Calculate daily/hourly change, 3) Trigger notification on configurable threshold (e.g., ±10%).",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Portfolio tracking"],
    "examples": ["Morning notification: 'Portfolio up 5% to $50,000'", "Alert: 'Portfolio dropped 10% in last hour'"]
  },
  {
    "feature_name": "Tax Report Generation",
    "description": "Generate tax reports with capital gains/losses calculation for supported jurisdictions.",
    "inspired_by": "Koinly, CoinTracker, Coinbase Tax Center",
    "research_notes": "ExportService.swift exists for CSV. Extend for tax: 1) Calculate cost basis (FIFO, LIFO, HIFO), 2) Identify taxable events, 3) Generate Form 8949 compatible report, 4) Support multiple tax jurisdictions. Consider integration with Koinly/CoinTracker API.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["Transaction history", "Price history"],
    "examples": ["Generate 2024 US tax report", "Calculate total capital gains"]
  },
  {
    "feature_name": "Testnet Toggle",
    "description": "Easy toggle between mainnet and testnet for all supported chains with clear visual indicator.",
    "inspired_by": "MetaMask, Developer tools",
    "research_notes": "App supports bitcoin-testnet and ethereum-sepolia but UI to switch may be unclear. Add: 1) Global testnet mode toggle, 2) Prominent visual indicator (colored banner), 3) Separate key derivation for testnet, 4) Auto-switch all RPC endpoints.",
    "implementation_status": "unknown",
    "priority": "low",
    "dependencies": [],
    "examples": ["Developer testing transactions without real funds", "Learning to use wallet safely"]
  },
  {
    "feature_name": "Custom RPC Endpoints",
    "description": "Allow users to configure custom RPC endpoints for each chain instead of defaults.",
    "inspired_by": "MetaMask, Rainbow",
    "research_notes": "Power user feature for privacy (own node) or reliability (paid RPCs). Implementation: 1) Settings UI for RPC URLs per chain, 2) Connection testing, 3) Fallback to default if custom fails. Store in UserDefaults.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Connect to own Ethereum node", "Use Alchemy/Infura paid endpoint"]
  },
  {
    "feature_name": "Tor Network Support",
    "description": "Route blockchain queries through Tor for enhanced privacy.",
    "inspired_by": "Wasabi Wallet, Sparrow",
    "research_notes": "Embedding Tor in macOS app is complex and may violate App Store guidelines. Consider for side-loaded version only.",
    "implementation_status": "not feasible",
    "priority": "low",
    "dependencies": [],
    "examples": ["All API calls routed through Tor"]
  },
  {
    "feature_name": "App Lock with Duress PIN",
    "description": "Secondary PIN that opens a decoy wallet with minimal funds, for coercion scenarios.",
    "inspired_by": "Samourai Wallet",
    "research_notes": "Plausible deniability feature. Implementation: 1) Configure duress PIN, 2) Duress PIN derives different wallet, 3) Attacker sees convincing but minimal wallet. Complex UX to explain clearly.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["BIP-39 passphrase"],
    "examples": ["Under duress, enter alternate PIN showing $50 wallet instead of $50,000"]
  },
  {
    "feature_name": "Widget Support (macOS/iOS)",
    "description": "Home screen widgets showing portfolio value, price tickers, or quick actions.",
    "inspired_by": "Coinbase, Trust Wallet, iOS apps",
    "research_notes": "Use WidgetKit for macOS Sonoma+ widgets. Show: 1) Total portfolio value, 2) Individual asset prices, 3) 24h change. Must share data via App Groups. Be mindful of privacy on lock screen.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["Widget showing BTC price on desktop", "Portfolio total in notification center"]
  },
  {
    "feature_name": "Siri/Shortcuts Integration",
    "description": "Support Siri Shortcuts for quick actions like 'Check Bitcoin price' or 'Show my portfolio'.",
    "inspired_by": "iOS apps with Shortcuts support",
    "research_notes": "Use App Intents framework. Safe intents: price checks, balance viewing. Avoid transaction intents via voice for security. Define custom intents and donate to Shortcuts app.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["'Hey Siri, what's my crypto portfolio worth?'", "Shortcut to copy receive address"]
  },
  {
    "feature_name": "Deep Link Support",
    "description": "Handle deep links for payment requests, WalletConnect, and inter-app communication.",
    "inspired_by": "All mobile wallets",
    "research_notes": "Register URL schemes (hawala://) and universal links. Handle: 1) Payment requests (bitcoin:, ethereum:), 2) WalletConnect URIs (wc:), 3) App-specific actions. Configure in Info.plist.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Click bitcoin: link opens app with pre-filled send", "WalletConnect QR opens connection flow"]
  },
  {
    "feature_name": "App Store Release Preparation",
    "description": "Complete all requirements for macOS App Store submission: sandboxing, notarization, screenshots, description.",
    "inspired_by": "Apple App Store guidelines",
    "research_notes": "Requirements: 1) App Sandbox entitlements, 2) Notarization, 3) Privacy manifest, 4) App Store Connect metadata, 5) Screenshots for all supported sizes, 6) Review compliance (crypto apps have additional scrutiny).",
    "implementation_status": "missing",
    "priority": "high",
    "dependencies": [],
    "examples": ["Submit to App Store", "Pass Apple review"]
  },
  {
    "feature_name": "Auto-Update Mechanism",
    "description": "Automatic update checking and installation for non-App Store distribution.",
    "inspired_by": "Sparkle framework, many macOS apps",
    "research_notes": "Use Sparkle framework for auto-updates. Requires: 1) Sparkle integration, 2) Hosted appcast.xml, 3) Code signing for updates, 4) Delta updates for efficiency. Only needed for direct distribution.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["Notification: 'Update available, click to install'"]
  },
  {
    "feature_name": "Crash Reporting",
    "description": "Opt-in crash reporting to identify and fix issues in production.",
    "inspired_by": "All production apps",
    "research_notes": "Options: Sentry, Firebase Crashlytics, or Apple's built-in. Must be opt-in with clear privacy policy. Strip sensitive data from crash logs. Essential for production quality.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["User opts in to help improve app", "Developer sees crash statistics"]
  },
  {
    "feature_name": "Analytics (Privacy-Respecting)",
    "description": "Optional, privacy-respecting analytics to understand feature usage.",
    "inspired_by": "Plausible, Fathom, TelemetryDeck",
    "research_notes": "Use privacy-focused analytics: no PII, aggregate only. Track: feature usage, error rates, performance metrics. Must be opt-in. Consider TelemetryDeck for Swift-native solution.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": [],
    "examples": ["See % of users who use staking feature", "Identify slow screens"]
  },
  {
    "feature_name": "In-App Help & FAQ",
    "description": "Contextual help tooltips and searchable FAQ within the app.",
    "inspired_by": "Coinbase, most consumer apps",
    "research_notes": "OnboardingView.swift exists for first-time flow. Add: 1) ? icon on complex screens, 2) Popover explanations, 3) Searchable help center, 4) Link to documentation. Reduce support requests.",
    "implementation_status": "missing",
    "priority": "medium",
    "dependencies": [],
    "examples": ["'What is gas?' tooltip next to gas field", "Search 'stuck transaction' in help"]
  },
  {
    "feature_name": "Interactive Tutorials",
    "description": "Step-by-step guided tutorials for complex features like staking, multisig, hardware wallet setup.",
    "inspired_by": "Ledger Live tutorials",
    "research_notes": "Beyond OnboardingView, create feature-specific tutorials with highlighted UI elements, progress tracking, and practice mode where applicable.",
    "implementation_status": "missing",
    "priority": "low",
    "dependencies": ["In-app help"],
    "examples": ["Tutorial: 'Set up your first hardware wallet'", "Guide: 'Understanding Bitcoin fees'"]
  },
  {
    "feature_name": "Terms of Service & Privacy Policy",
    "description": "Clear, accessible terms of service and privacy policy within the app.",
    "inspired_by": "All consumer apps",
    "research_notes": "Legal requirement for App Store and good practice. Include: 1) First-run acceptance, 2) Accessible from settings, 3) Clear explanation of data handling, 4) No hidden telemetry.",
    "implementation_status": "missing",
    "priority": "high",
    "dependencies": [],
    "examples": ["Accept ToS on first launch", "View privacy policy from settings"]
  }
]
```

---

## Why Solana and XRP Cannot Support Transaction Cancellation

### Solana: ~400ms Finality

**How Solana Works:**
- Solana uses **Proof of History (PoH)** combined with **Tower BFT consensus**
- Transactions are processed in ~400 milliseconds (0.4 seconds)
- Once a transaction enters a block, it's **immediately final**
- There's no mempool in the traditional sense - transactions flow directly to the leader

**Why Cancellation is Impossible:**
1. **No pending state** - Transactions don't sit waiting; they're processed instantly
2. **No replacement mechanism** - Unlike Bitcoin's RBF or Ethereum's nonce, Solana has no way to "replace" a transaction
3. **Time window too small** - Even if possible, 400ms is faster than human reaction time
4. **Finality is absolute** - Once confirmed, there's no rollback possible

**The only "cancellation":** Don't sign in the first place. Once signed and broadcast, it's done.

---

### XRP (Ripple): 3-5 Second Consensus

**How XRP Works:**
- XRP uses **Ripple Protocol Consensus Algorithm (RPCA)**
- Trusted validators reach consensus every 3-5 seconds
- Transactions are validated by 80%+ of Unique Node List (UNL) validators
- Once consensus is reached, transactions are **irreversibly final**

**Why Cancellation is Impractical:**
1. **Extremely narrow window** - Only 3-5 seconds between broadcast and finality
2. **No replacement protocol** - XRP has no RBF-like mechanism
3. **Sequence numbers are not replaceable** - While XRP has sequence numbers, you cannot replace a pending transaction
4. **Consensus is deterministic** - Once validators see the transaction, it will be included

**Theoretical possibility:** If you could broadcast a conflicting transaction within 1-2 seconds to a different set of validators... but this is technically impractical and unreliable.

---

### Comparison Summary

| Aspect | Bitcoin | Ethereum | Solana | XRP |
|--------|---------|----------|--------|-----|
| **Confirmation Time** | 10-60 min | 12-15 sec | ~400ms | 3-5 sec |
| **Mempool** | Yes | Yes | No (direct) | Brief |
| **Replacement** | RBF (BIP-125) | Nonce | None | None |
| **Cancel Window** | Minutes-hours | Seconds | None | None |
| **Cancellation** | ✅ Feasible | ✅ Feasible | ❌ Impossible | ❌ Impractical |

---

## Existing Features to Fix

*(This section will be populated as we identify broken features)*

| Feature | File | Issue | Status |
|---------|------|-------|--------|
| Bitcoin RBF Speed-Up | `SpeedUpTransactionSheet.swift` | Throws "featureInProgress" | To Fix |
| Staking Transactions | `StakingManager.swift` | Throws "notImplemented" | To Fix |
| Hardware Wallet Signing | `HardwareWalletManager.swift` | Incomplete flow | To Fix |
| Multisig PSBT | `MultisigManager.swift` | Missing transaction creation | To Fix |

---

## Next Steps

1. **Fix existing broken features** (prioritized list above)
2. **Implement high-priority missing features**
3. **Security audit before release**
4. **App Store preparation**

---

*Last Updated: November 30, 2025*
