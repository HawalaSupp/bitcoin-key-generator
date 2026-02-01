import Foundation
import SwiftUI

// MARK: - AllKeys Chain Info Extension
// This extension provides the chainInfos computed property that converts
// all wallet keys into displayable ChainInfo objects for the UI

extension AllKeys {
    var chainInfos: [ChainInfo] {
        // Build Bitcoin key details including Taproot if available
        var bitcoinDetails: [KeyDetail] = [
            KeyDetail(label: "Private Key (hex)", value: bitcoin.privateHex),
            KeyDetail(label: "Private Key (WIF)", value: bitcoin.privateWif),
            KeyDetail(label: "Public Key (compressed hex)", value: bitcoin.publicCompressedHex),
            KeyDetail(label: "Address (SegWit)", value: bitcoin.address)
        ]
        if let taprootAddress = bitcoin.taprootAddress {
            bitcoinDetails.append(KeyDetail(label: "Address (Taproot)", value: taprootAddress))
        }
        if let xOnly = bitcoin.xOnlyPubkey {
            bitcoinDetails.append(KeyDetail(label: "X-Only Pubkey (Taproot)", value: xOnly))
        }
        
        var bitcoinTestnetDetails: [KeyDetail] = [
            KeyDetail(label: "Private Key (hex)", value: bitcoinTestnet.privateHex),
            KeyDetail(label: "Private Key (WIF)", value: bitcoinTestnet.privateWif),
            KeyDetail(label: "Public Key (compressed hex)", value: bitcoinTestnet.publicCompressedHex),
            KeyDetail(label: "Testnet Address (SegWit)", value: bitcoinTestnet.address)
        ]
        if let taprootAddress = bitcoinTestnet.taprootAddress {
            bitcoinTestnetDetails.append(KeyDetail(label: "Testnet Address (Taproot)", value: taprootAddress))
        }
        if let xOnly = bitcoinTestnet.xOnlyPubkey {
            bitcoinTestnetDetails.append(KeyDetail(label: "X-Only Pubkey (Taproot)", value: xOnly))
        }
        
        var cards: [ChainInfo] = [
            ChainInfo(
                id: "bitcoin",
                title: "Bitcoin",
                subtitle: "SegWit P2WPKH + Taproot P2TR",
                iconName: "bitcoinsign.circle.fill",
                accentColor: Color.orange,
                details: bitcoinDetails,
                receiveAddress: bitcoin.address
            ),
            ChainInfo(
                id: "bitcoin-testnet",
                title: "Bitcoin Testnet",
                subtitle: "SegWit + Taproot (Testnet)",
                iconName: "bitcoinsign.circle",
                accentColor: Color.orange.opacity(0.7),
                details: bitcoinTestnetDetails,
                receiveAddress: bitcoinTestnet.address
            ),
            ChainInfo(
                id: "litecoin",
                title: "Litecoin",
                subtitle: "Bech32 P2WPKH",
                iconName: "l.circle.fill",
                accentColor: Color.green,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: litecoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: litecoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: litecoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: litecoin.address)
                ],
                receiveAddress: litecoin.address
            ),
            ChainInfo(
                id: "monero",
                title: "Monero",
                subtitle: "Primary Account",
                iconName: "m.circle.fill",
                accentColor: Color.purple,
                details: [
                    KeyDetail(label: "Private Spend Key", value: monero.privateSpendHex),
                    KeyDetail(label: "Private View Key", value: monero.privateViewHex),
                    KeyDetail(label: "Public Spend Key", value: monero.publicSpendHex),
                    KeyDetail(label: "Public View Key", value: monero.publicViewHex),
                    KeyDetail(label: "Primary Address", value: monero.address)
                ],
                receiveAddress: monero.address
            ),
            ChainInfo(
                id: "solana",
                title: "Solana",
                subtitle: "Ed25519 Keypair",
                iconName: "s.circle.fill",
                accentColor: Color.blue,
                details: [
                    KeyDetail(label: "Private Seed (hex)", value: solana.privateSeedHex),
                    KeyDetail(label: "Private Key (base58)", value: solana.privateKeyBase58),
                    KeyDetail(label: "Public Key / Address", value: solana.publicKeyBase58)
                ],
                receiveAddress: solana.publicKeyBase58
            ),
            ChainInfo(
                id: "xrp",
                title: "XRP Ledger",
                subtitle: "Classic Address",
                iconName: "xmark.seal.fill",
                accentColor: Color.indigo,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: xrp.privateHex),
                    KeyDetail(label: "Public Key (compressed hex)", value: xrp.publicCompressedHex),
                    KeyDetail(label: "Classic Address", value: xrp.classicAddress)
                ],
                receiveAddress: xrp.classicAddress
            )
        ]

        // Ethereum
        let ethereumDetails = [
            KeyDetail(label: "Private Key (hex)", value: ethereum.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: ethereum.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: ethereum.address)
        ]

        cards.append(
            ChainInfo(
                id: "ethereum",
                title: "Ethereum",
                subtitle: "EIP-55 Address",
                iconName: "e.circle.fill",
                accentColor: Color.pink,
                details: ethereumDetails,
                receiveAddress: ethereum.address
            )
        )

        cards.append(
            ChainInfo(
                id: "ethereum-sepolia",
                title: "Ethereum Sepolia",
                subtitle: "Testnet Address",
                iconName: "e.circle",
                accentColor: Color.pink.opacity(0.7),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: ethereumSepolia.privateHex),
                    KeyDetail(label: "Public Key (uncompressed hex)", value: ethereumSepolia.publicUncompressedHex),
                    KeyDetail(label: "Checksummed Address", value: ethereumSepolia.address)
                ],
                receiveAddress: ethereumSepolia.address
            )
        )

        // BNB Smart Chain
        let bnbDetails = [
            KeyDetail(label: "Private Key (hex)", value: bnb.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: bnb.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: bnb.address)
        ]

        cards.append(
            ChainInfo(
                id: "bnb",
                title: "BNB Smart Chain",
                subtitle: "EVM Compatible",
                iconName: "b.circle.fill",
                accentColor: Color(red: 0.95, green: 0.77, blue: 0.23),
                details: bnbDetails,
                receiveAddress: bnb.address
            )
        )

        // ERC-20 Tokens
        let tokenEntries: [(idPrefix: String, title: String, subtitle: String, accent: Color, contract: String)] = [
            ("usdt", "Tether USD (USDT)", "ERC-20 Token", Color(red: 0.0, green: 0.64, blue: 0.54), "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
            ("usdc", "USD Coin (USDC)", "ERC-20 Token", Color.blue, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            ("dai", "Dai (DAI)", "ERC-20 Token", Color.yellow, "0x6B175474E89094C44Da98b954EedeAC495271d0F")
        ]

        for entry in tokenEntries {
            let tokenDetails: [KeyDetail] = [
                KeyDetail(label: "Ethereum Wallet Address", value: ethereum.address),
                KeyDetail(label: "Token Contract", value: entry.contract)
            ]

            cards.append(
                ChainInfo(
                    id: "\(entry.idPrefix)-erc20",
                    title: entry.title,
                    subtitle: entry.subtitle,
                    iconName: "dollarsign.circle.fill",
                    accentColor: entry.accent,
                    details: tokenDetails,
                    receiveAddress: ethereum.address
                )
            )
        }

        // MARK: - New Chains (wallet-core integration)
        cards.append(contentsOf: walletCoreChains)
        
        // MARK: - EVM Compatible Chains
        cards.append(contentsOf: evmCompatibleChains)
        
        // MARK: - Bitcoin Forks
        cards.append(contentsOf: bitcoinForkChains)
        
        // MARK: - Cosmos Ecosystem
        cards.append(contentsOf: cosmosEcosystemChains)
        
        // MARK: - Other Major Chains
        cards.append(contentsOf: otherMajorChains)
        
        // MARK: - Extended Chain Support (16 new chains)
        cards.append(contentsOf: extendedChains)

        return cards
    }
    
    // MARK: - Wallet Core Chains
    
    private var walletCoreChains: [ChainInfo] {
        [
            ChainInfo(
                id: "ton",
                title: "TON",
                subtitle: "The Open Network",
                iconName: "diamond.fill",
                accentColor: Color(red: 0.0, green: 0.58, blue: 0.87),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: ton.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: ton.publicHex),
                    KeyDetail(label: "Address", value: ton.address)
                ],
                receiveAddress: ton.address
            ),
            ChainInfo(
                id: "aptos",
                title: "Aptos",
                subtitle: "Layer 1 Blockchain",
                iconName: "a.circle.fill",
                accentColor: Color(red: 0.0, green: 0.82, blue: 0.69),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: aptos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: aptos.publicHex),
                    KeyDetail(label: "Address", value: aptos.address)
                ],
                receiveAddress: aptos.address
            ),
            ChainInfo(
                id: "sui",
                title: "Sui",
                subtitle: "Layer 1 Blockchain",
                iconName: "drop.fill",
                accentColor: Color(red: 0.29, green: 0.56, blue: 0.89),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: sui.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: sui.publicHex),
                    KeyDetail(label: "Address", value: sui.address)
                ],
                receiveAddress: sui.address
            ),
            ChainInfo(
                id: "polkadot",
                title: "Polkadot",
                subtitle: "DOT Network",
                iconName: "circle.hexagongrid.fill",
                accentColor: Color(red: 0.9, green: 0.05, blue: 0.45),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: polkadot.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: polkadot.publicHex),
                    KeyDetail(label: "Polkadot Address", value: polkadot.address),
                    KeyDetail(label: "Kusama Address", value: polkadot.kusamaAddress)
                ],
                receiveAddress: polkadot.address
            ),
            ChainInfo(
                id: "kusama",
                title: "Kusama",
                subtitle: "KSM Network",
                iconName: "bird.fill",
                accentColor: Color(red: 0.13, green: 0.13, blue: 0.13),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: polkadot.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: polkadot.publicHex),
                    KeyDetail(label: "Kusama Address", value: polkadot.kusamaAddress)
                ],
                receiveAddress: polkadot.kusamaAddress
            )
        ]
    }
    
    // MARK: - EVM Compatible Chains
    
    private var evmCompatibleChains: [ChainInfo] {
        [
            makeEVMChain(id: "polygon", title: "Polygon", subtitle: "POL Network (Chain ID: 137)", iconName: "hexagon.fill", color: Color(red: 0.51, green: 0.27, blue: 0.83), chainId: "137"),
            makeEVMChain(id: "arbitrum", title: "Arbitrum One", subtitle: "L2 Rollup (Chain ID: 42161)", iconName: "a.circle.fill", color: Color(red: 0.16, green: 0.42, blue: 0.77), chainId: "42161"),
            makeEVMChain(id: "optimism", title: "OP Mainnet", subtitle: "L2 Rollup (Chain ID: 10)", iconName: "o.circle.fill", color: Color(red: 1.0, green: 0.04, blue: 0.04), chainId: "10"),
            makeEVMChain(id: "base", title: "Base", subtitle: "Coinbase L2 (Chain ID: 8453)", iconName: "b.circle.fill", color: Color(red: 0.0, green: 0.32, blue: 1.0), chainId: "8453"),
            makeEVMChain(id: "avalanche", title: "Avalanche C-Chain", subtitle: "AVAX (Chain ID: 43114)", iconName: "a.circle.fill", color: Color(red: 0.89, green: 0.23, blue: 0.26), chainId: "43114"),
            makeEVMChain(id: "fantom", title: "Fantom", subtitle: "FTM Opera (Chain ID: 250)", iconName: "f.circle.fill", color: Color(red: 0.07, green: 0.46, blue: 0.91), chainId: "250"),
            makeEVMChain(id: "cronos", title: "Cronos", subtitle: "CRO Chain (Chain ID: 25)", iconName: "c.circle.fill", color: Color(red: 0.0, green: 0.18, blue: 0.31), chainId: "25"),
            makeEVMChain(id: "zksync", title: "zkSync Era", subtitle: "ZK Rollup (Chain ID: 324)", iconName: "z.circle.fill", color: Color(red: 0.28, green: 0.35, blue: 0.97), chainId: "324"),
            makeEVMChain(id: "linea", title: "Linea", subtitle: "ConsenSys L2 (Chain ID: 59144)", iconName: "l.circle.fill", color: Color(red: 0.38, green: 0.38, blue: 0.38), chainId: "59144"),
            makeEVMChain(id: "scroll", title: "Scroll", subtitle: "ZK Rollup (Chain ID: 534352)", iconName: "scroll.fill", color: Color(red: 1.0, green: 0.84, blue: 0.5), chainId: "534352"),
            makeEVMChain(id: "blast", title: "Blast", subtitle: "Native Yield L2 (Chain ID: 81457)", iconName: "bolt.circle.fill", color: Color(red: 0.99, green: 0.98, blue: 0.0), chainId: "81457"),
            makeEVMChain(id: "mantle", title: "Mantle", subtitle: "MNT Network (Chain ID: 5000)", iconName: "m.circle.fill", color: Color(red: 0.0, green: 0.0, blue: 0.0), chainId: "5000"),
            makeEVMChain(id: "moonbeam", title: "Moonbeam", subtitle: "GLMR (Chain ID: 1284)", iconName: "moon.fill", color: Color(red: 0.32, green: 0.85, blue: 0.89), chainId: "1284"),
            makeEVMChain(id: "moonriver", title: "Moonriver", subtitle: "MOVR (Chain ID: 1285)", iconName: "moon.stars.fill", color: Color(red: 0.95, green: 0.76, blue: 0.18), chainId: "1285"),
            makeEVMChain(id: "gnosis", title: "Gnosis Chain", subtitle: "xDAI (Chain ID: 100)", iconName: "g.circle.fill", color: Color(red: 0.02, green: 0.55, blue: 0.48), chainId: "100"),
            makeEVMChain(id: "celo", title: "Celo", subtitle: "CELO (Chain ID: 42220)", iconName: "c.circle.fill", color: Color(red: 0.21, green: 0.81, blue: 0.55), chainId: "42220"),
            makeEVMChain(id: "polygon-zkevm", title: "Polygon zkEVM", subtitle: "ZK Rollup (Chain ID: 1101)", iconName: "hexagon.fill", color: Color(red: 0.51, green: 0.27, blue: 0.83).opacity(0.8), chainId: "1101"),
            makeEVMChain(id: "metis", title: "Metis", subtitle: "METIS (Chain ID: 1088)", iconName: "m.circle.fill", color: Color(red: 0.0, green: 0.85, blue: 0.73), chainId: "1088"),
            makeEVMChain(id: "aurora", title: "Aurora", subtitle: "NEAR EVM (Chain ID: 1313161554)", iconName: "a.circle.fill", color: Color(red: 0.47, green: 0.85, blue: 0.44), chainId: "1313161554"),
            makeEVMChain(id: "evmos", title: "Evmos", subtitle: "EVM on Cosmos (Chain ID: 9001)", iconName: "e.circle.fill", color: Color(red: 0.93, green: 0.29, blue: 0.23), chainId: "9001"),
            makeEVMChain(id: "kava-evm", title: "Kava EVM", subtitle: "KAVA (Chain ID: 2222)", iconName: "k.circle.fill", color: Color(red: 1.0, green: 0.22, blue: 0.22), chainId: "2222"),
            makeEVMChain(id: "opbnb", title: "opBNB", subtitle: "BNB L2 (Chain ID: 204)", iconName: "o.circle.fill", color: Color(red: 0.95, green: 0.77, blue: 0.23), chainId: "204"),
            makeEVMChain(id: "sonic", title: "Sonic", subtitle: "S Token (Chain ID: 146)", iconName: "s.circle.fill", color: Color(red: 0.18, green: 0.07, blue: 0.91), chainId: "146"),
            makeEVMChain(id: "arbitrum-nova", title: "Arbitrum Nova", subtitle: "AnyTrust L2 (Chain ID: 42170)", iconName: "a.circle.fill", color: Color(red: 0.91, green: 0.56, blue: 0.2), chainId: "42170"),
            makeEVMChain(id: "manta", title: "Manta Pacific", subtitle: "Modular L2 (Chain ID: 169)", iconName: "m.circle.fill", color: Color(red: 0.25, green: 0.78, blue: 0.94), chainId: "169")
        ]
    }
    
    private func makeEVMChain(id: String, title: String, subtitle: String, iconName: String, color: Color, chainId: String) -> ChainInfo {
        ChainInfo(
            id: id,
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            accentColor: color,
            details: [
                KeyDetail(label: "Private Key (hex)", value: ethereum.privateHex),
                KeyDetail(label: "Public Key (uncompressed hex)", value: ethereum.publicUncompressedHex),
                KeyDetail(label: "Address", value: ethereum.address),
                KeyDetail(label: "Chain ID", value: chainId)
            ],
            receiveAddress: ethereum.address
        )
    }
    
    // MARK: - Bitcoin Fork Chains
    
    private var bitcoinForkChains: [ChainInfo] {
        [
            ChainInfo(
                id: "dogecoin",
                title: "Dogecoin",
                subtitle: "DOGE",
                iconName: "d.circle.fill",
                accentColor: Color(red: 0.78, green: 0.63, blue: 0.26),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: dogecoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: dogecoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: dogecoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: dogecoin.address)
                ],
                receiveAddress: dogecoin.address
            ),
            ChainInfo(
                id: "bitcoin-cash",
                title: "Bitcoin Cash",
                subtitle: "BCH (CashAddr)",
                iconName: "bitcoinsign.circle.fill",
                accentColor: Color(red: 0.55, green: 0.78, blue: 0.25),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoinCash.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoinCash.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoinCash.publicCompressedHex),
                    KeyDetail(label: "Legacy Address", value: bitcoinCash.legacyAddress),
                    KeyDetail(label: "CashAddr", value: bitcoinCash.cashAddress)
                ],
                receiveAddress: bitcoinCash.cashAddress
            )
        ]
    }
    
    // MARK: - Cosmos Ecosystem Chains
    
    private var cosmosEcosystemChains: [ChainInfo] {
        [
            ChainInfo(
                id: "cosmos",
                title: "Cosmos Hub",
                subtitle: "ATOM",
                iconName: "atom",
                accentColor: Color(red: 0.18, green: 0.16, blue: 0.35),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.cosmosAddress)
                ],
                receiveAddress: cosmos.cosmosAddress
            ),
            ChainInfo(
                id: "osmosis",
                title: "Osmosis",
                subtitle: "OSMO",
                iconName: "drop.fill",
                accentColor: Color(red: 0.46, green: 0.09, blue: 0.97),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.osmosisAddress)
                ],
                receiveAddress: cosmos.osmosisAddress
            ),
            ChainInfo(
                id: "celestia",
                title: "Celestia",
                subtitle: "TIA",
                iconName: "moon.stars.fill",
                accentColor: Color(red: 0.45, green: 0.31, blue: 0.71),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.celestiaAddress)
                ],
                receiveAddress: cosmos.celestiaAddress
            ),
            ChainInfo(
                id: "dydx",
                title: "dYdX",
                subtitle: "DYDX",
                iconName: "chart.line.uptrend.xyaxis",
                accentColor: Color(red: 0.4, green: 0.31, blue: 0.85),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.dydxAddress)
                ],
                receiveAddress: cosmos.dydxAddress
            ),
            ChainInfo(
                id: "injective",
                title: "Injective",
                subtitle: "INJ",
                iconName: "arrow.up.right.circle.fill",
                accentColor: Color(red: 0.0, green: 0.85, blue: 0.98),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.injectiveAddress)
                ],
                receiveAddress: cosmos.injectiveAddress
            ),
            ChainInfo(
                id: "sei",
                title: "Sei",
                subtitle: "SEI",
                iconName: "s.circle.fill",
                accentColor: Color(red: 0.6, green: 0.13, blue: 0.19),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cosmos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cosmos.publicHex),
                    KeyDetail(label: "Address", value: cosmos.seiAddress)
                ],
                receiveAddress: cosmos.seiAddress
            )
        ]
    }
    
    // MARK: - Other Major Chains
    
    private var otherMajorChains: [ChainInfo] {
        [
            ChainInfo(
                id: "cardano",
                title: "Cardano",
                subtitle: "ADA",
                iconName: "c.circle.fill",
                accentColor: Color(red: 0.0, green: 0.2, blue: 0.47),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: cardano.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: cardano.publicHex),
                    KeyDetail(label: "Address", value: cardano.address)
                ],
                receiveAddress: cardano.address
            ),
            ChainInfo(
                id: "tron",
                title: "Tron",
                subtitle: "TRX",
                iconName: "t.circle.fill",
                accentColor: Color(red: 0.92, green: 0.07, blue: 0.14),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: tron.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: tron.publicHex),
                    KeyDetail(label: "Address", value: tron.address)
                ],
                receiveAddress: tron.address
            ),
            ChainInfo(
                id: "algorand",
                title: "Algorand",
                subtitle: "ALGO",
                iconName: "a.circle.fill",
                accentColor: Color(red: 0.0, green: 0.0, blue: 0.0),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: algorand.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: algorand.publicHex),
                    KeyDetail(label: "Address", value: algorand.address)
                ],
                receiveAddress: algorand.address
            ),
            ChainInfo(
                id: "stellar",
                title: "Stellar",
                subtitle: "XLM",
                iconName: "star.fill",
                accentColor: Color(red: 0.07, green: 0.07, blue: 0.07),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: stellar.privateHex),
                    KeyDetail(label: "Secret Key", value: stellar.secretKey),
                    KeyDetail(label: "Public Key (hex)", value: stellar.publicHex),
                    KeyDetail(label: "Address", value: stellar.address)
                ],
                receiveAddress: stellar.address
            ),
            ChainInfo(
                id: "near",
                title: "NEAR Protocol",
                subtitle: "NEAR",
                iconName: "n.circle.fill",
                accentColor: Color(red: 0.0, green: 0.82, blue: 0.55),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: near.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: near.publicHex),
                    KeyDetail(label: "Implicit Address", value: near.implicitAddress)
                ],
                receiveAddress: near.implicitAddress
            ),
            ChainInfo(
                id: "tezos",
                title: "Tezos",
                subtitle: "XTZ",
                iconName: "t.circle.fill",
                accentColor: Color(red: 0.17, green: 0.49, blue: 0.94),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: tezos.privateHex),
                    KeyDetail(label: "Secret Key (edsk)", value: tezos.secretKey),
                    KeyDetail(label: "Public Key (hex)", value: tezos.publicHex),
                    KeyDetail(label: "Public Key (edpk)", value: tezos.publicKey),
                    KeyDetail(label: "Address", value: tezos.address)
                ],
                receiveAddress: tezos.address
            ),
            ChainInfo(
                id: "hedera",
                title: "Hedera",
                subtitle: "HBAR",
                iconName: "h.circle.fill",
                accentColor: Color(red: 0.0, green: 0.0, blue: 0.0),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: hedera.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: hedera.publicHex),
                    KeyDetail(label: "Public Key (DER)", value: hedera.publicKeyDer)
                ],
                receiveAddress: hedera.publicKeyDer
            )
        ]
    }
    
    // MARK: - Extended Chain Support (16 new chains)
    
    private var extendedChains: [ChainInfo] {
        [
            ChainInfo(
                id: "zcash",
                title: "Zcash",
                subtitle: "ZEC (t-address)",
                iconName: "z.circle.fill",
                accentColor: Color(red: 0.96, green: 0.78, blue: 0.07),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: zcash.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: zcash.privateWif),
                    KeyDetail(label: "Public Key (compressed)", value: zcash.publicCompressedHex),
                    KeyDetail(label: "Transparent Address", value: zcash.transparentAddress)
                ],
                receiveAddress: zcash.transparentAddress
            ),
            ChainInfo(
                id: "dash",
                title: "Dash",
                subtitle: "DASH",
                iconName: "d.circle.fill",
                accentColor: Color(red: 0.0, green: 0.55, blue: 0.85),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: dash.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: dash.privateWif),
                    KeyDetail(label: "Public Key (compressed)", value: dash.publicCompressedHex),
                    KeyDetail(label: "Address", value: dash.address)
                ],
                receiveAddress: dash.address
            ),
            ChainInfo(
                id: "ravencoin",
                title: "Ravencoin",
                subtitle: "RVN",
                iconName: "bird.fill",
                accentColor: Color(red: 0.94, green: 0.32, blue: 0.21),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: ravencoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: ravencoin.privateWif),
                    KeyDetail(label: "Public Key (compressed)", value: ravencoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: ravencoin.address)
                ],
                receiveAddress: ravencoin.address
            ),
            ChainInfo(
                id: "vechain",
                title: "VeChain",
                subtitle: "VET",
                iconName: "v.circle.fill",
                accentColor: Color(red: 0.0, green: 0.56, blue: 0.8),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: vechain.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: vechain.publicHex),
                    KeyDetail(label: "Address", value: vechain.address)
                ],
                receiveAddress: vechain.address
            ),
            ChainInfo(
                id: "filecoin",
                title: "Filecoin",
                subtitle: "FIL",
                iconName: "f.circle.fill",
                accentColor: Color(red: 0.0, green: 0.83, blue: 0.95),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: filecoin.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: filecoin.publicHex),
                    KeyDetail(label: "Address (f1...)", value: filecoin.address)
                ],
                receiveAddress: filecoin.address
            ),
            ChainInfo(
                id: "harmony",
                title: "Harmony",
                subtitle: "ONE",
                iconName: "1.circle.fill",
                accentColor: Color(red: 0.0, green: 0.68, blue: 0.87),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: harmony.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: harmony.publicHex),
                    KeyDetail(label: "Address (0x)", value: harmony.address),
                    KeyDetail(label: "Address (one1...)", value: harmony.bech32Address)
                ],
                receiveAddress: harmony.bech32Address
            ),
            ChainInfo(
                id: "oasis",
                title: "Oasis Network",
                subtitle: "ROSE",
                iconName: "o.circle.fill",
                accentColor: Color(red: 0.0, green: 0.58, blue: 0.95),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: oasis.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: oasis.publicHex),
                    KeyDetail(label: "Address (oasis1...)", value: oasis.address)
                ],
                receiveAddress: oasis.address
            ),
            ChainInfo(
                id: "internet-computer",
                title: "Internet Computer",
                subtitle: "ICP",
                iconName: "infinity.circle.fill",
                accentColor: Color(red: 0.16, green: 0.0, blue: 0.51),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: internetComputer.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: internetComputer.publicHex),
                    KeyDetail(label: "Principal ID", value: internetComputer.principalId),
                    KeyDetail(label: "Account ID", value: internetComputer.accountId)
                ],
                receiveAddress: internetComputer.principalId
            ),
            ChainInfo(
                id: "waves",
                title: "Waves",
                subtitle: "WAVES",
                iconName: "waveform.path",
                accentColor: Color(red: 0.0, green: 0.58, blue: 0.95),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: waves.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: waves.publicHex),
                    KeyDetail(label: "Address", value: waves.address)
                ],
                receiveAddress: waves.address
            ),
            ChainInfo(
                id: "multiversx",
                title: "MultiversX",
                subtitle: "EGLD (formerly Elrond)",
                iconName: "x.circle.fill",
                accentColor: Color(red: 0.14, green: 0.71, blue: 0.88),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: multiversx.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: multiversx.publicHex),
                    KeyDetail(label: "Address (erd1...)", value: multiversx.address)
                ],
                receiveAddress: multiversx.address
            ),
            ChainInfo(
                id: "flow",
                title: "Flow",
                subtitle: "FLOW",
                iconName: "flow.fill",
                accentColor: Color(red: 0.0, green: 0.94, blue: 0.47),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: flow.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: flow.publicHex),
                    KeyDetail(label: "Address", value: flow.address)
                ],
                receiveAddress: flow.address
            ),
            ChainInfo(
                id: "mina",
                title: "Mina Protocol",
                subtitle: "MINA",
                iconName: "m.circle.fill",
                accentColor: Color(red: 0.42, green: 0.16, blue: 0.88),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: mina.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: mina.publicHex),
                    KeyDetail(label: "Address (B62...)", value: mina.address)
                ],
                receiveAddress: mina.address
            ),
            ChainInfo(
                id: "zilliqa",
                title: "Zilliqa",
                subtitle: "ZIL",
                iconName: "z.circle.fill",
                accentColor: Color(red: 0.29, green: 0.84, blue: 0.75),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: zilliqa.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: zilliqa.publicHex),
                    KeyDetail(label: "Base16 Address", value: zilliqa.address),
                    KeyDetail(label: "Bech32 Address (zil1...)", value: zilliqa.bech32Address)
                ],
                receiveAddress: zilliqa.bech32Address
            ),
            ChainInfo(
                id: "eos",
                title: "EOS",
                subtitle: "EOS",
                iconName: "e.circle.fill",
                accentColor: Color(red: 0.0, green: 0.0, blue: 0.0),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: eos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: eos.publicHex),
                    KeyDetail(label: "Public Key (EOS format)", value: eos.publicKey)
                ],
                receiveAddress: eos.publicKey
            ),
            ChainInfo(
                id: "neo",
                title: "NEO",
                subtitle: "NEO",
                iconName: "n.circle.fill",
                accentColor: Color(red: 0.0, green: 0.9, blue: 0.47),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: neo.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: neo.publicHex),
                    KeyDetail(label: "Address (A...)", value: neo.address)
                ],
                receiveAddress: neo.address
            ),
            ChainInfo(
                id: "nervos",
                title: "Nervos CKB",
                subtitle: "CKB",
                iconName: "n.circle.fill",
                accentColor: Color(red: 0.24, green: 0.85, blue: 0.56),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: nervos.privateHex),
                    KeyDetail(label: "Public Key (hex)", value: nervos.publicHex),
                    KeyDetail(label: "Address (ckb1...)", value: nervos.address)
                ],
                receiveAddress: nervos.address
            )
        ]
    }
}
