import Foundation

// MARK: - ROADMAP-20: Production Analytics Provider (TelemetryDeck)

/// Privacy-first analytics provider using the TelemetryDeck API.
/// TelemetryDeck is GDPR-compliant, collects no PII, and stores data in the EU.
/// Docs: https://telemetrydeck.com/docs/
///
/// To enable:
/// 1. Create an account at https://dashboard.telemetrydeck.com
/// 2. Add your app and copy the App ID
/// 3. Set it in APIConfig or as an environment variable: TELEMETRYDECK_APP_ID
struct TelemetryDeckProvider: AnalyticsProvider {
    let name = "TelemetryDeck"
    
    /// TelemetryDeck ingest API endpoint
    private let ingestURL = URL(string: "https://nom.telemetrydeck.com/v2/")!
    
    /// App ID from TelemetryDeck dashboard
    private let appID: String
    
    init(appID: String? = nil) {
        self.appID = appID
            ?? ProcessInfo.processInfo.environment["TELEMETRYDECK_APP_ID"]
            ?? ""
    }
    
    var isConfigured: Bool {
        !appID.isEmpty
    }
    
    func send(events: [AnalyticsEvent]) async throws {
        guard isConfigured else {
            #if DEBUG
            print("[TelemetryDeck] Not configured — skipping \(events.count) events")
            #endif
            return
        }
        
        // TelemetryDeck v2 ingest format
        let signals = events.map { event -> [String: Any] in
            var payload: [String: String] = event.properties
            payload["eventName"] = event.name
            payload["sessionID"] = event.sessionId
            
            return [
                "appID": appID,
                "clientUser": event.deviceId, // anonymous hash — no PII
                "sessionID": event.sessionId,
                "type": event.name,
                "payload": payload.map { "\($0.key):\($0.value)" },
                "isTestMode": isTestMode
            ] as [String: Any]
        }
        
        let body = try JSONSerialization.data(withJSONObject: signals, options: [])
        
        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TelemetryDeckError.sendFailed(statusCode: statusCode)
        }
        
        #if DEBUG
        print("[TelemetryDeck] Successfully sent \(events.count) events")
        #endif
    }
    
    private var isTestMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

enum TelemetryDeckError: LocalizedError {
    case sendFailed(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .sendFailed(let code):
            return "TelemetryDeck send failed with status \(code)"
        }
    }
}
