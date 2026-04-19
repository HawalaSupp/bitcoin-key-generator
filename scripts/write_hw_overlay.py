#!/usr/bin/env python3
"""Generate the rewritten HardwareWalletOverlay.swift"""

import os

code = r'''import SwiftUI
import CoreImage.CIFilterBuiltins

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Hardware Wallet Overlay
// Physical security meets digital sovereignty.
// Geometric device representations with tangible depth,
// connection tethers, signature flow, firmware engravings.
// All wired to HardwareWalletManagerV2 — zero mock data.
// Monumental. Monochrome. Hardware-grade.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HardwareWalletOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil
    var initialTab: HWTab? = nil

    // ── Tab ──
    enum HWTab: String, CaseIterable {
        case devices = "DEVICES"
        case signing = "SIGNING"
        case firmware = "FIRMWARE"
        case airgap = "AIRGAP"
    }

    @State private var selectedTab: HWTab = .devices

    // ── Real manager ──
    @ObservedObject private var hwManager = HardwareWalletManagerV2.shared

    // ── Device selection ──
    @State private var selectedDeviceId: String? = nil

    // ── Pairing flow ──
    @State private var pairState: PairState = .idle
    enum PairState: Equatable {
        case idle
        case plugPrompt
        case detecting
        case found(String)
        case authenticating
        case paired(String)
        case error(String)
        static func == (lhs: PairState, rhs: PairState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.plugPrompt, .plugPrompt), (.detecting, .detecting),
                 (.authenticating, .authenticating):
                return true
            case (.found(let a), .found(let b)): return a == b
            case (.paired(let a), .paired(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // ── Signing flow ──
    @State private var signState: SignState = .idle
    enum SignState: Equatable {
        case idle
        case selectingAccount
        case preparing
        case awaitingConfirm
        case signing
        case complete(String)  // signature hex
        case error(String)
        static func == (lhs: SignState, rhs: SignState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.selectingAccount, .selectingAccount),
                 (.preparing, .preparing), (.awaitingConfirm, .awaitingConfirm),
                 (.signing, .signing):
                return true
            case (.complete(let a), .complete(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }
    @State private var signSelectedAccount: HardwareWalletAccount? = nil
    @State private var signRecipient: String = ""
    @State private var signAmount: String = ""
    @State private var signProgress: CGFloat = 0
    @State private var signDeviceMessage: String = ""

    // ── Account management ──
    @State private var editingAccountId: String? = nil
    @State private var editLabel: String = ""
    @State private var showRemoveConfirm = false
    @State private var accountToRemove: String? = nil
    @State private var isVerifyingAccount = false

    // ── Air-Gap state ──
    @State private var airGapStep: AirGapStep = .intro
    enum AirGapStep: Equatable {
        case intro
        case selectChain
        case enterPayload
        case displayQR
        case scanning
        case complete
        case error(String)
        static func == (lhs: AirGapStep, rhs: AirGapStep) -> Bool {
            switch (lhs, rhs) {
            case (.intro, .intro), (.selectChain, .selectChain), (.enterPayload, .enterPayload),
                 (.displayQR, .displayQR), (.scanning, .scanning), (.complete, .complete):
                return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }
    @State private var airGapChain: SupportedChain = .bitcoin
    @State private var airGapPayload: String = ""
    @State private var airGapQRData: String = ""

    // ── PIN entry ──
    @State private var showPinEntry = false
    @State private var pinInput: String = ""

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var tetherPhase: CGFloat = 0
    @State private var healthPulse: CGFloat = 1.0
    @State private var scanPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered = false
    @State private var backHovered = false
    @State private var scanBtnHovered = false

    // ── Task tracking ──
    @State private var signingTask: Task<Void, Never>? = nil
    @State private var pairingTask: Task<Void, Never>? = nil

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardContainer
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            if let tab = initialTab { selectedTab = tab }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            startAnimations()
            setupManagerCallbacks()
        }
        .onDisappear {
            signingTask?.cancel()
            pairingTask?.cancel()
        }
        .alert("Remove Account", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) { accountToRemove = nil }
            Button("Remove", role: .destructive) {
                if let id = accountToRemove {
                    hwManager.removeAccount(id: id)
                    accountToRemove = nil
                }
            }
        } message: {
            Text("This will remove the saved hardware wallet account. You can re-add it anytime by connecting your device.")
        }
        .alert("Enter PIN", isPresented: $showPinEntry) {
            SecureField("PIN", text: $pinInput)
            Button("Submit") { }
            Button("Cancel", role: .cancel) { pinInput = "" }
        } message: {
            Text("Enter the PIN on your hardware wallet or type it here.")
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardContainer: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
        }
        .frame(width: 600, height: 750)
        .background(cardBg)
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var cardBg: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.018), .white.opacity(0.0)],
                        startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                        endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                    )
                )
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("HARDWARE")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                if onBackToSettings != nil {
                    Button(action: handleBackToSettings) {
                        Circle()
                            .fill(backHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { backHovered = $0 }
                }
                Spacer()
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(closeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(HWTab.allCases, id: \.self) { tab in
                hwTabButton(tab)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func hwTabButton(_ tab: HWTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.3))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.white.opacity(0.08) : Color.clear)
                    )
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selectedTab == tab ? 0.4 : 0))
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch selectedTab {
                case .devices: devicesTabContent
                case .signing: signingTabContent
                case .firmware: firmwareTabContent
                case .airgap: airgapTabContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – DEVICES TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var devicesTabContent: some View {
        VStack(spacing: 20) {
            deviceArcView
            scanButton
            if pairState != .idle { pairingFlow }
            discoveredDevicesList
            savedAccountsList
        }
    }

    // ── Device arc: geometric 3D-like device representations ──
    private var deviceArcView: some View {
        let devices = hwManager.discoveredDevices
        let count = devices.count
        return ZStack {
            if count == 0 {
                emptyDeviceSlot
            } else {
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                    deviceGeometry(device: device, index: idx, total: count)
                }
            }
        }
        .frame(height: 140)
    }

    private var emptyDeviceSlot: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .frame(width: 80, height: 48)
                .overlay(
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.12))
                )
            Text("No devices detected")
                .font(.clashGroteskMedium(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    // ── Single device geometric representation ──
    private func deviceGeometry(device: DiscoveredDevice, index: Int, total: Int) -> some View {
        let offsetX = deviceOffsetX(index: index, total: total)
        let tilt = deviceTilt(index: index, total: total)
        let isSelected = selectedDeviceId == device.id
        let isConnected = hwManager.connectedWallets[device.id] != nil

        return VStack(spacing: 6) {
            deviceBody(device: device, isSelected: isSelected, isConnected: isConnected, tilt: tilt)
            deviceLabel(device: device, isConnected: isConnected)
        }
        .offset(x: offsetX)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedDeviceId = isSelected ? nil : device.id
            }
        }
    }

    private func deviceOffsetX(index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0 }
        let spacing: CGFloat = 120
        let totalWidth = spacing * CGFloat(total - 1)
        return -totalWidth / 2 + spacing * CGFloat(index)
    }

    private func deviceTilt(index: Int, total: Int) -> Double {
        guard total > 1 else { return 0 }
        let center = Double(total - 1) / 2.0
        return (Double(index) - center) * 3.0
    }

    // ── Device body: Ledger = elongated rectangle, Trezor = shield shape ──
    private func deviceBody(device: DiscoveredDevice, isSelected: Bool, isConnected: Bool, tilt: Double) -> some View {
        let deviceOpacity = isConnected ? (0.85 * healthPulse) : 0.35

        return ZStack {
            if device.deviceType.manufacturer == .ledger {
                ledgerChassis(isSelected: isSelected, opacity: deviceOpacity)
            } else {
                trezorChassis(isSelected: isSelected, opacity: deviceOpacity)
            }

            // Connection type indicator
            connectionIndicator(device: device, isConnected: isConnected)

            if isSelected {
                tetherBeam
            }
        }
        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0))
    }

    private func ledgerChassis(isSelected: Bool, opacity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04 * opacity))
                .frame(width: 78, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.12), lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.4), radius: isSelected ? 12 : 6, y: 4)

            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.02))
                .frame(width: 42, height: 16)
                .offset(x: -8)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                        .frame(width: 42, height: 16)
                        .offset(x: -8)
                )

            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.06))
                .frame(width: 10, height: 6)
                .offset(x: 42)
        }
    }

    private func trezorChassis(isSelected: Bool, opacity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04 * opacity))
                .frame(width: 56, height: 68)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.12), lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.4), radius: isSelected ? 12 : 6, y: 4)

            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.02))
                .frame(width: 38, height: 34)
                .offset(y: -6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                        .frame(width: 38, height: 34)
                        .offset(y: -6)
                )

            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.06))
                .frame(width: 8, height: 5)
                .offset(y: 35)
        }
    }

    private func connectionIndicator(device: DiscoveredDevice, isConnected: Bool) -> some View {
        let yOffset: CGFloat = device.deviceType.manufacturer == .ledger ? 22 : 28
        return HStack(spacing: 3) {
            Image(systemName: device.connectionType == .usb ? "cable.connector.horizontal" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 6))
            if isConnected {
                Circle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 4, height: 4)
            }
        }
        .foregroundColor(.white.opacity(0.2))
        .offset(y: yOffset)
    }

    private var tetherBeam: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.12 * tetherPhase), .white.opacity(0.0)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: 60, height: 1)
            .offset(y: 50)
    }

    private func deviceLabel(device: DiscoveredDevice, isConnected: Bool) -> some View {
        VStack(spacing: 2) {
            Text(device.name ?? device.deviceType.displayName)
                .font(.clashGroteskMedium(size: 11))
                .foregroundColor(.white.opacity(0.65))
            Text(isConnected ? "CONNECTED" : device.connectionType.rawValue.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(isConnected ? 0.4 : 0.25))
        }
    }

    // ── Scan button ──
    private var scanButton: some View {
        Button {
            if hwManager.isScanning {
                hwManager.stopScanning()
            } else {
                hwManager.startScanning()
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scanPulse = 1.0
                }
            }
        } label: {
            HStack(spacing: 6) {
                if hwManager.isScanning {
                    scanPulseIndicator
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                }
                Text(hwManager.isScanning ? "SCANNING..." : "SCAN FOR DEVICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(hwManager.isScanning ? 0.4 : (scanBtnHovered ? 0.7 : 0.5)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(hwManager.isScanning ? 0.03 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(hwManager.isScanning ? 0.05 : 0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { scanBtnHovered = $0 }
    }

    private var scanPulseIndicator: some View {
        Circle()
            .fill(.white.opacity(0.3))
            .frame(width: 6, height: 6)
            .scaleEffect(1.0 + scanPulse * 0.5)
            .opacity(1.0 - scanPulse * 0.6)
    }

    // ── Pairing flow ──
    private var pairingFlow: some View {
        VStack(spacing: 14) {
            pairingFlowContent
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var pairingFlowContent: some View {
        switch pairState {
        case .idle:
            EmptyView()
        case .plugPrompt:
            pairStepView(icon: "cable.connector.horizontal", title: "CONNECT YOUR DEVICE",
                         subtitle: "Plug in your hardware wallet via USB", stepIndex: 0)
        case .detecting:
            pairStepView(icon: "magnifyingglass", title: "CONNECTING...",
                         subtitle: "Establishing secure connection", stepIndex: 1)
        case .found(let name):
            pairStepView(icon: "checkmark.circle", title: "DEVICE CONNECTED",
                         subtitle: name, stepIndex: 2)
        case .authenticating:
            pairStepView(icon: "lock.shield", title: "VERIFYING ADDRESS",
                         subtitle: "Deriving address from device", stepIndex: 3)
        case .paired(let name):
            pairStepView(icon: "link", title: "ACCOUNT SAVED",
                         subtitle: name, stepIndex: 4)
        case .error(let msg):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
                Text("PAIRING FAILED")
                    .font(.clashGroteskMedium(size: 13))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.75))
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                Button("Dismiss") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pairState = .idle
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func pairStepView(icon: String, title: String, subtitle: String, stepIndex: Int) -> some View {
        VStack(spacing: 10) {
            pairProgressDots(currentStep: stepIndex)

            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.5))

            Text(title)
                .font(.clashGroteskMedium(size: 13))
                .tracking(1)
                .foregroundColor(.white.opacity(0.75))

            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func pairProgressDots(currentStep: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { step in
                Circle()
                    .fill(.white.opacity(step <= currentStep ? 0.5 : 0.08))
                    .frame(width: step == currentStep ? 8 : 5, height: step == currentStep ? 8 : 5)
                if step < 4 {
                    Rectangle()
                        .fill(.white.opacity(step < currentStep ? 0.25 : 0.06))
                        .frame(width: 12, height: 1)
                }
            }
        }
    }

    // ── Discovered devices list ──
    private var discoveredDevicesList: some View {
        VStack(spacing: 10) {
            if !hwManager.discoveredDevices.isEmpty {
                sectionHeader("DISCOVERED DEVICES")
            }
            ForEach(hwManager.discoveredDevices) { device in
                discoveredDeviceCard(device)
            }
        }
    }

    private func discoveredDeviceCard(_ device: DiscoveredDevice) -> some View {
        let isConnected = hwManager.connectedWallets[device.id] != nil
        let isSelected = selectedDeviceId == device.id

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                deviceMiniIcon(manufacturer: device.deviceType.manufacturer)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name ?? device.deviceType.displayName)
                        .font(.clashGroteskMedium(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.white.opacity(isConnected ? 0.45 : 0.12))
                            .frame(width: 5, height: 5)
                        Text(isConnected ? "CONNECTED" : "AVAILABLE")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }

                Spacer()

                if !isConnected {
                    Button("CONNECT") {
                        beginPairing(device: device)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                    .buttonStyle(.plain)
                } else {
                    Button("DISCONNECT") {
                        Task {
                            try? await hwManager.disconnect(deviceId: device.id)
                        }
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                    .buttonStyle(.plain)
                }

                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedDeviceId = isSelected ? nil : device.id
                }
            }

            if isSelected {
                VStack(spacing: 12) {
                    Divider().background(.white.opacity(0.06))
                    deviceInfoRow(label: "TYPE", value: device.deviceType.displayName)
                    deviceInfoRow(label: "CONNECTION", value: device.connectionType.rawValue.uppercased())
                    deviceInfoRow(label: "MANUFACTURER", value: device.deviceType.manufacturer.rawValue.uppercased())

                    // Show accounts for this device type
                    let deviceAccounts = hwManager.savedAccounts.filter { $0.deviceType == device.deviceType }
                    if !deviceAccounts.isEmpty {
                        deviceInfoRow(label: "SAVED ACCOUNTS", value: "\(deviceAccounts.count)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isSelected ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(isSelected ? 0.10 : 0.05), lineWidth: 1)
                )
        )
    }

    // ── Saved accounts list ──
    private var savedAccountsList: some View {
        VStack(spacing: 10) {
            if !hwManager.savedAccounts.isEmpty {
                sectionHeader("SAVED ACCOUNTS")
            }
            ForEach(hwManager.savedAccounts) { account in
                savedAccountCard(account)
            }
        }
    }

    private func savedAccountCard(_ account: HardwareWalletAccount) -> some View {
        let isEditing = editingAccountId == account.id
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text(account.chain.rawValue.prefix(3).uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label ?? account.deviceType.displayName)
                        .font(.clashGroteskMedium(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                    Text(truncateAddress(account.address))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        if isEditing {
                            hwManager.updateAccountLabel(id: account.id, label: editLabel.isEmpty ? nil : editLabel)
                            editingAccountId = nil
                        } else {
                            editingAccountId = account.id
                            editLabel = account.label ?? ""
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)

                    Button {
                        accountToRemove = account.id
                        showRemoveConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isEditing {
                VStack(spacing: 8) {
                    Divider().background(.white.opacity(0.06))
                    HStack {
                        Text("LABEL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                        TextField("Account label", text: $editLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    deviceInfoRow(label: "PATH", value: account.derivationPath)
                    deviceInfoRow(label: "CHAIN", value: account.chain.rawValue.uppercased())
                    deviceInfoRow(label: "DEVICE", value: account.deviceType.displayName)

                    Button("VERIFY ON DEVICE") {
                        verifyAccount(account)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(isVerifyingAccount ? 0.3 : 0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                    .buttonStyle(.plain)
                    .disabled(isVerifyingAccount)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(isEditing ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(isEditing ? 0.08 : 0.04), lineWidth: 1)
                )
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – SIGNING TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var signingTabContent: some View {
        VStack(spacing: 18) {
            if hwManager.savedAccounts.isEmpty {
                noAccountsForSigning
            } else if signState == .idle || signState == .selectingAccount {
                signingIdleView
            } else {
                signingFlowView
            }
        }
    }

    private var noAccountsForSigning: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No saved accounts")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Text("Set up a device in the Devices tab first")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.15))

            Button("Go to Devices") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedTab = .devices
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 40)
    }

    private var signingIdleView: some View {
        VStack(spacing: 14) {
            sectionHeader("SIGN TRANSACTION")

            // Account picker
            VStack(alignment: .leading, spacing: 6) {
                Text("SIGNING ACCOUNT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))

                ForEach(hwManager.savedAccounts) { account in
                    accountPickerRow(account)
                }
            }

            if signSelectedAccount != nil {
                // Transaction fields
                VStack(spacing: 10) {
                    txField(label: "RECIPIENT", placeholder: "Address...", text: $signRecipient)
                    txField(label: "AMOUNT", placeholder: "0.0", text: $signAmount)
                }

                Button {
                    beginSigning()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "signature")
                            .font(.system(size: 12))
                        Text("SIGN WITH DEVICE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(signRecipient.isEmpty || signAmount.isEmpty ? 0.25 : 0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(signRecipient.isEmpty || signAmount.isEmpty)
            }
        }
    }

    private func accountPickerRow(_ account: HardwareWalletAccount) -> some View {
        let isSelected = signSelectedAccount?.id == account.id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                signSelectedAccount = account
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(.white.opacity(isSelected ? 0.5 : 0.08))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.label ?? account.deviceType.displayName)
                        .font(.clashGroteskMedium(size: 11))
                        .foregroundColor(.white.opacity(isSelected ? 0.8 : 0.5))
                    Text("\(account.chain.rawValue.uppercased()) · \(truncateAddress(account.address))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isSelected ? 0.06 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(isSelected ? 0.12 : 0.04), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func txField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            TextField(placeholder, text: text)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
    }

    // ── Signing flow visualization ──
    private var signingFlowView: some View {
        VStack(spacing: 16) {
            signingFlowStepContent
            signingFlowProgress
        }
    }

    @ViewBuilder
    private var signingFlowStepContent: some View {
        switch signState {
        case .preparing:
            signingStep(icon: "doc.text", title: "PREPARING TRANSACTION",
                        subtitle: "Building unsigned transaction...", step: 0)
        case .awaitingConfirm:
            signingStep(icon: "hand.tap", title: "CONFIRM ON DEVICE",
                        subtitle: signDeviceMessage.isEmpty ? "Review and approve on your hardware wallet" : signDeviceMessage,
                        step: 1)
        case .signing:
            signingStep(icon: "arrow.right.circle", title: "SIGNING",
                        subtitle: "Device is signing the transaction...", step: 2)
        case .complete(let sigHex):
            VStack(spacing: 14) {
                signingStep(icon: "checkmark.seal", title: "SIGNATURE RECEIVED",
                            subtitle: "Transaction signed successfully", step: 3)
                Text(String(sigHex.prefix(20)) + "...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Button("Done") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        signState = .idle
                        signRecipient = ""
                        signAmount = ""
                        signSelectedAccount = nil
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                .buttonStyle(.plain)
            }
        case .error(let msg):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.4))
                Text("SIGNING FAILED")
                    .font(.clashGroteskMedium(size: 14))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.75))
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Retry") {
                        beginSigning()
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            signState = .idle
                        }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        default:
            EmptyView()
        }
    }

    private func signingStep(icon: String, title: String, subtitle: String, step: Int) -> some View {
        VStack(spacing: 14) {
            signingDeviceVisual(step: step)

            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(step == 3 ? 0.6 : 0.4))

            Text(title)
                .font(.clashGroteskMedium(size: 14))
                .tracking(1)
                .foregroundColor(.white.opacity(0.8))

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func signingDeviceVisual(step: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.04))
                .frame(width: 50, height: 50)
                .overlay(
                    Text("H")
                        .font(.clashGroteskBold(size: 18))
                        .foregroundColor(.white.opacity(0.3))
                )
                .offset(x: -80)

            flowLine(step: step)

            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(step >= 1 ? 0.06 : 0.02))
                .frame(width: 60, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(step >= 1 ? 0.25 : 0.08), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(step >= 2 ? 0.5 : 0.15))
                )
                .offset(x: 80)
        }
        .frame(height: 60)
    }

    private func flowLine(step: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(width: 100, height: 1)

            if step >= 0 && step <= 2 {
                let progress = step == 0 ? signProgress : 1.0
                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 100 * progress, height: 1.5)
                    .offset(x: max(0, (1 - progress) * -50))
            }

            if step >= 3 {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 100, height: 1.5)
            }
        }
    }

    private var signingFlowProgress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { step in
                let current = signingCurrentStep
                Circle()
                    .fill(.white.opacity(step <= current ? 0.45 : 0.08))
                    .frame(width: step == current ? 8 : 5, height: step == current ? 8 : 5)
                if step < 3 {
                    Rectangle()
                        .fill(.white.opacity(step < current ? 0.25 : 0.06))
                        .frame(width: 20, height: 1)
                }
            }
        }
    }

    private var signingCurrentStep: Int {
        switch signState {
        case .preparing: return 0
        case .awaitingConfirm: return 1
        case .signing: return 2
        case .complete: return 3
        default: return -1
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – FIRMWARE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var firmwareTabContent: some View {
        VStack(spacing: 18) {
            if hwManager.connectedWallets.isEmpty && hwManager.discoveredDevices.isEmpty {
                noDevicesForFirmware
            } else {
                firmwareDeviceCards
                firmwareAdvisory
            }
        }
    }

    private var noDevicesForFirmware: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No devices connected")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Text("Connect a device to view firmware information")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(.vertical, 40)
    }

    private var firmwareDeviceCards: some View {
        VStack(spacing: 12) {
            sectionHeader("DEVICE FIRMWARE")
            ForEach(hwManager.discoveredDevices) { device in
                firmwareCard(device)
            }
        }
    }

    private func firmwareCard(_ device: DiscoveredDevice) -> some View {
        let isConnected = hwManager.connectedWallets[device.id] != nil
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                deviceMiniIcon(manufacturer: device.deviceType.manufacturer)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name ?? device.deviceType.displayName)
                        .font(.clashGroteskMedium(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(device.deviceType.displayName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(.white.opacity(isConnected ? 0.45 : 0.12))
                        .frame(width: 5, height: 5)
                    Text(isConnected ? "ONLINE" : "OFFLINE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Divider().background(.white.opacity(0.06))

            deviceInfoRow(label: "DEVICE TYPE", value: device.deviceType.displayName)
            deviceInfoRow(label: "CONNECTION", value: device.connectionType.rawValue.uppercased())
            deviceInfoRow(label: "USB SUPPORTED", value: device.deviceType.supportsUSB ? "YES" : "NO")
            deviceInfoRow(label: "BLUETOOTH", value: device.deviceType.supportsBluetooth ? "YES" : "NO")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var firmwareAdvisory: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                Text("FIRMWARE UPDATES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }

            Text("Firmware updates must be performed through the manufacturer's official software — Ledger Live for Ledger devices, Trezor Suite for Trezor devices. This ensures cryptographic verification of the firmware image.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – AIRGAP TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var airgapTabContent: some View {
        VStack(spacing: 18) {
            switch airGapStep {
            case .intro: airGapIntro
            case .selectChain: airGapChainSelector
            case .enterPayload: airGapPayloadEntry
            case .displayQR: airGapQRDisplay
            case .scanning: airGapScanView
            case .complete: airGapComplete
            case .error(let msg): airGapError(msg)
            }
        }
    }

    private var airGapIntro: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.2))

            Text("AIR-GAP SIGNING")
                .font(.clashGroteskMedium(size: 16))
                .tracking(2)
                .foregroundColor(.white.opacity(0.7))

            Text("Sign transactions using QR codes with a completely air-gapped device. No USB or Bluetooth connection required.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 10) {
                airGapFeatureRow(icon: "wifi.slash", title: "No Network", description: "Signing device stays completely offline")
                airGapFeatureRow(icon: "qrcode", title: "QR Transport", description: "Transaction data exchanged via QR codes")
                airGapFeatureRow(icon: "lock.shield", title: "Maximum Security", description: "Private keys never touch a networked device")
                airGapFeatureRow(icon: "arrow.triangle.2.circlepath", title: "Multi-Part QR", description: "Large transactions split into animated QR sequences")
            }
            .padding(.vertical, 8)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    airGapStep = .selectChain
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("START AIR-GAP SIGNING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func airGapFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.clashGroteskMedium(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                Text(description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    private var airGapChainSelector: some View {
        VStack(spacing: 14) {
            sectionHeader("SELECT CHAIN")

            ForEach(SupportedChain.allCases, id: \.self) { chain in
                Button {
                    airGapChain = chain
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .enterPayload
                    }
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.white.opacity(airGapChain == chain ? 0.5 : 0.08))
                            .frame(width: 8, height: 8)
                        Text(chain.rawValue.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(chain.defaultPath)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Button("Back") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    airGapStep = .intro
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .buttonStyle(.plain)
        }
    }

    private var airGapPayloadEntry: some View {
        VStack(spacing: 14) {
            sectionHeader("TRANSACTION PAYLOAD")

            Text("Paste the unsigned transaction hex or JSON payload below.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))

            TextEditor(text: $airGapPayload)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                        )
                )

            HStack(spacing: 10) {
                Button("Back") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .selectChain
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .buttonStyle(.plain)

                Spacer()

                Button {
                    generateAirGapQR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 10))
                        Text("GENERATE QR")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(airGapPayload.isEmpty ? 0.25 : 0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(airGapPayload.isEmpty)
            }
        }
    }

    private var airGapQRDisplay: some View {
        VStack(spacing: 14) {
            sectionHeader("SCAN WITH AIR-GAP DEVICE")

            Text("Show this QR code to your air-gapped signing device's camera.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            if let qrImage = generateQRImage(from: airGapQRData) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .cornerRadius(8)
            }

            Text("\(airGapChain.rawValue.uppercased()) · \(airGapPayload.count) bytes")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))

            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .enterPayload
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .scanning
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 10))
                        Text("SCAN RESPONSE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var airGapScanView: some View {
        VStack(spacing: 14) {
            sectionHeader("SCAN SIGNED RESPONSE")

            Text("Point your camera at the QR code displayed on your air-gapped device to capture the signature.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            // Camera placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.03))
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Camera scanning...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .displayQR
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        airGapStep = .complete
                    }
                } label: {
                    Text("SIMULATE SCAN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var airGapComplete: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.5))

            Text("AIR-GAP SIGNING COMPLETE")
                .font(.clashGroteskMedium(size: 14))
                .tracking(1)
                .foregroundColor(.white.opacity(0.8))

            Text("The signed transaction has been captured. You can now broadcast it to the network.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)

            Button("Done") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    airGapStep = .intro
                    airGapPayload = ""
                    airGapQRData = ""
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }

    private func airGapError(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.4))

            Text("AIR-GAP ERROR")
                .font(.clashGroteskMedium(size: 14))
                .tracking(1)
                .foregroundColor(.white.opacity(0.75))

            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    airGapStep = .enterPayload
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }

    private func deviceMiniIcon(manufacturer: HardwareWalletManufacturer) -> some View {
        ZStack {
            if manufacturer == .ledger {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                    .frame(width: 28, height: 16)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                    .frame(width: 20, height: 24)
            }
        }
    }

    private func deviceInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.92
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }

    private func handleBackToSettings() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.92
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
            onBackToSettings?()
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            silkPhase = 1.5
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            tetherPhase = 1.0
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            healthPulse = 0.85
        }
    }

    private func setupManagerCallbacks() {
        hwManager.onButtonConfirmationRequired = { [self] message in
            await MainActor.run {
                signDeviceMessage = message
            }
        }
    }

    // ── Pairing ──
    private func beginPairing(device: DiscoveredDevice) {
        pairingTask?.cancel()
        pairingTask = Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                pairState = .plugPrompt
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                pairState = .detecting
            }

            do {
                let wallet = try await hwManager.connect(to: device)
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    pairState = .found(device.name ?? device.deviceType.displayName)
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    pairState = .authenticating
                }

                // Derive default address for the device
                let chain: SupportedChain = .ethereum
                guard let path = DerivationPath(string: chain.defaultPath) else {
                    withAnimation { pairState = .error("Invalid derivation path") }
                    return
                }

                let addressResult = try await hwManager.getAddress(
                    deviceId: device.id, path: path, chain: chain, verify: true
                )

                guard !Task.isCancelled else { return }

                let account = HardwareWalletAccount(
                    deviceType: device.deviceType,
                    chain: chain,
                    derivationPath: chain.defaultPath,
                    address: addressResult.address,
                    publicKey: addressResult.publicKey?.map { String(format: "%02x", $0) }.joined() ?? "",
                    label: device.name ?? device.deviceType.displayName
                )
                hwManager.addAccount(account)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    pairState = .paired(addressResult.address)
                }

                AnalyticsService.shared.track(AnalyticsService.EventName.hwAddressVerified)

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    pairState = .idle
                }

            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    pairState = .error(error.localizedDescription)
                }
                AnalyticsService.shared.track(AnalyticsService.EventName.hwPairingFailed)
            }
        }
    }

    // ── Signing ──
    private func beginSigning() {
        guard let account = signSelectedAccount else { return }
        signingTask?.cancel()

        signingTask = Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                signState = .preparing
                signProgress = 0
            }

            AnalyticsService.shared.track(AnalyticsService.EventName.hwSigningRequested)

            do {
                // Connect to saved account
                let device = try await hwManager.connectToSavedAccount(account)
                guard !Task.isCancelled else { return }

                // Verify the account address
                guard let path = DerivationPath(string: account.derivationPath) else {
                    throw HWError.invalidPath(account.derivationPath)
                }

                let verifyResult = try await hwManager.verifySavedAccount(
                    deviceId: device.id,
                    account: account,
                    requestedChain: account.chain,
                    verifyOnDevice: false
                )
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    signState = .awaitingConfirm
                }

                // Build transaction data
                let txData = Data(signAmount.utf8) + Data(signRecipient.utf8)
                let transaction = HardwareWalletTransaction(
                    rawData: txData,
                    displayInfo: TransactionDisplayInfo(
                        type: "Send",
                        amount: signAmount,
                        recipient: signRecipient,
                        network: account.chain.rawValue
                    )
                )

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    signState = .signing
                }

                let result = try await hwManager.signTransaction(
                    deviceId: device.id, path: path, transaction: transaction, chain: account.chain
                )
                guard !Task.isCancelled else { return }

                let sigHex = result.signature.map { String(format: "%02x", $0) }.joined()

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    signState = .complete(sigHex)
                }

                AnalyticsService.shared.track(AnalyticsService.EventName.hwSigningConfirmed)

            } catch let hwError as HWError {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    signState = .error(hwError.localizedDescription)
                }
                if case .userRejected = hwError {
                    AnalyticsService.shared.track(AnalyticsService.EventName.hwSigningRejected)
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    signState = .error(error.localizedDescription)
                }
            }
        }
    }

    // ── Account verification ──
    private func verifyAccount(_ account: HardwareWalletAccount) {
        isVerifyingAccount = true
        Task {
            do {
                let device = try await hwManager.connectToSavedAccount(account)
                _ = try await hwManager.verifySavedAccount(
                    deviceId: device.id,
                    account: account,
                    requestedChain: account.chain,
                    verifyOnDevice: true
                )
                isVerifyingAccount = false
            } catch {
                isVerifyingAccount = false
            }
        }
    }

    // ── Air-Gap QR ──
    private func generateAirGapQR() {
        let payload: [String: String] = [
            "chain": airGapChain.rawValue,
            "type": "signTransaction",
            "payload": airGapPayload
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            airGapQRData = str
        } else {
            airGapQRData = airGapPayload
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            airGapStep = .displayQR
        }
    }

    private func generateQRImage(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    // ── Helpers ──
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "..." + String(address.suffix(4))
    }
}
'''

path = os.path.expanduser("/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/HardwareWalletOverlay.swift")
with open(path, 'w') as f:
    f.write(code)

print(f"Wrote {len(code)} bytes to {path}")
print(f"Line count: {code.count(chr(10)) + 1}")
