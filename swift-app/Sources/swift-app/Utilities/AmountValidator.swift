import Foundation

enum AmountValidationResult: Equatable {
    case empty
    case valid
    case invalid(String)
}

struct AmountValidator {
    private static let parsingLocale = Locale(identifier: "en_US_POSIX")

    static func validateBitcoin(amountString: String,
                                availableSats: Int64,
                                estimatedFeeSats: Int64,
                                dustLimit: Int64 = 546) -> AmountValidationResult {
        let trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard !exceedsPrecision(trimmed, maxFractionDigits: 8) else {
            return .invalid("Bitcoin supports up to 8 decimal places")
        }

        guard let decimalAmount = Decimal(string: trimmed, locale: parsingLocale) else {
            return .invalid("Enter a numeric BTC amount")
        }

        guard decimalAmount > .zero else {
            return .invalid("Amount must be greater than zero")
        }

        let satoshisDecimal = decimalAmount * Decimal(100_000_000)
        let satoshis = NSDecimalNumber(decimal: satoshisDecimal).int64Value

        guard satoshis >= dustLimit else {
            return .invalid("Amount must be at least 546 sats")
        }

        guard availableSats > 0 else {
            return .invalid("Balance not loaded yet")
        }

        guard satoshis + max(estimatedFeeSats, 0) <= availableSats else {
            return .invalid("Not enough balance after fees")
        }

        return .valid
    }

    static func validateDecimalAsset(amountString: String,
                                     assetName: String,
                                     available: Decimal,
                                     precision: Int,
                                     minimum: Decimal,
                                     reserved: Decimal = .zero) -> AmountValidationResult {
        let trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard !exceedsPrecision(trimmed, maxFractionDigits: precision) else {
            return .invalid("\(assetName) supports up to \(precision) decimal places")
        }

        guard let decimalAmount = Decimal(string: trimmed, locale: parsingLocale) else {
            return .invalid("Enter a numeric \(assetName) amount")
        }

        guard decimalAmount > .zero else {
            return .invalid("Amount must be greater than zero")
        }

        guard decimalAmount >= minimum else {
            let formattedMin = format(decimal: minimum, precision: precision)
            return .invalid("Amount must be at least \(formattedMin) \(assetName)")
        }

        let spendable = available - reserved
        guard spendable > .zero else {
            return .invalid("Not enough available \(assetName) after fees")
        }

        guard decimalAmount <= spendable else {
            return .invalid("Amount exceeds available \(assetName) after fees")
        }

        return .valid
    }

    private static func exceedsPrecision(_ value: String, maxFractionDigits: Int) -> Bool {
        guard maxFractionDigits >= 0, let dotIndex = value.firstIndex(of: ".") else { return false }
        let fraction = value[value.index(after: dotIndex)...]
        let sanitized = fraction.prefix { $0.isNumber }
        return sanitized.count > maxFractionDigits
    }

    private static func format(decimal: Decimal, precision: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = parsingLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = min(max(precision, 0), 8)
        formatter.maximumFractionDigits = min(max(precision, 0), 8)
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }
}
