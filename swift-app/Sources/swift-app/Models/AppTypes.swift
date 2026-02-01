import SwiftUI
import LocalAuthentication

// MARK: - Onboarding

enum OnboardingStep: Int {
    case welcome
    case security
    case passcode
    case ready
}

// MARK: - Fiat Currency

enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case cny = "CNY"
    case inr = "INR"
    case pln = "PLN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        case .cad: return "Canadian Dollar"
        case .aud: return "Australian Dollar"
        case .chf: return "Swiss Franc"
        case .cny: return "Chinese Yuan"
        case .inr: return "Indian Rupee"
        case .pln: return "Polish Złoty"
        }
    }

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .cad: return "CA$"
        case .aud: return "A$"
        case .chf: return "CHF"
        case .cny: return "¥"
        case .inr: return "₹"
        case .pln: return "zł"
        }
    }

    var coingeckoID: String {
        rawValue.lowercased()
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    var menuIconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Auto Lock

enum AutoLockIntervalOption: Double, CaseIterable, Identifiable, Hashable {
    case immediate = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .immediate: return "Immediately"
        case .thirtySeconds: return "After 30 seconds"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .never: return "Never"
        }
    }

    var description: String {
        switch self {
        case .immediate:
            return "Lock whenever Hawala leaves the foreground."
        case .thirtySeconds:
            return "Lock after 30 seconds of inactivity."
        case .oneMinute:
            return "Lock after 1 minute of inactivity."
        case .fiveMinutes:
            return "Lock after 5 minutes of inactivity."
        case .fifteenMinutes:
            return "Lock after 15 minutes of inactivity."
        case .never:
            return "Keep sessions unlocked until manually locked or the app backgrounded."
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .immediate:
            return 0
        case .never:
            return nil
        default:
            return rawValue >= 0 ? rawValue : nil
        }
    }
}

// MARK: - Biometric State

enum BiometricState: Equatable {
    case unknown
    case available(BiometryKind)
    case unavailable(String)

    enum BiometryKind: String {
        case touchID
        case faceID
        case generic

        var displayName: String {
            switch self {
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .generic: return "Biometrics"
            }
        }

        var iconName: String {
            switch self {
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .generic: return "lock.circle"
            }
        }
    }

    var supportsUnlock: Bool {
        if case .available = self { return true }
        return false
    }

    var statusMessage: String {
        switch self {
        case .unknown:
            return "Checking biometric capabilities…"
        case .available(let kind):
            return "Use \(kind.displayName) to unlock faster."
        case .unavailable(let reason):
            return reason
        }
    }
}

// MARK: - View Preference Keys

struct ViewWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Transaction Broadcast Result

/// Result info passed back after successful transaction broadcast
struct TransactionBroadcastResult {
    let txid: String
    let chainId: String
    let chainName: String
    let amount: String
    let recipient: String
    let isRBFEnabled: Bool
    let feeRate: Int?
    let nonce: Int?
    
    init(
        txid: String,
        chainId: String,
        chainName: String,
        amount: String,
        recipient: String,
        isRBFEnabled: Bool = true,
        feeRate: Int? = nil,
        nonce: Int? = nil
    ) {
        self.txid = txid
        self.chainId = chainId
        self.chainName = chainName
        self.amount = amount
        self.recipient = recipient
        self.isRBFEnabled = isRBFEnabled
        self.feeRate = feeRate
        self.nonce = nonce
    }
}
