import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State private var keys: AllKeys?
    @State private var rawJSON: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var copyMessage: String?
    @State private var selectedChain: ChainInfo?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multi-Chain Key Generator")
                .font(.largeTitle)
                .bold()

            Text("Generate production-ready key material for Bitcoin, Litecoin, Monero, Solana, Ethereum, BNB, XRP, and popular ERC-20 tokens. Tap a card to inspect and copy individual keys.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await runGenerator() }
                } label: {
                    Label("Generate Keys", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                Button {
                    keys = nil
                    rawJSON = ""
                    errorMessage = nil
                    copyMessage = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || (keys == nil && errorMessage == nil))

                Button {
                    copyOutput()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || rawJSON.isEmpty)
            }

            if isGenerating {
                ProgressView("Running Rust generator...")
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let copyMessage {
                Text(copyMessage)
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            contentArea

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
        .sheet(item: $selectedChain) { chain in
            ChainDetailSheet(chain: chain) { value in
                copyToClipboard(value)
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let keys {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(keys.chainInfos) { chain in
                        Button {
                            selectedChain = chain
                        } label: {
                            ChainCard(chain: chain)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No key material yet")
                    .font(.headline)
                Text("Generate a fresh set of keys to review per-chain details and copy them securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func runGenerator() async {
        isGenerating = true
        errorMessage = nil
        copyMessage = nil

        do {
            let (result, jsonString) = try await runRustKeyGenerator()
            await MainActor.run {
                keys = result
                rawJSON = jsonString
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func copyOutput() {
        guard !rawJSON.isEmpty else { return }
        copyToClipboard(rawJSON)
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif

        copyMessage = "Copied to clipboard."
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { copyMessage = nil }
        }
    }

    private func runRustKeyGenerator() async throws -> (AllKeys, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "cargo",
                "run",
                "--manifest-path",
                manifestPath,
                "--quiet",
                "--",
                "--json"
            ]
            process.currentDirectoryURL = workspaceRoot

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                guard proc.terminationStatus == 0 else {
                    let message = errorString.isEmpty ? "Rust generator failed with exit code \(proc.terminationStatus)" : errorString
                    continuation.resume(throwing: KeyGeneratorError.executionFailed(message))
                    return
                }

                guard let jsonData = outputString.data(using: .utf8) else {
                    continuation.resume(throwing: KeyGeneratorError.executionFailed("Invalid UTF-8 output from generator"))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let decoded = try decoder.decode(AllKeys.self, from: jsonData)
                    continuation.resume(returning: (decoded, outputString))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private var workspaceRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // ContentView.swift
        url.deleteLastPathComponent() // Sources
        url.deleteLastPathComponent() // swift-app
        return url // workspace root
    }

    private var manifestPath: String {
        workspaceRoot
            .appendingPathComponent("rust-app")
            .appendingPathComponent("Cargo.toml")
            .path
    }
}

private struct ChainCard: View {
    let chain: ChainInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: chain.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(chain.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(chain.title)
                    .font(.headline)
                Text(chain.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Text("View keys")
                    .font(.footnote)
                    .foregroundStyle(chain.accentColor)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(chain.accentColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(chain.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ChainDetailSheet: View {
    let chain: ChainInfo
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chain.details) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.label)
                                .font(.headline)
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button {
                                    onCopy(item.value)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .padding(8)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle(chain.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

struct ChainInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let details: [KeyDetail]
}

struct KeyDetail: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

struct AllKeys: Decodable {
    let bitcoin: BitcoinKeys
    let litecoin: LitecoinKeys
    let monero: MoneroKeys
    let solana: SolanaKeys
    let ethereum: EthereumKeys
    let bnb: BnbKeys
    let xrp: XrpKeys

    var chainInfos: [ChainInfo] {
        var cards: [ChainInfo] = [
            ChainInfo(
                id: "bitcoin",
                title: "Bitcoin",
                subtitle: "SegWit P2WPKH",
                iconName: "bitcoinsign.circle.fill",
                accentColor: Color.orange,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: bitcoin.address)
                ]
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
                ]
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
                ]
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
                ]
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
                ]
            )
        ]

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
                details: ethereumDetails
            )
        )

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
                details: bnbDetails
            )
        )

        let tokenEntries: [(String, String, String, Color)] = [
            ("usdt", "Tether USD (USDT)", "ERC-20 Token", Color(red: 0.0, green: 0.64, blue: 0.54)),
            ("usdc", "USD Coin (USDC)", "ERC-20 Token", Color.blue),
            ("dai", "Dai (DAI)", "ERC-20 Token", Color.yellow)
        ]

        for entry in tokenEntries {
            cards.append(
                ChainInfo(
                    id: "\(entry.0)-erc20",
                    title: entry.1,
                    subtitle: entry.2,
                    iconName: "dollarsign.circle.fill",
                    accentColor: entry.3,
                    details: ethereumDetails
                )
            )
        }

        return cards
    }
}

struct BitcoinKeys: Decodable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String
}

struct LitecoinKeys: Decodable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String
}

struct MoneroKeys: Decodable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String
}

struct SolanaKeys: Decodable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String
}

struct EthereumKeys: Decodable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String
}

struct BnbKeys: Decodable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String
}

struct XrpKeys: Decodable {
    let privateHex: String
    let publicCompressedHex: String
    let classicAddress: String
}

enum KeyGeneratorError: LocalizedError {
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        }
    }
}

#Preview {
    ContentView()
}
