import Foundation

/// Manages transaction notes/labels stored in UserDefaults
@MainActor
class TransactionNotesManager {
    static let shared = TransactionNotesManager()
    
    private let notesKey = "hawala.transactionNotes"
    
    private init() {}
    
    /// Get note for a transaction
    func getNote(for txHash: String) -> String? {
        let notes = getAllNotes()
        return notes[txHash]
    }
    
    /// Set or update note for a transaction
    func setNote(_ note: String?, for txHash: String) {
        var notes = getAllNotes()
        if let note = note, !note.isEmpty {
            notes[txHash] = note
        } else {
            notes.removeValue(forKey: txHash)
        }
        saveNotes(notes)
    }
    
    /// Get all transaction notes
    func getAllNotes() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return notes
    }
    
    /// Delete note for a transaction
    func deleteNote(for txHash: String) {
        setNote(nil, for: txHash)
    }
    
    /// Clear all notes
    func clearAllNotes() {
        UserDefaults.standard.removeObject(forKey: notesKey)
    }
    
    private func saveNotes(_ notes: [String: String]) {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
    }
}
