import Testing
import Foundation
import GRDB
@testable import swift_app

@Suite
struct TransactionRawDataPersistenceTests {

    @MainActor
    @Test func testEnsureActiveWalletRecordCreatesRow() async throws {
        // Ensure there is at least one wallet in the WalletRepository.
        // (This is a lightweight, local-only wallet profile; no network.)
        if WalletRepository.shared.wallets.isEmpty {
            _ = try await WalletRepository.shared.createWallet(
                name: "Test Wallet Repo",
                seedPhrase: Array(repeating: "abandon", count: 12),
                passphrase: nil,
                isWatchOnly: false
            )
        }

        let walletId = try await TransactionStore.shared.ensureActiveWalletRecord()
        #expect(!(walletId.isEmpty))

        // Verify row exists.
        let exists = try DatabaseManager.shared.read { db in
            try WalletRecord.filter(Column("id") == walletId).fetchCount(db) > 0
        }
        #expect(exists)
    }

    @Test func testTransactionRecordRawDataRoundTrip() async throws {
        // Ensure a wallet exists for the transaction foreign key.
        let walletId = UUID().uuidString
        let wallet = WalletRecord(
            id: walletId,
            name: "Test Wallet",
            createdAt: Date(),
            isWatchOnly: false,
            colorIndex: 0,
            displayOrder: 0,
            lastSyncedAt: nil
        )
        try DatabaseManager.shared.write { db in
            try wallet.save(db)
        }

        // Use a unique tx hash so repeated test runs don't collide.
        let txHash = "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let chainId = "ethereum-sepolia"

        let rawHex = "0x02deadbeef"
        guard let rawData = rawHex.data(using: .utf8) else {
            #expect(Bool(false), "Failed to create raw data")
            return
        }

        // Create a minimal transaction record first.
        let record = TransactionRecord.from(
            walletId: walletId,
            chainId: chainId,
            txHash: txHash,
            type: .send,
            fromAddress: nil,
            toAddress: nil,
            amount: "0",
            fee: nil,
            asset: "ETH",
            timestamp: Date(),
            status: .pending
        )
        try await TransactionStore.shared.save(record)

        try await TransactionStore.shared.attachRawData(txHash: txHash, chainId: chainId, rawData: rawData)

        let loaded = try await TransactionStore.shared.fetchRawData(txHash: txHash, chainId: chainId)
        #expect(loaded == rawData)

        // Ensure it decodes back to the same string.
        guard let loadedData = loaded else {
            #expect(Bool(false), "Loaded data was nil")
            return
        }
        let loadedString = String(data: loadedData, encoding: .utf8)
        #expect(loadedString == rawHex)
    }
}
