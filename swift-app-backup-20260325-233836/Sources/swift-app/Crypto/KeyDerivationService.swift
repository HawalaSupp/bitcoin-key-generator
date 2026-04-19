import Foundation

// MARK: - Key Derivation Service

/// Service for deriving keys from seed using the Rust backend.
/// This is the single source of truth for all key derivation.
@MainActor
final class KeyDerivationService: ObservableObject {
    
    /// Shared instance
    static let shared = KeyDerivationService()
    
    private init() {}
    
    // MARK: - Key Generation
    
    /// Generate a new wallet with fresh mnemonic
    /// - Returns: Mnemonic phrase and derived keys
    func generateNewWallet() async throws -> (mnemonic: String, keys: DerivedKeys) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = RustService.shared.generateKeys()
                
                guard !result.isEmpty, result != "{}" else {
                    continuation.resume(throwing: KeyDerivationError.generationFailed)
                    return
                }
                
                do {
                    // Parse the JSON response from Rust
                    guard let data = result.data(using: .utf8) else {
                        continuation.resume(throwing: KeyDerivationError.invalidResponse)
                        return
                    }
                    
                    let response = try JSONDecoder().decode(WalletGenerationResponse.self, from: data)
                    let keys = DerivedKeys(from: response.keys)
                    continuation.resume(returning: (response.mnemonic, keys))
                } catch {
                    continuation.resume(throwing: KeyDerivationError.decodingFailed(error))
                }
            }
        }
    }
    
    /// Restore a wallet from existing mnemonic
    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - passphrase: Optional BIP39 passphrase
    /// - Returns: Derived keys
    func restoreWallet(from mnemonic: String, passphrase: String = "") async throws -> DerivedKeys {
        // Validate mnemonic first
        let validation = MnemonicValidator.validate(mnemonic)
        guard validation.isValid else {
            throw KeyDerivationError.invalidMnemonic(validation.errorMessage ?? "Invalid mnemonic")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let normalizedMnemonic = MnemonicValidator.normalizePhrase(mnemonic).joined(separator: " ")
                // Pass passphrase to Rust backend (BIP-39 passphrase support)
                let result = RustService.shared.restoreWallet(mnemonic: normalizedMnemonic, passphrase: passphrase)
                
                guard !result.isEmpty, result != "{}" else {
                    continuation.resume(throwing: KeyDerivationError.restorationFailed)
                    return
                }
                
                do {
                    guard let data = result.data(using: .utf8) else {
                        continuation.resume(throwing: KeyDerivationError.invalidResponse)
                        return
                    }
                    
                    let allKeys = try JSONDecoder().decode(RustAllKeys.self, from: data)
                    let keys = DerivedKeys(from: allKeys)
                    continuation.resume(returning: keys)
                } catch {
                    continuation.resume(throwing: KeyDerivationError.decodingFailed(error))
                }
            }
        }
    }
    
    /// Derive seed from mnemonic (for fingerprint calculation)
    func deriveSeed(from mnemonic: String, passphrase: String = "") -> Data? {
        SeedDeriver.deriveSeed(from: mnemonic, passphrase: passphrase)
    }
    
    /// Calculate wallet fingerprint from seed
    func calculateFingerprint(seed: Data) -> Data {
        SeedDeriver.fingerprint(from: seed)
    }
}

// MARK: - Derived Keys

/// Structured representation of all derived keys
struct DerivedKeys: Codable, Sendable {
    let bitcoin: ChainKeys
    let bitcoinTestnet: ChainKeys
    let ethereum: ChainKeys
    let ethereumSepolia: ChainKeys
    let litecoin: ChainKeys
    let solana: SolanaChainKeys
    let xrp: ChainKeys
    let monero: MoneroChainKeys
    let bnb: ChainKeys
    
    init(from rustKeys: RustAllKeys) {
        self.bitcoin = ChainKeys(
            privateKey: rustKeys.bitcoin.private_hex,
            publicKey: rustKeys.bitcoin.public_compressed_hex,
            address: rustKeys.bitcoin.address,
            wif: rustKeys.bitcoin.private_wif
        )
        self.bitcoinTestnet = ChainKeys(
            privateKey: rustKeys.bitcoin_testnet.private_hex,
            publicKey: rustKeys.bitcoin_testnet.public_compressed_hex,
            address: rustKeys.bitcoin_testnet.address,
            wif: rustKeys.bitcoin_testnet.private_wif
        )
        self.ethereum = ChainKeys(
            privateKey: rustKeys.ethereum.private_hex,
            publicKey: rustKeys.ethereum.public_uncompressed_hex,
            address: rustKeys.ethereum.address,
            wif: nil
        )
        self.ethereumSepolia = ChainKeys(
            privateKey: rustKeys.ethereum_sepolia.private_hex,
            publicKey: rustKeys.ethereum_sepolia.public_uncompressed_hex,
            address: rustKeys.ethereum_sepolia.address,
            wif: nil
        )
        self.litecoin = ChainKeys(
            privateKey: rustKeys.litecoin.private_hex,
            publicKey: rustKeys.litecoin.public_compressed_hex,
            address: rustKeys.litecoin.address,
            wif: rustKeys.litecoin.private_wif
        )
        self.solana = SolanaChainKeys(
            privateSeedHex: rustKeys.solana.private_seed_hex,
            privateKeyBase58: rustKeys.solana.private_key_base58,
            publicKeyBase58: rustKeys.solana.public_key_base58
        )
        self.xrp = ChainKeys(
            privateKey: rustKeys.xrp.private_hex,
            publicKey: rustKeys.xrp.public_compressed_hex,
            address: rustKeys.xrp.classic_address,
            wif: nil
        )
        self.monero = MoneroChainKeys(
            privateSpendHex: rustKeys.monero.private_spend_hex,
            privateViewHex: rustKeys.monero.private_view_hex,
            publicSpendHex: rustKeys.monero.public_spend_hex,
            publicViewHex: rustKeys.monero.public_view_hex,
            address: rustKeys.monero.address
        )
        self.bnb = ChainKeys(
            privateKey: rustKeys.bnb.private_hex,
            publicKey: rustKeys.bnb.public_uncompressed_hex,
            address: rustKeys.bnb.address,
            wif: nil
        )
    }
    
    /// Get keys for a specific chain
    func keys(for chain: ChainIdentifier) -> ChainKeysProtocol? {
        switch chain {
        case .bitcoin: return bitcoin
        case .bitcoinTestnet: return bitcoinTestnet
        case .ethereum, .ethereumSepolia, .polygon, .arbitrum, .optimism, .base, .avalanche, .bnb:
            // All EVM chains use the same Ethereum keys
            return ethereum
        case .litecoin: return litecoin
        case .solana, .solanaDevnet: return solana
        case .xrp: return xrp
        case .monero: return monero
        }
    }
}

// MARK: - Chain Keys Types

protocol ChainKeysProtocol: Codable, Sendable {
    var address: String { get }
}

struct ChainKeys: ChainKeysProtocol, Codable, Sendable {
    let privateKey: String
    let publicKey: String
    let address: String
    let wif: String?
}

struct SolanaChainKeys: ChainKeysProtocol, Codable, Sendable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String
    
    var address: String { publicKeyBase58 }
}

struct MoneroChainKeys: ChainKeysProtocol, Codable, Sendable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String
}

// MARK: - Rust Response Types

struct WalletGenerationResponse: Codable {
    let mnemonic: String
    let keys: RustAllKeys
}

struct RustAllKeys: Codable {
    let bitcoin: RustBitcoinKeys
    let bitcoin_testnet: RustBitcoinKeys
    let litecoin: RustLitecoinKeys
    let monero: RustMoneroKeys
    let solana: RustSolanaKeys
    let ethereum: RustEthereumKeys
    let ethereum_sepolia: RustEthereumKeys
    let bnb: RustBnbKeys
    let xrp: RustXrpKeys
}

struct RustBitcoinKeys: Codable {
    let private_hex: String
    let private_wif: String
    let public_compressed_hex: String
    let address: String
    // Taproot (P2TR) fields - bc1p... for mainnet, tb1p... for testnet
    let taproot_address: String?
    let x_only_pubkey: String?
}

struct RustLitecoinKeys: Codable {
    let private_hex: String
    let private_wif: String
    let public_compressed_hex: String
    let address: String
}

struct RustMoneroKeys: Codable {
    let private_spend_hex: String
    let private_view_hex: String
    let public_spend_hex: String
    let public_view_hex: String
    let address: String
}

struct RustSolanaKeys: Codable {
    let private_seed_hex: String
    let private_key_base58: String
    let public_key_base58: String
}

struct RustEthereumKeys: Codable {
    let private_hex: String
    let public_uncompressed_hex: String
    let address: String
}

struct RustBnbKeys: Codable {
    let private_hex: String
    let public_uncompressed_hex: String
    let address: String
}

struct RustXrpKeys: Codable {
    let private_hex: String
    let public_compressed_hex: String
    let classic_address: String
}

// MARK: - Errors

enum KeyDerivationError: LocalizedError {
    case generationFailed
    case restorationFailed
    case invalidMnemonic(String)
    case invalidResponse
    case decodingFailed(Error)
    case rustBackendUnavailable
    
    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "Failed to generate new wallet keys"
        case .restorationFailed:
            return "Failed to restore wallet from mnemonic"
        case .invalidMnemonic(let reason):
            return reason
        case .invalidResponse:
            return "Invalid response from key derivation"
        case .decodingFailed(let error):
            return "Failed to decode keys: \(error.localizedDescription)"
        case .rustBackendUnavailable:
            return "Cryptographic backend unavailable"
        }
    }
}
