import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Passkey Auth Overlay
// Biometric passkey authentication configuration.
// Concentric scan rings, face-fill luminance, geometric device grid,
// draggable security threshold bar.
// Monumental. Monochrome. Biometric.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PasskeyAuthOverlay: View {
    @Binding var isPresented: Bool

    // ── Passkey state ──
    @State private var passkeyEnabled: Bool = true
    @State private var faceIdEnabled: Bool = true
    @State private var passkeys: [PasskeyDevice] = []

    // ── Security threshold ──
    @State private var thresholdUSD: Double = 500
    private let minThreshold: Double = 0
    private let maxThreshold: Double = 10000

    // ── Auth simulation ──
    @State private var isAuthenticating: Bool = false
    @State private var authProgress: CGFloat = 0
    @State private var authSuccess: Bool = false

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var ringExpansion: CGFloat = 0
    @State private var scanPulse: CGFloat = 0
    @State private var faceFill: CGFloat = 0
    @State private var glowPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var authButtonHovered: Bool = false
    @State private var addDeviceHovered: Bool = false

    // ── Threshold drag ──
    @State private var isDraggingThreshold: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            mainCard
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            loadDevices()
            startAnimations()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    biometricScanSection
                    enableToggleSection
                    securityThresholdSection
                    deviceGridSection
                    fallbackSection
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 450, height: 670)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("PASSKEY AUTH")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Spacer()
                closeButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var closeButton: some View {
        Button(action: dismissOverlay) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(closeHovered ? 0.9 : 0.4))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(closeHovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { closeHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Biometric Scan Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var biometricScanSection: some View {
        VStack(spacing: 16) {
            ZStack {
                concentricRings
                faceOutline
            }
            .frame(width: 160, height: 160)
            .onTapGesture { triggerAuth() }

            authStatusLabel
        }
    }

    private var concentricRings: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let delay = Double(i) * 0.15
                let baseSize: CGFloat = 60 + CGFloat(i) * 28
                let expanded = baseSize + ringExpansion * 20
                Circle()
                    .strokeBorder(
                        ringColor(index: i),
                        lineWidth: isAuthenticating ? 2.0 : 1.0
                    )
                    .frame(width: expanded, height: expanded)
                    .opacity(isAuthenticating ? (1.0 - Double(i) * 0.2) : 0.15 + Double(i) * 0.05)
                    .scaleEffect(isAuthenticating ? 1.0 + scanPulse * (0.03 + CGFloat(i) * 0.01) : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                            .delay(delay),
                        value: scanPulse
                    )
            }
        }
    }

    private func ringColor(index: Int) -> Color {
        if authSuccess {
            return .green.opacity(0.6 - Double(index) * 0.1)
        }
        if isAuthenticating {
            return .white.opacity(0.5 - Double(index) * 0.1)
        }
        return .white.opacity(0.12)
    }

    private var faceOutline: some View {
        ZStack {
            // Face outline path
            faceOutlinePath
                .stroke(
                    authSuccess ? Color.green.opacity(0.7) : Color.white.opacity(0.25),
                    lineWidth: 1.5
                )
                .frame(width: 52, height: 68)

            // Fill luminance overlay
            faceOutlinePath
                .fill(
                    LinearGradient(
                        colors: [
                            authSuccess ? Color.green.opacity(0.3 * faceFill) : Color.white.opacity(0.15 * faceFill),
                            authSuccess ? Color.green.opacity(0.1 * faceFill) : Color.white.opacity(0.05 * faceFill)
                        ],
                        startPoint: .bottom,
                        endPoint: UnitPoint(x: 0.5, y: 1.0 - faceFill)
                    )
                )
                .frame(width: 52, height: 68)

            // Scan line sweeping upward during auth
            if isAuthenticating {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 44, height: 2)
                    .offset(y: 34 - authProgress * 68)
            }
        }
    }

    private var faceOutlinePath: some Shape {
        RoundedRectangle(cornerRadius: 20)
    }

    private var authStatusLabel: some View {
        Group {
            if authSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green.opacity(0.8))
                    Text("AUTHENTICATED")
                        .font(.clashGroteskMedium(size: 11))
                        .tracking(2)
                        .foregroundColor(.green.opacity(0.8))
                }
            } else if isAuthenticating {
                Text("SCANNING...")
                    .font(.clashGroteskMedium(size: 11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("TAP TO AUTHENTICATE")
                    .font(.clashGroteskMedium(size: 11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Enable Toggle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var enableToggleSection: some View {
        VStack(spacing: 14) {
            toggleRow(
                icon: "faceid",
                label: "Face ID Signing",
                sublabel: "Authenticate transactions biometrically",
                isOn: $faceIdEnabled
            )
            toggleRow(
                icon: "key.fill",
                label: "Passkey Protection",
                sublabel: "Hardware-bound credential for all signing",
                isOn: $passkeyEnabled
            )
        }
    }

    private func toggleRow(icon: String, label: String, sublabel: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.clashGroteskMedium(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                Text(sublabel)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Security Threshold Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var securityThresholdSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "SECURITY THRESHOLD", icon: "shield.lefthalf.filled")

            thresholdDescription

            thresholdSliderBar

            thresholdLabels
        }
    }

    private var thresholdDescription: some View {
        Text("Transactions above this amount require biometric authentication")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.35))
    }

    private var thresholdSliderBar: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let fraction = CGFloat((thresholdUSD - minThreshold) / (maxThreshold - minThreshold))
            let handleX = fraction * trackWidth

            ZStack(alignment: .leading) {
                // Track background
                thresholdTrack

                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.10)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, handleX), height: 6)

                // Handle
                thresholdHandle(at: handleX)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingThreshold = true
                        let clamped = min(max(value.location.x, 0), trackWidth)
                        let frac = Double(clamped / trackWidth)
                        thresholdUSD = minThreshold + frac * (maxThreshold - minThreshold)
                        thresholdUSD = (thresholdUSD / 50).rounded() * 50 // snap to $50
                    }
                    .onEnded { _ in
                        isDraggingThreshold = false
                    }
            )
        }
        .frame(height: 32)
    }

    private var thresholdTrack: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white.opacity(0.08))
            .frame(height: 6)
    }

    private func thresholdHandle(at x: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(.white.opacity(isDraggingThreshold ? 0.5 : 0.25), lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .fill(.white.opacity(isDraggingThreshold ? 0.3 : 0.15))
                .frame(width: 8, height: 8)
        }
        .offset(x: x - 11)
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }

    private var thresholdLabels: some View {
        HStack {
            Text("$\(Int(thresholdUSD))")
                .font(.clashGroteskBold(size: 24))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(thresholdUSD >= maxThreshold ? "All transactions" : thresholdUSD <= 0 ? "Disabled" : "require auth")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Device Grid
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var deviceGridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "AUTHORIZED DEVICES", icon: "desktopcomputer")

            deviceGrid

            addDeviceButton
        }
    }

    private var deviceGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(passkeys) { device in
                deviceCard(device)
            }
        }
    }

    private func deviceCard(_ device: PasskeyDevice) -> some View {
        VStack(spacing: 8) {
            Image(systemName: device.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(device.isActive ? 0.8 : 0.25))

            Text(device.name)
                .font(.clashGroteskMedium(size: 12))
                .foregroundColor(.white.opacity(device.isActive ? 0.8 : 0.35))
                .lineLimit(1)

            HStack(spacing: 4) {
                Circle()
                    .fill(device.isActive ? Color.green.opacity(0.7) : .white.opacity(0.15))
                    .frame(width: 5, height: 5)
                Text(device.isActive ? "Active" : "Inactive")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(device.isActive ? 0.5 : 0.25))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(device.isActive ? 0.06 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            .white.opacity(device.isActive ? 0.10 : 0.04),
                            lineWidth: 1
                        )
                )
        )
    }

    private var addDeviceButton: some View {
        Button(action: registerNewDevice) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text("Register Device")
                    .font(.clashGroteskMedium(size: 12))
            }
            .foregroundColor(.white.opacity(addDeviceHovered ? 0.7 : 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        .white.opacity(addDeviceHovered ? 0.15 : 0.08),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { addDeviceHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Fallback Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "FALLBACK AUTH", icon: "arrow.counterclockwise")

            fallbackRow(
                icon: "icloud.fill",
                title: "iCloud Keychain",
                status: "Synced",
                statusColor: .green
            )
            fallbackRow(
                icon: "person.3.fill",
                title: "Social Recovery",
                status: "Not Set",
                statusColor: .orange
            )
            fallbackRow(
                icon: "lock.rectangle.stack.fill",
                title: "Hardware Key",
                status: "Available",
                statusColor: .green
            )
        }
    }

    private func fallbackRow(icon: String, title: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.04))
                )

            Text(title)
                .font(.clashGroteskMedium(size: 12))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor.opacity(0.6))
                    .frame(width: 5, height: 5)
                Text(status)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.03))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.clashGroteskMedium(size: 11))
                .tracking(2)
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func triggerAuth() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authProgress = 0
        faceFill = 0
        authSuccess = false

        // Animate scan line and face fill over 2 seconds
        withAnimation(.easeInOut(duration: 2.0)) {
            authProgress = 1.0
            faceFill = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    authSuccess = true
                    isAuthenticating = false
                }
            }
        }

        // Reset after showing success
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.5)) {
                    authSuccess = false
                    faceFill = 0
                    authProgress = 0
                }
            }
        }
    }

    private func registerNewDevice() {
        let names = ["iPad Pro", "MacBook Air", "Apple Watch", "Mac Studio"]
        let icons = ["ipad", "laptopcomputer", "applewatch", "desktopcomputer"]
        let idx = passkeys.count % names.count
        let device = PasskeyDevice(
            id: UUID().uuidString,
            name: names[idx],
            icon: icons[idx],
            isActive: true,
            createdAt: Date()
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            passkeys.append(device)
        }
    }

    private func loadDevices() {
        passkeys = [
            PasskeyDevice(id: "1", name: "MacBook Pro", icon: "laptopcomputer", isActive: true, createdAt: Date()),
            PasskeyDevice(id: "2", name: "iPhone 15", icon: "iphone", isActive: true, createdAt: Date().addingTimeInterval(-86400 * 7)),
            PasskeyDevice(id: "3", name: "iPad Mini", icon: "ipad", isActive: false, createdAt: Date().addingTimeInterval(-86400 * 30))
        ]
    }

    private func startAnimations() {
        // Continuous ring pulse
        withAnimation(
            .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
        ) {
            scanPulse = 1.0
        }

        // Gentle glow phase
        withAnimation(
            .linear(duration: 4.0)
                .repeatForever(autoreverses: false)
        ) {
            glowPhase = 1.0
        }

        // Subtle ring expansion
        withAnimation(
            .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
        ) {
            ringExpansion = 1.0
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Passkey Device Model
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PasskeyDevice: Identifiable {
    let id: String
    let name: String
    let icon: String
    let isActive: Bool
    let createdAt: Date
}
