import Foundation

enum ChainBalanceState: Equatable {
    case idle
    case loading
    case refreshing(previous: String, lastUpdated: Date?)
    case loaded(value: String, lastUpdated: Date)
    case stale(value: String, lastUpdated: Date?, message: String)
    case failed(String)
}

struct CachedBalance: Equatable {
    let value: String
    let lastUpdated: Date
}

struct BackoffTracker: Equatable {
    var failureCount: Int = 0
    var nextAllowedFetch: Date = .distantPast

    mutating func registerFailure() -> TimeInterval {
        failureCount += 1
        let delay = min(pow(2.0, Double(max(0, failureCount - 1))) * 0.5, 30)
        nextAllowedFetch = Date().addingTimeInterval(delay)
        return delay
    }

    mutating func registerSuccess() {
        failureCount = 0
        nextAllowedFetch = Date()
    }

    mutating func schedule(after interval: TimeInterval) {
        nextAllowedFetch = Date().addingTimeInterval(interval)
    }

    var isInBackoff: Bool { Date() < nextAllowedFetch }

    var remainingBackoff: TimeInterval {
        max(0, nextAllowedFetch.timeIntervalSinceNow)
    }
}

func relativeTimeDescription(from date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

enum ChainPriceState: Equatable {
    case idle
    case loading
    case refreshing(previous: String, lastUpdated: Date?)
    case loaded(value: String, lastUpdated: Date)
    case stale(value: String, lastUpdated: Date?, message: String)
    case failed(String)
}

struct CachedPrice: Equatable {
    let value: String
    let lastUpdated: Date
}
