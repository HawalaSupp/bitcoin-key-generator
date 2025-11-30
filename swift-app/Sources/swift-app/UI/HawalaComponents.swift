import SwiftUI

// MARK: - Hawala UI Components
// Reusable components following the design system

// MARK: - Animated Counter
struct AnimatedCounter: View {
    let value: Double
    let prefix: String
    let duration: Double
    let hideBalance: Bool
    
    @State private var displayValue: Double = 0
    @State private var hasAnimated = false
    
    init(value: Double, prefix: String = "$", duration: Double = 1.2, hideBalance: Bool = false) {
        self.value = value
        self.prefix = prefix
        self.duration = duration
        self.hideBalance = hideBalance
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HawalaTheme.Spacing.sm) {
            Text(prefix)
                .font(HawalaTheme.Typography.display(36))
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            if hideBalance {
                Text("•••••")
                    .font(HawalaTheme.Typography.display(48))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            } else {
                Text(formatNumber(displayValue))
                    .font(HawalaTheme.Typography.display(48))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
        .onAppear {
            if !hasAnimated && !hideBalance {
                animateValue()
                hasAnimated = true
            }
        }
        .onChange(of: value) { newValue in
            if !hideBalance {
                animateValue()
            }
        }
    }
    
    private func animateValue() {
        let startValue = displayValue
        let difference = value - startValue
        let steps = 60
        let stepDuration = duration / Double(steps)
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                let progress = easeOutCubic(Double(step) / Double(steps))
                withAnimation(.easeOut(duration: 0.05)) {
                    displayValue = startValue + (difference * progress)
                }
            }
        }
    }
    
    private func easeOutCubic(_ t: Double) -> Double {
        return 1 - pow(1 - t, 3)
    }
    
    private func formatNumber(_ num: Double) -> String {
        if num >= 1_000_000 {
            return String(format: "%.2fM", num / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.2fK", num / 1_000)
        } else {
            return String(format: "%.2f", num)
        }
    }
}

// MARK: - Transaction Status Pill
enum TxStatusType: String {
    case pending = "Pending"
    case confirmed = "Confirmed"
    case failed = "Failed"
    case processing = "Processing"
    
    var color: Color {
        switch self {
        case .pending: return HawalaTheme.Colors.warning
        case .confirmed: return HawalaTheme.Colors.success
        case .failed: return HawalaTheme.Colors.error
        case .processing: return HawalaTheme.Colors.accent
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .processing: return "arrow.triangle.2.circlepath"
        }
    }
}

struct TransactionStatusPill: View {
    let status: TxStatusType
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(status == .processing && isAnimating ? 360 : 0))
            
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
        // Removed forever animation - status indicators don't need continuous animation
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Animated icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [HawalaTheme.Colors.accent.opacity(0.3), HawalaTheme.Colors.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .opacity(isAnimating ? 0.5 : 1.0)
                
                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HawalaTheme.Colors.backgroundTertiary,
                                HawalaTheme.Colors.backgroundSecondary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            // Removed forever animation for empty state icon
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text(title)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(message)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            if let actionTitle = actionTitle, let action = action {
                HawalaPrimaryButton(actionTitle, icon: "plus", action: action)
                    .padding(.top, HawalaTheme.Spacing.sm)
            }
        }
        .padding(HawalaTheme.Spacing.xxl)
    }
}

// MARK: - Skeleton Loading View
struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    
    @State private var isAnimating = false
    
    init(width: CGFloat? = nil, height: CGFloat = 20) {
        self.width = width
        self.height = height
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: height / 4)
            .fill(
                LinearGradient(
                    colors: [
                        HawalaTheme.Colors.backgroundTertiary,
                        HawalaTheme.Colors.backgroundSecondary,
                        HawalaTheme.Colors.backgroundTertiary
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.5),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 300 : -300)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 4)
                    .fill(HawalaTheme.Colors.backgroundTertiary)
            )
            .onAppear {
                // Slower animation, less CPU intensive
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Skeleton Asset Row
struct SkeletonAssetRow: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Icon skeleton
            Circle()
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 42, height: 42)
            
            // Name skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 80, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 40, height: 10)
            }
            
            Spacer()
            
            // Sparkline skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 60, height: 24)
            
            // Balance skeleton
            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 70, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 50, height: 10)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .overlay(
            shimmerOverlay
        )
        .clipped()
    }
    
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 100)
                .offset(x: shimmerOffset)
                .onAppear {
                    // Slower shimmer animation
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        shimmerOffset = geo.size.width + 100
                    }
                }
        }
    }
}

// MARK: - Skeleton Balance Card
struct SkeletonBalanceCard: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        VStack(alignment: .center, spacing: HawalaTheme.Spacing.md) {
            // Label skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 80, height: 12)
            
            // Balance skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 180, height: 48)
            
            // Change skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 100, height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl, style: .continuous)
                .fill(HawalaTheme.Colors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
        )
        .overlay(shimmerOverlay)
        .clipped()
    }
    
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.03),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 150)
                .offset(x: shimmerOffset)
                .onAppear {
                    // Slower shimmer animation
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        shimmerOffset = geo.size.width + 150
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl, style: .continuous))
    }
}

// MARK: - Primary Button
struct HawalaPrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(title)
                        .font(HawalaTheme.Typography.bodySmall)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(isHovered ? HawalaTheme.Colors.accentHover : HawalaTheme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Secondary Button
struct HawalaSecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(HawalaTheme.Typography.bodySmall)
                    .fontWeight(.medium)
            }
            .foregroundColor(HawalaTheme.Colors.textPrimary)
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Icon Button
struct HawalaIconButton: View {
    let icon: String
    let badge: Int?
    let action: () -> Void
    
    init(_ icon: String, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.badge = badge
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(isHovered ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                
                if let badge = badge, badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(HawalaTheme.Colors.error)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Asset Row (Enhanced with hover effects and context menu)
struct HawalaAssetRow: View {
    let name: String
    let symbol: String
    let icon: String
    let chainColor: Color
    let balance: String
    let fiatValue: String
    let priceChange: Double?
    let sparklineData: [Double]
    let isSelected: Bool
    let action: () -> Void
    
    // Context menu actions (optional)
    var onCopyAddress: (() -> Void)?
    var onViewExplorer: (() -> Void)?
    var onSend: (() -> Void)?
    var onReceive: (() -> Void)?
    var address: String?
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Chain icon with glow on hover
                ZStack {
                    // Glow effect
                    if isHovered {
                        Circle()
                            .fill(chainColor.opacity(0.3))
                            .frame(width: 52, height: 52)
                            .blur(radius: 8)
                    }
                    
                    Circle()
                        .fill(chainColor.opacity(isHovered ? 0.25 : 0.15))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(chainColor)
                }
                .animation(.easeOut(duration: 0.2), value: isHovered)
                
                // Name and symbol
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(HawalaTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(symbol)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                // Mini sparkline (enhanced)
                if !sparklineData.isEmpty {
                    EnhancedSparkline(
                        data: sparklineData, 
                        color: (priceChange ?? 0) >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error,
                        showGradient: isHovered
                    )
                    .frame(width: 60, height: 28)
                }
                
                // Balance and value
                VStack(alignment: .trailing, spacing: 2) {
                    Text(balance)
                        .font(HawalaTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    HStack(spacing: 4) {
                        Text(fiatValue)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        if let change = priceChange {
                            HStack(spacing: 2) {
                                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(format: "%.1f%%", abs(change)))
                                    .font(HawalaTheme.Typography.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(change >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                        }
                    }
                }
                
                // Chevron with animation
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? HawalaTheme.Colors.textSecondary : HawalaTheme.Colors.textTertiary)
                    .offset(x: isHovered ? 2 : 0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                        .fill(isSelected ? HawalaTheme.Colors.accentSubtle : (isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear))
                    
                    // Subtle border on hover
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .strokeBorder(chainColor.opacity(0.2), lineWidth: 1)
                    }
                }
            )
            // Lift effect
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .shadow(color: isHovered ? chainColor.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            // Copy Address
            if address != nil, let copyAction = onCopyAddress {
                Button(action: copyAction) {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
            }
            
            // View in Explorer
            if let explorerAction = onViewExplorer {
                Button(action: explorerAction) {
                    Label("View in Explorer", systemImage: "safari")
                }
            }
            
            Divider()
            
            // Send
            if let sendAction = onSend {
                Button(action: sendAction) {
                    Label("Send \(symbol)", systemImage: "arrow.up.circle")
                }
            }
            
            // Receive
            if let receiveAction = onReceive {
                Button(action: receiveAction) {
                    Label("Receive \(symbol)", systemImage: "arrow.down.circle")
                }
            }
            
            Divider()
            
            // View Details (same as main action)
            Button(action: action) {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - Mini Sparkline
struct MiniSparkline: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = maxVal - minVal
                
                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)
                    
                    for (index, value) in data.enumerated() {
                        let x = stepX * CGFloat(index)
                        let normalizedY = range > 0 ? (value - minVal) / range : 0.5
                        let y = geo.size.height - (normalizedY * geo.size.height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Enhanced Sparkline (with gradient fill)
struct EnhancedSparkline: View {
    let data: [Double]
    let color: Color
    let showGradient: Bool
    
    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.001)
                
                ZStack {
                    // Gradient fill (shown on hover)
                    if showGradient {
                        Path { path in
                            let stepX = geo.size.width / CGFloat(data.count - 1)
                            
                            path.move(to: CGPoint(x: 0, y: geo.size.height))
                            
                            for (index, value) in data.enumerated() {
                                let x = stepX * CGFloat(index)
                                let normalizedY = (value - minVal) / range
                                let y = geo.size.height - (normalizedY * geo.size.height * 0.8) - geo.size.height * 0.1
                                
                                if index == 0 {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .animation(.easeOut(duration: 0.3), value: showGradient)
                    }
                    
                    // Line
                    Path { path in
                        let stepX = geo.size.width / CGFloat(data.count - 1)
                        
                        for (index, value) in data.enumerated() {
                            let x = stepX * CGFloat(index)
                            let normalizedY = (value - minVal) / range
                            let y = geo.size.height - (normalizedY * geo.size.height * 0.8) - geo.size.height * 0.1
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: showGradient ? 2 : 1.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // End dot (shown on hover)
                    if showGradient, let lastValue = data.last {
                        let normalizedY = (lastValue - minVal) / range
                        let y = geo.size.height - (normalizedY * geo.size.height * 0.8) - geo.size.height * 0.1
                        
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .position(x: geo.size.width, y: y)
                            .shadow(color: color.opacity(0.5), radius: 4)
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar Navigation Item
struct HawalaSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void
    
    init(_ icon: String, title: String, isSelected: Bool = false, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                    .frame(width: 24)
                
                Text(title)
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(HawalaTheme.Colors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous)
                    .fill(isSelected ? HawalaTheme.Colors.accentSubtle : (isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Transaction Row (Enhanced)
struct HawalaTransactionRow: View {
    let type: TransactionType
    let amount: String
    let symbol: String
    let fiatValue: String
    let date: String
    let status: TxStatus
    let counterparty: String?
    
    enum TransactionType {
        case send, receive, swap, stake
        
        var icon: String {
            switch self {
            case .send: return "arrow.up.right"
            case .receive: return "arrow.down.left"
            case .swap: return "arrow.triangle.2.circlepath"
            case .stake: return "lock.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .send: return HawalaTheme.Colors.error
            case .receive: return HawalaTheme.Colors.success
            case .swap: return HawalaTheme.Colors.info
            case .stake: return HawalaTheme.Colors.accent
            }
        }
        
        var label: String {
            switch self {
            case .send: return "Sent"
            case .receive: return "Received"
            case .swap: return "Swapped"
            case .stake: return "Staked"
            }
        }
    }
    
    enum TxStatus {
        case pending, confirmed, failed, processing
        
        var label: String {
            switch self {
            case .pending: return "Pending"
            case .confirmed: return "Confirmed"
            case .failed: return "Failed"
            case .processing: return "Processing"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return HawalaTheme.Colors.warning
            case .confirmed: return HawalaTheme.Colors.success
            case .failed: return HawalaTheme.Colors.error
            case .processing: return HawalaTheme.Colors.accent
            }
        }
        
        var icon: String {
            switch self {
            case .pending: return "clock"
            case .confirmed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .processing: return "arrow.triangle.2.circlepath"
            }
        }
    }
    
    @State private var isHovered = false
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Type icon with hover glow
            ZStack {
                if isHovered {
                    Circle()
                        .fill(type.color.opacity(0.2))
                        .frame(width: 46, height: 46)
                        .blur(radius: 6)
                }
                
                Circle()
                    .fill(type.color.opacity(isHovered ? 0.18 : 0.12))
                    .frame(width: 38, height: 38)
                
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(type.color)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(type.label)
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if let counterparty = counterparty {
                    Text(counterparty)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Enhanced status pill
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees((status == .processing || status == .pending) && isAnimating ? 360 : 0))
                
                Text(status.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status.color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(status.color.opacity(0.25), lineWidth: 1)
            )
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(type == .send ? "-" : "+")\(amount) \(symbol)")
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(type == .send ? HawalaTheme.Colors.error : HawalaTheme.Colors.success)
                
                Text(fiatValue)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            // Date
            Text(date)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous)
                .fill(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering // No animation - instant response
        }
        // Removed forever animation for transaction status
    }
}

// MARK: - Empty State
struct HawalaEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 72, height: 72)
                
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text(title)
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(message)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            if let actionTitle = actionTitle, let action = action {
                HawalaPrimaryButton(actionTitle, action: action)
                    .padding(.top, HawalaTheme.Spacing.sm)
            }
        }
        .padding(HawalaTheme.Spacing.xxl)
    }
}

// MARK: - Section Header
struct HawalaSectionHeader: View {
    let title: String
    let action: (() -> Void)?
    let actionLabel: String?
    
    init(_ title: String, action: (() -> Void)? = nil, actionLabel: String? = nil) {
        self.title = title
        self.action = action
        self.actionLabel = actionLabel
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(HawalaTheme.Typography.h4)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            if let action = action, let actionLabel = actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
}

// MARK: - Search Field
struct HawalaSearchField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            TextField(placeholder, text: $text)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm + 2)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Stat Card
struct HawalaStatCard: View {
    let title: String
    let value: String
    let change: String?
    let isPositive: Bool?
    let icon: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            
            Text(value)
                .font(HawalaTheme.Typography.h3)
                .fontWeight(.semibold)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            if let change = change, let isPositive = isPositive {
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(change)
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
            }
        }
        .hawalaCard()
    }
}

// MARK: - Floating Action Button (FAB)
struct FloatingActionButton: View {
    @Binding var isExpanded: Bool
    let onSend: () -> Void
    let onReceive: () -> Void
    let onSwap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: HawalaTheme.Spacing.sm) {
            // Expanded menu items
            if isExpanded {
                FABMenuItem(icon: "arrow.up.right", label: "Send", color: HawalaTheme.Colors.error) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = false
                    }
                    onSend()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: 20)),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
                
                FABMenuItem(icon: "arrow.down.left", label: "Receive", color: HawalaTheme.Colors.success) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = false
                    }
                    onReceive()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: 20)),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
                
                FABMenuItem(icon: "arrow.triangle.2.circlepath", label: "Swap", color: HawalaTheme.Colors.info) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = false
                    }
                    onSwap()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: 20)),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
            }
            
            // Main FAB button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(HawalaTheme.Colors.accent.opacity(0.3))
                        .frame(width: 64, height: 64)
                    // Button - simplified, no blur
                    Circle()
                        .fill(HawalaTheme.Colors.accent)
                        .frame(width: 56, height: 56)
                        .shadow(color: HawalaTheme.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    // Icon
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isExpanded ? 45 : 0))
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering // No animation
            }
        }
    }
}

struct FABMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Text(label)
                    .font(HawalaTheme.Typography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(HawalaTheme.Colors.backgroundSecondary)
                    )
                
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Pull to Refresh View
struct HawalaPullToRefresh: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    @State private var pullProgress: CGFloat = 0
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: HawalaTheme.Spacing.sm) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(HawalaTheme.Colors.backgroundTertiary, lineWidth: 3)
                        .frame(width: 36, height: 36)
                    
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: isRefreshing ? 1 : pullProgress)
                        .stroke(
                            HawalaTheme.Colors.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    
                    // Hawala logo
                    Text("H")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                
                if isRefreshing {
                    Text("Refreshing...")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(pullProgress > 0 || isRefreshing ? 1 : 0)
            .offset(y: isRefreshing ? 0 : -30)
        }
        .frame(height: isRefreshing ? 60 : 0)
        .onChange(of: isRefreshing) { refreshing in
            if refreshing {
                // Slower refresh animation
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }
}

// MARK: - Page Transition Wrapper
struct PageTransitionView<Content: View>: View {
    let content: Content
    let direction: TransitionDirection
    
    enum TransitionDirection {
        case leading, trailing, none
    }
    
    init(direction: TransitionDirection = .none, @ViewBuilder content: () -> Content) {
        self.direction = direction
        self.content = content()
    }
    
    var body: some View {
        content
            .transition(transitionForDirection)
    }
    
    private var transitionForDirection: AnyTransition {
        switch direction {
        case .leading:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .trailing:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .none:
            return .opacity
        }
    }
}

// MARK: - Animated Tab Content
struct AnimatedTabView<Content: View>: View {
    @Binding var selection: Int
    let content: [Content]
    
    @State private var previousSelection: Int = 0
    
    var body: some View {
        ZStack {
            content[selection]
                .id(selection)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: selection > previousSelection ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: selection > previousSelection ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
        .onChange(of: selection) { newValue in
            previousSelection = selection
        }
    }
}

// MARK: - Refresh Button with Animation
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    
    @State private var rotation: Double = 0
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onChange(of: isRefreshing) { refreshing in
            if refreshing {
                // Slower rotation animation
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    rotation = 0
                }
            }
        }
    }
}

// MARK: - Portfolio Pie Chart
struct PortfolioPieChart: View {
    let segments: [PieSegment]
    let totalValue: Double
    let currencySymbol: String
    
    @State private var selectedSegment: PieSegment?
    @State private var animationProgress: Double = 0
    
    struct PieSegment: Identifiable, Equatable {
        let id: String
        let name: String
        let value: Double
        let color: Color
        let icon: String
        
        var percentage: Double {
            return 0 // Calculated externally
        }
        
        static func == (lhs: PieSegment, rhs: PieSegment) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.xl) {
            // Donut chart
            ZStack {
                // Background ring
                Circle()
                    .stroke(HawalaTheme.Colors.backgroundTertiary, lineWidth: 24)
                    .frame(width: 160, height: 160)
                
                // Segments
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    PieSegmentView(
                        segment: segment,
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        isSelected: selectedSegment?.id == segment.id,
                        animationProgress: animationProgress
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedSegment?.id == segment.id {
                                selectedSegment = nil
                            } else {
                                selectedSegment = segment
                            }
                        }
                    }
                }
                
                // Center content
                VStack(spacing: 2) {
                    if let selected = selectedSegment {
                        Image(systemName: selected.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selected.color)
                        
                        Text(selected.name)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Text("\(currencySymbol)\(formatValue(selected.value))")
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(String(format: "%.1f%%", percentage(for: selected)))
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(selected.color)
                    } else {
                        Text("Total")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Text("\(currencySymbol)\(formatValue(totalValue))")
                            .font(HawalaTheme.Typography.h3)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedSegment?.id)
            }
            .frame(width: 160, height: 160)
            
            // Legend
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                ForEach(segments) { segment in
                    PieLegendRow(
                        segment: segment,
                        percentage: percentage(for: segment),
                        isSelected: selectedSegment?.id == segment.id,
                        currencySymbol: currencySymbol
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedSegment?.id == segment.id {
                                selectedSegment = nil
                            } else {
                                selectedSegment = segment
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animationProgress = 1.0
            }
        }
    }
    
    private func startAngle(for index: Int) -> Double {
        let precedingTotal = segments.prefix(index).reduce(0) { $0 + $1.value }
        return (precedingTotal / totalValue) * 360 - 90
    }
    
    private func endAngle(for index: Int) -> Double {
        let includingTotal = segments.prefix(index + 1).reduce(0) { $0 + $1.value }
        return (includingTotal / totalValue) * 360 - 90
    }
    
    private func percentage(for segment: PieSegment) -> Double {
        guard totalValue > 0 else { return 0 }
        return (segment.value / totalValue) * 100
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Pie Segment View
struct PieSegmentView: View {
    let segment: PortfolioPieChart.PieSegment
    let startAngle: Double
    let endAngle: Double
    let isSelected: Bool
    let animationProgress: Double
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius: CGFloat = 68
            let animatedEnd = startAngle + (endAngle - startAngle) * animationProgress
            
            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(animatedEnd),
                    clockwise: false
                )
            }
            .stroke(
                segment.color,
                style: StrokeStyle(
                    lineWidth: isSelected ? 28 : 24,
                    lineCap: .butt
                )
            )
            .shadow(color: isSelected ? segment.color.opacity(0.5) : .clear, radius: 8)
        }
        .frame(width: 160, height: 160)
    }
}

// MARK: - Pie Legend Row
struct PieLegendRow: View {
    let segment: PortfolioPieChart.PieSegment
    let percentage: Double
    let isSelected: Bool
    let currencySymbol: String
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Circle()
                .fill(segment.color)
                .frame(width: 10, height: 10)
            
            Image(systemName: segment.icon)
                .font(.system(size: 12))
                .foregroundColor(segment.color)
                .frame(width: 16)
            
            Text(segment.name)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
            
            Spacer()
            
            Text(String(format: "%.1f%%", percentage))
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(segment.color)
                .monospacedDigit()
        }
        .padding(.horizontal, HawalaTheme.Spacing.sm)
        .padding(.vertical, HawalaTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous)
                .fill(isSelected || isHovered ? segment.color.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Price History Chart
struct PriceHistoryChart: View {
    let data: [PricePoint]
    let chainColor: Color
    let currencySymbol: String
    
    @State private var selectedTimeframe: ChartTimeframe = .day
    @State private var hoveredPoint: PricePoint?
    @State private var showFullChart = false
    
    enum ChartTimeframe: String, CaseIterable {
        case hour = "1H"
        case day = "24H"
        case week = "7D"
        case month = "1M"
        case year = "1Y"
        
        var label: String { rawValue }
    }
    
    struct PricePoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let price: Double
    }
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Header with price info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let current = data.last {
                        Text("\(currencySymbol)\(String(format: "%.2f", current.price))")
                            .font(HawalaTheme.Typography.h2)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                    }
                    
                    if let change = priceChange {
                        HStack(spacing: 4) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            
                            Text(String(format: "%+.2f%%", change))
                                .font(HawalaTheme.Typography.bodySmall)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(change >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                    }
                }
                
                Spacer()
                
                // Timeframe selector
                HStack(spacing: 4) {
                    ForEach(ChartTimeframe.allCases, id: \.self) { timeframe in
                        TimeframeButton(
                            timeframe: timeframe,
                            isSelected: selectedTimeframe == timeframe,
                            color: chainColor
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTimeframe = timeframe
                            }
                        }
                    }
                }
            }
            
            // Chart
            ZStack(alignment: .topLeading) {
                // Chart area
                ChartLineView(
                    data: data,
                    color: chainColor,
                    hoveredPoint: $hoveredPoint
                )
                .frame(height: showFullChart ? 200 : 120)
                
                // Hover tooltip
                if let point = hoveredPoint {
                    ChartTooltip(
                        price: point.price,
                        date: point.timestamp,
                        currencySymbol: currencySymbol
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // Expand button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showFullChart.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Text(showFullChart ? "Collapse" : "Expand Chart")
                        .font(HawalaTheme.Typography.caption)
                    Image(systemName: showFullChart ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
        .frostedGlass(cornerRadius: HawalaTheme.Radius.lg, intensity: 0.15)
    }
    
    private var priceChange: Double? {
        guard let first = data.first, let last = data.last, first.price > 0 else { return nil }
        return ((last.price - first.price) / first.price) * 100
    }
}

// MARK: - Timeframe Button
struct TimeframeButton: View {
    let timeframe: PriceHistoryChart.ChartTimeframe
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(timeframe.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? color : HawalaTheme.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? color.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chart Line View
struct ChartLineView: View {
    let data: [PriceHistoryChart.PricePoint]
    let color: Color
    @Binding var hoveredPoint: PriceHistoryChart.PricePoint?
    
    @State private var animationProgress: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ZStack {
                // Gradient fill under line
                Path { path in
                    guard data.count > 1 else { return }
                    let points = normalizedPoints(in: CGSize(width: width, height: height))
                    
                    path.move(to: CGPoint(x: points[0].x, y: height))
                    path.addLine(to: points[0])
                    
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    
                    path.addLine(to: CGPoint(x: points.last!.x, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    Rectangle()
                        .frame(width: width * animationProgress)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
                
                // Main line
                Path { path in
                    guard data.count > 1 else { return }
                    let points = normalizedPoints(in: CGSize(width: width, height: height))
                    
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .trim(from: 0, to: animationProgress)
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                
                // End dot
                if animationProgress >= 1, let lastPoint = normalizedPoints(in: CGSize(width: width, height: height)).last {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(lastPoint)
                        .shadow(color: color.opacity(0.5), radius: 4)
                }
                
                // Hover detection
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let points = normalizedPoints(in: CGSize(width: width, height: height))
                                if let closest = findClosestPoint(to: value.location.x, points: points) {
                                    hoveredPoint = data[closest]
                                }
                            }
                            .onEnded { _ in
                                hoveredPoint = nil
                            }
                    )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animationProgress = 1.0
            }
        }
    }
    
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        
        let prices = data.map { $0.price }
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 1
        let priceRange = maxPrice - minPrice
        
        let padding: CGFloat = 10
        let effectiveHeight = size.height - padding * 2
        
        return data.enumerated().map { index, point in
            let x = CGFloat(index) / CGFloat(data.count - 1) * size.width
            let normalizedY = priceRange > 0 ? (point.price - minPrice) / priceRange : 0.5
            let y = padding + effectiveHeight * (1 - normalizedY)
            return CGPoint(x: x, y: y)
        }
    }
    
    private func findClosestPoint(to x: CGFloat, points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.enumerated().min(by: { abs($0.element.x - x) < abs($1.element.x - x) })?.offset
    }
}

// MARK: - Chart Tooltip
struct ChartTooltip: View {
    let price: Double
    let date: Date
    let currencySymbol: String
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(currencySymbol)\(String(format: "%.2f", price))")
                .font(HawalaTheme.Typography.bodySmall)
                .fontWeight(.semibold)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text(dateFormatter.string(from: date))
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .padding(.horizontal, HawalaTheme.Spacing.sm)
        .padding(.vertical, HawalaTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Profit/Loss Indicator
struct ProfitLossIndicator: View {
    let currentValue: Double
    let purchaseValue: Double
    let currencySymbol: String
    let size: IndicatorSize
    
    enum IndicatorSize {
        case small
        case medium
        case large
        
        var fontSize: Font {
            switch self {
            case .small: return HawalaTheme.Typography.caption
            case .medium: return HawalaTheme.Typography.bodySmall
            case .large: return HawalaTheme.Typography.body
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 14
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }
    
    private var pnlValue: Double {
        currentValue - purchaseValue
    }
    
    private var pnlPercentage: Double {
        guard purchaseValue > 0 else { return 0 }
        return ((currentValue - purchaseValue) / purchaseValue) * 100
    }
    
    private var isPositive: Bool {
        pnlValue >= 0
    }
    
    private var color: Color {
        isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: size.iconSize, weight: .bold))
            
            Text(String(format: "%+.2f%%", pnlPercentage))
                .font(size.fontSize)
                .fontWeight(.semibold)
            
            Text("(\(currencySymbol)\(formatPnL(pnlValue)))")
                .font(size.fontSize)
                .fontWeight(.medium)
                .opacity(0.8)
        }
        .foregroundColor(color)
        .padding(.horizontal, size.padding + 4)
        .padding(.vertical, size.padding)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
    
    private func formatPnL(_ value: Double) -> String {
        let absValue = abs(value)
        let prefix = value >= 0 ? "+" : "-"
        
        if absValue >= 1_000_000 {
            return "\(prefix)\(String(format: "%.2fM", absValue / 1_000_000))"
        } else if absValue >= 1_000 {
            return "\(prefix)\(String(format: "%.1fK", absValue / 1_000))"
        } else {
            return "\(prefix)\(String(format: "%.2f", absValue))"
        }
    }
}

// MARK: - Compact P&L Badge
struct CompactPnLBadge: View {
    let percentage: Double
    
    private var isPositive: Bool { percentage >= 0 }
    private var color: Color { isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "triangle.fill" : "triangle.fill")
                .font(.system(size: 6, weight: .bold))
                .rotationEffect(.degrees(isPositive ? 0 : 180))
            
            Text(String(format: "%.1f%%", abs(percentage)))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Asset P&L Card
struct AssetPnLCard: View {
    let assetName: String
    let assetIcon: String
    let chainColor: Color
    let currentValue: Double
    let purchaseValue: Double
    let currencySymbol: String
    
    @State private var isHovered = false
    
    private var pnlValue: Double { currentValue - purchaseValue }
    private var pnlPercentage: Double {
        guard purchaseValue > 0 else { return 0 }
        return ((currentValue - purchaseValue) / purchaseValue) * 100
    }
    private var isPositive: Bool { pnlValue >= 0 }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Asset icon
            ZStack {
                Circle()
                    .fill(chainColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: assetIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(chainColor)
            }
            
            // Asset info
            VStack(alignment: .leading, spacing: 2) {
                Text(assetName)
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Cost: \(currencySymbol)\(String(format: "%.2f", purchaseValue))")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // P&L values
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currencySymbol)\(String(format: "%.2f", currentValue))")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    
                    Text(String(format: "%+.2f%%", pnlPercentage))
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .fill(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    isHovered ? (isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error).opacity(0.3) : HawalaTheme.Colors.border,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Draggable Asset Row
struct DraggableAssetRow: View {
    let chain: ChainInfo
    let chainSymbol: String
    let chainColor: Color
    let balance: String
    let fiatValue: String
    let sparklineData: [Double]
    let isSelected: Bool
    let isDragging: Bool
    var hideBalance: Bool = false
    let onSelect: () -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let onDropTarget: (String) -> Void
    
    @State private var isHovered = false
    @State private var isDropTarget = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? HawalaTheme.Colors.textSecondary : HawalaTheme.Colors.textTertiary)
                .frame(width: 20)
            
            // Chain icon with glow on hover
            ZStack {
                if isHovered {
                    Circle()
                        .fill(chainColor.opacity(0.3))
                        .frame(width: 52, height: 52)
                        .blur(radius: 8)
                }
                
                Circle()
                    .fill(chainColor.opacity(isHovered ? 0.25 : 0.15))
                    .frame(width: 42, height: 42)
                
                Image(systemName: chain.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(chainColor)
            }
            .animation(.easeOut(duration: 0.2), value: isHovered)
            
            // Name and symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.title)
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(chainSymbol)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // Mini sparkline
            if !sparklineData.isEmpty {
                EnhancedSparkline(
                    data: sparklineData,
                    color: HawalaTheme.Colors.success,
                    showGradient: isHovered
                )
                .frame(width: 60, height: 28)
            }
            
            // Balance and value
            VStack(alignment: .trailing, spacing: 2) {
                Text(hideBalance ? "•••••" : balance)
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(hideBalance ? "•••••" : fiatValue)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHovered ? HawalaTheme.Colors.textSecondary : HawalaTheme.Colors.textTertiary)
                .offset(x: isHovered ? 2 : 0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .fill(isSelected ? HawalaTheme.Colors.accentSubtle : (isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear))
                
                // Drop target indicator
                if isDropTarget {
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                        .strokeBorder(HawalaTheme.Colors.accent, lineWidth: 2)
                }
                
                if isHovered && !isSelected && !isDropTarget {
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                        .strokeBorder(chainColor.opacity(0.2), lineWidth: 1)
                }
            }
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isDragging ? 0.95 : (isHovered ? 1.01 : 1.0))
        .shadow(color: isHovered ? chainColor.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: chain.id as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isDropTarget) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                if let draggedId = item as? String {
                    DispatchQueue.main.async {
                        onDropTarget(draggedId)
                    }
                }
            }
            onDragEnded()
            return true
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("View Details", systemImage: "info.circle")
            }
            
            Divider()
            
            if let addr = chain.receiveAddress {
                Button(action: {
                    #if canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addr, forType: .string)
                    #endif
                    ToastManager.shared.copied("\(chain.title) Address")
                }) {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    // Open explorer URL
                    if let url = explorerURL(for: chain) {
                        #if canImport(AppKit)
                        NSWorkspace.shared.open(url)
                        #endif
                        ToastManager.shared.info("Opening Explorer", message: "Viewing \(chain.title) on block explorer")
                    }
                }) {
                    Label("View in Explorer", systemImage: "safari")
                }
            }
        }
    }
    
    private func explorerURL(for chain: ChainInfo) -> URL? {
        guard let address = chain.receiveAddress else { return nil }
        
        switch chain.id {
        case "bitcoin":
            return URL(string: "https://mempool.space/address/\(address)")
        case "bitcoin-testnet":
            return URL(string: "https://mempool.space/testnet/address/\(address)")
        case "ethereum":
            return URL(string: "https://etherscan.io/address/\(address)")
        case "ethereum-sepolia":
            return URL(string: "https://sepolia.etherscan.io/address/\(address)")
        case "litecoin":
            return URL(string: "https://litecoinspace.org/address/\(address)")
        case "solana":
            return URL(string: "https://solscan.io/account/\(address)")
        case "xrp":
            return URL(string: "https://xrpscan.com/account/\(address)")
        case "bnb":
            return URL(string: "https://bscscan.com/address/\(address)")
        case "monero":
            return nil // Monero is private
        default:
            return nil
        }
    }
}

// MARK: - Toast Notification System
enum ToastType {
    case success
    case error
    case warning
    case info
    case copied
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .copied: return "doc.on.doc.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return HawalaTheme.Colors.success
        case .error: return HawalaTheme.Colors.error
        case .warning: return HawalaTheme.Colors.warning
        case .info: return HawalaTheme.Colors.info
        case .copied: return HawalaTheme.Colors.accent
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: Double
    
    init(type: ToastType, title: String, message: String? = nil, duration: Double = 3.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }
    
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastMessage?
    private var dismissTask: Task<Void, Never>?
    
    func show(_ toast: ToastMessage) {
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            currentToast = toast
        }
        
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) {
                    currentToast = nil
                }
            }
        }
    }
    
    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }
    }
    
    // Convenience methods
    func success(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .success, title: title, message: message))
    }
    
    func error(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .error, title: title, message: message))
    }
    
    func copied(_ item: String = "Address") {
        show(ToastMessage(type: .copied, title: "\(item) Copied", message: "Copied to clipboard", duration: 2.0))
    }
    
    func info(_ title: String, message: String? = nil) {
        show(ToastMessage(type: .info, title: title, message: message))
    }
}

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Icon with pulse animation
            ZStack {
                Circle()
                    .fill(toast.type.color.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: toast.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(toast.type.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if let message = toast.message {
                    Text(message)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(toast.type.color.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: 360)
    }
}

struct ToastContainer: View {
    @ObservedObject var toastManager = ToastManager.shared
    
    var body: some View {
        VStack {
            if let toast = toastManager.currentToast {
                ToastView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, HawalaTheme.Spacing.xl)
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toastManager.currentToast)
    }
}

// MARK: - Visual Feedback Effects
struct PulseEffect: ViewModifier {
    let color: Color
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.8)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    isPulsing = true
                }
            }
    }
}

struct RippleEffect: View {
    let color: Color
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Circle()
            .fill(color.opacity(0.3))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    scale = 2.0
                    opacity = 0
                }
            }
    }
}

struct SuccessCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 60, height: 60)
            
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: 60, height: 60)
            
            Path { path in
                path.move(to: CGPoint(x: 18, y: 32))
                path.addLine(to: CGPoint(x: 26, y: 40))
                path.addLine(to: CGPoint(x: 42, y: 22))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 60, height: 60)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                trimEnd = 1.0
            }
        }
    }
}

// MARK: - Biometric Lock Screen
struct BiometricLockScreen: View {
    let onUnlock: () -> Void
    let onPasscodeEntry: () -> Void
    
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var lockIconRotation: Double = 0
    
    var body: some View {
        ZStack {
            // Blurred background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Animated particles (subtle)
            ParticleBackgroundView(particleCount: 10, colors: [
                HawalaTheme.Colors.accent.opacity(0.1),
                Color.white.opacity(0.05)
            ])
            .opacity(0.4)
            
            VStack(spacing: HawalaTheme.Spacing.xxl) {
                Spacer()
                
                // Lock icon with animation
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    HawalaTheme.Colors.accent.opacity(0.2),
                                    HawalaTheme.Colors.accent.opacity(0)
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .fill(HawalaTheme.Colors.backgroundSecondary)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            HawalaTheme.Colors.accent.opacity(0.5),
                                            HawalaTheme.Colors.accent.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: isAuthenticating ? "faceid" : "lock.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accentHover],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(lockIconRotation))
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                // Title
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    Text("Hawala Locked")
                        .font(HawalaTheme.Typography.h1)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Authenticate to access your wallet")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .opacity(logoOpacity)
                
                // Error message
                if showError {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(HawalaTheme.Colors.error)
                        Text(errorMessage)
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.error)
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .fill(HawalaTheme.Colors.error.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: HawalaTheme.Spacing.md) {
                    // Biometric unlock button
                    Button(action: attemptBiometricAuth) {
                        HStack(spacing: HawalaTheme.Spacing.sm) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "faceid")
                                    .font(.system(size: 18, weight: .medium))
                            }
                            
                            Text(isAuthenticating ? "Authenticating..." : "Unlock with Face ID")
                                .font(HawalaTheme.Typography.body)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(
                            LinearGradient(
                                colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accentHover],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating)
                    
                    // Passcode entry button
                    Button(action: onPasscodeEntry) {
                        Text("Use Passcode Instead")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 300)
                .padding(.bottom, HawalaTheme.Spacing.xxxl)
            }
            .padding(HawalaTheme.Spacing.xl)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
    
    private func attemptBiometricAuth() {
        isAuthenticating = true
        showError = false
        
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            lockIconRotation = 10
        }
        
        // Simulate biometric auth (in real app, use LAContext)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                lockIconRotation = 0
                isAuthenticating = false
            }
            
            // For demo, always succeed
            onUnlock()
        }
    }
}

// MARK: - Settings Panel Components
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text(title)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(1)
            
            VStack(spacing: 0) {
                content
            }
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(icon: String, iconColor: Color = HawalaTheme.Colors.accent, title: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    @State private var isHovered = false
    
    init(icon: String, iconColor: Color = HawalaTheme.Colors.accent, title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(HawalaToggleStyle())
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        .onHover { isHovered = $0 }
    }
}

struct HawalaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 44, height: 26)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .padding(2)
                        .offset(x: configuration.isOn ? 9 : -9)
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

// MARK: - Copy Button with Feedback
struct CopyButton: View {
    let text: String
    let label: String
    
    @State private var showCopied = false
    
    var body: some View {
        Button(action: copyToClipboard) {
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                Text(showCopied ? "Copied!" : label)
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(showCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent)
            .padding(.horizontal, HawalaTheme.Spacing.sm)
            .padding(.vertical, HawalaTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill((showCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent).opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: showCopied)
    }
    
    private func copyToClipboard() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        showCopied = true
        ToastManager.shared.copied()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

// MARK: - Enhanced Skeleton Loading Components
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + (phase * geo.size.width * 2))
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

struct SkeletonShape: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(HawalaTheme.Colors.backgroundTertiary)
            .frame(width: width, height: height)
            .shimmer()
    }
}

// Multiple skeleton rows for asset list
struct SkeletonAssetList: View {
    let count: Int
    
    init(count: Int = 5) {
        self.count = count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                SkeletonAssetRow()
                    .opacity(1.0 - (Double(index) * 0.15))
            }
        }
    }
}

// Skeleton for transaction row
struct SkeletonTransactionRow: View {
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Icon skeleton
            Circle()
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(width: 40, height: 40)
                .shimmer()
            
            // Details
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                SkeletonShape(width: 100, height: 14)
                SkeletonShape(width: 140, height: 12)
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: HawalaTheme.Spacing.xs) {
                SkeletonShape(width: 60, height: 14)
                SkeletonShape(width: 40, height: 12)
            }
        }
        .padding(HawalaTheme.Spacing.md)
    }
}

// Skeleton for price/chart area
struct SkeletonPriceChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
            // Price header
            HStack {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                    SkeletonShape(width: 60, height: 12)
                    SkeletonShape(width: 120, height: 32, cornerRadius: 6)
                    SkeletonShape(width: 80, height: 12)
                }
                Spacer()
            }
            
            // Chart skeleton
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .fill(HawalaTheme.Colors.backgroundTertiary)
                .frame(height: 180)
                .shimmer()
            
            // Time range buttons skeleton
            HStack(spacing: HawalaTheme.Spacing.md) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonShape(width: 40, height: 28, cornerRadius: 14)
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .fill(HawalaTheme.Colors.backgroundSecondary)
        )
    }
}

// Loading overlay with spinner
struct LoadingOverlay: View {
    let message: String
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: HawalaTheme.Spacing.lg) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: HawalaTheme.Colors.accent))
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(HawalaTheme.Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Pull to Refresh
struct PullToRefreshView: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    @State private var pullProgress: CGFloat = 0
    @State private var rotation: Double = 0
    
    private let threshold: CGFloat = 80
    
    var body: some View {
        GeometryReader { geo in
            let offset = geo.frame(in: .named("scroll")).minY
            let progress = min(max(offset / threshold, 0), 1)
            
            HStack {
                Spacer()
                
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(HawalaTheme.Colors.backgroundTertiary, lineWidth: 3)
                        .frame(width: 32, height: 32)
                    
                    // Progress arc
                    Circle()
                        .trim(from: 0, to: isRefreshing ? 1 : progress)
                        .stroke(HawalaTheme.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90 + (isRefreshing ? rotation : 0)))
                    
                    // Arrow or checkmark
                    if !isRefreshing {
                        Image(systemName: progress >= 1 ? "arrow.down" : "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(HawalaTheme.Colors.accent)
                            .rotationEffect(.degrees(progress >= 1 ? 180 : 0))
                    }
                }
                .opacity(offset > 0 ? 1 : 0)
                .offset(y: offset > 0 ? offset / 2 - 40 : -40)
                
                Spacer()
            }
            .onChange(of: offset) { newValue in
                if newValue > threshold && !isRefreshing {
                    // Trigger refresh
                    let generator = NSHapticFeedbackManager.defaultPerformer
                    generator.perform(.alignment, performanceTime: .now)
                    
                    isRefreshing = true
                    onRefresh()
                }
            }
            .onChange(of: isRefreshing) { refreshing in
                if refreshing {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    rotation = 0
                }
            }
        }
        .frame(height: 0)
    }
}

// MARK: - Page Transition Effects
enum PageTransition {
    case slide
    case fade
    case scale
    case slideUp
    
    var animation: AnyTransition {
        switch self {
        case .slide:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .fade:
            return .opacity
        case .scale:
            return .scale(scale: 0.9).combined(with: .opacity)
        case .slideUp:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        }
    }
}

struct PageTransitionModifier: ViewModifier {
    let transition: PageTransition
    
    func body(content: Content) -> some View {
        content
            .transition(transition.animation)
    }
}

extension View {
    func pageTransition(_ transition: PageTransition) -> some View {
        modifier(PageTransitionModifier(transition: transition))
    }
}

// Direction-aware slide transition
struct DirectionalSlideTransition: ViewModifier {
    let direction: Int // -1 for left, 1 for right
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
            ))
    }
}

// Tab content wrapper with transitions
struct AnimatedTabContent<Content: View>: View {
    let tabIndex: Int
    @Binding var selectedIndex: Int
    let content: Content
    
    @State private var previousIndex: Int = 0
    
    init(tabIndex: Int, selectedIndex: Binding<Int>, @ViewBuilder content: () -> Content) {
        self.tabIndex = tabIndex
        self._selectedIndex = selectedIndex
        self.content = content()
    }
    
    var body: some View {
        Group {
            if tabIndex == selectedIndex {
                content
                    .modifier(DirectionalSlideTransition(direction: selectedIndex > previousIndex ? 1 : -1))
            }
        }
        .onChange(of: selectedIndex) { newValue in
            previousIndex = selectedIndex
        }
    }
}

// Smooth content switcher
struct SmoothTabSwitcher<Content: View>: View {
    @Binding var selection: Int
    let content: (Int) -> Content
    
    @State private var previousSelection: Int = 0
    
    var body: some View {
        ZStack {
            content(selection)
                .id(selection)
                .transition(.asymmetric(
                    insertion: .move(edge: selection > previousSelection ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .move(edge: selection > previousSelection ? .leading : .trailing)
                        .combined(with: .opacity)
                ))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
        .onChange(of: selection) { newValue in
            previousSelection = selection
        }
    }
}

// MARK: - Refresh Indicator
struct RefreshIndicator: View {
    @Binding var isRefreshing: Bool
    
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(HawalaTheme.Colors.backgroundTertiary, lineWidth: 2)
                .frame(width: 24, height: 24)
            
            if isRefreshing {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(HawalaTheme.Colors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
        }
    }
}

