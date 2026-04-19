import SwiftUI

/// Sheet for selecting which chain/asset to send — Hawala-themed full-size picker
struct SendAssetPickerSheet: View {
    let chains: [ChainInfo]
    let onSelect: (ChainInfo) -> Void
    let onBatchSend: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var hoveredChainID: String?

    private var filteredChains: [ChainInfo] {
        if searchText.isEmpty { return chains }
        let lowered = searchText.lowercased()
        return chains.filter {
            $0.title.lowercased().contains(lowered) ||
            $0.subtitle.lowercased().contains(lowered) ||
            $0.id.lowercased().contains(lowered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header bar
            headerBar

            // MARK: - Search bar
            searchBar
                .padding(.horizontal, HawalaTheme.Spacing.xl)
                .padding(.top, HawalaTheme.Spacing.lg)
                .padding(.bottom, HawalaTheme.Spacing.md)

            // MARK: - Content
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                    // Batch Send card
                    batchSendRow

                    // Divider label
                    sectionDivider

                    // Asset rows
                    ForEach(filteredChains) { chain in
                        chainRow(chain)
                    }

                    if filteredChains.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
                .padding(.bottom, HawalaTheme.Spacing.xxl)
            }
        }
        .background(HawalaTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .frame(width: 560, height: 700)
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack {
            // Close button
            Button {
                dismiss()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Title
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                Text("Send")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }

            Spacer()

            // Invisible spacer to balance the close button
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, HawalaTheme.Spacing.xl)
        .padding(.vertical, HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }

    // MARK: - Search
    private var searchBar: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.textTertiary)

            TextField("Search assets...", text: $searchText)
                .textFieldStyle(.plain)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm + 2)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Batch Send
    private var batchSendRow: some View {
        Button {
            dismiss()
            onBatchSend()
        } label: {
            HStack(spacing: HawalaTheme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.backgroundTertiary)
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                    Text("Batch Send")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    Text("Send to multiple addresses at once")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Divider
    private var sectionDivider: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Rectangle()
                .fill(HawalaTheme.Colors.divider)
                .frame(height: 1)
            Text("select an asset")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .layoutPriority(1)
            Rectangle()
                .fill(HawalaTheme.Colors.divider)
                .frame(height: 1)
        }
        .padding(.vertical, HawalaTheme.Spacing.xs)
    }

    // MARK: - Chain Row
    private func chainRow(_ chain: ChainInfo) -> some View {
        let isHovered = hoveredChainID == chain.id
        return Button {
            dismiss()
            onSelect(chain)
        } label: {
            HStack(spacing: HawalaTheme.Spacing.lg) {
                // Monochrome icon
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.backgroundTertiary)
                        .frame(width: 44, height: 44)
                    Image(systemName: chain.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }

                // Name & subtitle
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                    Text(chain.title)
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    Text(chain.subtitle)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Ticker badge
                Text(symbolForChain(chain.id))
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .padding(.horizontal, HawalaTheme.Spacing.sm)
                    .padding(.vertical, HawalaTheme.Spacing.xs)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .strokeBorder(isHovered ? HawalaTheme.Colors.borderHover : HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(HawalaTheme.Animation.fast) {
                hoveredChainID = over ? chain.id : nil
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            Text("No assets found")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            Text("Try a different search term")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HawalaTheme.Spacing.xxxl)
    }

    // MARK: - Helpers
    private func symbolForChain(_ id: String) -> String {
        switch id {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        case "ton": return "TON"
        case "aptos": return "APT"
        case "sui": return "SUI"
        case "polkadot": return "DOT"
        case "kusama": return "KSM"
        case "dogecoin": return "DOGE"
        case "dash": return "DASH"
        case "zcash": return "ZEC"
        case "bitcoin-cash": return "BCH"
        case "ravencoin": return "RVN"
        case "cardano": return "ADA"
        case "cosmos": return "ATOM"
        case "algorand": return "ALGO"
        case "tezos": return "XTZ"
        case "stellar": return "XLM"
        case "near": return "NEAR"
        case "tron": return "TRX"
        case "eos": return "EOS"
        case "neo": return "NEO"
        case "flow": return "FLOW"
        case "hedera": return "HBAR"
        case "harmony": return "ONE"
        case "vechain": return "VET"
        case "waves": return "WAVES"
        case "zilliqa": return "ZIL"
        case "mina": return "MINA"
        case "multiversx": return "EGLD"
        case "nervos": return "CKB"
        case "oasis": return "ROSE"
        case "internet-computer": return "ICP"
        case "filecoin": return "FIL"
        case "polygon": return "MATIC"
        case "optimism": return "OP"
        case "arbitrum": return "ARB"
        case "avalanche": return "AVAX"
        case "fantom": return "FTM"
        case "gnosis": return "xDAI"
        case "usdt-erc20": return "USDT"
        case "usdc-erc20": return "USDC"
        case "dai-erc20": return "DAI"
        default:
            if id.contains("erc20") { return "ERC20" }
            return id.uppercased()
        }
    }
}
