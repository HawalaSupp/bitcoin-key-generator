import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let content: String
    let size: CGFloat
    
    private var qrImage: CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(content.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up the QR code for crisp rendering
        let scale = size / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
    
    var body: some View {
        Group {
            if let cgImage = qrImage {
                #if canImport(AppKit)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                #elseif canImport(UIKit)
                let uiImage = UIImage(cgImage: cgImage)
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                #endif
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

#if DEBUG
struct QRCodeView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeView(content: "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", size: 200)
            .padding()
    }
}
#endif
