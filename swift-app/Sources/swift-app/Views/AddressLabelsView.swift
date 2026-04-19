import SwiftUI

/// Legacy address labels view — replaced by AddressBookOverlay.
/// Kept as a stub so any residual references compile.
struct AddressLabelsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("Address Labels has moved")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Text("Open Address Book from Settings.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
            Button("Close") { dismiss() }
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }
}
