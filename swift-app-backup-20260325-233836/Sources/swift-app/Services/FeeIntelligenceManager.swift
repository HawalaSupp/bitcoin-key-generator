import Foundation
import Combine

// MARK: - Fee Intelligence Manager
// Phase 5.2: Smart Transaction Features - Fee Intelligence

/// Supported chains for fee tracking
enum FeeTrackableChain: String, CaseIterable, Codable, Identifiable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case litecoin = "Litecoin"
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .litecoin: return "LTC"
        }
    }
    
    var feeUnit: String {
        switch self {
        case .bitcoin, .litecoin: return "sat/vB"
        case .ethereum: return "Gwei"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "diamond.fill"
        case .litecoin: return "l.circle.fill"
        }
    }
    
    /// Typical transaction size for fee estimation
    var typicalTxSize: Int {
        switch self {
        case .bitcoin: return 250    // P2WPKH ~140 vB, P2PKH ~250 vB
        case .ethereum: return 21000 // Standard ETH transfer gas
        case .litecoin: return 250
        }
    }
}

/// Fee level presets
enum FeePreset: String, CaseIterable, Codable, Identifiable {
    case economy = "Economy"
    case normal = "Normal"
    case priority = "Priority"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .economy: return "Lowest fee, may take hours"
        case .normal: return "Standard fee, ~30 min"
        case .priority: return "Fast confirmation, ~10 min"
        case .custom: return "Set your own fee rate"
        }
    }
    
    var icon: String {
        switch self {
        case .economy: return "tortoise.fill"
        case .normal: return "hare.fill"
        case .priority: return "bolt.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    var color: String {
        switch self {
        case .economy: return "green"
        case .normal: return "blue"
        case .priority: return "orange"
        case .custom: return "purple"
        }
    }
}

/// Network congestion level
enum CongestionLevel: String, Codable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case extreme = "Extreme"
    
    var description: String {
        switch self {
        case .low: return "Network is quiet, fees are low"
        case .moderate: return "Normal activity, standard fees"
        case .high: return "Heavy traffic, elevated fees"
        case .extreme: return "Very congested, high fees recommended"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "wifi.circle.fill"
        case .moderate: return "network"
        case .high: return "exclamationmark.triangle.fill"
        case .extreme: return "flame.fill"
        }
    }
    
    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "blue"
        case .high: return "orange"
        case .extreme: return "red"
        }
    }
}

/// Historical fee record
struct FeeRecord: Codable, Identifiable {
    let id: UUID
    let chain: FeeTrackableChain
    let timestamp: Date
    let economyFee: Double
    let normalFee: Double
    let priorityFee: Double
    let mempoolSize: Int?        // Pending tx count (BTC)
    let baseFee: Double?         // EIP-1559 base fee (ETH)
    let congestionLevel: CongestionLevel
    
    init(
        chain: FeeTrackableChain,
        economyFee: Double,
        normalFee: Double,
        priorityFee: Double,
        mempoolSize: Int? = nil,
        baseFee: Double? = nil,
        congestionLevel: CongestionLevel
    ) {
        self.id = UUID()
        self.chain = chain
        self.timestamp = Date()
        self.economyFee = economyFee
        self.normalFee = normalFee
        self.priorityFee = priorityFee
        self.mempoolSize = mempoolSize
        self.baseFee = baseFee
        self.congestionLevel = congestionLevel
    }
}

/// Fee prediction for optimal timing
struct FeePrediction: Identifiable {
    let id = UUID()
    let chain: FeeTrackableChain
    let optimalHour: Int            // Hour of day (0-23)
    let optimalDay: Int             // Day of week (1-7, Sunday = 1)
    let expectedFee: Double
    let confidence: Double          // 0-1 confidence score
    let recommendation: String
}

/// Transaction fee savings record
struct FeeSavingsRecord: Codable, Identifiable {
    let id: UUID
    let chain: FeeTrackableChain
    let transactionId: String
    let actualFee: Double
    let averageFee: Double
    let savedAmount: Double
    let timestamp: Date
    
    init(chain: FeeTrackableChain, transactionId: String, actualFee: Double, averageFee: Double) {
        self.id = UUID()
        self.chain = chain
        self.transactionId = transactionId
        self.actualFee = actualFee
        self.averageFee = averageFee
        self.savedAmount = averageFee - actualFee
        self.timestamp = Date()
    }
}

/// Custom fee preset configuration
struct CustomFeePreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var chain: FeeTrackableChain
    var feeRate: Double
    var description: String
    let createdAt: Date
    var isDefault: Bool
    
    init(name: String, chain: FeeTrackableChain, feeRate: Double, description: String = "", isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.chain = chain
        self.feeRate = feeRate
        self.description = description
        self.createdAt = Date()
        self.isDefault = isDefault
    }
}

/// Fee alert configuration
struct FeeAlert: Codable, Identifiable {
    let id: UUID
    var chain: FeeTrackableChain
    var targetFee: Double
    var isBelow: Bool               // Alert when fee drops below target
    var isEnabled: Bool
    let createdAt: Date
    var lastTriggered: Date?
    
    init(chain: FeeTrackableChain, targetFee: Double, isBelow: Bool = true) {
        self.id = UUID()
        self.chain = chain
        self.targetFee = targetFee
        self.isBelow = isBelow
        self.isEnabled = true
        self.createdAt = Date()
        self.lastTriggered = nil
    }
}

// MARK: - Fee Intelligence Manager

@MainActor
final class FeeIntelligenceManager: ObservableObject {
    static let shared = FeeIntelligenceManager()
    
    // MARK: - Published Properties
    
    @Published var currentFees: [FeeTrackableChain: FeeRecord] = [:]
    @Published var feeHistory: [FeeRecord] = []
    @Published var predictions: [FeePrediction] = []
    @Published var savingsHistory: [FeeSavingsRecord] = []
    @Published var customPresets: [CustomFeePreset] = []
    @Published var feeAlerts: [FeeAlert] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var totalSavings: Double = 0
    
    // MARK: - Settings
    
    @Published var autoRefreshEnabled: Bool = true
    @Published var refreshInterval: TimeInterval = 60  // seconds
    @Published var alertsEnabled: Bool = true
    @Published var showFiatEquivalent: Bool = true
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "hawala_fee_intel_"
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        loadData()
        startAutoRefresh()
        
        print("📊 Fee Intelligence Manager initialized")
        print("   History records: \(feeHistory.count)")
        print("   Custom presets: \(customPresets.count)")
        print("   Active alerts: \(feeAlerts.filter { $0.isEnabled }.count)")
    }
    
    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Public API
    
    /// Fetch current fees for all chains
    func refreshAllFees() async {
        isLoading = true
        lastError = nil
        
        await withTaskGroup(of: Void.self) { group in
            for chain in FeeTrackableChain.allCases {
                group.addTask {
                    await self.fetchFees(for: chain)
                }
            }
        }
        
        // Check alerts after refresh
        checkAlerts()
        
        // Generate predictions
        generatePredictions()
        
        isLoading = false
        saveData()
    }
    
    /// Fetch fees for a specific chain
    func fetchFees(for chain: FeeTrackableChain) async {
        do {
            let record = try await fetchFeesFromAPI(chain: chain)
            
            await MainActor.run {
                currentFees[chain] = record
                feeHistory.append(record)
                
                // Keep only last 7 days of history
                let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                feeHistory = feeHistory.filter { $0.timestamp > cutoff }
            }
        } catch {
            await MainActor.run {
                lastError = "Failed to fetch \(chain.rawValue) fees: \(error.localizedDescription)"
            }
        }
    }
    
    /// Get recommended fee for preset
    func getRecommendedFee(chain: FeeTrackableChain, preset: FeePreset) -> Double {
        guard let record = currentFees[chain] else {
            return getDefaultFee(chain: chain, preset: preset)
        }
        
        switch preset {
        case .economy: return record.economyFee
        case .normal: return record.normalFee
        case .priority: return record.priorityFee
        case .custom: return record.normalFee
        }
    }
    
    /// Get estimated transaction cost in fiat
    func getEstimatedCost(chain: FeeTrackableChain, preset: FeePreset, txSize: Int? = nil) -> (crypto: Double, fiat: Double) {
        let feeRate = getRecommendedFee(chain: chain, preset: preset)
        let size = txSize ?? chain.typicalTxSize
        
        var cryptoCost: Double = 0
        
        switch chain {
        case .bitcoin, .litecoin:
            // sat/vB * vBytes = total sats, then convert to coin
            cryptoCost = (feeRate * Double(size)) / 100_000_000
        case .ethereum:
            // Gwei * gas = total Gwei, then convert to ETH
            cryptoCost = (feeRate * Double(size)) / 1_000_000_000
        }
        
        // Get approximate fiat value (placeholder - would use real price)
        let fiatRate: Double
        switch chain {
        case .bitcoin: fiatRate = 100_000  // ~$100k BTC
        case .ethereum: fiatRate = 4_000   // ~$4k ETH
        case .litecoin: fiatRate = 100     // ~$100 LTC
        }
        
        let fiatCost = cryptoCost * fiatRate
        return (crypto: cryptoCost, fiat: fiatCost)
    }
    
    /// Get current congestion level
    func getCongestionLevel(for chain: FeeTrackableChain) -> CongestionLevel {
        return currentFees[chain]?.congestionLevel ?? .moderate
    }
    
    /// Get optimal time to send
    func getOptimalSendTime(for chain: FeeTrackableChain) -> FeePrediction? {
        return predictions.first { $0.chain == chain }
    }
    
    /// Record a fee savings
    func recordSavings(chain: FeeTrackableChain, transactionId: String, actualFee: Double) {
        guard let current = currentFees[chain] else { return }
        
        let record = FeeSavingsRecord(
            chain: chain,
            transactionId: transactionId,
            actualFee: actualFee,
            averageFee: current.normalFee
        )
        
        savingsHistory.append(record)
        totalSavings += record.savedAmount
        saveData()
    }
    
    // MARK: - Custom Presets
    
    func addCustomPreset(_ preset: CustomFeePreset) {
        customPresets.append(preset)
        saveData()
        print("➕ Added custom fee preset: \(preset.name)")
    }
    
    func updateCustomPreset(_ preset: CustomFeePreset) {
        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
            saveData()
        }
    }
    
    func deleteCustomPreset(_ preset: CustomFeePreset) {
        customPresets.removeAll { $0.id == preset.id }
        saveData()
        print("🗑️ Deleted custom preset: \(preset.name)")
    }
    
    func getCustomPresets(for chain: FeeTrackableChain) -> [CustomFeePreset] {
        return customPresets.filter { $0.chain == chain }
    }
    
    // MARK: - Fee Alerts
    
    func addAlert(_ alert: FeeAlert) {
        feeAlerts.append(alert)
        saveData()
        print("🔔 Added fee alert: \(alert.chain.rawValue) \(alert.isBelow ? "below" : "above") \(alert.targetFee)")
    }
    
    func updateAlert(_ alert: FeeAlert) {
        if let index = feeAlerts.firstIndex(where: { $0.id == alert.id }) {
            feeAlerts[index] = alert
            saveData()
        }
    }
    
    func deleteAlert(_ alert: FeeAlert) {
        feeAlerts.removeAll { $0.id == alert.id }
        saveData()
        print("🗑️ Deleted fee alert")
    }
    
    func toggleAlert(_ alert: FeeAlert) {
        if let index = feeAlerts.firstIndex(where: { $0.id == alert.id }) {
            feeAlerts[index].isEnabled.toggle()
            saveData()
        }
    }
    
    // MARK: - Analytics
    
    /// Get fee history for a chain within time range
    func getHistory(chain: FeeTrackableChain, hours: Int = 24) -> [FeeRecord] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        return feeHistory.filter { $0.chain == chain && $0.timestamp > cutoff }
    }
    
    /// Calculate average fee for time period
    func getAverageFee(chain: FeeTrackableChain, hours: Int = 24, preset: FeePreset = .normal) -> Double {
        let records = getHistory(chain: chain, hours: hours)
        guard !records.isEmpty else { return 0 }
        
        let total: Double
        switch preset {
        case .economy:
            total = records.reduce(0) { $0 + $1.economyFee }
        case .normal, .custom:
            total = records.reduce(0) { $0 + $1.normalFee }
        case .priority:
            total = records.reduce(0) { $0 + $1.priorityFee }
        }
        
        return total / Double(records.count)
    }
    
    /// Get min/max fees for time period
    func getFeeRange(chain: FeeTrackableChain, hours: Int = 24) -> (min: Double, max: Double) {
        let records = getHistory(chain: chain, hours: hours)
        guard !records.isEmpty else { return (0, 0) }
        
        let fees = records.map { $0.normalFee }
        return (min: fees.min() ?? 0, max: fees.max() ?? 0)
    }
    
    /// Get fee volatility (standard deviation)
    func getFeeVolatility(chain: FeeTrackableChain, hours: Int = 24) -> Double {
        let records = getHistory(chain: chain, hours: hours)
        guard records.count > 1 else { return 0 }
        
        let fees = records.map { $0.normalFee }
        let mean = fees.reduce(0, +) / Double(fees.count)
        let variance = fees.map { pow($0 - mean, 2) }.reduce(0, +) / Double(fees.count)
        return sqrt(variance)
    }
    
    /// Get busiest hours of the day (for scheduling)
    func getBusiestHours(chain: FeeTrackableChain) -> [Int: Double] {
        var hourlyAverage: [Int: [Double]] = [:]
        
        for record in feeHistory.filter({ $0.chain == chain }) {
            let hour = Calendar.current.component(.hour, from: record.timestamp)
            hourlyAverage[hour, default: []].append(record.normalFee)
        }
        
        return hourlyAverage.mapValues { fees in
            fees.reduce(0, +) / Double(fees.count)
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchFeesFromAPI(chain: FeeTrackableChain) async throws -> FeeRecord {
        // Simulated fee fetching - in production, would call real APIs
        // Bitcoin: mempool.space API
        // Ethereum: eth_gasPrice or EIP-1559 eth_feeHistory
        // Litecoin: blockcypher or similar
        
        switch chain {
        case .bitcoin:
            return try await fetchBitcoinFees()
        case .ethereum:
            return try await fetchEthereumFees()
        case .litecoin:
            return try await fetchLitecoinFees()
        }
    }
    
    private func fetchBitcoinFees() async throws -> FeeRecord {
        // In production: fetch from mempool.space/api/v1/fees/recommended
        // For now, simulate realistic fee data
        
        let baseEconomy = Double.random(in: 3...8)
        let baseNormal = Double.random(in: 10...25)
        let basePriority = Double.random(in: 30...60)
        let mempoolSize = Int.random(in: 10000...150000)
        
        let congestion: CongestionLevel
        if baseNormal < 10 {
            congestion = .low
        } else if baseNormal < 25 {
            congestion = .moderate
        } else if baseNormal < 50 {
            congestion = .high
        } else {
            congestion = .extreme
        }
        
        return FeeRecord(
            chain: .bitcoin,
            economyFee: baseEconomy,
            normalFee: baseNormal,
            priorityFee: basePriority,
            mempoolSize: mempoolSize,
            congestionLevel: congestion
        )
    }
    
    private func fetchEthereumFees() async throws -> FeeRecord {
        // In production: fetch from eth_gasPrice and eth_feeHistory
        // Simulate EIP-1559 style fees (in Gwei)
        
        let baseFee = Double.random(in: 10...50)
        let economyPriority = Double.random(in: 0.5...2)
        let normalPriority = Double.random(in: 2...5)
        let highPriority = Double.random(in: 5...15)
        
        let congestion: CongestionLevel
        if baseFee < 15 {
            congestion = .low
        } else if baseFee < 30 {
            congestion = .moderate
        } else if baseFee < 60 {
            congestion = .high
        } else {
            congestion = .extreme
        }
        
        return FeeRecord(
            chain: .ethereum,
            economyFee: baseFee + economyPriority,
            normalFee: baseFee + normalPriority,
            priorityFee: baseFee + highPriority,
            baseFee: baseFee,
            congestionLevel: congestion
        )
    }
    
    private func fetchLitecoinFees() async throws -> FeeRecord {
        // Litecoin typically has very low fees
        let baseEconomy = Double.random(in: 1...3)
        let baseNormal = Double.random(in: 3...8)
        let basePriority = Double.random(in: 8...15)
        
        return FeeRecord(
            chain: .litecoin,
            economyFee: baseEconomy,
            normalFee: baseNormal,
            priorityFee: basePriority,
            congestionLevel: .low  // LTC is rarely congested
        )
    }
    
    private func getDefaultFee(chain: FeeTrackableChain, preset: FeePreset) -> Double {
        switch (chain, preset) {
        case (.bitcoin, .economy): return 5
        case (.bitcoin, .normal): return 15
        case (.bitcoin, .priority): return 40
        case (.bitcoin, .custom): return 15
        case (.ethereum, .economy): return 15
        case (.ethereum, .normal): return 25
        case (.ethereum, .priority): return 50
        case (.ethereum, .custom): return 25
        case (.litecoin, .economy): return 2
        case (.litecoin, .normal): return 5
        case (.litecoin, .priority): return 10
        case (.litecoin, .custom): return 5
        }
    }
    
    private func checkAlerts() {
        guard alertsEnabled else { return }
        
        for (index, alert) in feeAlerts.enumerated() {
            guard alert.isEnabled else { continue }
            guard let current = currentFees[alert.chain] else { continue }
            
            let triggered: Bool
            if alert.isBelow {
                triggered = current.normalFee < alert.targetFee
            } else {
                triggered = current.normalFee > alert.targetFee
            }
            
            if triggered {
                feeAlerts[index].lastTriggered = Date()
                
                // Log alert (in production would show notification)
                let direction = alert.isBelow ? "dropped below" : "rose above"
                print("🚨 Fee alert: \(alert.chain.rawValue) fees \(direction) \(alert.targetFee) \(alert.chain.feeUnit)")
            }
        }
    }
    
    private func generatePredictions() {
        predictions.removeAll()
        
        for chain in FeeTrackableChain.allCases {
            let hourlyData = getBusiestHours(chain: chain)
            guard !hourlyData.isEmpty else { continue }
            
            // Find lowest fee hour
            let optimalEntry = hourlyData.min(by: { $0.value < $1.value })
            guard let optimal = optimalEntry else { continue }
            
            // Calculate confidence based on data points
            let confidence = min(1.0, Double(feeHistory.filter { $0.chain == chain }.count) / 50.0)
            
            let prediction = FeePrediction(
                chain: chain,
                optimalHour: optimal.key,
                optimalDay: 1,  // Would need more data for day-of-week analysis
                expectedFee: optimal.value,
                confidence: confidence,
                recommendation: "Best time to send: \(formatHour(optimal.key)) when fees are typically \(String(format: "%.1f", optimal.value)) \(chain.feeUnit)"
            )
            
            predictions.append(prediction)
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        guard autoRefreshEnabled else { return }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllFees()
            }
        }
        
        // Initial fetch
        Task {
            await refreshAllFees()
        }
    }
    
    func setAutoRefresh(enabled: Bool) {
        autoRefreshEnabled = enabled
        
        if enabled {
            startAutoRefresh()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        
        saveSettings()
    }
    
    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        
        // Restart timer with new interval
        if autoRefreshEnabled {
            refreshTimer?.invalidate()
            startAutoRefresh()
        }
        
        saveSettings()
    }
    
    // MARK: - Persistence
    
    private func saveData() {
        // Save fee history
        if let data = try? JSONEncoder().encode(feeHistory) {
            userDefaults.set(data, forKey: keyPrefix + "history")
        }
        
        // Save savings history
        if let data = try? JSONEncoder().encode(savingsHistory) {
            userDefaults.set(data, forKey: keyPrefix + "savings")
        }
        
        // Save custom presets
        if let data = try? JSONEncoder().encode(customPresets) {
            userDefaults.set(data, forKey: keyPrefix + "presets")
        }
        
        // Save alerts
        if let data = try? JSONEncoder().encode(feeAlerts) {
            userDefaults.set(data, forKey: keyPrefix + "alerts")
        }
        
        userDefaults.set(totalSavings, forKey: keyPrefix + "totalSavings")
        
        saveSettings()
    }
    
    private func saveSettings() {
        userDefaults.set(autoRefreshEnabled, forKey: keyPrefix + "autoRefresh")
        userDefaults.set(refreshInterval, forKey: keyPrefix + "refreshInterval")
        userDefaults.set(alertsEnabled, forKey: keyPrefix + "alertsEnabled")
        userDefaults.set(showFiatEquivalent, forKey: keyPrefix + "showFiat")
    }
    
    private func loadData() {
        // Load fee history
        if let data = userDefaults.data(forKey: keyPrefix + "history"),
           let decoded = try? JSONDecoder().decode([FeeRecord].self, from: data) {
            feeHistory = decoded
        }
        
        // Load savings history
        if let data = userDefaults.data(forKey: keyPrefix + "savings"),
           let decoded = try? JSONDecoder().decode([FeeSavingsRecord].self, from: data) {
            savingsHistory = decoded
        }
        
        // Load custom presets
        if let data = userDefaults.data(forKey: keyPrefix + "presets"),
           let decoded = try? JSONDecoder().decode([CustomFeePreset].self, from: data) {
            customPresets = decoded
        }
        
        // Load alerts
        if let data = userDefaults.data(forKey: keyPrefix + "alerts"),
           let decoded = try? JSONDecoder().decode([FeeAlert].self, from: data) {
            feeAlerts = decoded
        }
        
        totalSavings = userDefaults.double(forKey: keyPrefix + "totalSavings")
        
        // Load settings
        if userDefaults.object(forKey: keyPrefix + "autoRefresh") != nil {
            autoRefreshEnabled = userDefaults.bool(forKey: keyPrefix + "autoRefresh")
        }
        
        if userDefaults.object(forKey: keyPrefix + "refreshInterval") != nil {
            let interval = userDefaults.double(forKey: keyPrefix + "refreshInterval")
            if interval > 0 {
                refreshInterval = interval
            }
        }
        
        if userDefaults.object(forKey: keyPrefix + "alertsEnabled") != nil {
            alertsEnabled = userDefaults.bool(forKey: keyPrefix + "alertsEnabled")
        }
        
        if userDefaults.object(forKey: keyPrefix + "showFiat") != nil {
            showFiatEquivalent = userDefaults.bool(forKey: keyPrefix + "showFiat")
        }
    }
}

// MARK: - Extensions

extension FeeIntelligenceManager {
    /// Format fee with unit
    func formatFee(_ fee: Double, chain: FeeTrackableChain) -> String {
        return String(format: "%.1f %@", fee, chain.feeUnit)
    }
    
    /// Get human-readable confirmation time estimate
    func getConfirmationEstimate(chain: FeeTrackableChain, preset: FeePreset) -> String {
        switch (chain, preset) {
        case (.bitcoin, .economy): return "~1-6 hours"
        case (.bitcoin, .normal): return "~30-60 min"
        case (.bitcoin, .priority): return "~10-20 min"
        case (.bitcoin, .custom): return "Varies"
        case (.ethereum, .economy): return "~5-15 min"
        case (.ethereum, .normal): return "~1-3 min"
        case (.ethereum, .priority): return "~15-30 sec"
        case (.ethereum, .custom): return "Varies"
        case (.litecoin, .economy): return "~10-30 min"
        case (.litecoin, .normal): return "~5-10 min"
        case (.litecoin, .priority): return "~2-5 min"
        case (.litecoin, .custom): return "Varies"
        }
    }
    
    /// Check if current is a good time to send
    func isGoodTimeToSend(chain: FeeTrackableChain) -> (good: Bool, reason: String) {
        guard let current = currentFees[chain] else {
            return (false, "Unable to determine - refresh fees first")
        }
        
        let avg = getAverageFee(chain: chain, hours: 24)
        
        if current.normalFee < avg * 0.8 {
            return (true, "Fees are 20%+ below 24h average!")
        } else if current.normalFee > avg * 1.5 {
            return (false, "Fees are elevated - consider waiting")
        } else {
            return (true, "Fees are at normal levels")
        }
    }
}
