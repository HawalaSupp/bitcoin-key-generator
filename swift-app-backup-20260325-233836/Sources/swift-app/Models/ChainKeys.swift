import Foundation
import SwiftUI

// MARK: - Chain Information

struct ChainInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let details: [KeyDetail]
    let receiveAddress: String?
}

struct KeyDetail: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

// MARK: - Balance Fetch Errors

enum BalanceFetchError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case invalidStatus(Int)
    case invalidPayload
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Failed to build balance request."
        case .invalidResponse:
            return "Remote balance service returned an unexpected response."
        case .invalidStatus(let code):
            return "Balance service returned status code \(code)."
        case .invalidPayload:
            return "Balance service returned unexpected data."
        case .rateLimited:
            return "Rate limited - prices will update shortly."
        }
    }
}

// MARK: - Wallet Response Wrapper (from Rust CLI)

struct WalletResponse: Codable {
    let mnemonic: String
    let keys: AllKeys
}

// MARK: - All Keys Container

struct AllKeys: Codable {
    let bitcoin: BitcoinKeys
    let bitcoinTestnet: BitcoinKeys
    let litecoin: LitecoinKeys
    let monero: MoneroKeys
    let solana: SolanaKeys
    let ethereum: EthereumKeys
    let ethereumSepolia: EthereumKeys
    let bnb: BnbKeys
    let xrp: XrpKeys
    // New chains from wallet-core integration
    let ton: TonKeys
    let aptos: AptosKeys
    let sui: SuiKeys
    let polkadot: PolkadotKeys
    // Extended chain support
    let dogecoin: DogecoinKeys
    let bitcoinCash: BitcoinCashKeys
    let cosmos: CosmosKeys
    let cardano: CardanoKeys
    let tron: TronKeys
    let algorand: AlgorandKeys
    let stellar: StellarKeys
    let near: NearKeys
    let tezos: TezosKeys
    let hedera: HederaKeys
    // Extended chain support (16 new chains)
    let zcash: ZcashKeys
    let dash: DashKeys
    let ravencoin: RavencoinKeys
    let vechain: VechainKeys
    let filecoin: FilecoinKeys
    let harmony: HarmonyKeys
    let oasis: OasisKeys
    let internetComputer: InternetComputerKeys
    let waves: WavesKeys
    let multiversx: MultiversXKeys
    let flow: FlowKeys
    let mina: MinaKeys
    let zilliqa: ZilliqaKeys
    let eos: EosKeys
    let neo: NeoKeys
    let nervos: NervosKeys

    private enum CodingKeys: String, CodingKey {
        case bitcoin
        case bitcoinTestnet = "bitcoin_testnet"
        case litecoin
        case monero
        case solana
        case ethereum
        case ethereumSepolia = "ethereum_sepolia"
        case bnb
        case xrp
        case ton
        case aptos
        case sui
        case polkadot
        case dogecoin
        case bitcoinCash = "bitcoin_cash"
        case cosmos
        case cardano
        case tron
        case algorand
        case stellar
        case near
        case tezos
        case hedera
        case zcash
        case dash
        case ravencoin
        case vechain
        case filecoin
        case harmony
        case oasis
        case internetComputer = "internet_computer"
        case waves
        case multiversx
        case flow
        case mina
        case zilliqa
        case eos
        case neo
        case nervos
    }
}

// MARK: - Core Chain Keys

struct BitcoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String
    // Taproot (P2TR) address - bc1p... for mainnet, tb1p... for testnet
    let taprootAddress: String?
    let xOnlyPubkey: String?

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
        case taprootAddress = "taproot_address"
        case xOnlyPubkey = "x_only_pubkey"
    }
}

struct LitecoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct MoneroKeys: Codable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateSpendHex = "private_spend_hex"
        case privateViewHex = "private_view_hex"
        case publicSpendHex = "public_spend_hex"
        case publicViewHex = "public_view_hex"
        case address
    }
}

struct SolanaKeys: Codable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String

    private enum CodingKeys: String, CodingKey {
        case privateSeedHex = "private_seed_hex"
        case privateKeyBase58 = "private_key_base58"
        case publicKeyBase58 = "public_key_base58"
    }
}

struct EthereumKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct BnbKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct XrpKeys: Codable {
    let privateHex: String
    let publicCompressedHex: String
    let classicAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicCompressedHex = "public_compressed_hex"
        case classicAddress = "classic_address"
    }
}

// MARK: - New Chain Keys (wallet-core integration)

struct TonKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct AptosKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct SuiKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct PolkadotKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String
    let kusamaAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
        case kusamaAddress = "kusama_address"
    }
}

// MARK: - Bitcoin Fork Keys

struct DogecoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct BitcoinCashKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let legacyAddress: String
    let cashAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case legacyAddress = "legacy_address"
        case cashAddress = "cash_address"
    }
}

// MARK: - Cosmos Ecosystem Keys

struct CosmosKeys: Codable {
    let privateHex: String
    let publicHex: String
    let cosmosAddress: String
    let osmosisAddress: String
    let celestiaAddress: String
    let dydxAddress: String
    let injectiveAddress: String
    let seiAddress: String
    let akashAddress: String
    let kujiraAddress: String
    let strideAddress: String
    let secretAddress: String
    let stargazeAddress: String
    let junoAddress: String
    let terraAddress: String
    let neutronAddress: String
    let nobleAddress: String
    let axelarAddress: String
    let fetchAddress: String
    let persistenceAddress: String
    let sommelierAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case cosmosAddress = "cosmos_address"
        case osmosisAddress = "osmosis_address"
        case celestiaAddress = "celestia_address"
        case dydxAddress = "dydx_address"
        case injectiveAddress = "injective_address"
        case seiAddress = "sei_address"
        case akashAddress = "akash_address"
        case kujiraAddress = "kujira_address"
        case strideAddress = "stride_address"
        case secretAddress = "secret_address"
        case stargazeAddress = "stargaze_address"
        case junoAddress = "juno_address"
        case terraAddress = "terra_address"
        case neutronAddress = "neutron_address"
        case nobleAddress = "noble_address"
        case axelarAddress = "axelar_address"
        case fetchAddress = "fetch_address"
        case persistenceAddress = "persistence_address"
        case sommelierAddress = "sommelier_address"
    }
}

// MARK: - Other Major Chain Keys

struct CardanoKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct TronKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct AlgorandKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct StellarKeys: Codable {
    let privateHex: String
    let secretKey: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case secretKey = "secret_key"
        case publicHex = "public_hex"
        case address
    }
}

struct NearKeys: Codable {
    let privateHex: String
    let publicHex: String
    let implicitAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case implicitAddress = "implicit_address"
    }
}

struct TezosKeys: Codable {
    let privateHex: String
    let secretKey: String
    let publicHex: String
    let publicKey: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case secretKey = "secret_key"
        case publicHex = "public_hex"
        case publicKey = "public_key"
        case address
    }
}

struct HederaKeys: Codable {
    let privateHex: String
    let publicHex: String
    let publicKeyDer: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case publicKeyDer = "public_key_der"
    }
}

// MARK: - Extended Chain Keys (16 new chains)

struct ZcashKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let transparentAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case transparentAddress = "transparent_address"
    }
}

struct DashKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct RavencoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct VechainKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct FilecoinKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct HarmonyKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String
    let bech32Address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
        case bech32Address = "bech32_address"
    }
}

struct OasisKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct InternetComputerKeys: Codable {
    let privateHex: String
    let publicHex: String
    let principalId: String
    let accountId: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case principalId = "principal_id"
        case accountId = "account_id"
    }
}

struct WavesKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct MultiversXKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct FlowKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct MinaKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct ZilliqaKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String
    let bech32Address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
        case bech32Address = "bech32_address"
    }
}

struct EosKeys: Codable {
    let privateHex: String
    let publicHex: String
    let publicKey: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case publicKey = "public_key"
    }
}

struct NeoKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

struct NervosKeys: Codable {
    let privateHex: String
    let publicHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicHex = "public_hex"
        case address
    }
}

// MARK: - Keychain Storage

struct KeychainHelper {
    static let keysIdentifier = "com.hawala.wallet.keys"
    
    static func saveKeys(_ keys: AllKeys) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(keys)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecValueData as String: data,
            // Use kSecAttrAccessibleWhenUnlocked for dev builds to avoid password prompts
            // For production, use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func loadKeys() throws -> AllKeys? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            #if DEBUG
            print("ℹ️ User cancelled Keychain authentication")
            #endif
            return nil
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(AllKeys.self, from: data)
    }
    
    static func deleteKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save keys to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load keys from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete keys from Keychain (status: \(status))"
        case .userCancelled:
            return "Keychain authentication was cancelled by user"
        }
    }
}

enum KeyGeneratorError: LocalizedError {
    case executionFailed(String)
    case cargoNotFound

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        case .cargoNotFound:
            return "Unable to locate the cargo executable. Install Rust via https://rustup.rs or set the CARGO_BIN environment variable to the cargo path."
        }
    }
}
