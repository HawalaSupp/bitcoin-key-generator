import SwiftUI

/// Card view displaying chain balance/price info in the main grid
struct ChainCard: View, Equatable {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState
    var sparklineData: [Double] = []

    @State private var skeletonPhase: CGFloat = -0.8

    // Equatable — only re-render when data actually changes
    nonisolated static func == (lhs: ChainCard, rhs: ChainCard) -> Bool {
        lhs.chain == rhs.chain &&
        lhs.balanceState == rhs.balanceState &&
        lhs.priceState == rhs.priceState &&
        lhs.sparklineData == rhs.sparklineData
    }

    private var pricePrimary: String {
        switch priceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var isBalanceLoading: Bool {
        if case .loading = balanceState { return true }
        return false
    }

    private var isPriceLoading: Bool {
        if case .loading = priceState { return true }
        return false
    }

    private var priceDetail: (text: String, color: Color)? {
        switch priceState {
        case .refreshing(_, let timestamp):
            let detail = relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…"
            return (detail, .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    private var balancePrimary: String {
        switch balanceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var balanceDetail: (text: String, color: Color)? {
        switch balanceState {
        case .refreshing(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Refreshing… • updated \(relative)", .secondary)
            }
            return ("Refreshing…", .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: chain.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(chain.accentColor)
                    .frame(width: 40, height: 40)
                    .background(chain.accentColor.opacity(0.15))
                    .clipShape(Circle())
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(chain.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(chain.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Balance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isBalanceLoading {
                            SkeletonLine()
                        } else {
                            Text(balancePrimary)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    if isBalanceLoading {
                        SkeletonLine(width: 110, height: 8)
                            .padding(.top, 2)
                    } else if let detail = balanceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                    
                    HStack {
                        Text("Price")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isPriceLoading {
                            SkeletonLine(width: 70)
                        } else {
                            HStack(spacing: 8) {
                                Text(pricePrimary)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if !sparklineData.isEmpty {
                                    OptimizedSparklineView(dataPoints: sparklineData, lineColor: chain.accentColor)
                                }
                            }
                        }
                    }
                    if isPriceLoading {
                        SkeletonLine(width: 90, height: 8)
                            .padding(.top, 2)
                    } else if let detail = priceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .stroke(chain.accentColor.opacity(0.15), lineWidth: 1)
        )
        // GPU-accelerated compositing for smooth scrolling
        .drawingGroup(opaque: false)
        // ROADMAP-14 E12: VoiceOver accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chain.title), balance: \(balancePrimary), price: \(pricePrimary)")
        .accessibilityHint("Double-tap to view \(chain.title) details")
    }
}
