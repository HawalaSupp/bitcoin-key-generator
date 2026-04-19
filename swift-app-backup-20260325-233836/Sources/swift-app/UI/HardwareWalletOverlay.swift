import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Hardware Wallet Overlay
// Physical security meets digital sovereignty.
// Geometric device representations with tangible depth,
// connection tethers, signature flow, firmware engravings.
// Monumental. Monochrome. Hardware-grade.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HardwareWalletOverlay: View {
    @Binding var isPresented: Bool

    // ── Tab ──
    @State private var selectedTab: HWTab = .devices

    enum HWTab: String, CaseIterable {
        case devices = "DEVICES"
        case signing = "SIGNING"
        case firmware = "FIRMWARE"
    }

    // ── Devices ──
    @State private var connectedDevices: [HWDevice] = []
    @State private var selectedDeviceId: String? = nil
    @State private var isScanning: Bool = false
    @State private var scanPulse: CGFloat = 0

    // ── Pairing flow ──
    @State private var pairState: PairState = .idle
    enum PairState: Equatable {
        case idle
        case plugPrompt
        case detecting
        case found(String)
        case authenticating
        case paired(String)
    }

    // ── Signing flow ──
    @State private var signState: SignState = .idle
    enum SignState: Equatable {
        case idle
        case preparing
        case sentToDevice
        case waitingConfirm
        case signatureReceived
    }
    @State private var signTx: HWSignTx? = nil
    @State private var signProgress: CGFloat = 0

    // ── Firmware ──
    @State private var fwUpdateState: FWState = .idle
    enum FWState: Equatable {
        case idle
        case downloading
        case installing(CGFloat)
        case complete
    }

    // ── Device health pulse ──
    @State private var healthPulse: CGFloat = 1.0

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var tetherPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var scanBtnHovered: Bool = false

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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            loadMockDevices()
            startAnimations()
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
        .frame(width: 460, height: 680)
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
                Spacer()
                Button(action: dismissOverlay) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.9 : 0.4))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(closeHovered ? 0.12 : 0.06)))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
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
                    .font(.clashGroteskMedium(size: 12))
                    .tracking(2)
                    .foregroundColor(.white.opacity(selectedTab == tab ? 0.8 : 0.3))
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selectedTab == tab ? 0.4 : 0))
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Devices Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var devicesTabContent: some View {
        VStack(spacing: 20) {
            deviceArcView
            scanButton
            if pairState != .idle { pairingFlow }
            deviceListSection
        }
    }

    // ── Device arc: geometric 3D-like device representations ──
    private var deviceArcView: some View {
        let devices = connectedDevices
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
            Text("No devices connected")
                .font(.clashGroteskMedium(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    // ── Single device geometric representation ──
    private func deviceGeometry(device: HWDevice, index: Int, total: Int) -> some View {
        let offsetX = deviceOffsetX(index: index, total: total)
        let tilt = deviceTilt(index: index, total: total)
        let isSelected = selectedDeviceId == device.id

        return VStack(spacing: 6) {
            deviceBody(device: device, isSelected: isSelected, tilt: tilt)
            deviceLabel(device: device)
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
    private func deviceBody(device: HWDevice, isSelected: Bool, tilt: Double) -> some View {
        let isHealthy = device.connectionHealth > 0.7
        let deviceOpacity = isHealthy ? (0.85 * healthPulse) : 0.35

        return ZStack {
            // Device chassis
            if device.manufacturer == .ledger {
                ledgerChassis(isSelected: isSelected, opacity: deviceOpacity)
            } else {
                trezorChassis(isSelected: isSelected, opacity: deviceOpacity)
            }

            // Firmware engraving
            firmwareEngraving(device: device)

            // Connection tether to wallet center
            if isSelected {
                tetherBeam
            }
        }
        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0))
    }

    private func ledgerChassis(isSelected: Bool, opacity: Double) -> some View {
        ZStack {
            // Main body — elongated rounded rectangle
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04 * opacity))
                .frame(width: 78, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.12), lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.4), radius: isSelected ? 12 : 6, y: 4)

            // Screen area
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

            // USB connector stub
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.06))
                .frame(width: 10, height: 6)
                .offset(x: 42)
        }
    }

    private func trezorChassis(isSelected: Bool, opacity: Double) -> some View {
        ZStack {
            // Main body — slightly wider, more squared
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04 * opacity))
                .frame(width: 56, height: 68)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.12), lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.4), radius: isSelected ? 12 : 6, y: 4)

            // Touchscreen area
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

            // USB at bottom
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.06))
                .frame(width: 8, height: 5)
                .offset(y: 35)
        }
    }

    private func firmwareEngraving(device: HWDevice) -> some View {
        Text("v\(device.firmwareVersion)")
            .font(.system(size: 6, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.15))
            .offset(y: device.manufacturer == .ledger ? 22 : 28)
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

    private func deviceLabel(device: HWDevice) -> some View {
        VStack(spacing: 2) {
            Text(device.name)
                .font(.clashGroteskMedium(size: 11))
                .foregroundColor(.white.opacity(0.65))
            Text(device.connectionLabel)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // ── Scan button ──
    private var scanButton: some View {
        Button {
            beginScan()
        } label: {
            HStack(spacing: 6) {
                if isScanning {
                    scanPulseIndicator
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                }
                Text(isScanning ? "SCANNING..." : "SCAN FOR DEVICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(isScanning ? 0.4 : (scanBtnHovered ? 0.7 : 0.5)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isScanning ? 0.03 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(isScanning ? 0.05 : 0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { scanBtnHovered = $0 }
        .disabled(isScanning)
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
            pairStepView(icon: "magnifyingglass", title: "DETECTING...",
                         subtitle: "Searching for connected devices", stepIndex: 1)
        case .found(let name):
            pairStepView(icon: "checkmark.circle", title: "DEVICE FOUND",
                         subtitle: name, stepIndex: 2)
        case .authenticating:
            pairStepView(icon: "lock.shield", title: "AUTHENTICATE",
                         subtitle: "Enter PIN on your device", stepIndex: 3)
        case .paired(let name):
            pairStepView(icon: "link", title: "PAIRED SECURELY",
                         subtitle: name, stepIndex: 4)
        }
    }

    private func pairStepView(icon: String, title: String, subtitle: String, stepIndex: Int) -> some View {
        VStack(spacing: 10) {
            // Progress dots
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
            pairDot(step: 0, current: currentStep)
            pairDotConnector(completed: currentStep > 0)
            pairDot(step: 1, current: currentStep)
            pairDotConnector(completed: currentStep > 1)
            pairDot(step: 2, current: currentStep)
            pairDotConnector(completed: currentStep > 2)
            pairDot(step: 3, current: currentStep)
            pairDotConnector(completed: currentStep > 3)
            pairDot(step: 4, current: currentStep)
        }
    }

    private func pairDot(step: Int, current: Int) -> some View {
        Circle()
            .fill(.white.opacity(step <= current ? 0.5 : 0.08))
            .frame(width: step == current ? 8 : 5, height: step == current ? 8 : 5)
    }

    private func pairDotConnector(completed: Bool) -> some View {
        Rectangle()
            .fill(.white.opacity(completed ? 0.25 : 0.06))
            .frame(width: 12, height: 1)
    }

    // ── Device list (expanded details for selected) ──
    private var deviceListSection: some View {
        VStack(spacing: 10) {
            if !connectedDevices.isEmpty {
                sectionHeader("CONNECTED")
            }
            ForEach(connectedDevices) { device in
                deviceDetailCard(device)
            }
        }
    }

    private func deviceDetailCard(_ device: HWDevice) -> some View {
        let isSelected = selectedDeviceId == device.id
        return VStack(spacing: 0) {
            deviceDetailHeader(device, isSelected: isSelected)
            if isSelected {
                deviceDetailExpanded(device)
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

    private func deviceDetailHeader(_ device: HWDevice, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Mini device icon
            deviceMiniIcon(device)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.clashGroteskMedium(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                HStack(spacing: 4) {
                    connectionDot(health: device.connectionHealth)
                    Text(device.statusLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

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
    }

    private func deviceMiniIcon(_ device: HWDevice) -> some View {
        ZStack {
            if device.manufacturer == .ledger {
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

    private func connectionDot(health: Double) -> some View {
        Circle()
            .fill(.white.opacity(health > 0.7 ? 0.45 : (health > 0.3 ? 0.20 : 0.08)))
            .frame(width: 5, height: 5)
    }

    private func deviceDetailExpanded(_ device: HWDevice) -> some View {
        VStack(spacing: 12) {
            Divider().background(.white.opacity(0.06))
            deviceInfoRow(label: "MODEL", value: device.modelName)
            deviceInfoRow(label: "FIRMWARE", value: "v\(device.firmwareVersion)")
            deviceInfoRow(label: "CONNECTION", value: device.connectionType.uppercased())
            if let battery = device.batteryLevel {
                deviceBatteryRow(level: battery)
            }
            deviceInfoRow(label: "ACCOUNTS", value: "\(device.importedAccounts)")

            HStack(spacing: 10) {
                importAccountsBtn(device)
                disconnectBtn(device)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
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

    private func deviceBatteryRow(level: Int) -> some View {
        HStack {
            Text("BATTERY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            HStack(spacing: 4) {
                batteryBar(level: level)
                Text("\(level)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private func batteryBar(level: Int) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.06))
                .frame(width: 30, height: 6)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.30))
                .frame(width: 30 * CGFloat(level) / 100.0, height: 6)
        }
    }

    private func importAccountsBtn(_ device: HWDevice) -> some View {
        Button {
            // mock import
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 10))
                Text("IMPORT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func disconnectBtn(_ device: HWDevice) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                connectedDevices.removeAll { $0.id == device.id }
                if selectedDeviceId == device.id { selectedDeviceId = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eject")
                    .font(.system(size: 10))
                Text("EJECT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Signing Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var signingTabContent: some View {
        VStack(spacing: 18) {
            if connectedDevices.isEmpty {
                noDeviceForSigning
            } else if signState == .idle {
                signingIdleView
            } else {
                signingFlowView
            }
        }
    }

    private var noDeviceForSigning: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("Connect a device to sign")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Text("Switch to Devices tab to pair")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(.vertical, 40)
    }

    // ── Idle: show mock pending tx ──
    private var signingIdleView: some View {
        VStack(spacing: 14) {
            sectionHeader("PENDING SIGNATURE REQUEST")

            mockTxCard

            Button {
                beginSigningFlow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .font(.system(size: 12))
                    Text("SIGN WITH HARDWARE WALLET")
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

    private var mockTxCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEND")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Text("0.25 BTC")
                        .font(.clashGroteskBold(size: 20))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FEE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Text("0.00012 BTC")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            HStack {
                Text("TO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Text("bc1q...f5mdq")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // ── Signing flow steps ──
    private var signingFlowView: some View {
        VStack(spacing: 16) {
            signingFlowStepContent
            signingFlowProgress
        }
    }

    @ViewBuilder
    private var signingFlowStepContent: some View {
        switch signState {
        case .idle:
            EmptyView()
        case .preparing:
            signingStep(icon: "doc.text", title: "PREPARING TRANSACTION",
                        subtitle: "Building unsigned transaction...", step: 0)
        case .sentToDevice:
            signingStep(icon: "arrow.right.circle", title: "SENT TO DEVICE",
                        subtitle: "Review transaction on your hardware wallet", step: 1)
        case .waitingConfirm:
            signingStep(icon: "hand.tap", title: "CONFIRM ON DEVICE",
                        subtitle: "Press the button on your hardware wallet to approve", step: 2)
        case .signatureReceived:
            signingStep(icon: "checkmark.seal", title: "SIGNATURE RECEIVED",
                        subtitle: "Transaction signed successfully", step: 3)
        }
    }

    private func signingStep(icon: String, title: String, subtitle: String, step: Int) -> some View {
        VStack(spacing: 14) {
            // Device visual with flow
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

    // ── Device visual during signing: tx flows to device, signature flows back ──
    private func signingDeviceVisual(step: Int) -> some View {
        ZStack {
            // HAWALA side
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.04))
                .frame(width: 50, height: 50)
                .overlay(
                    Text("H")
                        .font(.clashGroteskBold(size: 18))
                        .foregroundColor(.white.opacity(0.3))
                )
                .offset(x: -80)

            // Flow line
            flowLine(step: step)

            // Hardware device side
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
            // Base line
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(width: 100, height: 1)

            // Tx flowing to device (step 0-1)
            if step >= 0 && step <= 2 {
                let progress = step == 0 ? signProgress : 1.0
                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 100 * progress, height: 1.5)
                    .offset(x: max(0, (1 - progress) * -50))
            }

            // Signature flowing back (step 3)
            if step >= 3 {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 100 * signProgress, height: 1.5)
            }
        }
    }

    private var signingFlowProgress: some View {
        HStack(spacing: 6) {
            signingDot(step: 0)
            signingConnector(done: signState != .preparing)
            signingDot(step: 1)
            signingConnector(done: signState == .waitingConfirm || signState == .signatureReceived)
            signingDot(step: 2)
            signingConnector(done: signState == .signatureReceived)
            signingDot(step: 3)
        }
    }

    private func signingDot(step: Int) -> some View {
        let current: Int
        switch signState {
        case .preparing: current = 0
        case .sentToDevice: current = 1
        case .waitingConfirm: current = 2
        case .signatureReceived: current = 3
        default: current = -1
        }
        let isActive = step <= current
        let isCurrent = step == current
        return Circle()
            .fill(.white.opacity(isActive ? 0.45 : 0.08))
            .frame(width: isCurrent ? 8 : 5, height: isCurrent ? 8 : 5)
    }

    private func signingConnector(done: Bool) -> some View {
        Rectangle()
            .fill(.white.opacity(done ? 0.25 : 0.06))
            .frame(width: 20, height: 1)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Firmware Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var firmwareTabContent: some View {
        VStack(spacing: 16) {
            if connectedDevices.isEmpty {
                noDeviceForFirmware
            } else {
                ForEach(connectedDevices) { device in
                    firmwareCard(device)
                }
            }
        }
    }

    private var noDeviceForFirmware: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No devices connected")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    private func firmwareCard(_ device: HWDevice) -> some View {
        VStack(spacing: 14) {
            firmwareCardHeader(device)
            firmwareVersionRow(device)

            if device.hasUpdate {
                firmwareUpdateSection(device)
            } else {
                firmwareUpToDate
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func firmwareCardHeader(_ device: HWDevice) -> some View {
        HStack(spacing: 10) {
            deviceMiniIcon(device)
            Text(device.name)
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.75))
            Spacer()
            if device.hasUpdate {
                updateBadge
            }
        }
    }

    private var updateBadge: some View {
        Text("UPDATE")
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(.white.opacity(0.08))
            )
    }

    private func firmwareVersionRow(_ device: HWDevice) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("CURRENT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Text("v\(device.firmwareVersion)")
                    .font(.clashGroteskMedium(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            if device.hasUpdate {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))

                VStack(spacing: 2) {
                    Text("AVAILABLE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Text("v\(device.latestFirmware)")
                        .font(.clashGroteskMedium(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var firmwareUpToDate: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
            Text("Firmware is up to date")
                .font(.system(size: 10))
        }
        .foregroundColor(.white.opacity(0.35))
    }

    private func firmwareUpdateSection(_ device: HWDevice) -> some View {
        VStack(spacing: 10) {
            // Update info
            HStack {
                Text("SIZE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(device.updateSize)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            HStack {
                Text("EST. TIME")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(device.updateTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            firmwareUpdateAction(device)
        }
    }

    @ViewBuilder
    private func firmwareUpdateAction(_ device: HWDevice) -> some View {
        switch fwUpdateState {
        case .idle:
            firmwareInstallButton
        case .downloading:
            firmwareProgressView(label: "DOWNLOADING...", progress: nil)
        case .installing(let pct):
            firmwareProgressView(label: "INSTALLING...", progress: pct)
        case .complete:
            firmwareCompleteView
        }
    }

    private var firmwareInstallButton: some View {
        VStack(spacing: 6) {
            // Warning
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 8))
                Text("Do not disconnect device during update")
                    .font(.system(size: 8))
            }
            .foregroundColor(.white.opacity(0.25))

            Button {
                beginFirmwareUpdate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                    Text("INSTALL UPDATE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func firmwareProgressView(label: String, progress: CGFloat?) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            // Geometric fill bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                    if let pct = progress {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.25))
                            .frame(width: geo.size.width * pct)
                    } else {
                        // Indeterminate shimmer
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.0), .white.opacity(0.15), .white.opacity(0.0)],
                                    startPoint: UnitPoint(x: silkPhase - 0.2, y: 0.5),
                                    endPoint: UnitPoint(x: silkPhase + 0.2, y: 0.5)
                                )
                            )
                    }
                }
            }
            .frame(height: 6)

            if let pct = progress {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Warning reminder
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 8))
                Text("Keep device connected")
                    .font(.system(size: 8))
            }
            .foregroundColor(.white.opacity(0.20))
        }
    }

    private var firmwareCompleteView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.5))
            Text("UPDATE COMPLETE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 6)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func beginScan() {
        guard !isScanning else { return }
        isScanning = true

        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            scanPulse = 1
        }

        // Simulate pair flow
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pairState = .plugPrompt
        }

        scheduleAfter(1.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pairState = .detecting
            }
        }
        scheduleAfter(2.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pairState = .found("Ledger Nano X")
            }
        }
        scheduleAfter(3.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pairState = .authenticating
            }
        }
        scheduleAfter(5.0) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    pairState = .paired("Ledger Nano X")
                    isScanning = false
                    scanPulse = 0
                }
            }
        }
        scheduleAfter(6.5) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    pairState = .idle
                }
            }
        }
    }

    private func beginSigningFlow() {
        signProgress = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            signState = .preparing
        }
        withAnimation(.easeInOut(duration: 1.5)) {
            signProgress = 1.0
        }

        scheduleAfter(1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                signState = .sentToDevice
            }
        }
        scheduleAfter(2.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                signState = .waitingConfirm
            }
        }
        scheduleAfter(5.0) {
            DispatchQueue.main.async {
                signProgress = 0
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    signState = .signatureReceived
                }
                withAnimation(.easeInOut(duration: 0.8)) {
                    signProgress = 1.0
                }
            }
        }
        scheduleAfter(8.0) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    signState = .idle
                }
            }
        }
    }

    private func beginFirmwareUpdate() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            fwUpdateState = .downloading
        }

        scheduleAfter(2.0) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    fwUpdateState = .installing(0.0)
                }
                animateFirmwareProgress(from: 0.0)
            }
        }
    }

    private func animateFirmwareProgress(from current: CGFloat) {
        guard current < 1.0 else {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    fwUpdateState = .complete
                }
            }
            // Update device firmware version
            scheduleAfter(0.3) {
                DispatchQueue.main.async {
                    for i in connectedDevices.indices {
                        if connectedDevices[i].hasUpdate {
                            connectedDevices[i].firmwareVersion = connectedDevices[i].latestFirmware
                            connectedDevices[i].hasUpdate = false
                        }
                    }
                }
            }
            return
        }
        let next = min(current + 0.08, 1.0)
        scheduleAfter(0.15) {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.12)) {
                    fwUpdateState = .installing(next)
                }
                animateFirmwareProgress(from: next)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockDevices() {
        connectedDevices = [
            HWDevice(
                id: "ledger-1",
                name: "Ledger Nano X",
                modelName: "Nano X",
                manufacturer: .ledger,
                firmwareVersion: "2.2.3",
                latestFirmware: "2.3.0",
                hasUpdate: true,
                updateSize: "1.8 MB",
                updateTime: "~3 min",
                connectionType: "Bluetooth",
                connectionHealth: 0.95,
                batteryLevel: 72,
                importedAccounts: 3
            ),
            HWDevice(
                id: "trezor-1",
                name: "Trezor Model T",
                modelName: "Model T",
                manufacturer: .trezor,
                firmwareVersion: "2.6.4",
                latestFirmware: "2.6.4",
                hasUpdate: false,
                updateSize: "",
                updateTime: "",
                connectionType: "USB",
                connectionHealth: 1.0,
                batteryLevel: nil,
                importedAccounts: 1
            )
        ]
        selectedDeviceId = "ledger-1"
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            silkPhase = 1.5
        }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            tetherPhase = 1.0
        }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            healthPulse = 0.92
        }
    }

    private func scheduleAfter(_ seconds: Double, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HWDevice: Identifiable {
    let id: String
    let name: String
    let modelName: String
    let manufacturer: HWManufacturer
    var firmwareVersion: String
    let latestFirmware: String
    var hasUpdate: Bool
    let updateSize: String
    let updateTime: String
    let connectionType: String
    let connectionHealth: Double
    let batteryLevel: Int?
    let importedAccounts: Int

    var statusLabel: String {
        if connectionHealth > 0.7 { return "CONNECTED" }
        if connectionHealth > 0.3 { return "WEAK" }
        return "UNSTABLE"
    }

    var connectionLabel: String {
        connectionType.uppercased()
    }

    enum HWManufacturer {
        case ledger, trezor
    }
}

struct HWSignTx {
    let amount: String
    let recipient: String
    let fee: String
}
