import Foundation
import Combine
import SwiftUI

// MARK: - Security Score Manager
/// Calculates and tracks the user's security posture across all security features
/// Gamifies security improvements with achievements and progress tracking

@MainActor
final class SecurityScoreManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var currentScore: Int = 0
    @Published private(set) var maxScore: Int = 100
    @Published private(set) var completedItems: Set<SecurityItem> = []
    @Published private(set) var achievements: [SecurityAchievement] = []
    @Published private(set) var securityLevel: SecurityLevel = .basic
    @Published private(set) var lastUpdated: Date = Date()
    
    // MARK: - Storage Keys
    private let completedItemsKey = "hawala.security.completedItems"
    private let achievementsKey = "hawala.security.achievements"
    
    // MARK: - Singleton
    static let shared = SecurityScoreManager()
    
    private init() {
        loadState()
        recalculateScore()
    }
    
    // MARK: - Security Items
    
    enum SecurityItem: String, CaseIterable, Codable, Identifiable {
        case passcodeCreated = "passcode"
        case biometricsEnabled = "biometrics"
        case backupCreated = "backup"
        case backupVerified = "backupVerified"
        case iCloudBackupEnabled = "iCloudBackup"
        case guardiansAdded = "guardians"
        case twoFactorEnabled = "twoFactor"
        case hardwareWalletConnected = "hardwareWallet"
        case autoLockEnabled = "autoLock"
        case hideBalancesEnabled = "hideBalances"
        case transactionLimitSet = "transactionLimit"
        case addressWhitelistEnabled = "addressWhitelist"
        case practiceCompleted = "practiceCompleted"
        case securityQuizPassed = "securityQuiz"
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .passcodeCreated: return "Create Passcode"
            case .biometricsEnabled: return "Enable Touch ID"
            case .backupCreated: return "Back Up Recovery Phrase"
            case .backupVerified: return "Verify Backup"
            case .iCloudBackupEnabled: return "Enable iCloud Backup"
            case .guardiansAdded: return "Add Guardian Contacts"
            case .twoFactorEnabled: return "Enable Two-Factor Auth"
            case .hardwareWalletConnected: return "Connect Hardware Wallet"
            case .autoLockEnabled: return "Enable Auto-Lock"
            case .hideBalancesEnabled: return "Enable Hide Balances"
            case .transactionLimitSet: return "Set Transaction Limits"
            case .addressWhitelistEnabled: return "Enable Address Whitelist"
            case .practiceCompleted: return "Complete Practice Mode"
            case .securityQuizPassed: return "Pass Security Quiz"
            }
        }
        
        var description: String {
            switch self {
            case .passcodeCreated: return "Protect your wallet with a PIN"
            case .biometricsEnabled: return "Use Touch ID for quick, secure access"
            case .backupCreated: return "Write down your 12/24 word recovery phrase"
            case .backupVerified: return "Verify your backup — unverified wallets lose 30 points"
            case .iCloudBackupEnabled: return "Store an encrypted backup in iCloud"
            case .guardiansAdded: return "Designate trusted contacts for recovery"
            case .twoFactorEnabled: return "Add another layer of authentication"
            case .hardwareWalletConnected: return "Use a hardware wallet for signing"
            case .autoLockEnabled: return "Automatically lock after inactivity"
            case .hideBalancesEnabled: return "Hide balances on the home screen"
            case .transactionLimitSet: return "Set daily/weekly spending limits"
            case .addressWhitelistEnabled: return "Only send to approved addresses"
            case .practiceCompleted: return "Complete a practice send/receive"
            case .securityQuizPassed: return "Demonstrate security knowledge"
            }
        }
        
        var icon: String {
            switch self {
            case .passcodeCreated: return "lock.fill"
            case .biometricsEnabled: return "touchid"
            case .backupCreated: return "doc.text.fill"
            case .backupVerified: return "checkmark.seal.fill"
            case .iCloudBackupEnabled: return "icloud.fill"
            case .guardiansAdded: return "person.2.fill"
            case .twoFactorEnabled: return "shield.checkered"
            case .hardwareWalletConnected: return "cpu.fill"
            case .autoLockEnabled: return "timer"
            case .hideBalancesEnabled: return "eye.slash.fill"
            case .transactionLimitSet: return "dollarsign.circle.fill"
            case .addressWhitelistEnabled: return "list.bullet.clipboard.fill"
            case .practiceCompleted: return "graduationcap.fill"
            case .securityQuizPassed: return "star.fill"
            }
        }
        
        var points: Int {
            switch self {
            // ROADMAP-02: backupVerified is 30 pts so unverified users face a -30 penalty
            // from maximum score. backupCreated reduced from 20→10 to keep max=100.
            case .passcodeCreated: return 15
            case .biometricsEnabled: return 10
            case .backupCreated: return 10
            case .backupVerified: return 30
            case .iCloudBackupEnabled: return 10
            case .guardiansAdded: return 10
            case .twoFactorEnabled: return 5
            case .hardwareWalletConnected: return 10
            case .autoLockEnabled: return 5
            case .hideBalancesEnabled: return 0 // Privacy, not security
            case .transactionLimitSet: return 0 // Optional
            case .addressWhitelistEnabled: return 0 // Optional
            case .practiceCompleted: return 0 // Educational
            case .securityQuizPassed: return 0 // Educational
            }
        }
        
        var category: SecurityCategory {
            switch self {
            case .passcodeCreated, .biometricsEnabled, .twoFactorEnabled, .autoLockEnabled:
                return .authentication
            case .backupCreated, .backupVerified, .iCloudBackupEnabled, .guardiansAdded:
                return .backup
            case .hardwareWalletConnected, .addressWhitelistEnabled, .transactionLimitSet:
                return .transactions
            case .hideBalancesEnabled, .practiceCompleted, .securityQuizPassed:
                return .awareness
            }
        }
        
        /// Whether this item is essential for basic security
        var isEssential: Bool {
            switch self {
            case .passcodeCreated, .backupCreated, .backupVerified:
                return true
            default:
                return false
            }
        }
    }
    
    enum SecurityCategory: String, CaseIterable {
        case authentication = "Authentication"
        case backup = "Backup & Recovery"
        case transactions = "Transaction Safety"
        case awareness = "Security Awareness"
        
        var icon: String {
            switch self {
            case .authentication: return "lock.shield.fill"
            case .backup: return "externaldrive.fill"
            case .transactions: return "arrow.left.arrow.right.circle.fill"
            case .awareness: return "lightbulb.fill"
            }
        }
        
        var items: [SecurityItem] {
            SecurityItem.allCases.filter { $0.category == self }
        }
    }
    
    enum SecurityLevel: String {
        case vulnerable = "Vulnerable"
        case basic = "Basic"
        case secure = "Secure"
        case fortress = "Fortress"
        
        var color: Color {
            switch self {
            case .vulnerable: return .red
            case .basic: return .orange
            case .secure: return .green
            case .fortress: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .vulnerable: return "exclamationmark.shield.fill"
            case .basic: return "shield.fill"
            case .secure: return "checkmark.shield.fill"
            case .fortress: return "shield.lefthalf.filled.badge.checkmark"
            }
        }
        
        var description: String {
            switch self {
            case .vulnerable: return "Your wallet needs immediate attention"
            case .basic: return "Basic protection enabled"
            case .secure: return "Good security practices in place"
            case .fortress: return "Maximum security achieved"
            }
        }
    }
    
    // MARK: - Achievements
    
    struct SecurityAchievement: Identifiable, Codable {
        let id: String
        let title: String
        let description: String
        let icon: String
        let unlockedAt: Date
        
        static let allAchievements: [String: (String, String, String)] = [
            "first_passcode": ("First Lock", "Created your first passcode", "lock.fill"),
            "backup_master": ("Backup Master", "Verified your recovery phrase", "checkmark.seal.fill"),
            "cloud_protected": ("Cloud Protected", "Enabled iCloud backup", "icloud.fill"),
            "trusted_circle": ("Trusted Circle", "Added guardian contacts", "person.2.fill"),
            "hardware_hero": ("Hardware Hero", "Connected a hardware wallet", "cpu.fill"),
            "security_scholar": ("Security Scholar", "Passed the security quiz", "graduationcap.fill"),
            "fortress_mode": ("Fortress Mode", "Achieved maximum security score", "shield.lefthalf.filled.badge.checkmark"),
            "practice_pro": ("Practice Pro", "Completed practice transactions", "star.fill")
        ]
    }
    
    // MARK: - Score Management
    
    /// Mark a security item as completed
    func complete(_ item: SecurityItem) {
        guard !completedItems.contains(item) else { return }
        
        completedItems.insert(item)
        recalculateScore()
        checkAchievements(for: item)
        saveState()
        lastUpdated = Date()
        
        #if DEBUG
        print("✅ Security item completed: \(item.title) (+\(item.points) points)")
        #endif
    }
    
    /// Mark a security item as incomplete (e.g., user disabled feature)
    func uncomplete(_ item: SecurityItem) {
        guard completedItems.contains(item) else { return }
        
        completedItems.remove(item)
        recalculateScore()
        saveState()
        lastUpdated = Date()
        
        #if DEBUG
        print("⚠️ Security item uncompleted: \(item.title)")
        #endif
    }
    
    /// Check if an item is completed
    func isCompleted(_ item: SecurityItem) -> Bool {
        completedItems.contains(item)
    }
    
    /// Get pending (not completed) items
    var pendingItems: [SecurityItem] {
        SecurityItem.allCases.filter { !completedItems.contains($0) && $0.points > 0 }
    }
    
    /// Get essential items that are still pending
    var pendingEssentialItems: [SecurityItem] {
        pendingItems.filter { $0.isEssential }
    }
    
    /// Get items by category
    func items(for category: SecurityCategory) -> [SecurityItem] {
        category.items
    }
    
    /// Get completion percentage for a category
    func completionPercentage(for category: SecurityCategory) -> Double {
        let categoryItems = items(for: category)
        guard !categoryItems.isEmpty else { return 0 }
        
        let completed = categoryItems.filter { completedItems.contains($0) }.count
        return Double(completed) / Double(categoryItems.count) * 100
    }
    
    // MARK: - Score Calculation
    
    private func recalculateScore() {
        currentScore = completedItems.reduce(0) { $0 + $1.points }
        maxScore = SecurityItem.allCases.reduce(0) { $0 + $1.points }
        
        // Determine security level
        let percentage = Double(currentScore) / Double(maxScore) * 100
        securityLevel = switch percentage {
        case 0..<25: .vulnerable
        case 25..<50: .basic
        case 50..<85: .secure
        default: .fortress
        }
    }
    
    // MARK: - Achievements
    
    private func checkAchievements(for item: SecurityItem) {
        var newAchievements: [String] = []
        
        switch item {
        case .passcodeCreated:
            newAchievements.append("first_passcode")
        case .backupVerified:
            newAchievements.append("backup_master")
        case .iCloudBackupEnabled:
            newAchievements.append("cloud_protected")
        case .guardiansAdded:
            newAchievements.append("trusted_circle")
        case .hardwareWalletConnected:
            newAchievements.append("hardware_hero")
        case .securityQuizPassed:
            newAchievements.append("security_scholar")
        case .practiceCompleted:
            newAchievements.append("practice_pro")
        default:
            break
        }
        
        // Check for fortress mode
        if securityLevel == .fortress && !achievements.contains(where: { $0.id == "fortress_mode" }) {
            newAchievements.append("fortress_mode")
        }
        
        for achievementId in newAchievements {
            unlockAchievement(achievementId)
        }
    }
    
    private func unlockAchievement(_ id: String) {
        guard !achievements.contains(where: { $0.id == id }),
              let info = SecurityAchievement.allAchievements[id] else { return }
        
        let achievement = SecurityAchievement(
            id: id,
            title: info.0,
            description: info.1,
            icon: info.2,
            unlockedAt: Date()
        )
        
        achievements.append(achievement)
        
        #if DEBUG
        print("🏆 Achievement unlocked: \(achievement.title)")
        #endif
        
        // Could show a toast/notification here
        NotificationCenter.default.post(
            name: .achievementUnlocked,
            object: achievement
        )
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        let completedRawValues = completedItems.map { $0.rawValue }
        UserDefaults.standard.set(completedRawValues, forKey: completedItemsKey)
        
        if let achievementsData = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(achievementsData, forKey: achievementsKey)
        }
    }
    
    private func loadState() {
        // Load completed items
        if let completedRawValues = UserDefaults.standard.stringArray(forKey: completedItemsKey) {
            completedItems = Set(completedRawValues.compactMap { SecurityItem(rawValue: $0) })
        }
        
        // Load achievements
        if let achievementsData = UserDefaults.standard.data(forKey: achievementsKey),
           let savedAchievements = try? JSONDecoder().decode([SecurityAchievement].self, from: achievementsData) {
            achievements = savedAchievements
        }
    }
    
    // MARK: - Reset (for testing)
    
    func resetAll() {
        completedItems.removeAll()
        achievements.removeAll()
        recalculateScore()
        saveState()
        
        #if DEBUG
        print("🔄 Security score reset")
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let achievementUnlocked = Notification.Name("com.hawala.achievementUnlocked")
    static let securityScoreChanged = Notification.Name("com.hawala.securityScoreChanged")
}

// MARK: - Security Score View

struct SecurityScoreDetailView: View {
    @ObservedObject var manager = SecurityScoreManager.shared
    @State private var selectedCategory: SecurityScoreManager.SecurityCategory?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Score Header
                scoreHeader
                
                // Categories
                categoriesSection
                
                // Recent Achievements
                if !manager.achievements.isEmpty {
                    achievementsSection
                }
                
                // Recommendations
                if !manager.pendingEssentialItems.isEmpty {
                    recommendationsSection
                }
            }
            .padding(24)
        }
        .background(Color.black)
    }
    
    private var scoreHeader: some View {
        VStack(spacing: 16) {
            // Score Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: Double(manager.currentScore) / Double(manager.maxScore))
                    .stroke(
                        manager.securityLevel.color,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(manager.currentScore)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("/ \(manager.maxScore)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Security Level Badge
            HStack(spacing: 8) {
                Image(systemName: manager.securityLevel.icon)
                Text(manager.securityLevel.rawValue)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(manager.securityLevel.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(manager.securityLevel.color.opacity(0.15))
            )
            
            Text(manager.securityLevel.description)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.bottom, 8)
    }
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security Categories")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            ForEach(SecurityScoreManager.SecurityCategory.allCases, id: \.rawValue) { category in
                CategoryRow(category: category, manager: manager)
            }
        }
    }
    
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Achievements")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(manager.achievements) { achievement in
                        AchievementBadge(achievement: achievement)
                    }
                }
            }
        }
    }
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recommended Actions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(manager.pendingEssentialItems.count) pending")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
            
            ForEach(manager.pendingEssentialItems.prefix(3)) { item in
                RecommendationRow(item: item)
            }
        }
    }
}

// MARK: - Supporting Views

private struct CategoryRow: View {
    let category: SecurityScoreManager.SecurityCategory
    @ObservedObject var manager: SecurityScoreManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: geo.size.width * manager.completionPercentage(for: category) / 100, height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Text("\(Int(manager.completionPercentage(for: category)))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct AchievementBadge: View {
    let achievement: SecurityScoreManager.SecurityAchievement
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: achievement.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
            }
            
            Text(achievement.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
    }
}

private struct RecommendationRow: View {
    let item: SecurityScoreManager.SecurityItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(.orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text("+\(item.points)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.green)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                .background(Color.orange.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#if DEBUG
struct SecurityScoreDetailView_Previews: PreviewProvider {
    static var previews: some View {
        SecurityScoreDetailView()
            .frame(width: 400, height: 700)
            .preferredColorScheme(.dark)
    }
}
#endif
