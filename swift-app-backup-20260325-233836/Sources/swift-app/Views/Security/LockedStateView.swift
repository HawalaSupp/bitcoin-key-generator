import SwiftUI

/// Displayed when the app is locked and requires passcode to unlock
struct LockedStateView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.primary)
            Text("Session locked")
                .font(.title3)
                .bold()
            Text("Unlock with your passcode to view or copy any key material. Keys are automatically cleared when the app locks itself.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
