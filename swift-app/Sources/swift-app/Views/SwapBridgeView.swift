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
    @State private var hoveringTab: Tab?
    
    /// Optional wallet keys for executing swaps/bridges
    var keys: AllKeys?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabBar
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Content
            switch selectedTab {
            case .swap:
                DEXAggregatorView(keys: keys)
            case .bridge:
                BridgeView(keys: keys)
            }
        }
        .background(HawalaTheme.Colors.background)
        .navigationTitle(selectedTab.rawValue)
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let isActive = selectedTab == tab
                let isHovering = hoveringTab == tab
                
                Button(action: {
                    withAnimation(HawalaTheme.Animation.spring) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                            Text(tab.rawValue)
                                .font(.clashGroteskMedium(size: 14))
                        }
                        .foregroundColor(isActive ? .white : (isHovering ? .white.opacity(0.6) : .white.opacity(0.35)))
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        
                        // Active indicator
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isActive ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .onHover { h in hoveringTab = h ? tab : nil }
                .animation(HawalaTheme.Animation.fast, value: isHovering)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.background)
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
