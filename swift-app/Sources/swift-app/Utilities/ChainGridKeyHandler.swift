import SwiftUI

// ROADMAP-13 E6: Arrow key navigation for the chain card grid
// Wrapped in a ViewModifier with availability check since onKeyPress requires macOS 14+

struct ChainGridKeyHandler: ViewModifier {
    let filteredChains: [ChainInfo]
    var focusedChainIndex: FocusState<Int?>.Binding
    let canAccessSensitiveData: Bool
    let onSelectChain: (ChainInfo) -> Void
    let onEscape: () -> Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.downArrow) {
                    let current = focusedChainIndex.wrappedValue ?? -1
                    if current < filteredChains.count - 1 {
                        focusedChainIndex.wrappedValue = current + 1
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    let current = focusedChainIndex.wrappedValue ?? 0
                    if current > 0 {
                        focusedChainIndex.wrappedValue = current - 1
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    if let idx = focusedChainIndex.wrappedValue, idx < filteredChains.count, canAccessSensitiveData {
                        onSelectChain(filteredChains[idx])
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    onEscape() ? .handled : .ignored
                }
        } else {
            content
        }
    }
}
