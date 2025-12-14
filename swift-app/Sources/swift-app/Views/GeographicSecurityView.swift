import SwiftUI
import CoreLocation

// MARK: - Geographic Security View
// Phase 3.4: Location-Based Security Settings

struct GeographicSecurityView: View {
    @StateObject private var geoManager = GeographicSecurityManager.shared
    @State private var showingAddZone = false
    @State private var showingTravelMode = false
    @State private var showingRestrictedCountries = false
    @State private var selectedZone: TrustedZone?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                geoSecurityHeader
                
                // Status Card
                statusCard
                
                // Security Level
                securityLevelSection
                
                // Travel Mode
                travelModeSection
                
                // Trusted Zones
                trustedZonesSection
                
                // Active Alerts
                if !geoManager.activeAlerts.filter({ !$0.isAcknowledged }).isEmpty {
                    activeAlertsSection
                }
                
                // Quick Actions
                quickActionsSection
            }
            .padding()
        }
        .background(Color.black)
        .sheet(isPresented: $showingAddZone) {
            AddTrustedZoneSheet(geoManager: geoManager)
        }
        .sheet(isPresented: $showingTravelMode) {
            TravelModeSheet(geoManager: geoManager)
        }
        .sheet(item: $selectedZone) { zone in
            EditTrustedZoneSheet(zone: zone, geoManager: geoManager)
        }
        .alert("Geographic Security", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Header
    private var geoSecurityHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "location.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
            }
            
            Text("Geographic Security")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Location-based protection for your wallet")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.vertical)
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protection Status")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(geoManager.isEnabled ? "Active" : "Disabled")
                        .font(.subheadline)
                        .foregroundColor(geoManager.isEnabled ? .green : .gray)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { geoManager.isEnabled },
                    set: { enabled in
                        if enabled {
                            geoManager.requestLocationAuthorization()
                            geoManager.startMonitoring()
                        } else {
                            geoManager.stopMonitoring()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 24) {
                GeoStatusItem(
                    icon: "location.fill",
                    title: "Location",
                    value: geoManager.isLocationAvailable ? "Available" : "Unavailable",
                    color: geoManager.isLocationAvailable ? .green : .orange
                )
                
                GeoStatusItem(
                    icon: "shield.checkered",
                    title: "Zone",
                    value: geoManager.isInTrustedZone() ? "Trusted" : "Unknown",
                    color: geoManager.isInTrustedZone() ? .green : .yellow
                )
                
                GeoStatusItem(
                    icon: "airplane",
                    title: "Travel",
                    value: geoManager.travelModeActive ? "Active" : "Off",
                    color: geoManager.travelModeActive ? .orange : .gray
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Security Level
    private var securityLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.blue)
                Text("Security Level")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                ForEach([GeographicSecurityLevel.standard, .high, .paranoid], id: \.self) { level in
                    GeoSecurityLevelRow(
                        level: level,
                        isSelected: geoManager.securityLevel == level,
                        action: { geoManager.setSecurityLevel(level) }
                    )
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Travel Mode
    private var travelModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airplane.departure")
                    .foregroundColor(.orange)
                Text("Travel Mode")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if geoManager.travelModeActive {
                    Text("ACTIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            if geoManager.travelModeActive, let config = geoManager.travelModeConfig {
                VStack(alignment: .leading, spacing: 8) {
                    GeoInfoRow(label: "Max Transaction", value: "$\(String(format: "%.2f", config.maxTransactionAmount))")
                    GeoInfoRow(label: "Ends", value: config.endDate.formatted(date: .abbreviated, time: .shortened))
                    GeoInfoRow(label: "Allowed Chains", value: config.allowedChains.joined(separator: ", "))
                    
                    HStack(spacing: 12) {
                        Button(action: { showingTravelMode = true }) {
                            Text("Modify")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            geoManager.disableTravelMode()
                        }) {
                            Text("Deactivate")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temporarily restrict wallet functionality while traveling.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    GeoFeatureItem(icon: "dollarsign.circle", text: "Limit transaction amounts")
                    GeoFeatureItem(icon: "link", text: "Restrict to specific chains")
                    GeoFeatureItem(icon: "key", text: "Require biometric for all actions")
                    
                    Button(action: { showingTravelMode = true }) {
                        HStack {
                            Image(systemName: "airplane")
                            Text("Enable Travel Mode")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Trusted Zones
    private var trustedZonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.green)
                Text("Trusted Zones")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingAddZone = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            if geoManager.trustedZones.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    
                    Text("No trusted zones configured")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("Add locations where full wallet access is allowed.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(geoManager.trustedZones) { zone in
                        TrustedZoneRow(zone: zone) {
                            selectedZone = zone
                        } onDelete: {
                            geoManager.removeTrustedZone(id: zone.id)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Active Alerts
    private var activeAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Active Alerts")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            ForEach(geoManager.activeAlerts.filter { !$0.isAcknowledged }) { alert in
                GeoAlertRow(alert: alert) {
                    geoManager.acknowledgeAlert(id: alert.id)
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                GeoQuickActionButton(
                    icon: "location.magnifyingglass",
                    title: "Verify Location",
                    color: .blue
                ) {
                    if geoManager.isLocationAvailable {
                        alertMessage = geoManager.isInTrustedZone() ?
                            "You are currently in a trusted zone." :
                            "You are not in any trusted zone."
                    } else {
                        alertMessage = "Location services unavailable."
                    }
                    showingAlert = true
                }
                
                GeoQuickActionButton(
                    icon: "globe",
                    title: "Countries",
                    color: .purple
                ) {
                    showingRestrictedCountries = true
                }
            }
            
            HStack(spacing: 12) {
                GeoQuickActionButton(
                    icon: "bell.badge",
                    title: "Clear Alerts",
                    color: .orange
                ) {
                    geoManager.clearOldAlerts()
                    alertMessage = "Old alerts cleared."
                    showingAlert = true
                }
                
                GeoQuickActionButton(
                    icon: "arrow.clockwise",
                    title: "Refresh",
                    color: .green
                ) {
                    geoManager.startMonitoring()
                    alertMessage = "Location refreshed."
                    showingAlert = true
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Supporting Views

struct GeoStatusItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeoSecurityLevelRow: View {
    let level: GeographicSecurityLevel
    let isSelected: Bool
    let action: () -> Void
    
    var levelInfo: (icon: String, title: String, description: String, color: Color) {
        switch level {
        case .standard:
            return ("shield", "Standard", "Basic location awareness", .green)
        case .high:
            return ("shield.lefthalf.filled", "High", "Trusted zone for large transactions", .orange)
        case .paranoid:
            return ("shield.fill", "Paranoid", "Trusted zone required for all transactions", .red)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: levelInfo.icon)
                    .font(.title3)
                    .foregroundColor(levelInfo.color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(levelInfo.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text(levelInfo.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(levelInfo.color)
                }
            }
            .padding()
            .background(isSelected ? levelInfo.color.opacity(0.2) : Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct GeoInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
}

struct GeoFeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct TrustedZoneRow: View {
    let zone: TrustedZone
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(zone.isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(zone.isEnabled ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text("\(Int(zone.radius))m radius")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct GeoAlertRow: View {
    let alert: GeographicAlert
    let onAcknowledge: () -> Void
    
    var alertIcon: String {
        switch alert.type {
        case .enteredTrustedZone: return "arrow.down.right.circle.fill"
        case .exitedTrustedZone: return "arrow.up.left.circle.fill"
        case .restrictedCountryEntry: return "exclamationmark.triangle.fill"
        case .suspiciousLocation: return "eye.trianglebadge.exclamationmark"
        case .travelModeActivated: return "airplane.departure"
        case .travelModeDeactivated: return "airplane.arrival"
        case .velocityAnomaly: return "speedometer"
        case .locationSpoofingDetected: return "exclamationmark.shield.fill"
        }
    }
    
    var alertColor: Color {
        switch alert.type {
        case .enteredTrustedZone: return .green
        case .exitedTrustedZone: return .orange
        case .restrictedCountryEntry, .suspiciousLocation, .velocityAnomaly, .locationSpoofingDetected: return .red
        case .travelModeActivated, .travelModeDeactivated: return .blue
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alertIcon)
                .foregroundColor(alertColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(alert.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: onAcknowledge) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(alertColor.opacity(0.1))
        .cornerRadius(10)
    }
}

struct GeoQuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.2))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Trusted Zone Sheet

struct AddTrustedZoneSheet: View {
    @ObservedObject var geoManager: GeographicSecurityManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var radius: Double = 500
    @State private var useCurrentLocation = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Zone Details") {
                    TextField("Zone Name", text: $name)
                    
                    Toggle("Use Current Location", isOn: $useCurrentLocation)
                    
                    if !useCurrentLocation {
                        TextField("Latitude", text: $latitude)
                        TextField("Longitude", text: $longitude)
                    }
                }
                
                Section("Radius") {
                    VStack(alignment: .leading) {
                        Text("\(Int(radius)) meters")
                            .font(.headline)
                        
                        Slider(value: $radius, in: 100...5000, step: 100)
                    }
                }
                
                Section {
                    Button("Add Trusted Zone") {
                        addZone()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .navigationTitle("Add Trusted Zone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 400)
    }
    
    private func addZone() {
        let coordinate: CLLocationCoordinate2D
        
        if useCurrentLocation, let location = geoManager.currentLocation {
            coordinate = location.coordinate
        } else if let lat = Double(latitude), let lon = Double(longitude) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            // Default to a placeholder
            coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        let zone = TrustedZone(
            name: name,
            coordinate: coordinate,
            radius: radius
        )
        
        geoManager.addTrustedZone(zone)
        dismiss()
    }
}

// MARK: - Edit Trusted Zone Sheet

struct EditTrustedZoneSheet: View {
    let zone: TrustedZone
    @ObservedObject var geoManager: GeographicSecurityManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var radius: Double
    @State private var isEnabled: Bool
    
    init(zone: TrustedZone, geoManager: GeographicSecurityManager) {
        self.zone = zone
        self.geoManager = geoManager
        _name = State(initialValue: zone.name)
        _radius = State(initialValue: zone.radius)
        _isEnabled = State(initialValue: zone.isEnabled)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Zone Details") {
                    TextField("Zone Name", text: $name)
                    Toggle("Enabled", isOn: $isEnabled)
                }
                
                Section("Radius") {
                    VStack(alignment: .leading) {
                        Text("\(Int(radius)) meters")
                            .font(.headline)
                        
                        Slider(value: $radius, in: 100...5000, step: 100)
                    }
                }
                
                Section("Location") {
                    Text("Lat: \(zone.coordinate.latitude, specifier: "%.6f")")
                    Text("Lon: \(zone.coordinate.longitude, specifier: "%.6f")")
                }
                
                Section {
                    Button("Save Changes") {
                        saveChanges()
                    }
                }
            }
            .navigationTitle("Edit Zone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 400)
    }
    
    private func saveChanges() {
        var updatedZone = zone
        updatedZone.name = name
        updatedZone.radius = radius
        updatedZone.isEnabled = isEnabled
        
        geoManager.updateTrustedZone(updatedZone)
        dismiss()
    }
}

// MARK: - Travel Mode Sheet

struct TravelModeSheet: View {
    @ObservedObject var geoManager: GeographicSecurityManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var endDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var maxAmount: Double = 100
    @State private var allowBitcoin = true
    @State private var allowEthereum = true
    @State private var allowLitecoin = false
    @State private var disableNewAddresses = true
    @State private var requireBiometric = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Duration") {
                    DatePicker("End Date", selection: $endDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Transaction Limit") {
                    VStack(alignment: .leading) {
                        Text("$\(String(format: "%.0f", maxAmount))")
                            .font(.headline)
                        
                        Slider(value: $maxAmount, in: 10...1000, step: 10)
                        
                        Text("Maximum per transaction while in travel mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Allowed Chains") {
                    Toggle("Bitcoin", isOn: $allowBitcoin)
                    Toggle("Ethereum", isOn: $allowEthereum)
                    Toggle("Litecoin", isOn: $allowLitecoin)
                }
                
                Section("Security") {
                    Toggle("Disable New Address Generation", isOn: $disableNewAddresses)
                    Toggle("Require Biometric for All Actions", isOn: $requireBiometric)
                }
                
                Section {
                    Button("Activate Travel Mode") {
                        activateTravelMode()
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Travel Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 450, height: 550)
    }
    
    private func activateTravelMode() {
        var allowedChains: [String] = []
        if allowBitcoin { allowedChains.append("Bitcoin") }
        if allowEthereum { allowedChains.append("Ethereum") }
        if allowLitecoin { allowedChains.append("Litecoin") }
        
        let config = TravelModeConfig(
            endDate: endDate,
            maxTransactionAmount: maxAmount,
            allowedChains: allowedChains,
            disableNewAddresses: disableNewAddresses,
            requireBiometricForAll: requireBiometric
        )
        
        geoManager.enableTravelMode(config: config)
        dismiss()
    }
}

// MARK: - Preview
#Preview {
    GeographicSecurityView()
}
