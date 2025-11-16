import XCTest
@testable import swift_app

final class PriceStateReducerTests: XCTestCase {
    func testLoadingStateUsesCacheWhenAvailable() {
        let now = Date()
        let cache = CachedPrice(value: "$25,000", lastUpdated: now.addingTimeInterval(-120))
        let state = PriceStateReducer.loadingState(
            cache: cache,
            staticDisplay: nil,
            now: now
        )

        switch state {
        case .refreshing(let previous, let timestamp):
            XCTAssertEqual(previous, cache.value)
            XCTAssertEqual(timestamp, cache.lastUpdated)
        default:
            XCTFail("Expected refreshing state, got \(state)")
        }
    }

    func testLoadingStateFallsBackToStaticDisplay() {
        let now = Date()
        let state = PriceStateReducer.loadingState(
            cache: nil,
            staticDisplay: "$1.00",
            now: now
        )

        switch state {
        case .loaded(let value, let timestamp):
            XCTAssertEqual(value, "$1.00")
            XCTAssertEqual(timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.01)
        default:
            XCTFail("Expected loaded static state, got \(state)")
        }
    }

    func testFailureStateSurfacesStaleWhenCacheExists() {
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
            XCTAssertEqual(value, cache.value)
            XCTAssertEqual(timestamp, cache.lastUpdated)
            XCTAssertEqual(message, "Temporarily rate limited")
        default:
            XCTFail("Expected stale state, got \(state)")
        }
    }

    func testFailureStateWithoutCacheFallsBackToError() {
        let state = PriceStateReducer.failureState(
            cache: nil,
            staticDisplay: nil,
            message: "Service unavailable",
            now: Date()
        )

        switch state {
        case .failed(let message):
            XCTAssertEqual(message, "Service unavailable")
        default:
            XCTFail("Expected failed state, got \(state)")
        }
    }
}
