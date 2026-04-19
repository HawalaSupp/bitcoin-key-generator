import SwiftUI

// MARK: - Swap & Bridge Unified Tabs (ROADMAP-07 E8)

/// Unified view with "Swap" and "Bridge" tabs for clear distinction
struct SwapBridgeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case swap = "Swap"
        case bridge = "Bridge"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .swap: return "arrow.triangle.2.circlepath"
            case .bridge: return "point.3.connected.trianglepath.dotted"
            }
        }
    }
    
    @State private var selectedTab: Tab = .swap
    
    /// Optional wallet keys for executing swaps/bridges
    var keys: AllKeys?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabBar
            
            Divider()
            
            // Content
            switch selectedTab {
            case .swap:
                DEXAggregatorView(keys: keys)
            case .bridge:
                BridgeView(keys: keys)
            }
        }
        .navigationTitle(selectedTab.rawValue)
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        
                        // Active indicator
                        Rectangle()
                            .fill(selectedTab == tab ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preview

#if DEBUG
struct SwapBridgeView_Previews: PreviewProvider {
    static var previews: some View {
        SwapBridgeView()
    }
}
#endif
