import Foundation

// MARK: - Wallet Identity Protocol

/// Base protocol for all wallet types (HD and Imported)
protocol WalletIdentity: Identifiable, Codable, Sendable {
    var id: UUID { get }
    var name: String { get set }
    var createdAt: Date { get }
}

// MARK: - Derivation Scheme

/// Supported derivation schemes for HD wallets
enum DerivationScheme: String, Codable, Sendable, CaseIterable {
    /// BIP44: m/44'/coin'/account'/change/index
    case bip44 = "BIP44"
    
    /// BIP49: m/49'/coin'/account'/change/index (SegWit P2SH)
    case bip49 = "BIP49"
    
    /// BIP84: m/84'/coin'/account'/change/index (Native SegWit)
    case bip84 = "BIP84"
    
    var displayName: String {
        switch self {
        case .bip44: return "Legacy (BIP44)"
        case .bip49: return "SegWit Compatible (BIP49)"
        case .bip84: return "Native SegWit (BIP84)"
        }
    }
    
    var purpose: UInt32 {
        switch self {
        case .bip44: return 44
        case .bip49: return 49
        case .bip84: return 84
        }
    }
}

// MARK: - Chain Identifier

/// Supported blockchain networks with their BIP44 coin types
enum ChainIdentifier: String, Codable, Sendable, CaseIterable, Identifiable {
    case bitcoin = "bitcoin"
    case bitcoinTestnet = "bitcoin-testnet"
    case ethereum = "ethereum"
    case litecoin = "litecoin"
    case solana = "solana"
    case xrp = "xrp"
    case monero = "monero"
    case bnb = "bnb"
    
    var id: String { rawValue }
    
    /// BIP44 coin type
    var coinType: UInt32 {
        switch self {
        case .bitcoin: return 0
        case .bitcoinTestnet: return 1
        case .ethereum: return 60
        case .litecoin: return 2
        case .solana: return 501
        case .xrp: return 144
        case .monero: return 128
        case .bnb: return 714
        }
    }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        case .solana: return "Solana"
        case .xrp: return "XRP"
        case .monero: return "Monero"
        case .bnb: return "BNB"
        }
    }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .bitcoinTestnet: return "tBTC"
        case .ethereum: return "ETH"
        case .litecoin: return "LTC"
        case .solana: return "SOL"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        case .bnb: return "BNB"
        }
    }
    
    var iconName: String {
        switch self {
        case .bitcoin, .bitcoinTestnet: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .solana: return "s.circle.fill"
        case .xrp: return "x.circle.fill"
        case .monero: return "m.circle.fill"
        case .bnb: return "b.circle.fill"
        }
    }
    
    /// Whether this chain supports HD derivation
    var supportsHD: Bool {
        switch self {
        case .monero:
            // Monero has its own key derivation scheme
            return false
        default:
            return true
        }
    }
}

// MARK: - Wallet Type Enum

/// Distinguishes between HD wallet accounts and imported standalone accounts
enum WalletType: String, Codable, Sendable {
    case hd = "hd"
    case imported = "imported"
}
