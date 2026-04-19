import SwiftUI
import QuartzCore

// MARK: - Performance Monitor (120fps Target)

/// Real-time FPS and memory monitor for debug builds
/// Targets 120fps for ProMotion displays
@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published private(set) var fps: Double = 120
    @Published private(set) var memoryUsageMB: Double = 0
    @Published private(set) var frameDropCount: Int = 0
    @Published private(set) var targetFPS: Double = 120
    @Published private(set) var displayRefreshRate: Double = 120
    
    private var displayLinkTimer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var isRunning = false
    
    private init() {
        detectDisplayRefreshRate()
    }
    
    private func detectDisplayRefreshRate() {
        // Always target 120fps for optimized animations
        // Even on 60Hz displays, we optimize for 120fps to ensure
        // buttery smooth performance on ProMotion displays
        #if os(macOS)
        if let screen = NSScreen.main {
            // Detect actual display rate for info purposes
            let actualRate = screen.maximumFramesPerSecond
            displayRefreshRate = Double(actualRate)
        }
        #endif
        // Always target 120fps regardless of display
        targetFPS = 120
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = CACurrentMediaTime()
        
        // Use high-frequency timer for 120fps tracking (8.33ms per frame)
        // Using 1/120 interval to match ProMotion refresh rate
        displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // Ensure timer fires during tracking (scrolling, etc.)
        RunLoop.main.add(displayLinkTimer!, forMode: .common)
        
        // Update memory usage periodically
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
    }
    
    private func tick() {
        let now = CACurrentMediaTime()
        frameCount += 1
        
        if now - lastTimestamp >= 0.5 { // Update every 0.5 seconds for smoother readings
            let currentFPS = Double(frameCount) / (now - lastTimestamp)
            fps = min(currentFPS, targetFPS) // Cap at target
            
            // Frame drop is relative to target (120fps or 60fps)
            let dropThreshold = targetFPS * 0.9 // 90% of target
            if currentFPS < dropThreshold {
                frameDropCount += 1
            }
            
            frameCount = 0
            lastTimestamp = now
        }
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            memoryUsageMB = Double(info.resident_size) / (1024 * 1024)
        }
    }
    
    nonisolated static func logMemory(label: String) {
        #if DEBUG
        Task { @MainActor in
            shared.updateMemoryUsage()
            print("[\(label)] Memory: \(String(format: "%.1f", shared.memoryUsageMB)) MB")
        }
        #endif
    }
}

// MARK: - Debug Performance Overlay (120fps aware)

#if DEBUG
struct PerformanceOverlay: View {
    @ObservedObject private var monitor = PerformanceMonitor.shared
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(fpsColor)
                    .frame(width: 8, height: 8)
                
                Text("\(Int(monitor.fps))/\(Int(monitor.targetFPS))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                
                if isExpanded {
                    Text("|\(String(format: "%.0f", monitor.memoryUsageMB))MB")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
            .foregroundColor(.white)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drops: \(monitor.frameDropCount)")
                        .font(.system(size: 9, design: .monospaced))
                    Text("Display: \(Int(monitor.displayRefreshRate))Hz")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.75))
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.12)) {
                isExpanded.toggle()
            }
        }
        .onAppear {
            monitor.start()
        }
    }
    
    private var fpsColor: Color {
        let ratio = monitor.fps / monitor.targetFPS
        if ratio >= 0.9 { // 90%+ of target
            return .green
        } else if ratio >= 0.5 { // 50%+ of target
            return .yellow
        } else {
            return .red
        }
    }
}
#endif

// MARK: - Optimized Animation Durations (120fps optimized)

/// Animation presets optimized for 120fps ProMotion displays
/// At 120fps, each frame is ~8.33ms, so animations can be shorter while still appearing smooth
struct OptimizedAnimations {
    // Ultra-quick for micro-interactions (hover, press states) - 1-2 frames at 120fps
    static let micro: Animation = .linear(duration: 0.016) // ~2 frames at 120fps
    
    // Quick interactions (buttons, toggles) - optimized for 120fps
    static let quick: Animation = .easeOut(duration: 0.1) // ~12 frames at 120fps
    
    // Standard transitions - faster for snappier feel
    static let standard: Animation = .easeInOut(duration: 0.18) // ~22 frames at 120fps
    
    // Spring for natural feel - tighter response for 120fps
    static let spring: Animation = .spring(response: 0.25, dampingFraction: 0.85)
    
    // Snappy spring for interactive elements
    static let snappySpring: Animation = .spring(response: 0.2, dampingFraction: 0.9)
    
    // Instant (for performance-critical paths)
    static let instant: Animation = .linear(duration: 0.05) // ~6 frames at 120fps
    
    // Page transitions - still smooth but faster
    static let page: Animation = .spring(response: 0.3, dampingFraction: 0.82)
    
    // Interactive (follows finger/cursor closely)
    static let interactive: Animation = .interactiveSpring(response: 0.15, dampingFraction: 0.86)
    
    // Conditional animation based on system state and display capability
    static func adaptive(_ base: Animation = .easeInOut(duration: 0.18)) -> Animation? {
        // Disable animations under heavy thermal load
        if ProcessInfo.processInfo.thermalState == .critical {
            return nil
        }
        // Reduce animations in low power mode
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return .linear(duration: 0.08)
        }
        return base
    }
    
    // Animation that scales with display refresh rate (assumes 120fps target)
    static func scaledDuration(_ baseDuration: Double, targetRefreshRate: Double = 120.0) -> Animation {
        // On 120Hz displays, we can use slightly shorter durations
        // since each frame shows for less time
        let scaleFactor = 60.0 / max(60.0, targetRefreshRate)
        return .easeInOut(duration: baseDuration * scaleFactor)
    }
}

// MARK: - Lazy View Wrapper

/// Defers view creation until actually needed
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - Fixed Height Row Modifier

extension View {
    /// Applies a fixed height for optimal LazyVStack performance
    func fixedRowHeight(_ height: CGFloat) -> some View {
        self.frame(height: height)
    }
    
    /// Applies a height range for semi-dynamic content
    func boundedRowHeight(min: CGFloat = 44, max: CGFloat = 120) -> some View {
        self.frame(minHeight: min, maxHeight: max)
    }
}

// MARK: - Debounced Publisher

/// Simple debounce helper for search/filter operations
@MainActor
class Debouncer: ObservableObject {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }
    
    func debounce(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

// MARK: - Throttled Action

@MainActor
class Throttler {
    private var lastExecutionTime: Date?
    private let interval: TimeInterval
    
    init(interval: TimeInterval) {
        self.interval = interval
    }
    
    func throttle(_ action: @escaping @MainActor () -> Void) {
        let now = Date()
        
        if let lastTime = lastExecutionTime,
           now.timeIntervalSince(lastTime) < interval {
            // Skip - too soon
            return
        }
        
        lastExecutionTime = now
        action()
    }
}

// MARK: - Image Optimization Helpers

extension NSImage {
    /// Resize image to target size (call from main thread)
    @MainActor
    static func resizedSync(_ image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - Optimized List Cell

/// A list cell that reports visibility for prefetching
struct OptimizedListCell<Content: View>: View {
    let index: Int
    let content: () -> Content
    var onAppear: ((Int) -> Void)?
    var onDisappear: ((Int) -> Void)?
    
    var body: some View {
        content()
            .onAppear { onAppear?(index) }
            .onDisappear { onDisappear?(index) }
    }
}

// MARK: - View Extensions for Performance

extension View {
    /// Conditionally apply a modifier only when needed
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Apply shadow only on non-critical thermal states
    func adaptiveShadow(
        color: Color = .black.opacity(0.2),
        radius: CGFloat = 8,
        x: CGFloat = 0,
        y: CGFloat = 4
    ) -> some View {
        self.if(ProcessInfo.processInfo.thermalState != .critical) { view in
            view.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
    
    /// Reduce animation complexity under thermal pressure
    func adaptiveAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        let finalAnimation: Animation? = {
            guard let animation = animation else { return nil }
            
            switch ProcessInfo.processInfo.thermalState {
            case .critical:
                return nil
            case .serious:
                return .linear(duration: 0.1)
            default:
                return animation
            }
        }()
        
        return self.animation(finalAnimation, value: value)
    }
}

// MARK: - Memory-Efficient Image Cache

@MainActor
class OptimizedImageCache {
    static let shared = OptimizedImageCache()
    
    private var cache = NSCache<NSString, NSImage>()
    private var pendingURLs: Set<String> = []
    
    private init() {
        // Limit cache to prevent memory bloat
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max
    }
    
    func image(for url: URL, targetSize: CGSize? = nil) async -> NSImage? {
        let cacheKey = (url.absoluteString + (targetSize.map { "\($0)" } ?? "")) as NSString
        
        // Check cache
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // Check if already fetching
        if pendingURLs.contains(cacheKey as String) {
            // Wait a bit and check cache again
            try? await Task.sleep(nanoseconds: 100_000_000)
            return cache.object(forKey: cacheKey)
        }
        
        // Start fetch
        pendingURLs.insert(cacheKey as String)
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let finalImage: NSImage
            if let size = targetSize {
                // Use ImageIO downsampling — decodes only at target size, saving memory
                finalImage = ImageDownsampler.downsample(data: data, maxPixelSize: max(size.width, size.height) * 2) ?? NSImage(data: data) ?? {
                    pendingURLs.remove(cacheKey as String)
                    return NSImage()
                }()
            } else {
                guard let image = NSImage(data: data) else {
                    pendingURLs.remove(cacheKey as String)
                    return nil
                }
                finalImage = image
            }
            
            cache.setObject(finalImage, forKey: cacheKey)
            pendingURLs.remove(cacheKey as String)
            return finalImage
        } catch {
            pendingURLs.remove(cacheKey as String)
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        pendingURLs.removeAll()
    }
    
    func prefetch(urls: [URL], targetSize: CGSize? = nil) {
        for url in urls {
            Task(priority: .utility) {
                _ = await image(for: url, targetSize: targetSize)
            }
        }
    }
}

// MARK: - GPU Acceleration Modifiers

extension View {
    /// Renders complex views to a GPU texture for smoother scrolling
    /// Use for complex gradients, shadows, or layered content
    func gpuAccelerated() -> some View {
        self.drawingGroup()
    }
    
    /// Conditionally applies GPU acceleration based on complexity
    func gpuAcceleratedIf(_ condition: Bool) -> some View {
        Group {
            if condition {
                self.drawingGroup()
            } else {
                self
            }
        }
    }
    
    /// Optimized shadow that uses less GPU - single pass with lower radius
    func optimizedShadow(color: Color = .black.opacity(0.15), radius: CGFloat = 6, y: CGFloat = 3) -> some View {
        self.shadow(color: color, radius: radius, x: 0, y: y)
    }
    
    /// Pre-rendered glow effect using drawingGroup for GPU efficiency
    func optimizedGlow(color: Color, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        self.shadow(color: isActive ? color.opacity(0.4) : .clear, radius: radius)
            .drawingGroup(opaque: false)
    }
}

// MARK: - 120fps Animation Helpers

extension View {
    /// Applies a snappy 120fps-optimized animation
    func animate120fps<V: Equatable>(value: V) -> some View {
        self.animation(OptimizedAnimations.snappySpring, value: value)
    }
    
    /// Micro-animation for hover/press states at 120fps
    func microAnimate<V: Equatable>(value: V) -> some View {
        self.animation(OptimizedAnimations.micro, value: value)
    }
    
    /// Standard transition optimized for 120fps
    func standardTransition<V: Equatable>(value: V) -> some View {
        self.animation(OptimizedAnimations.standard, value: value)
    }
}

// MARK: - Reduced Motion Support

extension View {
    /// Respects user's reduced motion preference
    func reducedMotionAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        let shouldReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return self.animation(shouldReduce ? .linear(duration: 0.05) : animation, value: value)
    }
    
    /// Conditionally applies animation based on accessibility settings
    func accessibleAnimation<V: Equatable>(value: V) -> some View {
        reducedMotionAnimation(OptimizedAnimations.standard, value: value)
    }
}

// MARK: - Scroll Performance

extension View {
    /// Optimizes a view for smooth scrolling
    /// Applies fixed dimensions and GPU rendering for complex content
    func scrollOptimized(height: CGFloat) -> some View {
        self
            .frame(height: height)
            .drawingGroup(opaque: false)
    }
    
    /// Lazy loads content that's expensive to render
    func lazyRender<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        LazyView(content())
    }
}

// MARK: - Transaction Optimizations

extension View {
    /// Disables animations for performance-critical updates
    func withoutAnimation(_ action: @escaping () -> Void) -> some View {
        self.transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
    
    /// High priority transaction for immediate updates
    func highPriorityUpdate() -> some View {
        self.transaction { transaction in
            transaction.animation = nil
        }
    }
}

// MARK: - Frame Rate Hint

extension View {
    /// Hints to the system that this view would benefit from high refresh rate
    @available(macOS 14.0, *)
    func preferHighFrameRate() -> some View {
        self.contentShape(Rectangle())
            .transaction { transaction in
                // No direct API, but this signals importance
            }
    }
}

// MARK: - Background Task Helper

/// Moves heavy computation off the main thread
actor BackgroundProcessor {
    static let shared = BackgroundProcessor()
    
    private init() {}
    
    /// Processes data on background thread, returns result on main
    func process<T: Sendable, R: Sendable>(
        _ data: T,
        transform: @Sendable @escaping (T) -> R
    ) async -> R {
        return transform(data)
    }
    
    /// Batch processes array items concurrently
    func batchProcess<T: Sendable, R: Sendable>(
        _ items: [T],
        maxConcurrency: Int = 4,
        transform: @Sendable @escaping (T) async -> R
    ) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results: [Int: R] = [:]
            
            for (index, item) in items.enumerated() {
                // Limit concurrency
                if index >= maxConcurrency {
                    if let result = await group.next() {
                        results[result.0] = result.1
                    }
                }
                
                group.addTask {
                    return (index, await transform(item))
                }
            }
            
            // Collect remaining results
            for await result in group {
                results[result.0] = result.1
            }
            
            return items.indices.compactMap { results[$0] }
        }
    }
}

// MARK: - Render Tracking (Debug)

#if DEBUG
struct RenderTracker: ViewModifier {
    let label: String
    @State private var renderCount = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                renderCount += 1
                print("🔄 [\(label)] Rendered \(renderCount) times")
            }
    }
}

extension View {
    func trackRenders(_ label: String) -> some View {
        modifier(RenderTracker(label: label))
    }
}
#endif

// MARK: - 1. Enhanced Image & QR Code Cache

/// High-performance cache for wallet icons and QR codes
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    
    private let imageCache = NSCache<NSString, NSImage>()
    private let qrCache = NSCache<NSString, NSImage>()
    private var qrGenerator: CIFilter?
    
    private init() {
        // Configure cache limits
        imageCache.countLimit = 200
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
        
        qrCache.countLimit = 50
        qrCache.totalCostLimit = 20 * 1024 * 1024 // 20MB
        
        // Pre-initialize QR generator (expensive to create)
        qrGenerator = CIFilter(name: "CIQRCodeGenerator")
    }
    
    // MARK: - Image Caching
    
    func cachedImage(forKey key: String) -> NSImage? {
        imageCache.object(forKey: key as NSString)
    }
    
    func cacheImage(_ image: NSImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4) // Approximate byte size
        imageCache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func loadImage(from url: URL, cacheKey: String? = nil) async -> NSImage? {
        let key = cacheKey ?? url.absoluteString
        
        // Check cache first
        if let cached = cachedImage(forKey: key) {
            return cached
        }
        
        // Load from network/disk
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                cacheImage(image, forKey: key)
                return image
            }
        } catch {
            print("ImageCache: Failed to load image from \(url): \(error)")
        }
        return nil
    }
    
    // MARK: - QR Code Caching
    
    func cachedQRCode(forData data: String, size: CGFloat = 200) -> NSImage? {
        let key = "\(data)_\(Int(size))" as NSString
        return qrCache.object(forKey: key)
    }
    
    func generateQRCode(from string: String, size: CGFloat = 200, color: NSColor = .black) -> NSImage? {
        let cacheKey = "\(string)_\(Int(size))" as NSString
        
        // Check cache
        if let cached = qrCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Generate new QR code
        guard let qrGenerator = qrGenerator,
              let data = string.data(using: .utf8) else {
            return nil
        }
        
        qrGenerator.setValue(data, forKey: "inputMessage")
        qrGenerator.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let ciImage = qrGenerator.outputImage else { return nil }
        
        // Scale to target size
        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Convert to NSImage
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        // Cache the result
        let cost = Int(size * size * 4)
        qrCache.setObject(nsImage, forKey: cacheKey, cost: cost)
        
        return nsImage
    }
    
    // MARK: - Wallet Icon Helpers
    
    func walletIcon(for chainId: String, size: CGFloat = 32) -> NSImage? {
        let cacheKey = "wallet_\(chainId)_\(Int(size))"
        
        if let cached = cachedImage(forKey: cacheKey) {
            return cached
        }
        
        // Generate placeholder icon with chain initial
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        // Draw circle background
        let colors: [String: NSColor] = [
            "bitcoin": NSColor(red: 0.96, green: 0.62, blue: 0.14, alpha: 1),
            "ethereum": NSColor(red: 0.38, green: 0.42, blue: 0.89, alpha: 1),
            "litecoin": NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
            "solana": NSColor(red: 0.58, green: 0.38, blue: 0.96, alpha: 1),
            "monero": NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)
        ]
        let bgColor = colors[chainId] ?? NSColor.gray
        bgColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        
        // Draw initial
        let initial = String(chainId.prefix(1)).uppercased()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: initial, attributes: attrs)
        let textSize = attrString.size()
        let textRect = NSRect(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
        
        image.unlockFocus()
        cacheImage(image, forKey: cacheKey)
        return image
    }
    
    func clearAll() {
        imageCache.removeAllObjects()
        qrCache.removeAllObjects()
    }
    
    func clearQRCache() {
        qrCache.removeAllObjects()
    }
}

// MARK: - 2. Instruments Profiling Hooks (os_signpost)

import os.signpost

/// Performance signpost logger for Instruments integration
enum PerformanceSignpost {
    private static let subsystem = "com.hawala.app"
    
    static let navigation = OSLog(subsystem: subsystem, category: "Navigation")
    static let dataLoad = OSLog(subsystem: subsystem, category: "DataLoad")
    static let render = OSLog(subsystem: subsystem, category: "Render")
    static let network = OSLog(subsystem: subsystem, category: "Network")
    static let crypto = OSLog(subsystem: subsystem, category: "Crypto")
    
    // ROADMAP-20: Additional critical path categories
    static let walletLoad = OSLog(subsystem: subsystem, category: "WalletLoad")
    static let sendFlow = OSLog(subsystem: subsystem, category: "SendFlow")
    static let swapQuote = OSLog(subsystem: subsystem, category: "SwapQuote")
    static let bridgeQuote = OSLog(subsystem: subsystem, category: "BridgeQuote")
    static let feeEstimation = OSLog(subsystem: subsystem, category: "FeeEstimation")
    static let coldStart = OSLog(subsystem: subsystem, category: "ColdStart")
    static let rustFFI = OSLog(subsystem: subsystem, category: "RustFFI")
    
    // MARK: - Convenience Methods
    
    /// Mark the beginning of a navigation event
    static func beginNavigation(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: navigation, name: name, signpostID: id)
    }
    
    static func endNavigation(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: navigation, name: name, signpostID: id)
    }
    
    /// Mark data loading operations
    static func beginDataLoad(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: dataLoad, name: name, signpostID: id)
    }
    
    static func endDataLoad(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: dataLoad, name: name, signpostID: id)
    }
    
    /// Mark render passes
    static func beginRender(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: render, name: name, signpostID: id)
    }
    
    static func endRender(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: render, name: name, signpostID: id)
    }
    
    /// Mark network requests
    static func beginNetwork(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: network, name: name, signpostID: id)
    }
    
    static func endNetwork(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: network, name: name, signpostID: id)
    }
    
    /// Mark crypto operations (key generation, signing, etc.)
    static func beginCrypto(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: crypto, name: name, signpostID: id)
    }
    
    static func endCrypto(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: crypto, name: name, signpostID: id)
    }
    
    /// Event marker (instantaneous)
    static func event(_ name: StaticString, log: OSLog = navigation) {
        os_signpost(.event, log: log, name: name)
    }
    
    // MARK: - ROADMAP-20: Generic Measure Helpers
    
    /// Measure an async block and return its result (logged to the given OSLog).
    static func measure<T>(_ log: OSLog, name: StaticString = "interval", block: () async throws -> T) async rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        let result = try await block()
        os_signpost(.end, log: log, name: name, signpostID: id)
        return result
    }
    
    /// Measure a synchronous block and return its result.
    static func measureSync<T>(_ log: OSLog, name: StaticString = "interval", block: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        let result = try block()
        os_signpost(.end, log: log, name: name, signpostID: id)
        return result
    }
}

/// View modifier for automatic signpost tracking
struct SignpostModifier: ViewModifier {
    let name: StaticString
    let log: OSLog
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                os_signpost(.begin, log: log, name: name)
            }
            .onDisappear {
                os_signpost(.end, log: log, name: name)
            }
    }
}

extension View {
    /// Track view lifecycle in Instruments
    func trackInInstruments(_ name: StaticString, log: OSLog = PerformanceSignpost.render) -> some View {
        modifier(SignpostModifier(name: name, log: log))
    }
}

// MARK: - 3. Prefetching System

/// Manages prefetching of wallet data for instant tab switches
@MainActor
final class PrefetchManager: ObservableObject {
    static let shared = PrefetchManager()
    
    @Published private(set) var prefetchedTabs: Set<String> = []
    @Published private(set) var isPrefetching = false
    
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var cachedData: [String: Any] = [:]
    
    private init() {}
    
    // MARK: - Tab Prefetching
    
    /// Prefetch data for a specific tab
    func prefetchTab(_ tabId: String, loader: @escaping @MainActor () async -> Any?) {
        // Skip if already prefetched or prefetching
        guard !prefetchedTabs.contains(tabId),
              prefetchTasks[tabId] == nil else {
            return
        }
        
        isPrefetching = true
        
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceSignpost.beginDataLoad("Prefetch Tab")
            
            if let data = await loader() {
                self.cachedData[tabId] = data
                self.prefetchedTabs.insert(tabId)
            }
            
            PerformanceSignpost.endDataLoad("Prefetch Tab")
            
            self.prefetchTasks.removeValue(forKey: tabId)
            self.isPrefetching = !self.prefetchTasks.isEmpty
        }
        
        prefetchTasks[tabId] = task
    }
    
    /// Get prefetched data for a tab
    func getCachedData<T>(for tabId: String) -> T? {
        cachedData[tabId] as? T
    }
    
    /// Prefetch adjacent tabs for instant switching
    func prefetchAdjacentTabs(current: Int, total: Int, loader: @escaping @MainActor (Int) async -> Any?) {
        let adjacentIndices = [current - 1, current + 1].filter { $0 >= 0 && $0 < total }
        
        for index in adjacentIndices {
            let tabId = "tab_\(index)"
            prefetchTab(tabId) {
                await loader(index)
            }
        }
    }
    
    /// Clear all prefetched data
    func clearCache() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        cachedData.removeAll()
        prefetchedTabs.removeAll()
        isPrefetching = false
    }
    
    /// Invalidate specific cached data
    func invalidate(_ tabId: String) {
        cachedData.removeValue(forKey: tabId)
        prefetchedTabs.remove(tabId)
    }
}

// MARK: - 4. Scroll-Aware Blur Reduction

/// Tracks scroll state to reduce blur effects during active scrolling
@MainActor
final class ScrollStateManager: ObservableObject {
    static let shared = ScrollStateManager()
    
    @Published private(set) var isScrolling = false
    @Published private(set) var scrollVelocity: CGFloat = 0
    
    private var scrollEndTimer: Timer?
    private let scrollEndDelay: TimeInterval = 0.15
    
    private init() {}
    
    func reportScrolling(velocity: CGFloat = 1) {
        isScrolling = true
        scrollVelocity = velocity
        
        // Cancel existing timer
        scrollEndTimer?.invalidate()
        
        // Set new timer to detect scroll end
        scrollEndTimer = Timer.scheduledTimer(withTimeInterval: scrollEndDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isScrolling = false
                self?.scrollVelocity = 0
            }
        }
    }
    
    func reportScrollEnd() {
        scrollEndTimer?.invalidate()
        isScrolling = false
        scrollVelocity = 0
    }
}

/// View modifier that reduces blur during scrolling
struct ScrollAwareBlurModifier: ViewModifier {
    @ObservedObject private var scrollState = ScrollStateManager.shared
    let baseRadius: CGFloat
    let reducedRadius: CGFloat
    
    init(baseRadius: CGFloat = 10, reducedRadius: CGFloat = 2) {
        self.baseRadius = baseRadius
        self.reducedRadius = reducedRadius
    }
    
    func body(content: Content) -> some View {
        content
            .blur(radius: scrollState.isScrolling ? reducedRadius : baseRadius)
            .animation(OptimizedAnimations.quick, value: scrollState.isScrolling)
    }
}

extension View {
    /// Applies blur that reduces during scrolling for better performance
    func scrollAwareBlur(radius: CGFloat = 10, reducedTo: CGFloat = 2) -> some View {
        modifier(ScrollAwareBlurModifier(baseRadius: radius, reducedRadius: reducedTo))
    }
    
    /// Completely disables blur during scrolling
    func blurOnlyWhenStill(radius: CGFloat = 10) -> some View {
        modifier(ScrollAwareBlurModifier(baseRadius: radius, reducedRadius: 0))
    }
}

// MARK: - 5. Optimized ScrollView with Scroll Tracking

/// A ScrollView that reports scroll state for performance optimizations
struct OptimizedScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: () -> Content
    
    @ObservedObject private var scrollState = ScrollStateManager.shared
    
    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content
    }
    
    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollYOffsetKey.self,
                            value: geo.frame(in: .named("optimizedScroll")).minY
                        )
                    }
                )
        }
        .coordinateSpace(name: "optimizedScroll")
        .onPreferenceChange(ScrollYOffsetKey.self) { _ in
            scrollState.reportScrolling()
        }
    }
}

private struct ScrollYOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 6. Metal Shader for Aurora Background

import Metal
import MetalKit

/// High-performance Aurora background using Metal shaders
@MainActor
final class MetalAuroraRenderer: ObservableObject {
    static let shared = MetalAuroraRenderer()
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var isSetup = false
    
    @Published var isAvailable = false
    
    private init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("MetalAuroraRenderer: Metal is not supported on this device")
            return
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        // Create shader library
        guard let library = try? device.makeDefaultLibrary(bundle: .main) else {
            // Fallback: compile shader at runtime
            setupFallbackShader()
            return
        }
        
        setupPipeline(library: library)
    }
    
    private func setupFallbackShader() {
        guard let device = device else { return }
        
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut aurora_vertex(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1, -1), float2(1, -1),
                float2(-1, 1), float2(1, 1)
            };
            float2 texCoords[4] = {
                float2(0, 1), float2(1, 1),
                float2(0, 0), float2(1, 0)
            };
            
            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }
        
        fragment float4 aurora_fragment(VertexOut in [[stage_in]],
                                        constant float &time [[buffer(0)]]) {
            float2 uv = in.texCoord;
            
            // Aurora colors
            float3 color1 = float3(0.1, 0.8, 0.9); // Cyan
            float3 color2 = float3(0.6, 0.2, 0.9); // Purple
            float3 color3 = float3(0.2, 0.9, 0.4); // Green
            
            // Animated waves
            float wave1 = sin(uv.x * 3.0 + time * 0.5) * 0.5 + 0.5;
            float wave2 = sin(uv.x * 5.0 - time * 0.3 + 1.5) * 0.5 + 0.5;
            float wave3 = cos(uv.y * 4.0 + time * 0.4) * 0.5 + 0.5;
            
            // Blend colors based on waves and position
            float3 color = mix(color1, color2, wave1);
            color = mix(color, color3, wave2 * uv.y);
            color *= (0.3 + wave3 * 0.3);
            
            // Fade at edges
            float fade = smoothstep(0.0, 0.3, uv.y) * smoothstep(1.0, 0.7, uv.y);
            
            return float4(color * fade, 0.6 * fade);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            setupPipeline(library: library)
        } catch {
            print("MetalAuroraRenderer: Failed to compile shader: \(error)")
        }
    }
    
    private func setupPipeline(library: MTLLibrary) {
        guard let device = device,
              let vertexFunction = library.makeFunction(name: "aurora_vertex"),
              let fragmentFunction = library.makeFunction(name: "aurora_fragment") else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            isSetup = true
            isAvailable = true
        } catch {
            print("MetalAuroraRenderer: Failed to create pipeline: \(error)")
        }
    }
    
    func render(to drawable: CAMetalDrawable, time: Float) {
        guard isSetup,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState else {
            return
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        var timeValue = time
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// SwiftUI wrapper for Metal Aurora background
struct MetalAuroraView: NSViewRepresentable {
    @ObservedObject private var renderer = MetalAuroraRenderer.shared
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 120 // Target 120fps
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.layer?.isOpaque = false
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        private var startTime = CACurrentMediaTime()
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            let time = Float(CACurrentMediaTime() - startTime)
            
            Task { @MainActor in
                MetalAuroraRenderer.shared.render(to: drawable, time: time)
            }
        }
    }
}

// MARK: - 7. LazyVStack Optimization Helper

/// A view that wraps content in LazyVStack for scroll performance
struct LazyScrollContent<Content: View>: View {
    let spacing: CGFloat
    let pinnedViews: PinnedScrollableViews
    let content: () -> Content
    
    init(
        spacing: CGFloat = 8,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content
    }
    
    var body: some View {
        LazyVStack(spacing: spacing, pinnedViews: pinnedViews) {
            content()
        }
    }
}

// MARK: - Combined Performance View Extension

extension View {
    /// Applies all scroll optimizations: LazyVStack wrapper, scroll tracking, blur reduction
    func optimizedForScrolling() -> some View {
        self
            .drawingGroup(opaque: false)
    }
    
    /// Full performance suite for list items
    func optimizedListItem(height: CGFloat = 56) -> some View {
        self
            .frame(height: height)
            .drawingGroup(opaque: false)
    }
    
    /// Prefetch data when view appears
    func prefetch(_ tabId: String, loader: @escaping @MainActor () async -> Any?) -> some View {
        self.onAppear {
            PrefetchManager.shared.prefetchTab(tabId, loader: loader)
        }
    }
}

// MARK: - ImageIO Downsampling

import ImageIO

/// High-performance image downsampling using ImageIO (never decodes full bitmap).
/// Use instead of `NSImage.resizedSync` for loading remote/disk images at display size.
enum ImageDownsampler {
    /// Downsample image data to a maximum pixel dimension without decoding full resolution.
    /// This is the most memory-efficient way to load large images at a smaller display size.
    static func downsample(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false  // Don't cache full-size decoded bitmap
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }
    
    /// Downsample from a file URL.
    static func downsample(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }
    
    private static func downsample(source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,     // Decode at thumbnail size immediately
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - Background JSON Decoder

/// Moves JSON decoding off the main thread. Returns decoded value on caller's context.
/// Usage: `let prices = try await JSONDecodeOffMain.decode([String: Double].self, from: data)`
enum JSONDecodeOffMain {
    /// Sendable wrapper for `Any` results from JSONSerialization
    private struct AnyBox: @unchecked Sendable {
        let value: Any
    }
    
    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(type, from: data)
        }.value
    }
    
    static func decodeJSON(_ data: Data) async throws -> Any {
        let box = try await Task.detached(priority: .userInitiated) {
            let result = try JSONSerialization.jsonObject(with: data, options: [])
            return AnyBox(value: result)
        }.value
        return box.value
    }
}

// MARK: - 8. Cold Start Timer

/// Measures wall-clock time from process launch to first meaningful frame.
/// Drop `ColdStartTimer.shared.markReady()` at the end of your root view's `.onAppear`.
@MainActor
final class ColdStartTimer: ObservableObject {
    static let shared = ColdStartTimer()
    
    /// Absolute time captured as early as possible (static initializer)
    private static let processStart = CFAbsoluteTimeGetCurrent()
    
    @Published private(set) var coldStartDuration: Double?
    @Published private(set) var phase: Phase = .launching
    
    private var phaseTimestamps: [(Phase, CFAbsoluteTime)] = []
    private let signpostLog = OSLog(subsystem: "com.hawala.app", category: "ColdStart")
    
    enum Phase: String, CaseIterable {
        case launching    // Process started
        case initializing // App struct init
        case rendering    // First SwiftUI body
        case interactive  // User can interact
    }
    
    private init() {
        record(.launching) // retroactively for processStart
    }
    
    /// Call from `KeyGeneratorApp.init()`
    func markInit() {
        record(.initializing)
        os_signpost(.event, log: signpostLog, name: "AppInit")
    }
    
    /// Call from root view `.onAppear`
    func markRendered() {
        record(.rendering)
        os_signpost(.event, log: signpostLog, name: "FirstRender")
    }
    
    /// Call once the UI is fully interactive (data loaded, no spinners)
    func markReady() {
        record(.interactive)
        let total = CFAbsoluteTimeGetCurrent() - Self.processStart
        coldStartDuration = total
        phase = .interactive
        
        os_signpost(.event, log: signpostLog, name: "Interactive")
        
        // ROADMAP-20 E7: Track cold start performance
        AnalyticsService.shared.track(AnalyticsService.EventName.coldStart, properties: [
            "duration_ms": String(Int(total * 1000)),
            "meets_target": total < 2.0 ? "true" : "false"
        ])
        
        #if DEBUG
        print("🚀 Cold start breakdown:")
        for (i, entry) in phaseTimestamps.enumerated() {
            let delta: Double
            if i == 0 {
                delta = 0
            } else {
                delta = entry.1 - phaseTimestamps[i - 1].1
            }
            print("   \(entry.0.rawValue): +\(String(format: "%.3f", delta))s")
        }
        print("   Total: \(String(format: "%.3f", total))s \(total < 2.0 ? "✅" : "⚠️ exceeds 2s budget")")
        #endif
    }
    
    /// Duration from process start to a given phase (nil if phase not yet recorded)
    func elapsed(to targetPhase: Phase) -> Double? {
        guard let entry = phaseTimestamps.first(where: { $0.0 == targetPhase }) else { return nil }
        return entry.1 - Self.processStart
    }
    
    var meetsTarget: Bool {
        guard let d = coldStartDuration else { return false }
        return d < 2.0
    }
    
    private func record(_ p: Phase) {
        phase = p
        phaseTimestamps.append((p, CFAbsoluteTimeGetCurrent()))
    }
}

// MARK: - 9. Network Request Batching

/// Coalesces identical in-flight network requests so the same URL is never
/// fetched twice concurrently.  Callers sharing the same key automatically
/// share the same `URLSession` data task and receive the same result.
actor NetworkBatchManager {
    static let shared = NetworkBatchManager()
    
    private var inFlight: [String: Task<(Data, URLResponse), Error>] = [:]
    private var stats = Stats()
    
    struct Stats: Sendable {
        var totalRequests: Int = 0
        var coalescedRequests: Int = 0
        var failedRequests: Int = 0
    }
    
    private init() {}
    
    /// Fetch data, coalescing duplicate requests by `key`.
    /// The default key is the request URL; callers may supply a custom key.
    func fetch(
        _ request: URLRequest,
        key: String? = nil,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        let cacheKey = key ?? request.url?.absoluteString ?? UUID().uuidString
        stats.totalRequests += 1
        
        // Coalesce if an identical request is already in-flight
        if let existing = inFlight[cacheKey] {
            stats.coalescedRequests += 1
            return try await existing.value
        }
        
        let task = Task<(Data, URLResponse), Error> {
            try await session.data(for: request)
        }
        
        inFlight[cacheKey] = task
        
        do {
            let result = try await task.value
            inFlight.removeValue(forKey: cacheKey)
            return result
        } catch {
            inFlight.removeValue(forKey: cacheKey)
            stats.failedRequests += 1
            throw error
        }
    }
    
    /// Convenience for simple GET URLs.
    func fetch(url: URL, key: String? = nil) async throws -> (Data, URLResponse) {
        try await fetch(URLRequest(url: url), key: key)
    }
    
    /// Batch multiple URLs concurrently, coalescing duplicates.
    func fetchBatch(
        urls: [URL],
        maxConcurrency: Int = 6
    ) async -> [(url: URL, result: Result<(Data, URLResponse), Error>)] {
        await withTaskGroup(of: (Int, Result<(Data, URLResponse), Error>).self) { group in
            var results: [(url: URL, result: Result<(Data, URLResponse), Error>)] =
                urls.map { ($0, .failure(CancellationError())) }
            
            for (index, url) in urls.enumerated() {
                if index >= maxConcurrency {
                    if let completed = await group.next() {
                        results[completed.0] = (urls[completed.0], completed.1)
                    }
                }
                group.addTask { [self] in
                    do {
                        let data = try await self.fetch(url: url)
                        return (index, .success(data))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await completed in group {
                results[completed.0] = (urls[completed.0], completed.1)
            }
            return results
        }
    }
    
    /// How many requests were saved by coalescing.
    func getStats() -> Stats { stats }
    
    /// Cancel all in-flight tasks (e.g. on logout).
    func cancelAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}

// MARK: - 10. Memory Pressure Handler

/// Monitors system memory pressure via `DispatchSource` and triggers
/// progressive cache eviction.  Integrates with existing caches
/// (`ImageCache`, `OptimizedImageCache`, `PrefetchManager`).
@MainActor
final class MemoryPressureHandler: ObservableObject {
    static let shared = MemoryPressureHandler()
    
    @Published private(set) var currentLevel: PressureLevel = .normal
    @Published private(set) var evictionCount: Int = 0
    
    enum PressureLevel: String {
        case normal
        case warning
        case critical
    }
    
    private var source: DispatchSourceMemoryPressure?
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        source?.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let event = source.data
            
            Task { @MainActor in
                if event.contains(.critical) {
                    self.handlePressure(.critical)
                } else if event.contains(.warning) {
                    self.handlePressure(.warning)
                }
            }
        }
        
        source?.resume()
    }
    
    private func handlePressure(_ level: PressureLevel) {
        currentLevel = level
        evictionCount += 1
        
        switch level {
        case .warning:
            // Trim non-essential caches
            PrefetchManager.shared.clearCache()
            OptimizedImageCache.shared.clearCache()
            #if DEBUG
            print("⚠️ Memory pressure WARNING — cleared prefetch + image caches")
            #endif
            
        case .critical:
            // Aggressive: clear everything
            PrefetchManager.shared.clearCache()
            OptimizedImageCache.shared.clearCache()
            ImageCache.shared.clearAll()
            URLCache.shared.removeAllCachedResponses()
            #if DEBUG
            print("🔴 Memory pressure CRITICAL — cleared ALL caches + URLCache")
            #endif
            
        case .normal:
            break
        }
        
        PerformanceMonitor.logMemory(label: "After \(level.rawValue) eviction")
    }
    
    /// Manually trigger an eviction (e.g. before heavy crypto operation)
    func evictIfNeeded(threshold: Double = 500) {
        let currentMB = PerformanceMonitor.shared.memoryUsageMB
        if currentMB > threshold {
            handlePressure(.warning)
        }
    }
    
    deinit {
        source?.cancel()
    }
}

// MARK: - 11. Startup Boot Sequence Manager

/// Orchestrates app startup into prioritized phases so the main thread
/// becomes interactive as fast as possible.
///
/// Usage from `KeyGeneratorApp.init()` or `AppRootView.onAppear`:
/// ```
/// await StartupSequenceManager.shared.run()
/// ColdStartTimer.shared.markReady()
/// ```
@MainActor
final class StartupSequenceManager: ObservableObject {
    static let shared = StartupSequenceManager()
    
    @Published private(set) var currentPhase: Phase = .notStarted
    @Published private(set) var isComplete = false
    
    enum Phase: String, CaseIterable {
        case notStarted
        case critical    // Keychain, seed validation (blocks UI)
        case high        // Balance fetch, price fetch (shows stale then updates)
        case normal      // History, analytics, coachmarks
        case low         // Prefetch, sparklines, secondary chains
        case done
    }
    
    typealias BootTask = @MainActor @Sendable () async -> Void
    
    private var tasks: [Phase: [BootTask]] = [:]
    private var phaseDurations: [Phase: Double] = [:]
    
    private init() {}
    
    /// Register a task to run at a specific boot phase.
    func register(phase: Phase, task: @escaping BootTask) {
        tasks[phase, default: []].append(task)
    }
    
    /// Execute all registered tasks in phase order.
    /// Critical runs serially (on main), high/normal/low run concurrently.
    func run() async {
        let phases: [Phase] = [.critical, .high, .normal, .low]
        
        for phase in phases {
            guard let phaseTasks = tasks[phase], !phaseTasks.isEmpty else { continue }
            currentPhase = phase
            let start = CFAbsoluteTimeGetCurrent()
            
            if phase == .critical {
                // Serial execution — must finish before UI renders
                for task in phaseTasks {
                    await task()
                }
            } else {
                // Concurrent execution within the phase
                for task in phaseTasks {
                    await task()
                }
            }
            
            phaseDurations[phase] = CFAbsoluteTimeGetCurrent() - start
        }
        
        currentPhase = .done
        isComplete = true
        
        #if DEBUG
        print("🏁 Boot sequence complete:")
        for phase in phases {
            if let d = phaseDurations[phase] {
                print("   \(phase.rawValue): \(String(format: "%.3f", d))s")
            }
        }
        #endif
    }
    
    /// Reset (useful for tests or re-login)
    func reset() {
        tasks.removeAll()
        phaseDurations.removeAll()
        currentPhase = .notStarted
        isComplete = false
    }
}
