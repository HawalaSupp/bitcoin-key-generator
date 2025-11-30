import SwiftUI
@preconcurrency import AVFoundation
#if canImport(AppKit)
import AppKit
#endif

/// Camera-based QR code scanner view for macOS
struct QRCameraScannerView: View {
    @Binding var isPresented: Bool
    var onScan: (String) -> Void
    
    @StateObject private var cameraManager = CameraManager()
    @State private var errorMessage: String?
    @State private var scannedCode: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Scan QR Code")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Camera preview or error state
            ZStack {
                if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if error.contains("permission") {
                            Button("Open System Preferences") {
                                openCameraPreferences()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Try Again") {
                                Task {
                                    await cameraManager.startScanning()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(40)
                } else if cameraManager.isScanning {
                    CameraPreviewView(cameraManager: cameraManager)
                        .overlay(
                            // Scanning frame overlay
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor, lineWidth: 3)
                                .frame(width: 200, height: 200)
                        )
                        .overlay(alignment: .bottom) {
                            Text("Position QR code within frame")
                                .font(.caption)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .padding(.bottom, 20)
                        }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Starting camera...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 300)
            .background(Color.black.opacity(0.9))
            
            Divider()
            
            // Footer with alternative options
            HStack {
                Button {
                    scanFromFile()
                } label: {
                    Label("From File", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                
                Button {
                    scanFromClipboard()
                } label: {
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 400, height: 480)
        .onAppear {
            Task {
                await cameraManager.startScanning()
            }
        }
        .onDisappear {
            cameraManager.stopScanning()
        }
        .onChange(of: cameraManager.scannedCode) { newValue in
            if let code = newValue {
                scannedCode = code
                onScan(code)
                isPresented = false
            }
        }
        .onChange(of: cameraManager.error) { newValue in
            errorMessage = newValue
        }
    }
    
    private func scanFromFile() {
        if let text = QRCodeScanner.scanText() {
            onScan(text)
            isPresented = false
        }
    }
    
    private func scanFromClipboard() {
        switch QRCodeScanner.scanFromClipboard() {
        case .success(let text):
            onScan(text)
            isPresented = false
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
    
    private func openCameraPreferences() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Camera Manager

@MainActor
class CameraManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var scannedCode: String?
    @Published var error: String?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    func startScanning() async {
        error = nil
        scannedCode = nil
        
        // Check camera authorization
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await setupCamera()
            } else {
                error = "Camera permission denied. Please enable camera access in System Preferences."
            }
        case .authorized:
            await setupCamera()
        case .denied, .restricted:
            error = "Camera permission denied. Please enable camera access in System Preferences to scan QR codes."
        @unknown default:
            error = "Unknown camera authorization status"
        }
    }
    
    private func setupCamera() async {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            error = "No camera available on this device"
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                error = "Could not add camera input"
                return
            }
            
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            } else {
                error = "Could not add metadata output"
                return
            }
            
            captureSession = session
            
            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    self?.isScanning = true
                }
            }
        } catch {
            self.error = "Camera setup failed: \(error.localizedDescription)"
        }
    }
    
    func stopScanning() {
        captureSession?.stopRunning()
        captureSession = nil
        isScanning = false
    }
    
    var session: AVCaptureSession? {
        captureSession
    }
}

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let code = metadataObject.stringValue else {
            return
        }
        
        Task { @MainActor in
            // Play haptic/sound feedback
            NSSound.beep()
            
            scannedCode = code
            stopScanning()
        }
    }
}

// MARK: - Camera Preview View

#if canImport(AppKit)
struct CameraPreviewView: NSViewRepresentable {
    let cameraManager: CameraManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        if let session = cameraManager.session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(previewLayer)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = nsView.bounds
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    QRCameraScannerView(isPresented: .constant(true)) { code in
        print("Scanned: \(code)")
    }
}
