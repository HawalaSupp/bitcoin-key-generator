import Foundation

struct CryptoURI {
    let scheme: String?
    let target: String
    let queryItems: [String: String]

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let schemePart = trimmed[..<colonIndex]
            scheme = schemePart.isEmpty ? nil : schemePart.lowercased()
            let remainderIndex = trimmed.index(after: colonIndex)
            let remainder = trimmed[remainderIndex...]
            (target, queryItems) = CryptoURI.splitBody(String(remainder))
        } else {
            scheme = nil
            (target, queryItems) = CryptoURI.splitBody(trimmed)
        }
    }

    func queryValue(_ name: String) -> String? {
        queryItems[name.lowercased()]
    }

    private static func splitBody(_ body: String) -> (String, [String: String]) {
        var normalized = body
        if normalized.hasPrefix("//") {
            normalized.removeFirst(2)
        }
        guard let questionIndex = normalized.firstIndex(of: "?") else {
            return ((normalized.removingPercentEncoding ?? normalized), [:])
        }
        let target = String(normalized[..<questionIndex])
        let queryString = String(normalized[normalized.index(after: questionIndex)...])
        return ((target.removingPercentEncoding ?? target), parseQuery(queryString))
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var results: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            guard !pair.isEmpty else { continue }
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = components.first else { continue }
            let value = components.count > 1 ? String(components[1]) : ""
            let decodedKey = key.removingPercentEncoding?.lowercased() ?? key.lowercased()
            let decodedValue = value.removingPercentEncoding ?? value
            results[decodedKey] = decodedValue
        }
        return results
    }
}
