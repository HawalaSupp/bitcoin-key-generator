import Foundation
import CoreImage
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct QRCodeScanner {
    
    enum ScanError: LocalizedError {
        case noImageFound
        case noQRCodeDetected
        case invalidImageData
        
        var errorDescription: String? {
            switch self {
            case .noImageFound:
                return "No image found"
            case .noQRCodeDetected:
                return "No QR code detected in image"
            case .invalidImageData:
                return "Invalid image data"
            }
        }
    }
    
    /// Scan QR code from file picker
    @MainActor
    static func scanText() -> String? {
        #if canImport(AppKit)
        guard let imageURL = presentImagePicker() else { return nil }
        return decodeText(from: imageURL)
        #else
        return nil
        #endif
    }
    
    /// Scan QR code from clipboard
    @MainActor
    static func scanFromClipboard() -> Result<String, ScanError> {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        
        // Try to get image from clipboard
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ciImage = CIImage(cgImage: cgImage)
            if let text = decodeText(from: ciImage) {
                return .success(text)
            }
            return .failure(.noQRCodeDetected)
        }
        
        // Check if there's image data in clipboard
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: data),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ciImage = CIImage(cgImage: cgImage)
            if let text = decodeText(from: ciImage) {
                return .success(text)
            }
            return .failure(.noQRCodeDetected)
        }
        
        return .failure(.noImageFound)
        #else
        return .failure(.noImageFound)
        #endif
    }
    
    /// Parse a scanned QR code string to extract cryptocurrency address and metadata
    /// Handles BIP-21 URIs (bitcoin:address?params) and plain addresses
    static func parseAddress(from qrContent: String) -> ParsedQRCode {
        let trimmed = qrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for BIP-21 style URIs (bitcoin:, ethereum:, litecoin:, solana:, etc.)
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let scheme = String(trimmed[..<colonIndex]).lowercased()
            var rest = String(trimmed[trimmed.index(after: colonIndex)...])
            
            // Remove any query parameters to get the address
            var amount: String?
            var label: String?
            var message: String?
            
            if let queryIndex = rest.firstIndex(of: "?") {
                let queryString = String(rest[rest.index(after: queryIndex)...])
                rest = String(rest[..<queryIndex])
                
                // Parse query parameters
                let params = queryString.split(separator: "&")
                for param in params {
                    let parts = param.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0]).lowercased()
                        let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                        switch key {
                        case "amount":
                            amount = value
                        case "label":
                            label = value
                        case "message", "memo":
                            message = value
                        default:
                            break
                        }
                    }
                }
            }
            
            let chainType = chainTypeFromScheme(scheme)
            return ParsedQRCode(
                address: rest,
                chainType: chainType,
                amount: amount,
                label: label,
                message: message,
                rawContent: trimmed
            )
        }
        
        // Plain address - try to detect chain type from format
        let detectedChain = detectChainFromAddress(trimmed)
        return ParsedQRCode(
            address: trimmed,
            chainType: detectedChain,
            amount: nil,
            label: nil,
            message: nil,
            rawContent: trimmed
        )
    }
    
    private static func chainTypeFromScheme(_ scheme: String) -> QRChainType? {
        switch scheme {
        case "bitcoin":
            return .bitcoin
        case "litecoin":
            return .litecoin
        case "ethereum":
            return .ethereum
        case "solana", "solana-pay":
            return .solana
        case "ripple", "xrp":
            return .xrp
        case "bnb", "bsc":
            return .bnb
        default:
            return nil
        }
    }
    
    private static func detectChainFromAddress(_ address: String) -> QRChainType? {
        let lowercased = address.lowercased()
        
        // Bitcoin mainnet
        if lowercased.hasPrefix("bc1") || address.hasPrefix("1") || address.hasPrefix("3") {
            return .bitcoin
        }
        
        // Bitcoin testnet
        if lowercased.hasPrefix("tb1") || address.hasPrefix("m") || address.hasPrefix("n") || address.hasPrefix("2") {
            return .bitcoinTestnet
        }
        
        // Litecoin
        if lowercased.hasPrefix("ltc1") || address.hasPrefix("L") || address.hasPrefix("M") {
            return .litecoin
        }
        
        // Ethereum / BNB (0x addresses)
        if lowercased.hasPrefix("0x") && address.count == 42 {
            return .ethereum // Could also be BNB - user can select
        }
        
        // XRP (starts with 'r')
        if address.hasPrefix("r") && address.count >= 25 && address.count <= 35 {
            return .xrp
        }
        
        // Solana (Base58, 32-44 chars)
        if address.count >= 32 && address.count <= 44 {
            let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            if address.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) {
                return .solana
            }
        }
        
        return nil
    }

    #if canImport(AppKit)
    @MainActor
    private static func presentImagePicker() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select a QR code image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.level = .floating
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    private static func decodeText(from url: URL) -> String? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        return decodeText(from: ciImage)
    }
    
    private static func decodeText(from ciImage: CIImage) -> String? {
        let context = CIContext()
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options) else {
            return nil
        }
        let features = detector.features(in: ciImage)
        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature, let message = qrFeature.messageString {
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    #endif
}

/// Parsed QR code result
struct ParsedQRCode {
    let address: String
    let chainType: QRChainType?
    let amount: String?
    let label: String?
    let message: String?
    let rawContent: String
}

/// Chain types for QR code detection
enum QRChainType {
    case bitcoin
    case bitcoinTestnet
    case litecoin
    case ethereum
    case ethereumTestnet
    case solana
    case xrp
    case bnb
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .litecoin: return "Litecoin"
        case .ethereum: return "Ethereum"
        case .ethereumTestnet: return "Ethereum Testnet"
        case .solana: return "Solana"
        case .xrp: return "XRP"
        case .bnb: return "BNB Chain"
        }
    }
    
    var chainId: String {
        switch self {
        case .bitcoin: return "bitcoin"
        case .bitcoinTestnet: return "bitcoin-testnet"
        case .litecoin: return "litecoin"
        case .ethereum: return "ethereum"
        case .ethereumTestnet: return "ethereum-sepolia"
        case .solana: return "solana"
        case .xrp: return "xrp"
        case .bnb: return "bnb"
        }
    }
}
