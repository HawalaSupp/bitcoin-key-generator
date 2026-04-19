import Foundation
import CoreLocation
import CryptoKit

// MARK: - Geographic Security Manager
// Phase 3.4: Location-Based Security Restrictions

/// Manages geographic security features including geofencing, travel mode, and location-based restrictions
@MainActor
final class GeographicSecurityManager: NSObject, ObservableObject {
    static let shared = GeographicSecurityManager()
    
    // MARK: - Published State
    @Published var isEnabled: Bool = false
    @Published var travelModeActive: Bool = false
    @Published var currentLocation: CLLocation?
    @Published var trustedZones: [TrustedZone] = []
    @Published var restrictedCountries: [RestrictedCountry] = []
    @Published var securityLevel: GeographicSecurityLevel = .standard
    @Published var lastLocationCheck: Date?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationAvailable: Bool = false
    @Published var activeAlerts: [GeographicAlert] = []
    @Published var travelModeConfig: TravelModeConfig?
    
    // MARK: - Location Manager
    private var locationManager: CLLocationManager?
    private let keychainService = "com.hawala.geosecurity"
    private var hasLoadedConfig = false
    
    // MARK: - Initialization
    private override init() {
        super.init()
        // DON'T load from keychain on init - defer to avoid password prompts
        setupLocationManager()
    }
    
    /// Lazy load configuration from keychain
    public func ensureConfigurationLoaded() {
        guard !hasLoadedConfig else { return }
        hasLoadedConfig = true
        loadConfiguration()
    }
    
    // MARK: - Setup
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager?.distanceFilter = 100 // Update every 100 meters
    }
    
    // MARK: - Authorization
    func requestLocationAuthorization() {
        locationManager?.requestWhenInUseAuthorization()
    }
    
    func startMonitoring() {
        guard CLLocationManager.locationServicesEnabled() else {
            isLocationAvailable = false
            return
        }
        
        locationManager?.startUpdatingLocation()
        isEnabled = true
        saveConfiguration()
    }
    
    func stopMonitoring() {
        locationManager?.stopUpdatingLocation()
        isEnabled = false
        saveConfiguration()
    }
    
    // MARK: - Trusted Zones Management
    func addTrustedZone(_ zone: TrustedZone) {
        trustedZones.append(zone)
        
        // Set up geofence monitoring
        if let region = createRegion(for: zone) {
            locationManager?.startMonitoring(for: region)
        }
        
        saveConfiguration()
        Task { await NotificationManager.shared.sendNotification(
            type: .securityReminder,
            title: "Trusted Zone Added",
            body: "'\(zone.name)' has been added to your trusted locations."
        ) }
    }
    
    func removeTrustedZone(id: UUID) {
        if let zone = trustedZones.first(where: { $0.id == id }) {
            if let region = createRegion(for: zone) {
                locationManager?.stopMonitoring(for: region)
            }
        }
        trustedZones.removeAll { $0.id == id }
        saveConfiguration()
    }
    
    func updateTrustedZone(_ zone: TrustedZone) {
        if let index = trustedZones.firstIndex(where: { $0.id == zone.id }) {
            // Stop monitoring old region
            if let oldRegion = createRegion(for: trustedZones[index]) {
                locationManager?.stopMonitoring(for: oldRegion)
            }
            
            trustedZones[index] = zone
            
            // Start monitoring new region
            if let newRegion = createRegion(for: zone) {
                locationManager?.startMonitoring(for: newRegion)
            }
            
            saveConfiguration()
        }
    }
    
    private func createRegion(for zone: TrustedZone) -> CLCircularRegion? {
        let region = CLCircularRegion(
            center: zone.coordinate,
            radius: zone.radius,
            identifier: zone.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }
    
    // MARK: - Location Checks
    func isInTrustedZone() -> Bool {
        guard let currentLocation = currentLocation else { return false }
        
        for zone in trustedZones where zone.isEnabled {
            let zoneLocation = CLLocation(
                latitude: zone.coordinate.latitude,
                longitude: zone.coordinate.longitude
            )
            let distance = currentLocation.distance(from: zoneLocation)
            if distance <= zone.radius {
                return true
            }
        }
        return false
    }
    
    func getCurrentCountryCode() -> String? {
        // In production, use reverse geocoding
        // For now, return simulated value
        return "US"
    }
    
    func isInRestrictedCountry() -> Bool {
        guard let countryCode = getCurrentCountryCode() else { return false }
        return restrictedCountries.contains { $0.code == countryCode && $0.isRestricted }
    }
    
    // MARK: - Transaction Security
    func canPerformTransaction(amount: Double, chain: String) -> TransactionPermission {
        // Check if geographic security is enabled
        guard isEnabled else {
            return .allowed(reason: "Geographic security disabled")
        }
        
        // Check travel mode restrictions
        if travelModeActive, let config = travelModeConfig {
            if amount > config.maxTransactionAmount {
                return .denied(reason: "Transaction exceeds travel mode limit of \(config.maxTransactionAmount)")
            }
            
            if !config.allowedChains.contains(chain) {
                return .denied(reason: "\(chain) transactions disabled in travel mode")
            }
        }
        
        // Check if in trusted zone
        if !isInTrustedZone() && securityLevel == .paranoid {
            return .requiresConfirmation(reason: "Transaction from untrusted location requires extra confirmation")
        }
        
        // Check restricted countries
        if isInRestrictedCountry() {
            return .denied(reason: "Transactions not allowed from current location")
        }
        
        return .allowed(reason: "All geographic checks passed")
    }
    
    // MARK: - Travel Mode
    func enableTravelMode(config: TravelModeConfig) {
        travelModeConfig = config
        travelModeActive = true
        
        // Apply travel mode restrictions
        securityLevel = .high
        
        // Record activation
        let alert = GeographicAlert(
            type: .travelModeActivated,
            message: "Travel mode activated until \(config.endDate.formatted(date: .abbreviated, time: .omitted))",
            timestamp: Date(),
            location: currentLocation
        )
        activeAlerts.append(alert)
        
        saveConfiguration()
        
        Task { await NotificationManager.shared.sendNotification(
            type: .securityReminder,
            title: "Travel Mode Active",
            body: "Enhanced security restrictions are now in effect. Max transaction: \(config.maxTransactionAmount)"
        ) }
    }
    
    func disableTravelMode() {
        travelModeConfig = nil
        travelModeActive = false
        
        let alert = GeographicAlert(
            type: .travelModeDeactivated,
            message: "Travel mode deactivated",
            timestamp: Date(),
            location: currentLocation
        )
        activeAlerts.append(alert)
        
        saveConfiguration()
        
        Task { await NotificationManager.shared.sendNotification(
            type: .securityReminder,
            title: "Travel Mode Ended",
            body: "Normal transaction limits have been restored."
        ) }
    }
    
    func checkTravelModeExpiration() {
        if let config = travelModeConfig, Date() > config.endDate {
            disableTravelMode()
        }
    }
    
    // MARK: - Restricted Countries
    func addRestrictedCountry(_ country: RestrictedCountry) {
        if !restrictedCountries.contains(where: { $0.code == country.code }) {
            restrictedCountries.append(country)
            saveConfiguration()
        }
    }
    
    func removeRestrictedCountry(code: String) {
        restrictedCountries.removeAll { $0.code == code }
        saveConfiguration()
    }
    
    // MARK: - Security Level
    func setSecurityLevel(_ level: GeographicSecurityLevel) {
        securityLevel = level
        saveConfiguration()
        
        Task { await NotificationManager.shared.sendNotification(
            type: .securityReminder,
            title: "Security Level Changed",
            body: "Geographic security set to \(level.rawValue.capitalized)"
        ) }
    }
    
    // MARK: - Alerts
    func acknowledgeAlert(id: UUID) {
        if let index = activeAlerts.firstIndex(where: { $0.id == id }) {
            activeAlerts[index].isAcknowledged = true
            saveConfiguration()
        }
    }
    
    func clearOldAlerts() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days
        activeAlerts.removeAll { $0.timestamp < cutoff && $0.isAcknowledged }
        saveConfiguration()
    }
    
    // MARK: - Persistence
    private func saveConfiguration() {
        let config = GeographicSecurityConfig(
            isEnabled: isEnabled,
            travelModeActive: travelModeActive,
            trustedZones: trustedZones,
            restrictedCountries: restrictedCountries,
            securityLevel: securityLevel,
            travelModeConfig: travelModeConfig,
            activeAlerts: activeAlerts
        )
        
        do {
            let data = try JSONEncoder().encode(config)
            saveToKeychain(data: data, key: "geoSecurityConfig")
        } catch {
            print("Failed to save geographic security config: \(error)")
        }
    }
    
    private func loadConfiguration() {
        guard let data = loadFromKeychain(key: "geoSecurityConfig"),
              let config = try? JSONDecoder().decode(GeographicSecurityConfig.self, from: data) else {
            return
        }
        
        isEnabled = config.isEnabled
        travelModeActive = config.travelModeActive
        trustedZones = config.trustedZones
        restrictedCountries = config.restrictedCountries
        securityLevel = config.securityLevel
        travelModeConfig = config.travelModeConfig
        activeAlerts = config.activeAlerts
    }
    
    // MARK: - Keychain Operations
    private func saveToKeychain(data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        
        SecItemAdd(newQuery as CFDictionary, nil)
    }
    
    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            return nil
        }
        
        return status == errSecSuccess ? result as? Data : nil
    }
}

// MARK: - CLLocationManagerDelegate
extension GeographicSecurityManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            
            self.currentLocation = location
            self.lastLocationCheck = Date()
            self.isLocationAvailable = true
            
            // Check if location changed significantly
            self.checkLocationSecurity(location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Location manager error: \(error)")
            self.isLocationAvailable = false
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationAuthorizationStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationManager?.startUpdatingLocation()
            case .denied, .restricted:
                self.isEnabled = false
            default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let regionId = region.identifier
        Task { @MainActor in
            if let zone = self.trustedZones.first(where: { $0.id.uuidString == regionId }) {
                let alert = GeographicAlert(
                    type: .enteredTrustedZone,
                    message: "Entered trusted zone: \(zone.name)",
                    timestamp: Date(),
                    location: self.currentLocation
                )
                self.activeAlerts.append(alert)
                
                Task { await NotificationManager.shared.sendNotification(
                    type: .securityReminder,
                    title: "Entered Trusted Zone",
                    body: "You've entered '\(zone.name)'. Full wallet access available."
                ) }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let regionId = region.identifier
        Task { @MainActor in
            if let zone = self.trustedZones.first(where: { $0.id.uuidString == regionId }) {
                let alert = GeographicAlert(
                    type: .exitedTrustedZone,
                    message: "Left trusted zone: \(zone.name)",
                    timestamp: Date(),
                    location: self.currentLocation
                )
                self.activeAlerts.append(alert)
                
                if self.securityLevel == .paranoid {
                    Task { await NotificationManager.shared.sendNotification(
                        type: .securityReminder,
                        title: "Left Trusted Zone",
                        body: "You've left '\(zone.name)'. Some features may be restricted."
                    ) }
                }
            }
        }
    }
    
    private func checkLocationSecurity(_ location: CLLocation) {
        // Check travel mode expiration
        checkTravelModeExpiration()
        
        // Check for restricted country entry
        if isInRestrictedCountry() && !activeAlerts.contains(where: { 
            $0.type == .restrictedCountryEntry && !$0.isAcknowledged 
        }) {
            let alert = GeographicAlert(
                type: .restrictedCountryEntry,
                message: "You appear to be in a restricted region. Wallet functions limited.",
                timestamp: Date(),
                location: location
            )
            activeAlerts.append(alert)
            
            Task { await NotificationManager.shared.sendNotification(
                type: .securityReminder,
                title: "⚠️ Restricted Region",
                body: "Some wallet features are disabled in your current location."
            ) }
        }
    }
}

// MARK: - Models

struct TrustedZone: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var radius: Double // meters
    var isEnabled: Bool
    var createdAt: Date
    var restrictions: ZoneRestrictions
    
    init(
        id: UUID = UUID(),
        name: String,
        coordinate: CLLocationCoordinate2D,
        radius: Double = 500,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        restrictions: ZoneRestrictions = .init()
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.radius = radius
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.restrictions = restrictions
    }
    
    static func == (lhs: TrustedZone, rhs: TrustedZone) -> Bool {
        lhs.id == rhs.id
    }
}

struct ZoneRestrictions: Codable {
    var maxTransactionAmount: Double?
    var allowedChains: [String]?
    var requireBiometric: Bool
    
    init(
        maxTransactionAmount: Double? = nil,
        allowedChains: [String]? = nil,
        requireBiometric: Bool = false
    ) {
        self.maxTransactionAmount = maxTransactionAmount
        self.allowedChains = allowedChains
        self.requireBiometric = requireBiometric
    }
}

struct RestrictedCountry: Identifiable, Codable {
    let id: UUID
    var code: String
    var name: String
    var isRestricted: Bool
    var reason: String?
    
    init(id: UUID = UUID(), code: String, name: String, isRestricted: Bool = true, reason: String? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.isRestricted = isRestricted
        self.reason = reason
    }
}

struct TravelModeConfig: Codable {
    var startDate: Date
    var endDate: Date
    var maxTransactionAmount: Double
    var allowedChains: [String]
    var disableNewAddresses: Bool
    var requireBiometricForAll: Bool
    var autoDisableOnReturn: Bool
    var homeZoneId: UUID?
    
    init(
        startDate: Date = Date(),
        endDate: Date,
        maxTransactionAmount: Double = 100.0,
        allowedChains: [String] = ["Bitcoin", "Ethereum"],
        disableNewAddresses: Bool = true,
        requireBiometricForAll: Bool = true,
        autoDisableOnReturn: Bool = true,
        homeZoneId: UUID? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.maxTransactionAmount = maxTransactionAmount
        self.allowedChains = allowedChains
        self.disableNewAddresses = disableNewAddresses
        self.requireBiometricForAll = requireBiometricForAll
        self.autoDisableOnReturn = autoDisableOnReturn
        self.homeZoneId = homeZoneId
    }
}

struct GeographicAlert: Identifiable, Codable {
    let id: UUID
    var type: GeographicAlertType
    var message: String
    var timestamp: Date
    var locationCoordinate: CodableCoordinate?
    var isAcknowledged: Bool
    
    var location: CLLocation? {
        guard let coord = locationCoordinate else { return nil }
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
    }
    
    init(
        id: UUID = UUID(),
        type: GeographicAlertType,
        message: String,
        timestamp: Date = Date(),
        location: CLLocation? = nil,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.timestamp = timestamp
        self.locationCoordinate = location.map { CodableCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        self.isAcknowledged = isAcknowledged
    }
}

struct CodableCoordinate: Codable {
    var latitude: Double
    var longitude: Double
}

enum GeographicAlertType: String, Codable {
    case enteredTrustedZone
    case exitedTrustedZone
    case restrictedCountryEntry
    case suspiciousLocation
    case travelModeActivated
    case travelModeDeactivated
    case velocityAnomaly // Impossible travel detected
    case locationSpoofingDetected
}

enum GeographicSecurityLevel: String, Codable {
    case standard = "standard"    // Basic location awareness
    case high = "high"            // Require trusted zone for large txs
    case paranoid = "paranoid"    // Require trusted zone for all txs
}

enum TransactionPermission {
    case allowed(reason: String)
    case denied(reason: String)
    case requiresConfirmation(reason: String)
    
    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
    
    var message: String {
        switch self {
        case .allowed(let reason): return reason
        case .denied(let reason): return reason
        case .requiresConfirmation(let reason): return reason
        }
    }
}

struct GeographicSecurityConfig: Codable {
    var isEnabled: Bool
    var travelModeActive: Bool
    var trustedZones: [TrustedZone]
    var restrictedCountries: [RestrictedCountry]
    var securityLevel: GeographicSecurityLevel
    var travelModeConfig: TravelModeConfig?
    var activeAlerts: [GeographicAlert]
}

// MARK: - CLLocationCoordinate2D Codable
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
