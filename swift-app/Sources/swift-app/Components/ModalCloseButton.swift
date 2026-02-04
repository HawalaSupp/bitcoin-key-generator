import SwiftUI

// MARK: - Standard Modal Close Button

/// A consistent close button for modal sheets
/// Usage: Place in trailing position of NavigationStack toolbar
/// or in top-right of modal header
public struct ModalCloseButton: View {
    let action: () -> Void
    let style: CloseButtonStyle
    
    public enum CloseButtonStyle {
        case filled   // xmark.circle.fill (default, more prominent)
        case plain    // xmark (subtle)
        case large    // larger touch target for accessibility
    }
    
    public init(style: CloseButtonStyle = .filled, action: @escaping () -> Void) {
        self.action = action
        self.style = style
    }
    
    public var body: some View {
        Button(action: action) {
            switch style {
            case .filled:
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            case .plain:
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            case .large:
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityHint("Closes this sheet")
    }
}

// MARK: - Modal Container View

/// A container view that provides consistent modal behavior:
/// - Disables swipe-to-dismiss (use × button instead)
/// - Provides consistent close button placement
/// - Enforces gesture standards from ROADMAP-03
public struct ModalContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String?
    let showCloseButton: Bool
    let allowInteractiveDismiss: Bool
    let content: () -> Content
    
    public init(
        title: String? = nil,
        showCloseButton: Bool = true,
        allowInteractiveDismiss: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showCloseButton = showCloseButton
        self.allowInteractiveDismiss = allowInteractiveDismiss
        self.content = content
    }
    
    public var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title ?? "")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if showCloseButton {
                        ToolbarItem(placement: .cancellationAction) {
                            ModalCloseButton { dismiss() }
                        }
                    }
                }
        }
        .interactiveDismissDisabled(!allowInteractiveDismiss)
    }
}

// MARK: - View Extension for Modal Configuration

public extension View {
    /// Configure this view as a proper modal that follows Hawala gesture standards
    /// - Parameter allowSwipeDismiss: If false (default), swipe-to-dismiss is disabled
    func hawalaModal(allowSwipeDismiss: Bool = false) -> some View {
        self.interactiveDismissDisabled(!allowSwipeDismiss)
    }
    
    /// Add a standard close button to the toolbar
    func withModalCloseButton(action: @escaping () -> Void) -> some View {
        self.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ModalCloseButton(action: action)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ModalCloseButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Filled Style:")
                Spacer()
                ModalCloseButton(style: .filled) {}
            }
            
            HStack {
                Text("Plain Style:")
                Spacer()
                ModalCloseButton(style: .plain) {}
            }
            
            HStack {
                Text("Large Style:")
                Spacer()
                ModalCloseButton(style: .large) {}
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
