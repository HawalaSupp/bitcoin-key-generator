//
//  AirGapDemoView.swift
//  Hawala
//
//  Demo view for Air-Gap Signing feature accessible from Settings.
//  Shows how QR code signing works for offline transaction signing.
//

import SwiftUI

struct AirGapDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var demoStep: DemoStep = .intro
    @State private var sampleQRData = "hawala://tx/demo123456"
    
    enum DemoStep {
        case intro
        case showQR
        case scanDemo
        case complete
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch demoStep {
                case .intro:
                    introView
                case .showQR:
                    qrDisplayView
                case .scanDemo:
                    scanDemoView
                case .complete:
                    completeView
                }
            }
            .padding(24)
            .navigationTitle("Air-Gap Signing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Intro View
    private var introView: some View {
        VStack(spacing: 24) {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Air-Gap Signing")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Sign transactions on a completely offline device for maximum security. Your private keys never touch an internet-connected device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "shield.checkered", title: "Maximum Security", description: "Keys stay on air-gapped device")
                featureRow(icon: "arrow.triangle.2.circlepath", title: "QR Exchange", description: "Transfer data via animated QR codes")
                featureRow(icon: "checkmark.seal", title: "Verified Signing", description: "Review transaction on secure device")
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            Button {
                withAnimation {
                    demoStep = .showQR
                }
            } label: {
                Text("See Demo")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - QR Display View
    private var qrDisplayView: some View {
        VStack(spacing: 24) {
            Text("Step 1: Display Transaction")
                .font(.headline)
            
            Text("This QR code contains your unsigned transaction. Scan it with your air-gapped signing device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Demo QR Code
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 200, height: 200)
                
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .foregroundColor(.black)
            }
            .shadow(radius: 10)
            
            Text("Demo Transaction")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("To:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("0x1234...5678")
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Amount:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("0.1 ETH")
                        .font(.headline)
                }
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            Button {
                withAnimation {
                    demoStep = .scanDemo
                }
            } label: {
                Text("Next: Scan Signature")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Scan Demo View
    private var scanDemoView: some View {
        VStack(spacing: 24) {
            Text("Step 2: Scan Signature")
                .font(.headline)
            
            Text("After signing on your air-gapped device, scan the signature QR code back into Hawala.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
                    .frame(height: 250)
                
                VStack {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 100))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("Camera would activate here")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Text("In a real scenario, point your camera at the signature QR code from your offline device.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button {
                withAnimation {
                    demoStep = .complete
                }
            } label: {
                Text("Simulate Successful Scan")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Complete View
    private var completeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Transaction Signed!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("The signature has been applied to your transaction. It's now ready to broadcast to the network.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text("Ready to Broadcast")
                        .foregroundColor(.green)
                }
                Divider()
                HStack {
                    Text("Signature:")
                    Spacer()
                    Text("0x7f8a...9c2b")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    // Would broadcast
                    dismiss()
                } label: {
                    Text("Broadcast Transaction")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    demoStep = .intro
                } label: {
                    Text("Restart Demo")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#if DEBUG
struct AirGapDemoView_Previews: PreviewProvider {
    static var previews: some View {
        AirGapDemoView()
    }
}
#endif
