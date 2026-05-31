import SwiftUI

/// Settings view for configuring duress/decoy wallet — Hawala glass design
struct DuressSettingsView: View {
    @ObservedObject private var duressManager = DuressWalletManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showSetupSheet = false
    @State private var showChangePasscodeSheet = false
    @State private var showDisableConfirmation = false
    @State private var showPanicWipeConfirmation = false
    @State private var showTips = false
    @State private var showInfo = false
    @State private var errorMessage: String?

    var body: some View {
        HawalaSheetShell(title: "Duress Protection", width: 460, height: 600) {

            // ── Status ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "shield.lefthalf.filled", title: "Status")

                HStack(spacing: 14) {
                    Image(systemName: duressManager.isDuressEnabled ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 22))
                        .foregroundColor(duressManager.isDuressEnabled
                            ? Color(red: 0.20, green: 0.84, blue: 0.29)
                            : .white.opacity(0.25))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duress Protection")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        Text(duressManager.isDuressEnabled ? "Active" : "Not Configured")
                            .font(.system(size: 12))
                            .foregroundColor(duressManager.isDuressEnabled
                                ? Color(red: 0.20, green: 0.84, blue: 0.29)
                                : .white.opacity(0.35))
                    }
                    Spacer()
                    if duressManager.isDuressEnabled {
                        HawalaStatusBadge(text: "Enabled", color: Color(red: 0.20, green: 0.84, blue: 0.29))
                    }
                }
            }
            .hawalaSectionCard()

            // ── What is Duress Mode ──
            VStack(spacing: 12) {
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showInfo.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                        Text("WHAT IS DURESS MODE?")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.25))
                            .rotationEffect(.degrees(showInfo ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showInfo {
                    VStack(spacing: 10) {
                        duressInfoRow(icon: "eye.slash", title: "Decoy Wallet", desc: "A separate wallet with its own funds that opens when you enter the decoy passcode.")
                        duressInfoRow(icon: "lock.shield", title: "Plausible Deniability", desc: "No way to detect the real wallet exists when in decoy mode.")
                        duressInfoRow(icon: "hand.raised", title: "Coercion Protection", desc: "Under duress, enter the decoy passcode to show the decoy wallet.")
                        duressInfoRow(icon: "exclamationmark.triangle", title: "Important", desc: "Keep small amounts in your decoy wallet to make it believable.")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .hawalaSectionCard()

            // ── Configuration ──
            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "gearshape", title: "Configuration")

                if !duressManager.isDuressEnabled {
                    HawalaActionButton(icon: "plus.circle", label: "Set Up Decoy Wallet", style: .primary) {
                        showSetupSheet = true
                    }
                } else {
                    HawalaActionButton(icon: "key", label: "Change Decoy Passcode", style: .secondary) {
                        showChangePasscodeSheet = true
                    }
                    HawalaActionButton(icon: "trash", label: "Disable Duress Protection", style: .destructive) {
                        showDisableConfirmation = true
                    }
                }
            }
            .hawalaSectionCard()

            // ── Emergency (only when enabled) ──
            if duressManager.isDuressEnabled {
                VStack(spacing: 12) {
                    HawalaOverlaySectionHeader(icon: "exclamationmark.octagon", title: "Emergency")

                    HawalaActionButton(icon: "exclamationmark.triangle.fill", label: "Emergency Wipe", style: .destructive) {
                        showPanicWipeConfirmation = true
                    }

                    if !duressManager.isInDecoyMode {
                        HawalaInfoRow(icon: "info.circle", text: "Only available in decoy mode", color: .white.opacity(0.3))
                    }
                }
                .hawalaSectionCard()
                .opacity(duressManager.isInDecoyMode ? 1 : 0.5)
            }

            // ── Tips ──
            VStack(spacing: 12) {
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showTips.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                        Text("TIPS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.25))
                            .rotationEffect(.degrees(showTips ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showTips {
                    VStack(spacing: 8) {
                        duressTipRow("Use a passcode you can remember under stress")
                        duressTipRow("Keep a believable amount in your decoy wallet")
                        duressTipRow("Practice switching between wallets")
                        duressTipRow("The decoy passcode should be similar but different")
                        duressTipRow("Never reveal that duress mode exists")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .hawalaSectionCard()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            if let msg = errorMessage {
                Text(HawalaUserError.from(message: msg, context: .duress)?.message ?? msg)
            }
        }
        .alert("Disable Duress Protection?", isPresented: $showDisableConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disable", role: .destructive) {
                duressManager.disableDuress()
                AnalyticsService.shared.track(AnalyticsService.EventName.duressModeDisabled)
            }
        } message: {
            Text("This will remove the decoy wallet and its passcode. You can set it up again later.")
        }
        .alert("Emergency Wipe", isPresented: $showPanicWipeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("WIPE REAL WALLET", role: .destructive) {
                duressManager.panicWipeRealWallet()
            }
        } message: {
            Text("THIS CANNOT BE UNDONE\n\nThis will permanently destroy your real wallet. Only use this in extreme emergency situations.")
        }
        .sheet(isPresented: $showSetupSheet) {
            DuressSetupSheet(onComplete: { showSetupSheet = false })
        }
        .sheet(isPresented: $showChangePasscodeSheet) {
            DuressChangePasscodeSheet(onComplete: { showChangePasscodeSheet = false })
        }
    }

    // ── Helpers ──

    @ViewBuilder
    private func duressInfoRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func duressTipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.6))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

// MARK: - Setup Sheet

struct DuressSetupSheet: View {
    let onComplete: () -> Void

    @ObservedObject private var duressManager = DuressWalletManager.shared
    @AppStorage("hawala.passcodeHash") private var realPasscodeHash: String?

    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    @State private var step = 0 // 0=intro, 1=passcode, 2=done

    var body: some View {
        HawalaSheetShell(title: "Set Up Decoy Wallet", width: 420, height: 480) {

            HawalaStepIndicator(totalSteps: 3, currentStep: step)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 8)

            switch step {
            case 0: introContent
            case 1: passcodeContent
            case 2: confirmationContent
            default: EmptyView()
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 12))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.08))
                .cornerRadius(8)
            }
        }
    }

    private var introContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.white.opacity(0.35))

            Text("Duress Protection")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("Create a decoy wallet that opens with a separate passcode. Use it to protect your real funds under coercion.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer().frame(height: 4)
            HawalaActionButton(icon: "arrow.right", label: "Continue", style: .primary) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = 1 }
            }
        }
    }

    private var passcodeContent: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)
            Image(systemName: "key.fill")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(.white.opacity(0.45))

            Text("Create Decoy Passcode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("Must be different from your real passcode.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))

            HawalaSecureField(placeholder: "Decoy Passcode", text: $passcode)
            HawalaSecureField(placeholder: "Confirm Passcode", text: $confirmPasscode)

            HawalaActionButton(icon: "checkmark", label: "Set Passcode", style: .primary) {
                validateAndProceed()
            }
        }
    }

    private var confirmationContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))

            Text("Decoy Wallet Created")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("Enter your decoy passcode at unlock to access it.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                HawalaInfoRow(icon: "exclamationmark.triangle", text: "Add some funds to make it believable", color: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.8))
                HawalaInfoRow(icon: "eye.slash", text: "Never reveal that you have a decoy wallet", color: Color(red: 1, green: 0.84, blue: 0.04).opacity(0.8))
            }
            .padding(12)
            .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.15), lineWidth: 1)
            )

            HawalaActionButton(icon: "checkmark.circle", label: "Done", style: .primary) {
                onComplete()
            }
        }
    }

    private func validateAndProceed() {
        errorMessage = nil

        guard passcode == confirmPasscode else {
            errorMessage = "Passcodes don't match"
            return
        }

        guard passcode.count >= 4 else {
            errorMessage = "Passcode must be at least 4 characters"
            return
        }

        let result = duressManager.setDuressPin(passcode, confirmPin: confirmPasscode)
        switch result {
        case .success:
            AnalyticsService.shared.track(AnalyticsService.EventName.duressModeEnabled)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = 2 }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Change Passcode Sheet

struct DuressChangePasscodeSheet: View {
    let onComplete: () -> Void

    @ObservedObject private var duressManager = DuressWalletManager.shared
    @AppStorage("hawala.passcodeHash") private var realPasscodeHash: String?

    @State private var oldPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        HawalaSheetShell(title: "Change Decoy Passcode", width: 380, height: 400) {

            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "key", title: "Current Passcode")
                HawalaSecureField(placeholder: "Current Decoy Passcode", text: $oldPasscode)
            }
            .hawalaSectionCard()

            VStack(spacing: 12) {
                HawalaOverlaySectionHeader(icon: "key.fill", title: "New Passcode")
                HawalaSecureField(placeholder: "New Decoy Passcode", text: $newPasscode)
                HawalaSecureField(placeholder: "Confirm New Passcode", text: $confirmPasscode)
            }
            .hawalaSectionCard()

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 12))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.08))
                .cornerRadius(8)
            }

            HawalaActionButton(icon: "checkmark", label: "Change Passcode", style: .primary) {
                changePasscode()
            }
        }
    }

    private func changePasscode() {
        errorMessage = nil

        guard newPasscode == confirmPasscode else {
            errorMessage = "New passcodes don't match"
            return
        }

        let result = duressManager.changeDuressPin(oldPin: oldPasscode, newPin: newPasscode, confirmPin: confirmPasscode)
        switch result {
        case .success:
            onComplete()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Audit Log and Setup Compatibility Views

struct DuressAuditLogView: View {
    @ObservedObject private var duressManager = DuressWalletManager.shared

    var body: some View {
        let logs = duressManager.getDuressActivationLogs() ?? []

        HawalaSheetShell(title: "Security Audit", width: 420, height: 480) {
            if logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundColor(.white.opacity(0.45))
                    Text("No duress events recorded")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(logs) { log in
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.white.opacity(0.45))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.formattedDate)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                                Text(log.deviceInfo)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                        }
                        .hawalaSectionCard()
                    }
                }
            }
        }
    }
}

struct DuressSetupView: View {
    var body: some View {
        DuressSetupSheet(onComplete: {})
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationStack {
        DuressSettingsView()
    }
    .frame(width: 500, height: 700)
}
#endif
#endif
#endif
