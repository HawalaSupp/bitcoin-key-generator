import SwiftUI

/// Comprehensive security settings including passcode, biometrics, and advanced features
struct SecuritySettingsView: View {
    let hasPasscode: Bool
    let onSetPasscode: (String) -> Void
    let onRemovePasscode: () -> Void
    let biometricState: BiometricState
    @Binding var biometricEnabled: Bool
    @Binding var biometricForSends: Bool
    @Binding var biometricForKeyReveal: Bool
    @Binding var autoLockSelection: AutoLockIntervalOption
    let onBiometricRequest: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        HawalaSheetShell(title: "Security Settings", width: 440, height: 700) {

            // ── Session Lock ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "lock.fill", title: "Session Lock")

                if hasPasscode {
                    HawalaInfoRow(icon: "checkmark.circle", text: "Passcode is active", color: Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.7))
                    HawalaActionButton(icon: "lock.open", label: "Remove Passcode", style: .destructive) {
                        onRemovePasscode()
                        dismiss()
                    }
                } else {
                    HawalaInfoRow(icon: "info.circle", text: "No passcode set. Add one to lock key data.", color: .white.opacity(0.35))
                }
            }
            .hawalaSectionCard()

            // ── Set New Passcode ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "key", title: "Set New Passcode")
                HawalaSecureField(placeholder: "New passcode", text: $passcode)
                HawalaSecureField(placeholder: "Confirm passcode", text: $confirmPasscode)

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                        Text(errorMessage)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                HawalaActionButton(icon: "lock", label: "Save Passcode", style: .primary) {
                    validateAndSave()
                }
            }
            .hawalaSectionCard()

            // ── Biometric Unlock ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: biometricIcon, title: "Biometric Unlock")

                HawalaInfoRow(icon: "info.circle", text: biometricState.statusMessage, color: .white.opacity(0.35))

                if biometricState.supportsUnlock {
                    HawalaToggleRow(icon: biometricIcon, label: "Enable \(biometricLabel)", isOn: $biometricEnabled)

                    if !hasPasscode {
                        HawalaInfoRow(icon: "exclamationmark.triangle", text: "Set a passcode to turn on biometrics.", color: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
                    } else if biometricEnabled {
                        HawalaActionButton(icon: "hand.raised.fill", label: "Test \(biometricLabel)", style: .secondary) {
                            onBiometricRequest()
                        }
                    }
                }
            }
            .hawalaSectionCard()

            // ── Biometric Protection ──
            if BiometricAuthHelper.isBiometricAvailable {
                VStack(spacing: 12) {
                    HawalaOverlaySectionHeader(icon: "shield.fill", title: "Biometric Protection")
                    HawalaToggleRow(icon: "paperplane.fill", label: "Require for Sends", isOn: $biometricForSends)
                    HawalaToggleRow(icon: "key.fill", label: "Require for Key Reveal", isOn: $biometricForKeyReveal)
                    HawalaInfoRow(icon: "info.circle", text: "\(biometricLabel) required before sending or viewing keys.", color: .white.opacity(0.3))
                }
                .hawalaSectionCard()
            }

            // ── Auto-Lock Timer ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "timer", title: "Auto-Lock Timer")

                HStack(spacing: 8) {
                    ForEach(AutoLockIntervalOption.allCases, id: \.self) { option in
                        Button(action: { autoLockSelection = option }) {
                            Text(option.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(autoLockSelection == option
                                    ? Color.white.opacity(0.5)
                                    : .white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(autoLockSelection == option
                                    ? Color.white.opacity(0.15)
                                    : Color.white.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(autoLockSelection == option
                                            ? Color.white.opacity(0.3)
                                            : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasPasscode)
                    }
                }

                HawalaInfoRow(icon: "info.circle", text: autoLockSelection.description, color: .white.opacity(0.3))

                if !hasPasscode {
                    HawalaInfoRow(icon: "exclamationmark.triangle", text: "Auto-lock requires a passcode.", color: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
                }
            }
            .hawalaSectionCard()

            // ── Duress Protection ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "shield.checkered", title: "Duress Protection")
                DuressProtectionRow(hasPasscode: hasPasscode)
            }
            .hawalaSectionCard()
        }
    }

    private func validateAndSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Choose at least 6 characters."
            return
        }
        guard trimmed == confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "Passcodes do not match."
            return
        }
        errorMessage = nil
        onSetPasscode(trimmed)
        dismiss()
    }

    private var biometricLabel: String {
        if case .available(let kind) = biometricState {
            return kind.displayName
        }
        return "Biometrics"
    }

    private var biometricIcon: String {
        if case .available(let kind) = biometricState {
            return kind.iconName
        }
        return "lock.circle"
    }
}

// MARK: - Duress Protection Row

struct DuressProtectionRow: View {
    let hasPasscode: Bool
    @StateObject private var duressManager = DuressWalletManager.shared
    @State private var showDuressSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: duressManager.isConfigured ? "shield.checkered" : "exclamationmark.shield")
                    .font(.system(size: 14))
                    .foregroundColor(duressManager.isConfigured
                        ? Color(red: 0.20, green: 0.84, blue: 0.29)
                        : Color(red: 1, green: 0.84, blue: 0.04))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Duress PIN")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text(duressManager.isConfigured ? "Protected with decoy wallet" : "Not configured")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                HawalaActionButton(
                    icon: duressManager.isConfigured ? "gearshape" : "plus.circle",
                    label: duressManager.isConfigured ? "Manage" : "Set Up",
                    style: .primary
                ) {
                    showDuressSetup = true
                }
                .frame(width: 120)
            }

            if !hasPasscode {
                HawalaInfoRow(icon: "exclamationmark.triangle", text: "Set a passcode first to enable duress protection.", color: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
            }

            if duressManager.isInDuressMode {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text("Currently in duress mode")
                        .font(.system(size: 11))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
            }
        }
        .sheet(isPresented: $showDuressSetup) {
            DuressSettingsView()
        }
    }
}

