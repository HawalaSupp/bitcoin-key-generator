import SwiftUI

/// Sheet showing details for a specific chain including balance, price, and receive address
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isBitcoinChain {
                        quickActionsSection
                    }
                    
                    if let receiveAddress = chain.receiveAddress {
                        receiveSection(address: receiveAddress)
                    }
                    balanceSummary
                    priceSummary
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
        .frame(width: 480, height: 600)
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
            Button {
                onSendRequested(chain)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(keys == nil)
            
            Button {
                withAnimation { showReceiveInfo = true }
            } label: {
                Label("Receive", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func receiveSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3)
                    .foregroundStyle(chain.accentColor)
                Text("Receive")
                    .font(.headline)
                Spacer()
                Button(showReceiveInfo ? "Hide" : "Show") {
                    withAnimation { showReceiveInfo.toggle() }
                }
                .buttonStyle(.bordered)
            }

            if showReceiveInfo {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share this address to receive funds:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // QR Code (toggleable)
                    if showReceiveQR {
                        HStack {
                            Spacer()
                            QRCodeView(content: address, size: 160)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Address display
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Action buttons
                    HStack(spacing: 10) {
                        Button {
                            copyWithFeedback(value: address, label: "Receive address")
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(chain.accentColor)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showReceiveQR.toggle()
                            }
                        } label: {
                            Label(
                                showReceiveQR ? "Hide QR" : "Show QR",
                                systemImage: showReceiveQR ? "qrcode" : "qrcode.viewfinder"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        #if canImport(AppKit)
                        Button {
                            shareReceiveAddress(address)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(chain.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        HStack(alignment: .center, spacing: 12) {
            Label("Balance", systemImage: "creditcard.fill")
                .font(.headline)
            Spacer()
            switch balanceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        HStack(alignment: .center, spacing: 12) {
            Label("Price", systemImage: "dollarsign.circle.fill")
                .font(.headline)
            Spacer()
            switch priceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
