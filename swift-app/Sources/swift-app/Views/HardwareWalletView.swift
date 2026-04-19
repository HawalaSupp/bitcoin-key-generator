import SwiftUI

/// Legacy hardware wallet view - redirects to HardwareWalletOverlay.
/// Kept as a stub so SheetCoordinator references compile.
struct HardwareWalletView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("Hardware Wallet has moved")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Text("Open Hardware Wallet from Settings.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
            Button("Close") { dismiss() }
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }
}
