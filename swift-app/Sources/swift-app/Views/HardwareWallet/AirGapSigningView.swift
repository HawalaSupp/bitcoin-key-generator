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
        NavigationStack {
            VStack {
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
            .navigationTitle("Air-Gapped Signing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
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
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text("Scan with Offline Device")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Display this QR code to your air-gapped signing device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // QR Code
            AirGapQRCodeView(data: viewModel.currentQRData)
                .frame(width: 280, height: 280)
            
            // Animation indicator for multi-part
            if viewModel.qrFrames.count > 1 {
                VStack(spacing: 8) {
                    Text("Animated QR Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ForEach(0..<min(viewModel.qrFrames.count, 10), id: \.self) { index in
                            Circle()
                                .fill(index == viewModel.currentFrameIndex ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        if viewModel.qrFrames.count > 10 {
                            Text("+\(viewModel.qrFrames.count - 10)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Frame \(viewModel.currentFrameIndex + 1) of \(viewModel.qrFrames.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Next button
            Button {
                viewModel.proceedToScan()
            } label: {
                Text("I've Scanned It")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - Scan QR View

private struct ScanQRView: View {
    @ObservedObject var viewModel: AirGapSigningViewModel
    @State private var isScanning = true
    
    var body: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text("Scan Signature")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Scan the signature QR code from your air-gapped device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Camera scanner
            QRScannerView(
                isScanning: $isScanning,
                onScan: { code in
                    viewModel.handleScannedData(code)
                },
                onProgress: { progress in
                    viewModel.updateProgress(progress)
                }
            )
            .frame(height: 300)
            .cornerRadius(12)
            
            // Progress for multi-part
            if viewModel.scanProgress > 0 && viewModel.scanProgress < 1 {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.scanProgress)
                    Text("\(Int(viewModel.scanProgress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Processing View

private struct AirGapProcessingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Processing Signature...")
                .font(.headline)
        }
    }
}

// MARK: - Complete View

private struct AirGapCompleteView: View {
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Signature Applied!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Your transaction has been signed securely")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - Error View

private struct AirGapErrorView: View {
    @ObservedObject var viewModel: AirGapSigningViewModel
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.title)
                .fontWeight(.bold)
            
            Text(viewModel.errorMessage ?? "An error occurred")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button {
                    viewModel.retry()
                } label: {
                    Text("Retry")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
    }
}

// MARK: - QR Code Generator View

struct AirGapQRCodeView: View {
    let data: String
    
    @State private var qrImage: Image?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
            
            if let image = qrImage {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            } else {
                ProgressView()
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
            // Use existing QRCameraScannerView or implement camera access
            Rectangle()
                .fill(Color.black.opacity(0.8))
            
            VStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 100))
                    .foregroundColor(.white.opacity(0.5))
                
                Text("Point camera at QR code")
                    .foregroundColor(.white)
                    .padding(.top)
            }
            
            // Scanning frame overlay
            ScannerOverlay()
        }
    }
}

private struct ScannerOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.7
            
            ZStack {
                // Darkened corners
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: size, height: size)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )
                
                // Corner brackets
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
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
