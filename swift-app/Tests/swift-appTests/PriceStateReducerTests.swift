import Testing
import Foundation
@testable import swift_app

@Suite
struct PriceStateReducerTests {
    @Test func testLoadingStateUsesCacheWhenAvailable() {
        let now = Date()
        let cache = CachedPrice(value: "$25,000", lastUpdated: now.addingTimeInterval(-120))
        let state = PriceStateReducer.loadingState(
            cache: cache,
            staticDisplay: nil,
            now: now
        )

        switch state {
        case .refreshing(let previous, let timestamp):
            #expect(previous == cache.value)
            #expect(timestamp == cache.lastUpdated)
        default:
            #expect(Bool(false), "Expected refreshing state, got \(state)")
        }
    }

    @Test func testLoadingStateFallsBackToStaticDisplay() {
        let now = Date()
        let state = PriceStateReducer.loadingState(
            cache: nil,
            staticDisplay: "$1.00",
            now: now
        )

        switch state {
        case .loaded(let value, let timestamp):
            #expect(value == "$1.00")
            #expect(abs(timestamp.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.01)
        default:
            #expect(Bool(false), "Expected loaded static state, got \(state)")
        }
    }

    @Test func testFailureStateSurfacesStaleWhenCacheExists() {
        let now = Date()
        let cache = CachedPrice(value: "$31,200", lastUpdated: now.addingTimeInterval(-90))
        let state = PriceStateReducer.failureState(
            cache: cache,
            staticDisplay: nil,
            message: "Temporarily rate limited",
            now: now
        )

        switch state {
        case .stale(let value, let timestamp, let message):
            #expect(value == cache.value)
            #expect(timestamp == cache.lastUpdated)
            #expect(message == "Temporarily rate limited")
        default:
            #expect(Bool(false), "Expected stale state, got \(state)")
        }
    }

    @Test func testFailureStateWithoutCacheFallsBackToError() {
        let state = PriceStateReducer.failureState(
            cache: nil,
            staticDisplay: nil,
            message: "Service unavailable",
            now: Date()
        )

        switch state {
        case .failed(let message):
            #expect(message == "Service unavailable")
        default:
            #expect(Bool(false), "Expected failed state, got \(state)")
        }
    }
}
