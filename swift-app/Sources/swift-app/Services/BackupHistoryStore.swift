import Foundation

// MARK: - Backup History Store

/// Persists real backup events (phrase views, exports, imports, verifications) in UserDefaults.
@MainActor
final class BackupHistoryStore: ObservableObject {

    static let shared = BackupHistoryStore()

    private let key = "com.hawala.backup.history"
    private let reminderKey = "com.hawala.backup.reminderMonths"

    @Published var entries: [BackupHistoryEntry] = []

    /// Reminder interval in months (1, 3, 6, or 0 = never)
    @Published var reminderMonths: Int {
        didSet { UserDefaults.standard.set(reminderMonths, forKey: reminderKey) }
    }

    // MARK: - Computed

    var isBackedUp: Bool {
        entries.contains { $0.eventType == .exportCreated }
    }

    var lastVerifiedDate: Date? {
        entries.first(where: { $0.eventType == .verificationPassed })?.date
    }

    var lastExportDate: Date? {
        entries.first(where: { $0.eventType == .exportCreated })?.date
    }

    var lastImportDate: Date? {
        entries.first(where: { $0.eventType == .importCompleted })?.date
    }

    // MARK: - Init

    private init() {
        self.reminderMonths = UserDefaults.standard.object(forKey: reminderKey) as? Int ?? 3
        self.entries = Self.load(key: key)
    }

    // MARK: - Mutating

    func recordEvent(_ type: BackupEventType, detail: String) {
        let entry = BackupHistoryEntry(
            id: UUID(),
            eventType: type,
            detail: detail,
            date: Date()
        )
        entries.insert(entry, at: 0)
        // Cap at 50 entries
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        save()
    }

    func clearHistory() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(key: String) -> [BackupHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([BackupHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }
}

// MARK: - Models

enum BackupEventType: String, Codable {
    case phraseViewed
    case verificationPassed
    case verificationFailed
    case exportCreated
    case importCompleted
}

struct BackupHistoryEntry: Identifiable, Codable {
    let id: UUID
    let eventType: BackupEventType
    let detail: String
    let date: Date

    var icon: String {
        switch eventType {
        case .phraseViewed:         return "eye"
        case .verificationPassed:   return "checkmark.shield"
        case .verificationFailed:   return "xmark.shield"
        case .exportCreated:        return "arrow.down.doc"
        case .importCompleted:      return "arrow.up.doc"
        }
    }

    var actionLabel: String {
        switch eventType {
        case .phraseViewed:         return "PHRASE VIEWED"
        case .verificationPassed:   return "VERIFICATION PASSED"
        case .verificationFailed:   return "VERIFICATION FAILED"
        case .exportCreated:        return "BACKUP EXPORTED"
        case .importCompleted:      return "BACKUP IMPORTED"
        }
    }
}
