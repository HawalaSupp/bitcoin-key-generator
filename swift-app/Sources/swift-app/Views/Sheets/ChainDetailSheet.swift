import SwiftUI

/// Sheet showing details for a specific chain — Hawala glass design
struct ChainDetailSheet: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState
    let keys: AllKeys?
    let onCopy: (String) -> Void
    let onSendRequested: (ChainInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showReceiveInfo = false
    @State private var showReceiveQR = false
    @State private var copyFeedbackMessage: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

    private var isBitcoinChain: Bool {
        chain.id.starts(with: "bitcoin")
    }

    var body: some View {
        HawalaSheetShell(title: chain.title, width: 480, height: 600) {

            if isBitcoinChain {
                quickActionsSection
            }

            if let receiveAddress = chain.receiveAddress {
                receiveSection(address: receiveAddress)
            }

            balanceSummary
            priceSummary
        }
        .overlay(alignment: .bottom) {
            if let message = copyFeedbackMessage {
                CopyFeedbackBanner(message: message)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            HawalaActionButton(icon: "paperplane.fill", label: "Send", style: .primary) {
                onSendRequested(chain)
            }
            HawalaActionButton(icon: "arrow.down.circle.fill", label: "Receive", style: .secondary) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showReceiveInfo = true }
            }
        }
    }

    @ViewBuilder
    private func receiveSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showReceiveInfo.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                    Text("RECEIVE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.25))
                        .rotationEffect(.degrees(showReceiveInfo ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showReceiveInfo {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share this address to receive funds:")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))

                    if showReceiveQR {
                        HStack {
                            Spacer()
                            QRCodeView(content: address, size: 160)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    Text(address)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        HawalaActionButton(icon: "doc.on.doc", label: "Copy", style: .primary) {
                            copyWithFeedback(value: address, label: "Receive address")
                        }
                        HawalaActionButton(icon: showReceiveQR ? "qrcode" : "qrcode.viewfinder", label: showReceiveQR ? "Hide QR" : "Show QR", style: .secondary) {
                            withAnimation(.easeInOut(duration: 0.2)) { showReceiveQR.toggle() }
                        }
                        #if canImport(AppKit)
                        HawalaActionButton(icon: "square.and.arrow.up", label: "Share", style: .secondary) {
                            shareReceiveAddress(address)
                        }
                        #endif
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .hawalaSectionCard()
    }

    #if canImport(AppKit)
    private func shareReceiveAddress(_ address: String) {
        let sharingText = "My \(chain.title) address: \(address)"
        let picker = NSSharingServicePicker(items: [sharingText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }
    #endif

    @ViewBuilder
    private var balanceSummary: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                    Text("Balance")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                stateDisplay(balanceState)
            }
        }
        .hawalaSectionCard()
        .contextMenu {
            if let copyValue = balanceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) balance")
                } label: {
                    Label("Copy Balance", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var priceSummary: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                    Text("Price")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                priceStateDisplay(priceState)
            }
        }
        .hawalaSectionCard()
        .contextMenu {
            if let copyValue = priceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) price")
                } label: {
                    Label("Copy Price", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func stateDisplay(_ state: ChainBalanceState) -> some View {
        switch state {
        case .idle:
            Text("—")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .refreshing(let value, let timestamp):
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                Text(relativeTimeDescription(from: timestamp).map { "Refreshing... \($0)" } ?? "Refreshing...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        case .loaded(let value, let timestamp):
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                if let relative = relativeTimeDescription(from: timestamp) {
                    Text("Updated \(relative)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        case .stale(let value, let timestamp, let message):
            let detail: String = {
                if let relative = relativeTimeDescription(from: timestamp) {
                    return "\(message) \(relative)"
                }
                return message
            }()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.6))
            }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Unavailable")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private func priceStateDisplay(_ state: ChainPriceState) -> some View {
        switch state {
        case .idle:
            Text("—")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .refreshing(let value, let timestamp):
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                Text(relativeTimeDescription(from: timestamp).map { "Refreshing... \($0)" } ?? "Refreshing...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        case .loaded(let value, let timestamp):
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                if let relative = relativeTimeDescription(from: timestamp) {
                    Text("Updated \(relative)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        case .stale(let value, let timestamp, let message):
            let detail: String = {
                if let relative = relativeTimeDescription(from: timestamp) {
                    return "\(message) \(relative)"
                }
                return message
            }()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.6))
            }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Unavailable")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var balanceCopyValue: String? {
        switch balanceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private var priceCopyValue: String? {
        switch priceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private func copyWithFeedback(value: String, label: String) {
        onCopy(value)
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                copyFeedbackMessage = "\(label) copied"
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                copyFeedbackMessage = nil
            }
        }
    }
}
