import Foundation

struct PriceStateReducer {
    static func loadingState(
        cache: CachedPrice?,
        staticDisplay: String?,
        now: Date
    ) -> ChainPriceState {
        if let staticDisplay {
            let timestamp = cache?.lastUpdated ?? now
            return .loaded(value: staticDisplay, lastUpdated: timestamp)
        }

        if let cache {
            return .refreshing(previous: cache.value, lastUpdated: cache.lastUpdated)
        }

        return .loading
    }

    static func failureState(
        cache: CachedPrice?,
        staticDisplay: String?,
        message: String,
        now: Date
    ) -> ChainPriceState {
        if let staticDisplay {
            let timestamp = cache?.lastUpdated ?? now
            return .loaded(value: staticDisplay, lastUpdated: timestamp)
        }

        if let cache {
            return .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: message)
        }

        return .failed(message)
    }
}
