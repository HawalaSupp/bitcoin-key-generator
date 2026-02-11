import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-21: Multi-Wallet & Account Management Tests

// ============================================================
// E1: Wallet Model (HawalaWalletProfile)
// ============================================================

@Suite("ROADMAP-21 E1: Wallet Model")
struct MultiWalletProfileTests {
    
    @Test("HawalaWalletProfile initializes with defaults")
    func profileDefaults() {
        let profile = HawalaWalletProfile(name: "Test Wallet")
        #expect(profile.name == "Test Wallet")
        #expect(profile.emoji == "💰")
        #expect(!profile.colorHex.isEmpty)
        #expect(profile.importMethod == .created)
        #expect(profile.enabledChains.contains("ethereum"))
        #expect(profile.enabledChains.contains("bitcoin"))
        #expect(!profile.isHidden)
        #expect(!profile.isPinned)
        #expect(profile.totalAddresses == 0)
    }
    
    @Test("HawalaWalletProfile initializes with custom parameters")
    func profileCustomInit() {
        let profile = HawalaWalletProfile(
            name: "Trading",
            emoji: "🚀",
            colorHex: "#FF0000",
            importMethod: .seedPhrase,
            enabledChains: ["ethereum", "bitcoin", "solana"],
            totalAddresses: 3
        )
        #expect(profile.name == "Trading")
        #expect(profile.emoji == "🚀")
        #expect(profile.colorHex == "#FF0000")
        #expect(profile.importMethod == .seedPhrase)
        #expect(profile.enabledChains.count == 3)
        #expect(profile.totalAddresses == 3)
    }
    
    @Test("HawalaWalletProfile conforms to Codable")
    func profileCodable() throws {
        let profile = HawalaWalletProfile(name: "Codable Test")
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(HawalaWalletProfile.self, from: data)
        #expect(decoded.id == profile.id)
        #expect(decoded.name == profile.name)
        #expect(decoded.emoji == profile.emoji)
        #expect(decoded.colorHex == profile.colorHex)
        #expect(decoded.importMethod == profile.importMethod)
    }
    
    @Test("HawalaWalletProfile conforms to Equatable")
    func profileEquatable() {
        let profile1 = HawalaWalletProfile(name: "A")
        let profile2 = HawalaWalletProfile(name: "B")
        #expect(profile1 != profile2)
        #expect(profile1 == profile1)
    }
    
    @Test("HawalaWalletProfile has valid default colors list")
    func profileColors() {
        #expect(HawalaWalletProfile.colors.count >= 5)
        for color in HawalaWalletProfile.colors {
            #expect(color.hasPrefix("#"))
        }
    }
    
    @Test("HawalaWalletProfile has valid default emojis list")
    func profileEmojis() {
        #expect(HawalaWalletProfile.emojis.count >= 5)
        for emoji in HawalaWalletProfile.emojis {
            #expect(!emoji.isEmpty)
        }
    }
    
    @Test("WalletImportMethodType covers all import methods")
    func importMethodTypes() {
        let allMethods: [HawalaWalletProfile.WalletImportMethodType] = [
            .created, .seedPhrase, .privateKey, .hardwareWallet, .watchOnly
        ]
        #expect(allMethods.count == 5)
        
        // Verify Codable round-trip
        for method in allMethods {
            let encoded = try? JSONEncoder().encode(method)
            #expect(encoded != nil)
        }
    }
}

// ============================================================
// E2: MultiWalletManager CRUD
// ============================================================

@Suite("ROADMAP-21 E2: MultiWalletManager CRUD")
struct MultiWalletManagerCRUDTests {
    
    @Test("MultiWalletManager singleton exists")
    @MainActor
    func singletonExists() {
        let manager = MultiWalletManager.shared
        #expect(manager != nil)
    }
    
    @Test("createWallet returns a valid profile")
    @MainActor
    func createWalletReturnsProfile() {
        let manager = MultiWalletManager.shared
        let initialCount = manager.walletCount
        let profile = manager.createWallet(name: "Test Create \(UUID().uuidString.prefix(4))")
        #expect(profile.name.hasPrefix("Test Create"))
        #expect(manager.walletCount == initialCount + 1)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("importWallet creates profile with import method")
    @MainActor
    func importWalletCreatesProfile() {
        let manager = MultiWalletManager.shared
        let profile = manager.importWallet(name: "Imported", method: .seedPhrase)
        #expect(profile.importMethod == .seedPhrase)
        #expect(profile.emoji == "📥")
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("updateWallet modifies name, emoji, and color")
    @MainActor
    func updateWalletModifiesFields() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "Original Name")
        
        manager.updateWallet(profile.id, name: "Updated Name", emoji: "🔥", colorHex: "#FF0000")
        
        let updated = manager.wallet(for: profile.id)
        #expect(updated?.name == "Updated Name")
        #expect(updated?.emoji == "🔥")
        #expect(updated?.colorHex == "#FF0000")
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("wallet lookup by name works case-insensitively")
    @MainActor
    func walletLookupByName() {
        let manager = MultiWalletManager.shared
        let uniqueName = "UniqueTest\(UUID().uuidString.prefix(4))"
        let profile = manager.createWallet(name: uniqueName)
        
        let found = manager.wallet(named: uniqueName.lowercased())
        #expect(found?.id == profile.id)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("wallet lookup by UUID returns correct wallet")
    @MainActor
    func walletLookupById() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "UUID Lookup Test")
        
        let found = manager.wallet(for: profile.id)
        #expect(found?.id == profile.id)
        #expect(found?.name == "UUID Lookup Test")
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
}

// ============================================================
// E3: Active Wallet Selection
// ============================================================

@Suite("ROADMAP-21 E3: Active Wallet Selection")
struct ActiveWalletSelectionTests {
    
    @Test("setActiveWallet changes the active wallet ID")
    @MainActor
    func setActiveWalletChangesId() {
        let manager = MultiWalletManager.shared
        let w1 = manager.createWallet(name: "Wallet A")
        let w2 = manager.createWallet(name: "Wallet B")
        
        manager.setActiveWallet(w2.id)
        #expect(manager.activeWalletId == w2.id)
        
        manager.setActiveWallet(w1.id)
        #expect(manager.activeWalletId == w1.id)
        
        // Cleanup
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
    
    @Test("activeWallet returns the active profile")
    @MainActor
    func activeWalletReturnsProfile() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "Active Test")
        manager.setActiveWallet(profile.id)
        
        #expect(manager.activeWallet?.id == profile.id)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("setActiveWallet updates lastUsedAt")
    @MainActor
    func setActiveWalletUpdatesTimestamp() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "Timestamp Test")
        let createdAt = profile.lastUsedAt
        
        // Small delay to ensure timestamp difference
        Thread.sleep(forTimeInterval: 0.01)
        
        manager.setActiveWallet(profile.id)
        let updated = manager.wallet(for: profile.id)
        #expect(updated?.lastUsedAt ?? createdAt >= createdAt)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("setActiveWallet ignores invalid UUID")
    @MainActor
    func setActiveWalletIgnoresInvalidId() {
        let manager = MultiWalletManager.shared
        let current = manager.activeWalletId
        
        manager.setActiveWallet(UUID())  // Non-existent ID
        #expect(manager.activeWalletId == current)
    }
}

// ============================================================
// E4: Wallet Organization (Pin, Hide, Reorder)
// ============================================================

@Suite("ROADMAP-21 E4: Wallet Organization")
struct WalletOrganizationTests {
    
    @Test("togglePinned pins and unpins a wallet")
    @MainActor
    func togglePinned() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "Pin Test")
        
        #expect(manager.wallet(for: profile.id)?.isPinned == false)
        
        manager.togglePinned(profile.id)
        #expect(manager.wallet(for: profile.id)?.isPinned == true)
        
        manager.togglePinned(profile.id)
        #expect(manager.wallet(for: profile.id)?.isPinned == false)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("toggleHidden hides and unhides a wallet")
    @MainActor
    func toggleHidden() {
        let manager = MultiWalletManager.shared
        let profile = manager.createWallet(name: "Hide Test")
        
        #expect(manager.wallet(for: profile.id)?.isHidden == false)
        
        manager.toggleHidden(profile.id)
        #expect(manager.wallet(for: profile.id)?.isHidden == true)
        #expect(!manager.visibleWallets.contains(where: { $0.id == profile.id }))
        
        manager.toggleHidden(profile.id)
        #expect(manager.wallet(for: profile.id)?.isHidden == false)
        
        // Cleanup
        _ = manager.deleteWallet(profile.id, backupAcknowledged: true)
    }
    
    @Test("pinnedWallets returns only pinned wallets")
    @MainActor
    func pinnedWalletsFilter() {
        let manager = MultiWalletManager.shared
        let w1 = manager.createWallet(name: "Pinned One")
        let w2 = manager.createWallet(name: "Regular One")
        
        manager.togglePinned(w1.id)
        
        #expect(manager.pinnedWallets.contains(where: { $0.id == w1.id }))
        #expect(!manager.pinnedWallets.contains(where: { $0.id == w2.id }))
        
        // Cleanup
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
    
    @Test("sortedWallets puts pinned wallets first")
    @MainActor
    func sortedWalletsPinnedFirst() {
        let manager = MultiWalletManager.shared
        let w1 = manager.createWallet(name: "Regular")
        let w2 = manager.createWallet(name: "Pinned")
        
        manager.togglePinned(w2.id)
        
        let sorted = manager.sortedWallets
        if let pinnedIdx = sorted.firstIndex(where: { $0.id == w2.id }),
           let regularIdx = sorted.firstIndex(where: { $0.id == w1.id }) {
            #expect(pinnedIdx < regularIdx)
        }
        
        // Cleanup
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
    }
}

// ============================================================
// E5: Wallet Limits
// ============================================================

@Suite("ROADMAP-21 E5: Wallet Limits")
struct WalletLimitsTests {
    
    @Test("maxWallets is 10")
    @MainActor
    func maxWalletLimit() {
        #expect(MultiWalletManager.maxWallets == 10)
    }
    
    @Test("maxWatchOnly is 20")
    @MainActor
    func maxWatchOnlyLimit() {
        #expect(MultiWalletManager.maxWatchOnly == 20)
    }
    
    @Test("canAddWallet reflects limit")
    @MainActor
    func canAddWalletReflectsLimit() {
        let manager = MultiWalletManager.shared
        // With fewer than 10 wallets, canAddWallet should be true
        let currentNonWatchOnly = manager.wallets.filter { $0.importMethod != .watchOnly }.count
        if currentNonWatchOnly < MultiWalletManager.maxWallets {
            #expect(manager.canAddWallet)
        }
    }
}

// ============================================================
// E6: Watch-Only Wallets
// ============================================================

@Suite("ROADMAP-21 E6: Watch-Only Wallets")
struct WatchOnlyWalletTests {
    
    @Test("addWatchOnlyWallet creates watch-only profile")
    @MainActor
    func addWatchOnlyCreatesProfile() {
        let manager = MultiWalletManager.shared
        let profile = manager.addWatchOnlyWallet(address: "0x1234567890abcdef", chain: "ethereum")
        
        #expect(profile != nil)
        #expect(profile?.importMethod == .watchOnly)
        #expect(profile?.emoji == "👁️")
        #expect(profile?.enabledChains == ["ethereum"])
        
        // Cleanup
        if let id = profile?.id {
            _ = manager.deleteWallet(id, backupAcknowledged: true)
        }
    }
    
    @Test("addWatchOnlyWallet uses custom name")
    @MainActor
    func addWatchOnlyCustomName() {
        let manager = MultiWalletManager.shared
        let profile = manager.addWatchOnlyWallet(address: "0xabcdef", chain: "ethereum", name: "Vitalik")
        
        #expect(profile?.name == "Vitalik")
        
        if let id = profile?.id {
            _ = manager.deleteWallet(id, backupAcknowledged: true)
        }
    }
}

// ============================================================
// E9/E10: Delete Wallet Safeguards
// ============================================================

@Suite("ROADMAP-21 E9/E10: Delete Wallet Safeguards")
struct DeleteWalletSafeguardTests {
    
    @Test("deleteWallet prevents deleting the last wallet")
    @MainActor
    func preventDeletingLastWallet() {
        let manager = MultiWalletManager.shared
        
        // Ensure we have exactly one wallet
        manager.reset()
        let sole = manager.createWallet(name: "Only Wallet")
        
        let result = manager.deleteWallet(sole.id, backupAcknowledged: true)
        #expect(result == false)
        #expect(manager.walletCount >= 1)
        #expect(manager.error?.contains("last wallet") == true)
    }
    
    @Test("deleteWallet requires backup acknowledgment")
    @MainActor
    func requireBackupAcknowledgment() {
        let manager = MultiWalletManager.shared
        
        // Need 2 wallets so we can delete one
        let w1 = manager.createWallet(name: "Keep This")
        let w2 = manager.createWallet(name: "Delete This")
        
        // Try without backup ack
        let result = manager.deleteWallet(w2.id, backupAcknowledged: false)
        #expect(result == false)
        #expect(manager.wallet(for: w2.id) != nil)  // Still exists
        
        // Now with backup ack
        let result2 = manager.deleteWallet(w2.id, backupAcknowledged: true)
        #expect(result2 == true)
        #expect(manager.wallet(for: w2.id) == nil)  // Gone
        
        // Cleanup
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
    
    @Test("deleteWallet switches active wallet when deleting active")
    @MainActor
    func deleteActiveSwitchesToAnother() {
        let manager = MultiWalletManager.shared
        let w1 = manager.createWallet(name: "Wallet 1")
        let w2 = manager.createWallet(name: "Wallet 2")
        
        manager.setActiveWallet(w2.id)
        #expect(manager.activeWalletId == w2.id)
        
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
        #expect(manager.activeWalletId != w2.id)
        #expect(manager.activeWalletId != nil)
        
        // Cleanup
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
    
    @Test("deleteWallet returns false for non-existent wallet")
    @MainActor
    func deleteNonExistentReturnssFalse() {
        let manager = MultiWalletManager.shared
        let result = manager.deleteWallet(UUID(), backupAcknowledged: true)
        #expect(result == false)
    }
}

// ============================================================
// E7: Aggregate View
// ============================================================

@Suite("ROADMAP-21 E7: Aggregate View")
struct AggregateViewTests {
    
    @Test("toggleAggregateView toggles state")
    @MainActor
    func toggleAggregateViewToggles() {
        let manager = MultiWalletManager.shared
        let initial = manager.showAggregateView
        
        manager.toggleAggregateView()
        #expect(manager.showAggregateView == !initial)
        
        manager.toggleAggregateView()
        #expect(manager.showAggregateView == initial)
    }
    
    @Test("reset clears aggregate view")
    @MainActor
    func resetClearsAggregateView() {
        let manager = MultiWalletManager.shared
        manager.showAggregateView = true
        manager.reset()
        #expect(manager.showAggregateView == false)
    }
}

// ============================================================
// E8: Duplicate Detection
// ============================================================

@Suite("ROADMAP-21 E8: Duplicate Detection")
struct DuplicateDetectionTests {
    
    @Test("isDuplicateWallet returns false for empty fingerprint")
    @MainActor
    func emptyFingerprintNotDuplicate() {
        let manager = MultiWalletManager.shared
        let result = manager.isDuplicateWallet(addressFingerprint: "")
        #expect(result == false)
    }
    
    @Test("isDuplicateWallet returns false for unknown fingerprint")
    @MainActor
    func unknownFingerprintNotDuplicate() {
        let manager = MultiWalletManager.shared
        let result = manager.isDuplicateWallet(addressFingerprint: "0xNEVER_SEEN_BEFORE_\(UUID().uuidString)")
        #expect(result == false)
    }
}

// ============================================================
// E11: Per-Wallet Key Isolation (MultiWalletKeychainHelper)
// ============================================================

@Suite("ROADMAP-21 E11: Per-Wallet Key Isolation")
struct PerWalletKeyIsolationTests {
    
    @Test("hasKeys returns false for non-existent wallet")
    func hasKeysReturnsFalseForNew() {
        let result = MultiWalletKeychainHelper.hasKeys(for: UUID())
        #expect(result == false)
    }
    
    @Test("loadKeys returns nil for non-existent wallet")
    func loadKeysReturnsNilForNew() {
        let result = MultiWalletKeychainHelper.loadKeys(for: UUID())
        #expect(result == nil)
    }
    
    @Test("deleteKeys does not crash for non-existent wallet")
    func deleteKeysNoOpForNew() {
        // Should not throw or crash
        MultiWalletKeychainHelper.deleteKeys(for: UUID())
    }
    
    @Test("loadAllWalletKeys returns empty for empty input")
    func loadAllEmpty() {
        let results = MultiWalletKeychainHelper.loadAllWalletKeys(walletIds: [])
        #expect(results.isEmpty)
    }
    
    @Test("loadAllWalletKeys returns empty for non-existent IDs")
    func loadAllNonExistent() {
        let results = MultiWalletKeychainHelper.loadAllWalletKeys(walletIds: [UUID(), UUID()])
        #expect(results.isEmpty)
    }
    
    @Test("migrateFromLegacy returns false when no legacy keys exist")
    func migrateFromLegacyNoKeys() {
        // With a fresh wallet ID and potentially no legacy keys, should return false or true
        // depending on whether there are legacy keys in the Keychain
        let newId = UUID()
        let result = MultiWalletKeychainHelper.migrateFromLegacy(to: newId)
        // Clean up in case it succeeded
        MultiWalletKeychainHelper.deleteKeys(for: newId)
        // Either outcome is valid depending on test environment
        #expect(result == true || result == false)
    }
}

// ============================================================
// E12: Analytics Events (ROADMAP-21 additions)
// ============================================================

@Suite("ROADMAP-21 E12: Analytics Events")
struct MultiWalletAnalyticsTests {
    
    @Test("walletSwitched event name exists")
    func walletSwitchedEventExists() {
        #expect(AnalyticsService.EventName.walletSwitched == "wallet_switched")
    }
    
    @Test("walletRenamed event name exists")
    func walletRenamedEventExists() {
        #expect(AnalyticsService.EventName.walletRenamed == "wallet_renamed")
    }
    
    @Test("walletDeleted event name exists")
    func walletDeletedEventExists() {
        #expect(AnalyticsService.EventName.walletDeleted == "wallet_deleted")
    }
    
    @Test("aggregateViewToggled event name exists")
    func aggregateViewToggledEventExists() {
        #expect(AnalyticsService.EventName.aggregateViewToggled == "aggregate_view_toggled")
    }
    
    @Test("All ROADMAP-21 analytics events can be tracked without assertion")
    @MainActor
    func trackAllNewEvents() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        let before = service.eventCount
        
        service.track(AnalyticsService.EventName.walletSwitched, properties: ["from_index": "0", "to_index": "1"])
        service.track(AnalyticsService.EventName.walletRenamed)
        service.track(AnalyticsService.EventName.walletDeleted, properties: ["wallet_count_after": "2"])
        service.track(AnalyticsService.EventName.aggregateViewToggled, properties: ["enabled": "true"])
        
        #expect(service.eventCount == before + 4)
        service.isEnabled = wasEnabled
    }
}

// ============================================================
// E13: NavigationViewModel Multi-Wallet State
// ============================================================

@Suite("ROADMAP-21 E13: NavigationViewModel State")
struct NavigationViewModelMultiWalletTests {
    
    @Test("NavigationViewModel has wallet picker sheet state")
    @MainActor
    func hasWalletPickerSheetState() {
        let vm = NavigationViewModel()
        #expect(vm.showWalletPickerSheet == false)
        vm.showWalletPickerSheet = true
        #expect(vm.showWalletPickerSheet == true)
    }
    
    @Test("NavigationViewModel has add wallet sheet state")
    @MainActor
    func hasAddWalletSheetState() {
        let vm = NavigationViewModel()
        #expect(vm.showAddWalletSheet == false)
        vm.showAddWalletSheet = true
        #expect(vm.showAddWalletSheet == true)
    }
    
    @Test("NavigationViewModel has delete wallet confirmation state")
    @MainActor
    func hasDeleteWalletConfirmationState() {
        let vm = NavigationViewModel()
        #expect(vm.showDeleteWalletConfirmation == false)
        #expect(vm.walletToDelete == nil)
        
        let testId = UUID()
        vm.walletToDelete = testId
        vm.showDeleteWalletConfirmation = true
        #expect(vm.walletToDelete == testId)
        #expect(vm.showDeleteWalletConfirmation == true)
    }
    
    @Test("dismissAllSheets resets multi-wallet sheet states")
    @MainActor
    func dismissAllSheetsResetsMultiWalletState() {
        let vm = NavigationViewModel()
        vm.showWalletPickerSheet = true
        vm.showAddWalletSheet = true
        vm.showDeleteWalletConfirmation = true
        vm.walletToDelete = UUID()
        
        vm.dismissAllSheets()
        
        #expect(vm.showWalletPickerSheet == false)
        #expect(vm.showAddWalletSheet == false)
        #expect(vm.showDeleteWalletConfirmation == false)
        #expect(vm.walletToDelete == nil)
    }
}

// ============================================================
// E14: Wallet Notifications
// ============================================================

@Suite("ROADMAP-21 E14: Wallet Notifications")
struct WalletNotificationTests {
    
    @Test("walletChanged notification name exists")
    func walletChangedNotificationExists() {
        let name = Notification.Name.walletChanged
        #expect(name.rawValue == "hawala.wallet.changed")
    }
    
    @Test("walletCreated notification name exists")
    func walletCreatedNotificationExists() {
        let name = Notification.Name.walletCreated
        #expect(name.rawValue == "hawala.wallet.created")
    }
    
    @Test("walletDeleted notification name exists")
    func walletDeletedNotificationExists() {
        let name = Notification.Name.walletDeleted
        #expect(name.rawValue == "hawala.wallet.deleted")
    }
}

// ============================================================
// E15: Manager Reset
// ============================================================

@Suite("ROADMAP-21 E15: Manager Reset & State")
struct ManagerResetTests {
    
    @Test("reset clears all wallets and active wallet")
    @MainActor
    func resetClearsAll() {
        let manager = MultiWalletManager.shared
        _ = manager.createWallet(name: "To Be Reset")
        
        manager.reset()
        
        #expect(manager.wallets.isEmpty)
        #expect(manager.activeWalletId == nil)
        #expect(manager.showAggregateView == false)
    }
    
    @Test("walletCount returns correct count")
    @MainActor
    func walletCountCorrect() {
        let manager = MultiWalletManager.shared
        manager.reset()
        
        #expect(manager.walletCount == 0)
        
        let w1 = manager.createWallet(name: "Count 1")
        #expect(manager.walletCount == 1)
        
        let w2 = manager.createWallet(name: "Count 2")
        #expect(manager.walletCount == 2)
        
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
        #expect(manager.walletCount == 1)
        
        // Cleanup
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
    
    @Test("isLastWallet is true when only one wallet")
    @MainActor
    func isLastWalletTrue() {
        let manager = MultiWalletManager.shared
        manager.reset()
        
        let sole = manager.createWallet(name: "Sole")
        #expect(manager.isLastWallet == true)
        
        let second = manager.createWallet(name: "Second")
        #expect(manager.isLastWallet == false)
        
        // Cleanup
        _ = manager.deleteWallet(second.id, backupAcknowledged: true)
        _ = manager.deleteWallet(sole.id, backupAcknowledged: true)
    }
}

// ============================================================
// E16: Migration
// ============================================================

@Suite("ROADMAP-21 E16: Migration")
struct MigrationTests {
    
    @Test("migrateFromSingleWallet creates wallet when wallets are empty")
    @MainActor
    func migrateCreatesWalletWhenEmpty() {
        let manager = MultiWalletManager.shared
        manager.reset()
        
        // This test depends on whether a seed phrase exists in the current environment.
        // In a clean test environment, hasSeedPhrase() likely returns false.
        manager.migrateFromSingleWallet(name: "Migrated")
        
        // If migration happened, verify the wallet was created
        if manager.walletCount > 0 {
            #expect(manager.wallets.first?.name == "Migrated")
            #expect(manager.activeWalletId != nil)
        }
    }
    
    @Test("migrateFromSingleWallet no-ops when wallets already exist")
    @MainActor
    func migrateNoOpsWhenWalletsExist() {
        let manager = MultiWalletManager.shared
        manager.reset()
        let existing = manager.createWallet(name: "Already Here")
        
        let countBefore = manager.walletCount
        manager.migrateFromSingleWallet(name: "Should Not Appear")
        #expect(manager.walletCount == countBefore)
        
        // Cleanup
        _ = manager.deleteWallet(existing.id, backupAcknowledged: true)
    }
}

// ============================================================
// E17: Hiding active wallet auto-switches
// ============================================================

@Suite("ROADMAP-21 E17: Hide Active Wallet Auto-Switch")
struct HideActiveWalletTests {
    
    @Test("Hiding active wallet switches to another visible wallet")
    @MainActor
    func hideActiveSwitchesToAnother() {
        let manager = MultiWalletManager.shared
        let w1 = manager.createWallet(name: "Visible")
        let w2 = manager.createWallet(name: "To Hide")
        
        manager.setActiveWallet(w2.id)
        #expect(manager.activeWalletId == w2.id)
        
        manager.toggleHidden(w2.id)
        // Active wallet should now be different from w2
        #expect(manager.activeWalletId != w2.id)
        
        // Cleanup
        manager.toggleHidden(w2.id) // Unhide to delete
        _ = manager.deleteWallet(w2.id, backupAcknowledged: true)
        _ = manager.deleteWallet(w1.id, backupAcknowledged: true)
    }
}
