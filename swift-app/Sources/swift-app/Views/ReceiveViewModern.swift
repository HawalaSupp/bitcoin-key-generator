import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Bitcoin Address Derivation

/// Derives legacy (P2PKH) and wrapped SegWit (P2SH-P2WPKH) addresses from a compressed public key hex.
enum BitcoinAddressDerivation {
    
    /// Derive a P2PKH legacy address (1...) from compressed public key hex
    static func legacyAddress(publicKeyHex: String, testnet: Bool = false) -> String? {
        guard let pubKeyData = Data(hexString: publicKeyHex), pubKeyData.count == 33 else { return nil }
        let h160 = hash160(pubKeyData)
        let version: UInt8 = testnet ? 0x6F : 0x00
        return base58CheckEncode(version: version, payload: h160)
    }
    
    /// Derive a P2SH-P2WPKH wrapped SegWit address (3...) from compressed public key hex
    static func wrappedSegwitAddress(publicKeyHex: String, testnet: Bool = false) -> String? {
        guard let pubKeyData = Data(hexString: publicKeyHex), pubKeyData.count == 33 else { return nil }
        let h160 = hash160(pubKeyData)
        // Witness script: OP_0 (0x00) + PUSH20 (0x14) + hash160
        var witnessScript = Data([0x00, 0x14])
        witnessScript.append(h160)
        let scriptHash = hash160(witnessScript)
        let version: UInt8 = testnet ? 0xC4 : 0x05
        return base58CheckEncode(version: version, payload: scriptHash)
    }
    
    /// HASH160 = RIPEMD160(SHA256(data))
    private static func hash160(_ data: Data) -> Data {
        let sha = Data(SHA256.hash(data: data))
        return ripemd160(sha)
    }
    
    /// Base58Check encode: version + payload + 4-byte checksum
    private static func base58CheckEncode(version: UInt8, payload: Data) -> String {
        var versionedPayload = Data([version])
        versionedPayload.append(payload)
        let checksum = doubleSHA256(versionedPayload).prefix(4)
        versionedPayload.append(checksum)
        return base58Encode(versionedPayload)
    }
    
    private static func doubleSHA256(_ data: Data) -> Data {
        Data(SHA256.hash(data: Data(SHA256.hash(data: data))))
    }
    
    private static func base58Encode(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        
        // Count leading zeros
        let leadingZeros = data.prefix(while: { $0 == 0 }).count
        
        // Convert to base58
        let num = data.reduce(into: [UInt32]()) { result, byte in
            var carry = UInt32(byte)
            for i in 0..<result.count {
                carry += result[i] << 8
                result[i] = carry % 58
                carry /= 58
            }
            while carry > 0 {
                result.append(carry % 58)
                carry /= 58
            }
        }
        
        // Build string
        let prefix = String(repeating: "1", count: leadingZeros)
        let encoded = num.reversed().map { alphabet[Int($0)] }
        return prefix + String(encoded)
    }
    
    // MARK: - RIPEMD-160
    
    private static func ripemd160(_ data: Data) -> Data {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xc3d2e1f0
        
        var message = data
        let originalLength = UInt64(data.count * 8)
        message.append(0x80)
        while (message.count % 64) != 56 { message.append(0x00) }
        var len = originalLength
        message.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
        
        let rl: [Int] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
                         7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
                         3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
                         1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
                         4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13]
        let rr: [Int] = [5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
                         6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
                         15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
                         8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
                         12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11]
        let sl: [UInt32] = [11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
                            7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
                            11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
                            11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
                            9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6]
        let sr: [UInt32] = [8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
                            9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
                            9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
                            15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
                            8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11]
        let kl: [UInt32] = [0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]
        let kr: [UInt32] = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000]
        
        func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            switch j / 16 {
            case 0: return x ^ y ^ z
            case 1: return (x & y) | (~x & z)
            case 2: return (x | ~y) ^ z
            case 3: return (x & z) | (y & ~z)
            case 4: return x ^ (y | ~z)
            default: return 0
            }
        }
        
        for blockStart in stride(from: 0, to: message.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let o = blockStart + i * 4
                x[i] = UInt32(message[o]) | (UInt32(message[o+1]) << 8) |
                        (UInt32(message[o+2]) << 16) | (UInt32(message[o+3]) << 24)
            }
            
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4
            
            for j in 0..<80 {
                let round = j / 16
                var tl = al &+ f(j, bl, cl, dl) &+ x[rl[j]] &+ kl[round]
                tl = (tl << sl[j] | tl >> (32 - sl[j])) &+ el
                al = el; el = dl; dl = cl << 10 | cl >> 22; cl = bl; bl = tl
                
                let rj = 79 - j
                let rRound = rj / 16
                var tr = ar &+ f(rj, br, cr, dr) &+ x[rr[j]] &+ kr[rRound]
                tr = (tr << sr[j] | tr >> (32 - sr[j])) &+ er
                ar = er; er = dr; dr = cr << 10 | cr >> 22; cr = br; br = tr
            }
            
            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er; h2 = h3 &+ el &+ ar; h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr; h0 = t
        }
        
        var result = Data(count: 20)
        for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
            result[i*4] = UInt8(h & 0xff)
            result[i*4+1] = UInt8((h >> 8) & 0xff)
            result[i*4+2] = UInt8((h >> 16) & 0xff)
            result[i*4+3] = UInt8((h >> 24) & 0xff)
        }
        return result
    }
}

// MARK: - Bitcoin Address Format
enum BitcoinAddressFormat: String, CaseIterable, Identifiable {
    case nativeSegwit = "Native SegWit"
    case segwit = "SegWit"
    case legacy = "Legacy"
    
    var id: String { rawValue }
    
    var prefix: String {
        switch self {
        case .nativeSegwit: return "bc1"
        case .segwit: return "3"
        case .legacy: return "1"
        }
    }
    
    var description: String {
        switch self {
        case .nativeSegwit: return "Lowest fees (bc1...)"
        case .segwit: return "Compatible (3...)"
        case .legacy: return "Universal (1...)"
        }
    }
    
    var icon: String {
        switch self {
        case .nativeSegwit: return "bolt.fill"
        case .segwit: return "shield.checkered"
        case .legacy: return "clock.fill"
        }
    }
}

// MARK: - Modern Receive View

struct ReceiveViewModern: View {
    @Environment(\.dismiss) private var envDismiss
    
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    var onDismiss: (() -> Void)? = nil
    
    /// Unified dismiss: prefers overlay callback, falls back to sheet environment
    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            envDismiss()
        }
    }
    
    @State private var selectedChain: ChainInfo?
    @State private var requestAmount: String = ""
    @State private var requestAmountUSD: String = ""
    @State private var memo: String = ""
    @State private var showCopiedToast = false
    @State private var copiedText = ""
    @State private var appearAnimation = false
    @State private var selectedAddressFormat: BitcoinAddressFormat = .nativeSegwit
    @State private var showAddressVerification = false
    @State private var verificationStep = 0
    @State private var verificationFailed = false
    @State private var isAmountInUSD = false
    @State private var qrAnimationScale: CGFloat = 1.0
    @State private var cardScale: CGFloat = 0.92
    @State private var contentOpacity: Double = 0
    
    /// Whether the chain was pre-selected from a crypto card
    private var chainPreSelected: Bool
    
    // Price for USD conversion (would come from price service in real app)
    private let btcPrice: Double = 42500.0
    private let ethPrice: Double = 2250.0
    private let ltcPrice: Double = 72.0
    
    init(chains: [ChainInfo], initialChain: ChainInfo? = nil, onCopy: @escaping (String) -> Void, onDismiss: (() -> Void)? = nil) {
        self.chains = chains
        self.onCopy = onCopy
        self.onDismiss = onDismiss
        self.chainPreSelected = initialChain != nil
        // Use provided chain or default to first chain with an address
        if let initial = initialChain {
            _selectedChain = State(initialValue: initial)
        } else {
            _selectedChain = State(initialValue: chains.first(where: { $0.receiveAddress != nil }))
        }
    }
    
    @ObservedObject private var passcodeManager = PasscodeManager.shared
    @State private var requiresUnlock = false
    
    /// The address to display based on selected chain and address format.
    /// For Bitcoin, derives legacy/wrapped-segwit variants from the public key.
    private var currentDisplayAddress: String? {
        guard let chain = selectedChain, let baseAddr = chain.receiveAddress else { return nil }
        
        // Only derive alternate formats for Bitcoin chains
        guard chain.id.lowercased().contains("bitcoin") else { return baseAddr }
        
        let isTestnet = chain.id.lowercased().contains("testnet")
        
        switch selectedAddressFormat {
        case .nativeSegwit:
            return baseAddr // Already native segwit (bc1q...)
        case .segwit:
            if let pubHex = chain.publicKeyHex {
                return BitcoinAddressDerivation.wrappedSegwitAddress(publicKeyHex: pubHex, testnet: isTestnet) ?? baseAddr
            }
            return baseAddr
        case .legacy:
            if let pubHex = chain.publicKeyHex {
                return BitcoinAddressDerivation.legacyAddress(publicKeyHex: pubHex, testnet: isTestnet) ?? baseAddr
            }
            return baseAddr
        }
    }
    
    var body: some View {
        ZStack {
            // Background — matching settings colorway
            Color(red: 0.06, green: 0.06, blue: 0.07)
            
            // ROADMAP-06 E8: Gate receive view when wallet is locked
            if passcodeManager.isLocked {
                walletLockedOverlay
            } else {
            VStack(spacing: 0) {
                // Header
                receiveHeader
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Chain Selector (only if not pre-selected from crypto card)
                        if !chainPreSelected {
                            chainSelectorSection
                        }
                        
                        // Address Format Selector (Bitcoin only)
                        if let chain = selectedChain, chain.id.lowercased().contains("bitcoin") {
                            addressFormatSection
                        }
                        
                        // QR Code Display
                        if let chain = selectedChain, let address = currentDisplayAddress {
                            qrCodeSection(chain: chain, address: address)
                            
                            // Address Display with Verify
                            addressSection(address: address)
                            
                            // Request Amount with USD toggle
                            requestAmountSection(chain: chain)
                            
                            // Action Buttons
                            actionButtonsSection(chain: chain, address: address)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .opacity(contentOpacity)
            
            // Copied Toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    copiedToastView
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Address Verification Overlay
            if showAddressVerification {
                addressVerificationOverlay
            }
            } // end else (wallet not locked)
        }
        .frame(width: 680, height: 700)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
        .scaleEffect(cardScale)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                appearAnimation = true
                cardScale = 1
                contentOpacity = 1
            }
        }
    }
    
    // MARK: - Wallet Locked Overlay (ROADMAP-06 E8)
    
    private var walletLockedOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(Color.orange.opacity(0.8))
            
            Text("Wallet Locked")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)
            
            Text("Unlock your wallet to view receive addresses.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                Task {
                    let context = LAContext()
                    do {
                        let success = try await context.evaluatePolicy(
                            .deviceOwnerAuthentication,
                            localizedReason: "Unlock wallet to view receive address"
                        )
                        if success {
                            await MainActor.run { passcodeManager.unlock() }
                        }
                    } catch {
                        #if DEBUG
                        print("[ReceiveView] Biometric unlock failed: \\(error)")
                        #endif
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                    Text("Unlock")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                .frame(maxWidth: 200)
                .frame(height: 48)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button("Cancel") { dismiss() }
                .foregroundColor(Color.white.opacity(0.4))
                .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Header
    
    /// Clean crypto name for the title
    private var cryptoName: String {
        guard let chain = selectedChain else { return "" }
        let id = chain.id.lowercased()
        if id.contains("bitcoin") { return "Bitcoin" }
        if id.contains("ethereum") { return "Ethereum" }
        if id.contains("litecoin") { return "Litecoin" }
        if id.contains("solana") { return "Solana" }
        if id.contains("xrp") { return "XRP" }
        if id.contains("monero") { return "Monero" }
        if id.contains("polygon") { return "Polygon" }
        if id.contains("bnb") || id.contains("bsc") { return "BNB" }
        if id.contains("arbitrum") { return "Arbitrum" }
        if id.contains("optimism") { return "Optimism" }
        if id.contains("base") { return "Base" }
        if id.contains("avalanche") { return "Avalanche" }
        return chain.title
    }
    
    private var receiveHeader: some View {
        ZStack {
            // Centered title
            Text(chainPreSelected ? "Receive \(cryptoName)" : "Receive")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)
            
            // Close button — right aligned
            HStack {
                Spacer()
                Button(action: { dismissAnimated() }) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss receive view")
                .accessibilityIdentifier("receive_close_button")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    /// Animated dismiss with scale-down
    private func dismissAnimated() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            contentOpacity = 0
            cardScale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dismiss()
        }
    }
    
    // MARK: - Chain Selector
    
    private var chainSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NETWORK")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
                .tracking(1)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chains.filter { $0.receiveAddress != nil }) { chain in
                        ReceiveChainPill(
                            chain: chain,
                            isSelected: selectedChain?.id == chain.id,
                            action: { 
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    selectedChain = chain
                                    requestAmount = ""
                                    requestAmountUSD = ""
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    qrAnimationScale = 0.9
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                                    qrAnimationScale = 1.0
                                }
                            }
                        )
                    }
                }
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
    }
    
    // MARK: - Address Format Section (Bitcoin)
    
    private var addressFormatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADDRESS FORMAT")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
                .tracking(1)
            
            HStack(spacing: 8) {
                ForEach(BitcoinAddressFormat.allCases) { format in
                    AddressFormatPill(
                        format: format,
                        isSelected: selectedAddressFormat == format,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedAddressFormat = format
                            }
                            // QR bounce feedback
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                qrAnimationScale = 0.9
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                                qrAnimationScale = 1.0
                            }
                        }
                    )
                }
            }
            
            // Info text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(selectedAddressFormat.description)
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.white.opacity(0.4))
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.05), value: appearAnimation)
    }
    
    // MARK: - QR Code Section
    
    private func qrCodeSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: 16) {
            // QR Code with Hawala Logo — clean centered design
            ZStack {
                // Subtle glow behind QR
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 280, height: 280)
                    .blur(radius: 30)
                
                // White background for QR
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
                    .frame(width: 260, height: 260)
                
                // QR Code with embedded Hawala logo
                QRCodeView(content: generatePaymentURI(chain: chain, address: address), size: 240, showLogo: true)
            }
            .scaleEffect(qrAnimationScale)
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            .accessibilityLabel("QR code for receiving \(chain.symbol)")
            .accessibilityHint("Scan this code to send \(chain.symbol) to your wallet")
            .accessibilityIdentifier("receive_qr_code")
            
            // Chain Name Badge with Amount
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(chain.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                
                if !requestAmount.isEmpty {
                    Text("•")
                        .foregroundColor(Color.white.opacity(0.3))
                    Text("\(requestAmount) \(chain.symbol)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            
            // Verify Address Button
            Button(action: { startVerification() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Verify on Device")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Verify address on device")
            .accessibilityHint("Confirm your wallet address matches displayed address")
            .accessibilityIdentifier("receive_verify_button")
        }
        .padding(.vertical, 16)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Address Section
    
    private func addressSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR ADDRESS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(1)
                
                Spacer()
                
                // Copy button
                Button(action: { copyAddress(address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy address")
                .accessibilityHint("Copy wallet address to clipboard")
                .accessibilityIdentifier("receive_copy_button")
            }
            
            // Address display - tappable to copy
            Button(action: { copyAddress(address) }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PrivacyManager.shared.redactAddress(formatAddress(address).prefix))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Text(PrivacyManager.shared.redactAddress(formatAddress(address).suffix))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    .textSelection(.enabled)
                    
                    Spacer()
                    
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.25))
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wallet address")
            .accessibilityValue(address)
            .accessibilityHint("Tap to copy address to clipboard")
            .accessibilityIdentifier("receive_address_display")
            
            // Warning text
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text("Only send \(selectedChain?.symbol ?? "") to this address")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.orange.opacity(0.8))
            .accessibilityLabel("Warning: Only send \(selectedChain?.symbol ?? "") to this address")
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.1), value: appearAnimation)
    }
    
    // Helper to format address for display
    private func formatAddress(_ address: String) -> (prefix: String, suffix: String) {
        let midpoint = address.count / 2
        let prefixEnd = address.index(address.startIndex, offsetBy: midpoint)
        return (String(address[..<prefixEnd]), String(address[prefixEnd...]))
    }
    
    // MARK: - Request Amount Section
    
    private func requestAmountSection(chain: ChainInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REQUEST AMOUNT")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(1)
                
                Text("(Optional)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.3))
                
                Spacer()
                
                // USD/Crypto toggle
                Button(action: { 
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        isAmountInUSD.toggle()
                        if isAmountInUSD {
                            if let crypto = Double(requestAmount), crypto > 0 {
                                requestAmountUSD = String(format: "%.2f", crypto * priceForChain(chain))
                            }
                        } else {
                            if let usd = Double(requestAmountUSD), usd > 0 {
                                requestAmount = String(format: "%.8f", usd / priceForChain(chain))
                            }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isAmountInUSD ? "USD" : chain.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Amount input
            HStack(spacing: 8) {
                Image(systemName: isAmountInUSD ? "dollarsign" : chain.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(width: 24)
                
                TextField("", text: isAmountInUSD ? $requestAmountUSD : $requestAmount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .placeholder(when: (isAmountInUSD ? requestAmountUSD : requestAmount).isEmpty) {
                        Text("0.00")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
                    .onChange(of: requestAmount) { newValue in
                        if !isAmountInUSD, let crypto = Double(newValue), crypto > 0 {
                            requestAmountUSD = String(format: "%.2f", crypto * priceForChain(chain))
                        }
                    }
                    .onChange(of: requestAmountUSD) { newValue in
                        if isAmountInUSD, let usd = Double(newValue), usd > 0 {
                            requestAmount = String(format: "%.8f", usd / priceForChain(chain))
                        }
                    }
                
                Spacer()
                
                Text(isAmountInUSD ? "USD" : chain.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            
            // Conversion preview
            if !requestAmount.isEmpty, let amount = Double(requestAmount), amount > 0 {
                HStack {
                    Text("≈")
                        .foregroundColor(Color.white.opacity(0.3))
                    if isAmountInUSD {
                        Text("\(requestAmount) \(chain.symbol)")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    } else {
                        Text("$\(String(format: "%.2f", amount * priceForChain(chain))) USD")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 8)
            }
            
            // Memo field
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.3))
                
                TextField("", text: $memo)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .placeholder(when: memo.isEmpty) {
                        Text("Memo / Note (optional)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            
            // Info text
            HStack(spacing: 4) {
                Image(systemName: "qrcode")
                    .font(.system(size: 10))
                Text("QR code updates automatically with amount")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.15), value: appearAnimation)
    }
    
    // Helper for price conversion
    private func priceForChain(_ chain: ChainInfo) -> Double {
        switch chain.id.lowercased() {
        case "bitcoin", "bitcoin-testnet": return btcPrice
        case "ethereum", "ethereum-sepolia": return ethPrice
        case "litecoin": return ltcPrice
        default: return 1.0
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: 8) {
            // Copy Address — primary action
            Button(action: { copyAddress(address) }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                    Text("Copy Address")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white)
                .foregroundColor(Color(red: 0.06, green: 0.06, blue: 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 8) {
                // Copy Payment Link
                Button(action: { copyPaymentLink(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12, weight: .medium))
                        Text("Copy Link")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Share
                Button(action: { shareAddress(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                        Text("Share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Save QR
                Button(action: { saveQRCode(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text("Save QR")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.2), value: appearAnimation)
    }
    
    // MARK: - Toast View
    
    private var copiedToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.green)
            
            Text(copiedText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Helper Functions
    
    private func generatePaymentURI(chain: ChainInfo, address: String) -> String {
        var uri = ""
        
        // Build URI scheme based on chain
        switch chain.id.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            uri = "bitcoin:\(address)"
        case "litecoin":
            uri = "litecoin:\(address)"
        case "ethereum", "ethereum-sepolia":
            uri = "ethereum:\(address)"
        case "solana":
            uri = "solana:\(address)"
        case "xrp":
            uri = "xrp:\(address)"
        default:
            uri = address
        }
        
        // Add amount if specified
        var queryParams: [String] = []
        if !requestAmount.isEmpty, let _ = Double(requestAmount) {
            queryParams.append("amount=\(requestAmount)")
        }
        if !memo.isEmpty {
            let encodedMemo = memo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memo
            queryParams.append("message=\(encodedMemo)")
        }
        
        if !queryParams.isEmpty {
            uri += "?" + queryParams.joined(separator: "&")
        }
        
        return uri
    }
    
    private func copyAddress(_ address: String) {
        ClipboardHelper.copySensitive(address, timeout: 60)
        onCopy(address)
        showToast("Address copied! Auto-clears in 60s.")
        
        // ROADMAP-20: Track receive address copied
        AnalyticsService.shared.track(AnalyticsService.EventName.receiveViewed)
    }
    
    private func copyPaymentLink(chain: ChainInfo, address: String) {
        let uri = generatePaymentURI(chain: chain, address: address)
        ClipboardHelper.copySensitive(uri, timeout: 60)
        showToast("Payment link copied! Auto-clears in 60s.")
    }
    
    private func shareAddress(chain: ChainInfo, address: String) {
        #if canImport(AppKit)
        let uri = generatePaymentURI(chain: chain, address: address)
        let shareText = "My \(chain.title) address: \(uri)"
        
        let picker = NSSharingServicePicker(items: [shareText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
    
    private func saveQRCode(chain: ChainInfo, address: String) {
        #if canImport(AppKit)
        let uri = generatePaymentURI(chain: chain, address: address)
        
        // Generate QR image
        guard let qrImage = generateQRImage(content: uri, size: 512) else {
            return
        }
        
        // Save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(chain.title)_address_qr.png"
        savePanel.message = "Save QR Code"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let pngData = qrImage.pngData() {
                    try? pngData.write(to: url)
                    showToast("QR code saved!")
                }
            }
        }
        #endif
    }
    
    private func generateQRImage(content: String, size: CGFloat) -> NSImage? {
        #if canImport(AppKit)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(content.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = size / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        #else
        return nil
        #endif
    }
    
    private func showToast(_ text: String) {
        copiedText = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopiedToast = false
            }
        }
    }
    
    // MARK: - Verification Functions
    
    private func startVerification() {
        verificationStep = 0
        verificationFailed = false
        withAnimation(HawalaTheme.Animation.spring) {
            showAddressVerification = true
        }
        
        performRealVerification()
    }
    
    /// Re-derives the address from the stored public key and compares it
    /// to the currently displayed address to confirm integrity.
    private func performRealVerification() {
        guard let chain = selectedChain,
              let displayedAddress = currentDisplayAddress else {
            markVerificationFailed()
            return
        }
        
        // Step 1: Preparing derivation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { verificationStep = 1 }
        }
        
        // Step 2: Re-deriving and comparing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { verificationStep = 2 }
        }
        
        // Step 3: Verify
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            let verified: Bool
            
            if chain.id.lowercased().contains("bitcoin"), let pubHex = chain.publicKeyHex {
                let isTestnet = chain.id.lowercased().contains("testnet")
                // Re-derive the address for the selected format
                let reDerived: String?
                switch selectedAddressFormat {
                case .nativeSegwit:
                    // Native segwit address is stored directly — compare with original
                    reDerived = chain.receiveAddress
                case .segwit:
                    reDerived = BitcoinAddressDerivation.wrappedSegwitAddress(publicKeyHex: pubHex, testnet: isTestnet)
                case .legacy:
                    reDerived = BitcoinAddressDerivation.legacyAddress(publicKeyHex: pubHex, testnet: isTestnet)
                }
                verified = (reDerived == displayedAddress)
            } else {
                // For non-Bitcoin chains, we can only confirm the address is present
                verified = (chain.receiveAddress == displayedAddress)
            }
            
            if verified {
                withAnimation { verificationStep = 3 }
                // Auto dismiss after success
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(HawalaTheme.Animation.spring) {
                        showAddressVerification = false
                    }
                }
            } else {
                markVerificationFailed()
            }
        }
    }
    
    private func markVerificationFailed() {
        withAnimation {
            verificationFailed = true
            verificationStep = 3
        }
    }
    
    // MARK: - Address Verification Overlay
    
    private var addressVerificationOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showAddressVerification = false
                    }
                }
            
            // Verification card
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(verificationStep == 3
                              ? (verificationFailed ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                              : Color.white.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    if verificationStep < 3 {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white.opacity(0.5), lineWidth: 3)
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(verificationStep > 0 ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: verificationStep)
                        
                        Image(systemName: "shield")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    } else if verificationFailed {
                        Image(systemName: "xmark.shield.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(Color.red)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(Color.green)
                    }
                }
                
                VStack(spacing: 8) {
                    Text(verificationStatusTitle)
                        .font(.clashGroteskMedium(size: 18))
                        .foregroundColor(.white)
                    
                    Text(verificationStatusSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                
                // Progress dots
                HStack(spacing: 12) {
                    ForEach(0..<3) { step in
                        Circle()
                            .fill(step <= verificationStep ? Color.white : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Done button
                if verificationStep == 3 {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showAddressVerification = false
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(32)
            .frame(maxWidth: 300)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private var verificationStatusTitle: String {
        if verificationStep == 3 && verificationFailed { return "Verification Failed" }
        switch verificationStep {
        case 0: return "Preparing..."
        case 1: return "Deriving Address"
        case 2: return "Comparing Address"
        case 3: return "Address Verified!"
        default: return ""
        }
    }
    
    private var verificationStatusSubtitle: String {
        if verificationStep == 3 && verificationFailed {
            return "The displayed address could not be verified. Do not use this address."
        }
        switch verificationStep {
        case 0: return "Initializing key derivation"
        case 1: return "Re-deriving from your public key"
        case 2: return "Confirming address matches derivation"
        case 3: return "This address is safe to use"
        default: return ""
        }
    }
}

// MARK: - Address Format Pill

struct AddressFormatPill: View {
    let format: BitcoinAddressFormat
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: format.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(format.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Receive Chain Pill

struct ReceiveChainPill: View {
    let chain: ChainInfo
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(chain.symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - NSImage PNG Extension

#if canImport(AppKit)
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
#endif

// MARK: - ChainInfo Extension

extension ChainInfo {
    var symbol: String {
        switch id.lowercased() {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        // New chains from wallet-core integration
        case "ton": return "TON"
        case "aptos": return "APT"
        case "sui": return "SUI"
        case "polkadot": return "DOT"
        case "kusama": return "KSM"
        default: return id.uppercased()
        }
    }
}
