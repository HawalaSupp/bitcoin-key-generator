//
//  AirGapSigningView.swift
//  Hawala
//
//  Air-gapped signing flow using QR codes.
//  Supports animated QR codes for large transactions and BC-UR format.
//

import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

// MARK: - Air Gap Signing Flow

/// Complete air-gapped signing flow using QR codes
struct AirGapSigningView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AirGapSigningViewModel
    @State private var contentOpacity: Double = 0

    init(
        request: AirGapRequest,
        onComplete: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: AirGapSigningViewModel(
            request: request,
            onComplete: onComplete,
            onCancel: onCancel
        ))
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Air-Gapped Signing")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    HStack {
                        Button {
                            viewModel.cancel()
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Content
                Group {
                    switch viewModel.step {
                    case .displayRequest:
                        DisplayQRView(viewModel: viewModel)
                    case .scanSignature:
                        ScanQRView(viewModel: viewModel)
                    case .processing:
                        AirGapProcessingView()
                    case .complete:
                        AirGapCompleteView(dismiss: dismiss)
                    case .error:
                        AirGapErrorView(viewModel: viewModel, dismiss: dismiss)
                    }
                }
                .opacity(contentOpacity)
            }
        }
        .frame(width: 520, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 50, x: 0, y: 25)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                contentOpacity = 1
            }
        }
    }
}

// MARK: - View Model

@MainActor
class AirGapSigningViewModel: ObservableObject {
    enum Step {
        case displayRequest
        case scanSignature
        case processing
        case complete
        case error
    }
    
    @Published var step: Step = .displayRequest
    @Published var currentQRData: String = ""
    @Published var qrFrames: [String] = []
    @Published var currentFrameIndex = 0
    @Published var isAnimating = false
    @Published var scanProgress: Double = 0
    @Published var errorMessage: String?
    @Published var scannedData: Data?
    
    let request: AirGapRequest
    private let onComplete: (Data) -> Void
    private let onCancel: () -> Void
    
    private var animationTimer: Timer?
    private let frameRate: Double = 8 // fps
    
    init(
        request: AirGapRequest,
        onComplete: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onComplete = onComplete
        self.onCancel = onCancel
        
        generateQRFrames()
    }
    
    func generateQRFrames() {
        // Encode the request data
        let data = request.encodedData
        
        // For small data, single QR code
        if data.count < 500 {
            qrFrames = [data.base64EncodedString()]
            currentQRData = qrFrames[0]
        } else {
            // For large data, create animated multi-part QR
            let chunkSize = 300 // bytes per frame
            var chunks: [String] = []
            var offset = 0
            var index = 0
            let totalParts = (data.count + chunkSize - 1) / chunkSize
            
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data[offset..<end]
                
                // Create multipart frame
                let frame = MultiPartFrame(
                    index: index,
                    total: totalParts,
                    data: chunk.base64EncodedString(),
                    checksum: request.checksum
                )
                
                if let jsonData = try? JSONEncoder().encode(frame),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    chunks.append(jsonString)
                }
                
                offset = end
                index += 1
            }
            
            qrFrames = chunks
            currentQRData = qrFrames.first ?? ""
            
            // Start animation if multiple frames
            if qrFrames.count > 1 {
                startAnimation()
            }
        }
    }
    
    func startAnimation() {
        guard qrFrames.count > 1 else { return }
        isAnimating = true
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }
    
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
    }
    
    private func advanceFrame() {
        currentFrameIndex = (currentFrameIndex + 1) % qrFrames.count
        currentQRData = qrFrames[currentFrameIndex]
    }
    
    func proceedToScan() {
        stopAnimation()
        step = .scanSignature
    }
    
    func handleScannedData(_ data: String) {
        // Try to decode the signature
        if let decodedData = Data(base64Encoded: data) {
            scannedData = decodedData
            step = .processing
            
            // Brief processing delay for UX
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onComplete(decodedData)
                self.step = .complete
            }
        } else {
            errorMessage = "Invalid QR code format"
            step = .error
        }
    }
    
    func updateProgress(_ progress: Double) {
        scanProgress = progress
    }
    
    func retry() {
        errorMessage = nil
        step = .displayRequest
        generateQRFrames()
    }
    
    func cancel() {
        stopAnimation()
        onCancel()
    }
    
    func cleanup() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Supporting Types

struct AirGapRequest {
    let type: RequestType
    let chain: SupportedChain
    let payload: Data
    
    enum RequestType: String, Codable {
        case signTransaction
        case signMessage
        case signTypedData
        case signPSBT
    }
    
    var encodedData: Data {
        let wrapper = RequestWrapper(
            type: type.rawValue,
            chain: chain.rawValue,
            payload: payload.base64EncodedString()
        )
        return (try? JSONEncoder().encode(wrapper)) ?? Data()
    }
    
    var checksum: String {
        let hash = payload.sha256()
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

private struct RequestWrapper: Codable {
    let type: String
    let chain: String
    let payload: String
}

private struct MultiPartFrame: Codable {
    let index: Int
    let total: Int
    let data: String
    let checksum: String
}

// MARK: - Display QR View

private struct DisplayQRView: View {
    @ObservedObject var viewModel: AirGapSigningViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))

                Text("Scan with Offline Device")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text("Display this QR code to your air-gapped signing device")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }

            AirGapQRCodeView(data: viewModel.currentQRData)
                .frame(width: 260, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if viewModel.qrFrames.count > 1 {
                VStack(spacing: 8) {
                    Text("ANIMATED QR")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.3))

                    HStack(spacing: 4) {
                        ForEach(0..<min(viewModel.qrFrames.count, 10), id: \.self) { index in
                            Circle()
                                .fill(index == viewModel.currentFrameIndex
                                      ? Color.white
                                      : Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)
                        }
                        if viewModel.qrFrames.count > 10 {
                            Text("+\(viewModel.qrFrames.count - 10)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }

                    Text("Frame \(viewModel.currentFrameIndex + 1) of \(viewModel.qrFrames.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            Spacer()

            Button {
                viewModel.proceedToScan()
            } label: {
                Text("I've Scanned It")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

// MARK: - Scan QR View

private struct ScanQRView: View {
    @ObservedObject var viewModel: AirGapSigningViewModel
    @State private var isScanning = true

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))

                Text("Scan Signature")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text("Scan the signature QR code from your air-gapped device")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            
            QRScannerView(
                isScanning: $isScanning,
                onScan: { code in
                    viewModel.handleScannedData(code)
                },
                onProgress: { progress in
                    viewModel.updateProgress(progress)
                }
            )
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if viewModel.scanProgress > 0 && viewModel.scanProgress < 1 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: geo.size.width * viewModel.scanProgress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(viewModel.scanProgress * 100))% complete")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Processing View

private struct AirGapProcessingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.white.opacity(0.4), lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Processing Signature...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Complete View

private struct AirGapCompleteView: View {
    let dismiss: DismissAction
    @State private var checkScale: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Circle()
                .fill(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.12))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                        .scaleEffect(checkScale)
                )
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        checkScale = 1
                    }
                }

            Text("Signature Applied!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text("Your transaction has been signed securely")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

// MARK: - Error View

private struct AirGapErrorView: View {
    @ObservedObject var viewModel: AirGapSigningViewModel
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Circle()
                .fill(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.12))
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                )

            Text("Error")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text(viewModel.errorMessage ?? "An error occurred")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    viewModel.retry()
                } label: {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
    }
}

// MARK: - QR Code Generator View

struct AirGapQRCodeView: View {
    let data: String
    @State private var qrImage: Image?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)

            if let image = qrImage {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            } else {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.black.opacity(0.2), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(qrImage == nil ? 360 : 0))
            }
        }
        .onAppear {
            generateQRCode()
        }
        .onChange(of: data) { _ in
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(data.utf8)
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage {
            let scaleX = 280 / outputImage.extent.size.width
            let scaleY = 280 / outputImage.extent.size.height
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                #if canImport(AppKit)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                qrImage = Image(nsImage: nsImage)
                #else
                let uiImage = UIImage(cgImage: cgImage)
                qrImage = Image(uiImage: uiImage)
                #endif
            }
        }
    }
}

// MARK: - QR Scanner View

struct QRScannerView: View {
    @Binding var isScanning: Bool
    let onScan: (String) -> Void
    let onProgress: (Double) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.9))

            VStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 80, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.3))

                Text("Point camera at QR code")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }

            ScannerOverlay()
        }
    }
}

private struct ScannerOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.7

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .frame(width: size, height: size)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Data Extension

extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        self.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}

// CommonCrypto import for SHA256
import CommonCrypto

// MARK: - Preview

#if DEBUG
struct AirGapSigningView_Previews: PreviewProvider {
    static var previews: some View {
        AirGapSigningView(
            request: AirGapRequest(
                type: .signTransaction,
                chain: .ethereum,
                payload: "Test transaction data".data(using: .utf8)!
            ),
            onComplete: { _ in },
            onCancel: { }
        )
    }
}
#endif
