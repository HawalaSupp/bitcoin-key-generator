import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Privacy blur overlay shown when app goes to background
struct PrivacyBlurOverlay: View {
    var body: some View {
        ZStack {
            // Blur background
            #if canImport(AppKit)
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            #else
            Rectangle()
                .fill(.ultraThinMaterial)
            #endif
            
            // Hawala branding
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("Hawala")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Wallet protected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

#if canImport(AppKit)
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif
