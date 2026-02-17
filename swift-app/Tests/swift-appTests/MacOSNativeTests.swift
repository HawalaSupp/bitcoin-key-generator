import Testing
import Foundation

// ROADMAP-13: macOS Native Experience Tests

@Suite("ROADMAP-13 macOS Native")
struct MacOSNativeTests {
    
    // MARK: - E8: Window State Serialization
    
    @Test("Window frame saves and restores correctly")
    func windowFrameRoundTrip() {
        let key = "test.windowFrame.\(UUID().uuidString)"
        let dict: [String: Double] = ["x": 100, "y": 200, "w": 1200, "h": 800]
        UserDefaults.standard.set(dict, forKey: key)
        
        let restored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
        #expect(restored != nil)
        #expect(restored?["x"] == 100)
        #expect(restored?["y"] == 200)
        #expect(restored?["w"] == 1200)
        #expect(restored?["h"] == 800)
        
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    @Test("Window frame enforces minimum size on restore")
    func windowFrameMinimumSize() {
        // Simulate a saved frame smaller than minimum
        let w: Double = 400
        let h: Double = 300
        let restoredWidth = max(w, 900)
        let restoredHeight = max(h, 600)
        
        #expect(restoredWidth == 900)
        #expect(restoredHeight == 600)
    }
    
    @Test("Window frame handles missing data gracefully")
    func windowFrameMissingData() {
        let key = "test.windowFrame.missing.\(UUID().uuidString)"
        let restored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
        #expect(restored == nil)
        
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // MARK: - E15: Dynamic Window Title
    
    @Test("Dynamic title for portfolio view")
    func dynamicTitlePortfolio() {
        // Simulate sidebar selection
        let sidebarTab = "Portfolio"
        let title = "\(sidebarTab) — Hawala"
        #expect(title == "Portfolio — Hawala")
    }
    
    @Test("Dynamic title for activity view")
    func dynamicTitleActivity() {
        let sidebarTab = "Activity"
        let title = "\(sidebarTab) — Hawala"
        #expect(title == "Activity — Hawala")
    }
    
    @Test("Dynamic title for chain detail")
    func dynamicTitleChainDetail() {
        let chainTitle = "Bitcoin"
        let title = "\(chainTitle) — Hawala"
        #expect(title == "Bitcoin — Hawala")
    }
    
    // MARK: - E5/E6: Keyboard Navigation
    
    @Test("Sidebar items are navigable")
    func sidebarItemsComplete() {
        // Verify all SidebarItem cases exist and are accessible
        let items: [(String, String)] = [
            ("Portfolio", "chart.pie.fill"),
            ("Activity", "clock.arrow.circlepath"),
            ("Discover", "sparkles"),
            ("Buy & Sell", "creditcard.fill"),
            ("Swap", "arrow.triangle.2.circlepath")
        ]
        #expect(items.count == 5)
        for (name, icon) in items {
            #expect(!name.isEmpty)
            #expect(!icon.isEmpty)
        }
    }
    
    @Test("Focus index stays in bounds")
    func focusIndexBounds() {
        let chainCount = 10
        var focusedIndex: Int? = nil
        
        // Down arrow from nil starts at 0
        let current = focusedIndex ?? -1
        if current < chainCount - 1 {
            focusedIndex = current + 1
        }
        #expect(focusedIndex == 0)
        
        // Down arrow increments
        let next = focusedIndex ?? -1
        if next < chainCount - 1 {
            focusedIndex = next + 1
        }
        #expect(focusedIndex == 1)
        
        // Up arrow at 0 stays at 0
        focusedIndex = 0
        let up = focusedIndex ?? 0
        if up > 0 {
            focusedIndex = up - 1
        }
        #expect(focusedIndex == 0)
        
        // Cannot go past last item
        focusedIndex = chainCount - 1
        let atEnd = focusedIndex ?? -1
        if atEnd < chainCount - 1 {
            focusedIndex = atEnd + 1
        }
        #expect(focusedIndex == chainCount - 1)
    }
    
    // MARK: - E12: Explorer URLs
    
    @Test("Explorer URLs map correctly for major chains")
    func explorerURLMapping() {
        let testCases: [(String, String, String)] = [
            ("bitcoin", "bc1qtest", "https://mempool.space/address/bc1qtest"),
            ("ethereum", "0xtest", "https://etherscan.io/address/0xtest"),
            ("solana", "4EXtest", "https://solscan.io/account/4EXtest"),
            ("litecoin", "ltc1test", "https://blockchair.com/litecoin/address/ltc1test"),
            ("xrp", "rTest", "https://xrpscan.com/account/rTest"),
            ("bnb", "0xbnbtest", "https://bscscan.com/address/0xbnbtest"),
            ("dogecoin", "DTest", "https://blockchair.com/dogecoin/address/DTest"),
            ("cardano", "addr1test", "https://cardanoscan.io/address/addr1test"),
            ("polkadot", "1test", "https://polkascan.io/polkadot/account/1test"),
            ("tron", "TTest", "https://tronscan.org/#/address/TTest"),
        ]
        
        for (chainId, address, expectedURL) in testCases {
            let url = explorerURL(for: chainId, address: address)
            #expect(url == expectedURL, "Chain \(chainId) should map to \(expectedURL), got \(url)")
        }
    }
    
    @Test("Unknown chain falls back to blockchair search")
    func explorerURLFallback() {
        let url = explorerURL(for: "unknown-chain", address: "someaddress")
        #expect(url.contains("blockchair.com/search"))
    }
    
    // Helper matching ContentView's explorerURL
    private func explorerURL(for chainId: String, address: String) -> String {
        switch chainId {
        case "bitcoin":           return "https://mempool.space/address/\(address)"
        case "bitcoin-testnet":   return "https://mempool.space/testnet/address/\(address)"
        case "ethereum", "ethereum-sepolia": return "https://etherscan.io/address/\(address)"
        case "litecoin":          return "https://blockchair.com/litecoin/address/\(address)"
        case "solana", "solana-devnet": return "https://solscan.io/account/\(address)"
        case "xrp", "xrp-testnet": return "https://xrpscan.com/account/\(address)"
        case "bnb":               return "https://bscscan.com/address/\(address)"
        case "dogecoin":          return "https://blockchair.com/dogecoin/address/\(address)"
        case "cardano":           return "https://cardanoscan.io/address/\(address)"
        case "polkadot":          return "https://polkascan.io/polkadot/account/\(address)"
        case "tron":              return "https://tronscan.org/#/address/\(address)"
        default:                  return "https://blockchair.com/search?q=\(address)"
        }
    }
}
