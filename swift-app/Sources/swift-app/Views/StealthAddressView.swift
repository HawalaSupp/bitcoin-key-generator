import SwiftUI

// MARK: - Stealth Address View (Stub)
// Functionality moved to AddressBookOverlay — STEALTH tab

struct StealthAddressView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.3))
            Text("Stealth Addresses have moved to the Address Book.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(width: 320, height: 180)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
