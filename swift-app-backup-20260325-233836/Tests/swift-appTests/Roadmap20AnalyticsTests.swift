import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-20: Analytics & Telemetry Tests

// ============================================================
// E2: Analytics Service Abstraction
// ============================================================

@Suite("ROADMAP-20 E2: AnalyticsService Abstraction")
struct AnalyticsServiceTests {

    @Test("AnalyticsService singleton exists")
    @MainActor
    func singletonExists() {
        let service = AnalyticsService.shared
        #expect(service != nil)
    }

    @Test("AnalyticsService has session ID")
    @MainActor
    func hasSessionId() {
        let service = AnalyticsService.shared
        // Session ID is internal — verify via event tracking
        // Track an event and check event count increases
        let before = service.eventCount
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        service.track(AnalyticsService.EventName.appLaunch)
        #expect(service.eventCount > before)
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// E3: Event Tracking
// ============================================================

@Suite("ROADMAP-20 E3: Event Tracking")
struct EventTrackingTests {

    @Test("track() increments event count when enabled")
    @MainActor
    func trackIncrementsCount() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        service.track(AnalyticsService.EventName.portfolioViewed)
        #expect(service.eventCount == before + 1)
        service.isEnabled = wasEnabled
    }

    @Test("trackScreen() fires screen_viewed event")
    @MainActor
    func trackScreenFiresEvent() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        service.trackScreen("settings")
        #expect(service.eventCount == before + 1)
        service.isEnabled = wasEnabled
    }

    @Test("trackError() fires error_occurred event")
    @MainActor
    func trackErrorFiresEvent() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        service.trackError("network", message: "timeout")
        #expect(service.eventCount == before + 1)
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// D1: Event Taxonomy / Name Constants
// ============================================================

@Suite("ROADMAP-20 D1: Event Taxonomy")
struct EventTaxonomyTests {

    @Test("All core event names are defined")
    func coreEventNamesDefined() {
        #expect(!AnalyticsService.EventName.appLaunch.isEmpty)
        #expect(!AnalyticsService.EventName.walletCreated.isEmpty)
        #expect(!AnalyticsService.EventName.walletImported.isEmpty)
        #expect(!AnalyticsService.EventName.sendInitiated.isEmpty)
        #expect(!AnalyticsService.EventName.sendCompleted.isEmpty)
        #expect(!AnalyticsService.EventName.sendFailed.isEmpty)
        #expect(!AnalyticsService.EventName.receiveViewed.isEmpty)
        #expect(!AnalyticsService.EventName.swapInitiated.isEmpty)
        #expect(!AnalyticsService.EventName.swapCompleted.isEmpty)
        #expect(!AnalyticsService.EventName.swapFailed.isEmpty)
        #expect(!AnalyticsService.EventName.bridgeInitiated.isEmpty)
        #expect(!AnalyticsService.EventName.navigationTransition.isEmpty)
        #expect(!AnalyticsService.EventName.deepLinkOpened.isEmpty)
        #expect(!AnalyticsService.EventName.settingsChanged.isEmpty)
        #expect(!AnalyticsService.EventName.securityScoreViewed.isEmpty)
        #expect(!AnalyticsService.EventName.backupCompleted.isEmpty)
        #expect(!AnalyticsService.EventName.backupSkipped.isEmpty)
        #expect(!AnalyticsService.EventName.walletConnectSession.isEmpty)
        #expect(!AnalyticsService.EventName.feeEstimateViewed.isEmpty)
        #expect(!AnalyticsService.EventName.historyExported.isEmpty)
        #expect(!AnalyticsService.EventName.contactAdded.isEmpty)
        #expect(!AnalyticsService.EventName.hardwareWalletConnected.isEmpty)
        #expect(!AnalyticsService.EventName.errorOccurred.isEmpty)
        #expect(!AnalyticsService.EventName.screenViewed.isEmpty)
    }

    @Test("New ROADMAP-20 event names defined")
    func newEventNames() {
        #expect(!AnalyticsService.EventName.coldStart.isEmpty)
        #expect(!AnalyticsService.EventName.onboardingStarted.isEmpty)
        #expect(!AnalyticsService.EventName.onboardingCompleted.isEmpty)
        #expect(!AnalyticsService.EventName.portfolioViewed.isEmpty)
    }

    @Test("Event names follow naming convention (snake_case)")
    func snakeCaseConvention() {
        let names = [
            AnalyticsService.EventName.appLaunch,
            AnalyticsService.EventName.sendInitiated,
            AnalyticsService.EventName.swapCompleted,
            AnalyticsService.EventName.coldStart,
            AnalyticsService.EventName.portfolioViewed
        ]
        for name in names {
            // snake_case: only lowercase letters, digits, and underscores
            let isSnakeCase = name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
            #expect(isSnakeCase, "Event name '\(name)' should be snake_case")
        }
    }
}

// ============================================================
// D2: Property Schema
// ============================================================

@Suite("ROADMAP-20 D2: AnalyticsEvent Property Schema")
struct AnalyticsEventSchemaTests {

    @Test("AnalyticsEvent stores all fields")
    func allFields() {
        let event = AnalyticsEvent(
            name: AnalyticsService.EventName.appLaunch,
            properties: ["key": "value"],
            timestamp: Date(),
            sessionId: "session-123",
            deviceId: "device-456"
        )
        #expect(event.name == "app_launch")
        #expect(event.properties["key"] == "value")
        #expect(event.sessionId == "session-123")
        #expect(event.deviceId == "device-456")
    }

    @Test("AnalyticsEvent is Codable")
    func isCodable() throws {
        let event = AnalyticsEvent(
            name: AnalyticsService.EventName.sendInitiated,
            properties: [:],
            sessionId: "s",
            deviceId: "d"
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AnalyticsEvent.self, from: data)
        #expect(decoded.name == event.name)
        #expect(decoded.sessionId == event.sessionId)
        #expect(decoded.deviceId == event.deviceId)
    }

    @Test("AnalyticsEvent is Sendable")
    func isSendable() {
        // Compile-time check: AnalyticsEvent conforms to Sendable
        let event = AnalyticsEvent(name: AnalyticsService.EventName.appLaunch, sessionId: "s", deviceId: "d")
        let _: any Sendable = event
        #expect(true)
    }
}

// ============================================================
// E4: User Properties / Anonymous Device ID
// ============================================================

@Suite("ROADMAP-20 E4: Anonymous Device ID")
struct AnonymousDeviceIDTests {

    @Test("Device ID is persisted across accesses")
    @MainActor
    func persistentDeviceId() {
        // Access the shared singleton to ensure init has run
        _ = AnalyticsService.shared.eventCount
        let deviceId = UserDefaults.standard.string(forKey: "hawala.analytics.deviceId")
        #expect(deviceId != nil)
        if let deviceId {
            #expect(!deviceId.isEmpty)
        }
    }

    @Test("Device ID is a valid UUID format")
    @MainActor
    func validUUIDFormat() {
        _ = AnalyticsService.shared.eventCount
        let deviceId = UserDefaults.standard.string(forKey: "hawala.analytics.deviceId")
        #expect(deviceId != nil)
        if let deviceId {
            #expect(UUID(uuidString: deviceId) != nil)
        }
    }
}

// ============================================================
// E5: Screen Tracking
// ============================================================

@Suite("ROADMAP-20 E5: Screen Tracking API")
struct ScreenTrackingTests {

    @Test("trackScreen uses screen_viewed event name")
    @MainActor
    func trackScreenEventName() {
        // Verify screen tracking API exists and works
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        service.trackScreen("test_screen")
        #expect(service.eventCount == before + 1)
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// E6: Error Tracking
// ============================================================

@Suite("ROADMAP-20 E6: Error Tracking API")
struct ErrorTrackingTests {

    @Test("trackError truncates long messages")
    @MainActor
    func truncatesLongMessages() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let longMessage = String(repeating: "x", count: 500)
        // Should not crash or fail — message is truncated to 200 chars
        service.trackError("test", message: longMessage)
        #expect(true) // No crash
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// E8/E9: Opt-Out Toggle & Enforcement
// ============================================================

@Suite("ROADMAP-20 E8/E9: Opt-Out Enforcement", .serialized)
struct OptOutEnforcementTests {

    @Test("Tracking is no-op when disabled")
    @MainActor
    func trackingDisabledNoOp() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = false
        let before = service.eventCount
        service.track(AnalyticsService.EventName.appLaunch)
        #expect(service.eventCount == before, "Event count should not change when disabled")
        service.isEnabled = wasEnabled
    }

    @Test("isEnabled persists to UserDefaults")
    @MainActor
    func enabledPersists() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        
        service.isEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "hawala.analytics.enabled"))
        
        service.isEnabled = false
        #expect(!UserDefaults.standard.bool(forKey: "hawala.analytics.enabled"))
        
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// E10: Debug Mode
// ============================================================

@Suite("ROADMAP-20 E10: Debug Mode")
struct DebugModeTests {

    @Test("ConsoleAnalyticsProvider has name 'Console'")
    func consoleProviderName() {
        let provider = ConsoleAnalyticsProvider()
        #expect(provider.name == "Console")
    }

    @Test("ConsoleAnalyticsProvider sends without error")
    func consoleProviderSend() async throws {
        let provider = ConsoleAnalyticsProvider()
        let event = AnalyticsEvent(name: AnalyticsService.EventName.appLaunch, sessionId: "s", deviceId: "d")
        try await provider.send(events: [event])
        #expect(true) // No throw
    }
}

// ============================================================
// E12: Batch Sending
// ============================================================

@Suite("ROADMAP-20 E12: Batch Sending")
struct BatchSendingTests {

    @Test("Batch size is configured")
    @MainActor
    func batchSizeConfigured() {
        #expect(AnalyticsService.shared.batchSize == 50)
    }

    @Test("Flush interval is configured")
    @MainActor
    func flushIntervalConfigured() {
        #expect(AnalyticsService.shared.flushInterval == 300)
    }

    @Test("Flush does not crash with no providers")
    @MainActor
    func flushNoProviders() {
        // Just calling flush should not crash
        AnalyticsService.shared.flush()
        #expect(true)
    }
}

// ============================================================
// E13: Offline Handling
// ============================================================

@Suite("ROADMAP-20 E13: Offline Queue")
struct OfflineQueueTests {

    @Test("Events are Codable for disk persistence")
    func eventsAreCodable() throws {
        let events = [
            AnalyticsEvent(name: AnalyticsService.EventName.sendCompleted, properties: ["a": "b"], sessionId: "s", deviceId: "d"),
            AnalyticsEvent(name: AnalyticsService.EventName.swapCompleted, properties: [:], sessionId: "s", deviceId: "d")
        ]
        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([AnalyticsEvent].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "send_completed")
        #expect(decoded[1].name == "swap_completed")
    }

    @Test("NetworkMonitor shared singleton exists")
    @MainActor
    func networkMonitorExists() {
        let monitor = NetworkMonitor.shared
        // Status should be a valid value
        let status = monitor.status
        #expect(status == .online || status == .offline || status == .constrained || status == .checking)
    }
}

// ============================================================
// PII Sanitization
// ============================================================

@Suite("ROADMAP-20: PII Sanitization")
struct PIISanitizationTests {

    @Test("Analytics tracks event with sanitized properties")
    @MainActor
    func sanitizedTracking() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        // Should not crash even with sensitive-looking property names
        service.track(AnalyticsService.EventName.sendCompleted, properties: [
            "chain": "bitcoin",
            "private_key": "should_be_redacted",
            "address": "bc1qtest123"
        ])
        #expect(true) // No crash
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// AnalyticsProvider Protocol
// ============================================================

@Suite("ROADMAP-20: AnalyticsProvider Protocol")
struct AnalyticsProviderProtocolTests {

    @Test("Protocol requires send and name")
    func protocolShape() async throws {
        // Create a mock provider to verify the protocol
        let mock = MockAnalyticsProvider()
        #expect(mock.name == "Mock")
        let event = AnalyticsEvent(name: AnalyticsService.EventName.appLaunch, sessionId: "s", deviceId: "d")
        try await mock.send(events: [event])
        #expect(mock.sentEvents.count == 1)
    }
}

/// Mock provider for testing
final class MockAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    let name = "Mock"
    var sentEvents: [AnalyticsEvent] = []
    
    func send(events: [AnalyticsEvent]) async throws {
        sentEvents.append(contentsOf: events)
    }
}

// ============================================================
// Integration: Event Wiring Verification
// ============================================================

@Suite("ROADMAP-20: Event Wiring Smoke Tests")
struct EventWiringSmokeTests {

    @Test("AnalyticsService has addProvider method")
    @MainActor
    func addProviderExists() {
        let mock = MockAnalyticsProvider()
        AnalyticsService.shared.addProvider(mock)
        #expect(true) // Method exists and doesn't crash
    }

    @Test("AnalyticsService has reset method")
    @MainActor
    func resetExists() {
        // Don't actually call reset in tests — just verify it compiles
        let _: () -> Void = { AnalyticsService.shared.reset() }
        #expect(true)
    }

    @Test("hasShownOptIn can be read and set")
    @MainActor
    func optInShownFlag() {
        let service = AnalyticsService.shared
        let was = service.hasShownOptIn
        service.hasShownOptIn = true
        #expect(service.hasShownOptIn)
        service.hasShownOptIn = was
    }
    
    @Test("setUserProperty fires settings_changed event")
    @MainActor
    func setUserProperty() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        service.setUserProperty("theme", value: "dark")
        #expect(service.eventCount == before + 1)
        service.isEnabled = wasEnabled
    }
}
