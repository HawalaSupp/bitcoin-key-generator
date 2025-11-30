import SwiftUI
import AppKit

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    // MARK: - Published Properties
    
    @Published var currentTheme: AppTheme {
        didSet {
            applyTheme()
            saveTheme()
        }
    }
    
    @Published var accentColor: AccentColor {
        didSet {
            saveAccentColor()
        }
    }
    
    // MARK: - Theme Options
    
    enum AppTheme: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
        
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    
    enum AccentColor: String, CaseIterable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case orange = "Orange"
        case green = "Green"
        case cyan = "Cyan"
        
        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .orange: return .orange
            case .green: return .green
            case .cyan: return .cyan
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved theme
        if let savedTheme = UserDefaults.standard.string(forKey: "hawala_theme"),
           let theme = AppTheme(rawValue: savedTheme) {
            currentTheme = theme
        } else {
            currentTheme = .dark
        }
        
        // Load saved accent color
        if let savedAccent = UserDefaults.standard.string(forKey: "hawala_accent_color"),
           let accent = AccentColor(rawValue: savedAccent) {
            accentColor = accent
        } else {
            accentColor = .blue
        }
        
        applyTheme()
    }
    
    // MARK: - Methods
    
    func applyTheme() {
        switch currentTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    
    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: "hawala_theme")
    }
    
    private func saveAccentColor() {
        UserDefaults.standard.set(accentColor.rawValue, forKey: "hawala_accent_color")
    }
}

// MARK: - Theme Settings View

struct ThemeSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Theme selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.subheadline.bold())
                
                HStack(spacing: 12) {
                    ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                        themeButton(theme)
                    }
                }
            }
            
            Divider()
            
            // Accent color selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Accent Color")
                    .font(.subheadline.bold())
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(ThemeManager.AccentColor.allCases, id: \.self) { accent in
                        accentButton(accent)
                    }
                }
            }
            
            Divider()
            
            // Preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.subheadline.bold())
                
                themePreview
            }
        }
        .padding(20)
    }
    
    private func themeButton(_ theme: ThemeManager.AppTheme) -> some View {
        let isSelected = themeManager.currentTheme == theme
        
        return Button {
            withAnimation(.spring(response: 0.3)) {
                themeManager.currentTheme = theme
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(previewBackground(for: theme))
                        .frame(width: 60, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? themeManager.accentColor.color : Color.clear, lineWidth: 2)
                        )
                    
                    Image(systemName: theme.icon)
                        .font(.body)
                        .foregroundColor(previewForeground(for: theme))
                }
                
                Text(theme.rawValue)
                    .font(.caption)
                    .foregroundColor(isSelected ? themeManager.accentColor.color : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func previewBackground(for theme: ThemeManager.AppTheme) -> Color {
        switch theme {
        case .system:
            return colorScheme == .dark ? Color.black : Color.white
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }
    
    private func previewForeground(for theme: ThemeManager.AppTheme) -> Color {
        switch theme {
        case .system:
            return colorScheme == .dark ? Color.white : Color.black
        case .light:
            return Color.black
        case .dark:
            return Color.white
        }
    }
    
    private func accentButton(_ accent: ThemeManager.AccentColor) -> some View {
        let isSelected = themeManager.accentColor == accent
        
        return Button {
            withAnimation(.spring(response: 0.3)) {
                themeManager.accentColor = accent
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(accent.color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        isSelected ?
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        : nil
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                    )
                
                Text(accent.rawValue)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var themePreview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Sample button
                Text("Primary Button")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.accentColor.color)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                // Secondary button
                Text("Secondary")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(cardBackground)
                    .foregroundColor(.primary)
                    .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                // Sample card
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Card")
                        .font(.caption.bold())
                    Text("Preview content")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(cardBackground)
                .cornerRadius(8)
                
                // Sample badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(themeManager.accentColor.color)
                        .frame(width: 8, height: 8)
                    Text("Badge")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(themeManager.accentColor.color.opacity(0.15))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Theme Modifier

struct ThemeModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .tint(themeManager.accentColor.color)
    }
}

extension View {
    func withTheme() -> some View {
        modifier(ThemeModifier())
    }
}

// MARK: - Preview

#if DEBUG
struct ThemeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeSettingsView()
            .frame(width: 400)
            .preferredColorScheme(.dark)
    }
}
#endif
