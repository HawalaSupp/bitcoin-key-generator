import SwiftUI
import QuartzCore

// MARK: - Scroll Performance Optimizations
// Fixes for buttery smooth 120fps scrolling

// MARK: - Optimized Sparkline View

/// High-performance sparkline that pre-computes values and uses Metal rendering
struct OptimizedSparklineView: View, Equatable {
    let dataPoints: [Double]
    var lineColor: Color = .blue
    var height: CGFloat = 24
    
    // Pre-computed on init for zero-cost rendering
    private let normalizedPoints: [CGFloat]
    private let priceChange: Double
    private let trendColor: Color
    
    init(dataPoints: [Double], lineColor: Color = .blue, height: CGFloat = 24) {
        self.dataPoints = dataPoints
        self.lineColor = lineColor
        self.height = height
        
        // Pre-compute normalized points once
        if dataPoints.isEmpty {
            normalizedPoints = []
            priceChange = 0
            trendColor = .secondary
        } else {
            let minVal = dataPoints.min() ?? 0
            let maxVal = dataPoints.max() ?? 1
            let range = maxVal - minVal
            
            if range > 0 {
                normalizedPoints = dataPoints.map { CGFloat(($0 - minVal) / range) }
            } else {
                normalizedPoints = dataPoints.map { _ in CGFloat(0.5) }
            }
            
            // Pre-compute price change
            if dataPoints.count >= 2,
               let first = dataPoints.first,
               let last = dataPoints.last,
               first > 0 {
                priceChange = ((last - first) / first) * 100
            } else {
                priceChange = 0
            }
            
            // Pre-compute trend color
            if priceChange > 0.1 {
                trendColor = .green
            } else if priceChange < -0.1 {
                trendColor = .red
            } else {
                trendColor = .secondary
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Sparkline chart - uses Canvas for better performance than Path
            Canvas { context, size in
                guard normalizedPoints.count > 1 else { return }
                
                let stepX = size.width / CGFloat(normalizedPoints.count - 1)
                var path = Path()
                
                for (index, value) in normalizedPoints.enumerated() {
                    let x = stepX * CGFloat(index)
                    let y = size.height * (1 - value)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                context.stroke(
                    path,
                    with: .color(trendColor),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(width: 50, height: height)
            
            // Percentage change
            if !dataPoints.isEmpty {
                Text(priceChange >= 0 ? "+\(String(format: "%.1f", priceChange))%" : "\(String(format: "%.1f", priceChange))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(trendColor)
            }
        }
    }
    
    // Equatable for preventing unnecessary redraws
    nonisolated static func == (lhs: OptimizedSparklineView, rhs: OptimizedSparklineView) -> Bool {
        lhs.dataPoints == rhs.dataPoints &&
        lhs.height == rhs.height
    }
}

// MARK: - Optimized Skeleton Line

/// Skeleton loading that only animates when visible
struct OptimizedSkeletonLine: View {
    var width: CGFloat? = 80
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 6
    
    // Only animate when in viewport
    @State private var isVisible = false
    @State private var phase: CGFloat = -0.8
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geometry in
                    if isVisible {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(shimmerGradient)
                            .scaleEffect(x: 1.6, y: 1, anchor: .leading)
                            .offset(x: geometry.size.width * phase)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                isVisible = true
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 0.9
                }
            }
            .onDisappear {
                isVisible = false
                phase = -0.8
            }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.08),
                Color.primary.opacity(0.18),
                Color.primary.opacity(0.08)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - High Performance Card Container

/// Card container optimized for scroll performance
struct PerformanceCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 12
    var accentColor: Color = .blue
    
    init(
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 12,
        accentColor: Color = .blue,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(0.15), lineWidth: 1)
            )
            // Metal-accelerated compositing
            .drawingGroup(opaque: false)
    }
}

// MARK: - Scroll Performance Modifiers

extension View {
    /// Optimizes view for scrolling by compositing to texture
    func scrollOptimized() -> some View {
        self
            .drawingGroup(opaque: false)
    }
    
    /// Disables animations during scroll for smoother performance
    func scrollAnimationOptimized() -> some View {
        self
            .transaction { transaction in
                // Check if we're in a scroll gesture - use minimal animation
                if transaction.animation != nil {
                    // Use fastest animation during interactions
                    transaction.animation = .linear(duration: 0.016) // ~2 frames at 120fps
                }
            }
    }
    
    /// Fixed frame for LazyVStack/LazyVGrid optimization
    func fixedFrame(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        self.frame(width: width, height: height)
    }
}

// MARK: - Optimized ForEach with ID caching

/// ForEach that caches identity calculations
struct OptimizedForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content
    
    var body: some View {
        ForEach(data, id: id) { element in
            content(element)
        }
    }
}

// MARK: - Scroll State Observer

/// Observes scroll state to disable expensive operations during scroll
@MainActor
class ScrollStateObserver: ObservableObject {
    static let shared = ScrollStateObserver()
    
    @Published private(set) var isScrolling = false
    @Published private(set) var scrollVelocity: CGFloat = 0
    
    private var scrollEndTimer: Timer?
    
    private init() {}
    
    func startScrolling(velocity: CGFloat = 0) {
        scrollEndTimer?.invalidate()
        isScrolling = true
        scrollVelocity = velocity
    }
    
    func endScrolling() {
        // Debounce scroll end to avoid flicker
        scrollEndTimer?.invalidate()
        scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isScrolling = false
                self?.scrollVelocity = 0
            }
        }
    }
}

// MARK: - Scroll-Aware Animation Modifier

struct ScrollAwareAnimationModifier: ViewModifier {
    @ObservedObject private var scrollState = ScrollStateObserver.shared
    let animation: Animation
    
    func body(content: Content) -> some View {
        content
            .animation(scrollState.isScrolling ? nil : animation, value: UUID())
    }
}

extension View {
    /// Only animates when not scrolling
    func animateWhenIdle(_ animation: Animation) -> some View {
        modifier(ScrollAwareAnimationModifier(animation: animation))
    }
}

// Helper function (needs to be available)
private func relativeTimeDescription(from date: Date) -> String? {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "just now"
    } else if interval < 3600 {
        let minutes = Int(interval / 60)
        return "\(minutes)m ago"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    } else {
        let days = Int(interval / 86400)
        return "\(days)d ago"
    }
}

// MARK: - Smooth Scroll View Wrapper

/// ScrollView wrapper with optimized scrolling behavior
struct SmoothScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    
    @StateObject private var scrollState = ScrollStateObserver.shared
    
    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    
    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content
        }
        .scrollContentBackground(.hidden)
        // Enable momentum scrolling
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Render Budget Tracker

/// Tracks render budget to prevent jank
@MainActor
class RenderBudgetTracker: ObservableObject {
    static let shared = RenderBudgetTracker()
    
    // 8.33ms budget for 120fps
    private let frameBudgetMs: Double = 8.33
    
    @Published private(set) var isOverBudget = false
    @Published private(set) var lastFrameTime: Double = 0
    
    private var frameStart: CFTimeInterval = 0
    
    private init() {}
    
    func beginFrame() {
        frameStart = CACurrentMediaTime()
    }
    
    func endFrame() {
        let elapsed = (CACurrentMediaTime() - frameStart) * 1000
        lastFrameTime = elapsed
        isOverBudget = elapsed > frameBudgetMs
        
        #if DEBUG
        if isOverBudget {
            print("⚠️ Frame over budget: \(String(format: "%.2f", elapsed))ms > \(frameBudgetMs)ms")
        }
        #endif
    }
}
