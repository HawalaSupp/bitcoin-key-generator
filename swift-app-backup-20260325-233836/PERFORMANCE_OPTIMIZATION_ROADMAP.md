# 🚀 macOS SwiftUI Performance Optimization Roadmap

> A comprehensive, step-by-step guide to transform a laggy macOS SwiftUI app into a smooth 60fps+ experience.

---

## Table of Contents

1. [Profiling and Measuring Performance](#1-profiling-and-measuring-performance)
2. [Optimizing UI Rendering and Lists](#2-optimizing-ui-rendering-and-lists)
3. [Offloading Work from the Main Thread](#3-offloading-work-from-the-main-thread)
4. [Handling Images and Assets Efficiently](#4-handling-images-and-assets-efficiently)
5. [Managing Memory and Avoiding Leaks](#5-managing-memory-and-avoiding-leaks)
6. [Tuning Animations and Effects](#6-tuning-animations-and-effects)
7. [Optimizing Data Flow and Loading](#7-optimizing-data-flow-and-loading)
8. [Quick Wins Checklist](#8-quick-wins-checklist)

---

## 1. Profiling and Measuring Performance

### Why This Matters
Before optimizing, you need data. Random optimizations often waste time on non-bottlenecks. Profiling identifies the **actual** performance issues.

### 1.1 Setting Up for Profiling

#### Step 1: Build for Profiling
```bash
# Build in Release mode (optimizations enabled)
Product → Build For → Profiling (⌘⇧I)
```

> ⚠️ **Important**: Always profile Release builds. Debug builds have significant overhead that masks real performance.

#### Step 2: Profile on Target Hardware
- Test on the **oldest Mac** your app supports
- M1 Macs can hide issues that appear on Intel
- Test with realistic data (1000+ items, not 10)

### 1.2 Essential Xcode Instruments

#### Time Profiler - Find CPU Bottlenecks
```
1. Product → Profile (⌘I)
2. Select "Time Profiler"
3. Click Record, interact with laggy areas
4. Stop and analyze the heaviest stack traces
```

**What to look for:**
- Functions taking >16ms (blocks 60fps)
- Repeated calls to the same function
- Main thread work that should be background

**Example interpretation:**
```
Weight    Self Weight    Symbol
45.2%     2.1%          closure #1 in ContentView.body.getter
  └─ 43.1%  40.0%       JSONDecoder.decode(_:from:)  ← BOTTLENECK!
```
*This shows JSON parsing is blocking the UI thread.*

#### SwiftUI Instrument - View Render Analysis
```
1. Product → Profile
2. Select "SwiftUI" instrument
3. Look for:
   - View Body Invocations (too many = bad)
   - View Updates (cascading updates = bad)
   - Time in Body (>1ms = investigate)
```

**Interpreting Results:**
| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Body invocations/sec | <100 | 100-500 | >500 |
| Time in body | <1ms | 1-5ms | >5ms |
| Update frequency | On user action | Every frame | Constant |

#### Core Animation Instrument - Rendering Issues
```
1. Select "Core Animation" template
2. Enable "Color Blended Layers" (red = overdraw)
3. Enable "Color Offscreen-Rendered" (yellow = expensive)
```

**Performance gains:** Fixing identified issues typically yields **2-5x improvement**.

### 1.3 Quick Performance Baseline Script

Add this to measure frame rendering:

```swift
// PerformanceMonitor.swift
import SwiftUI
import QuartzCore

class PerformanceMonitor: ObservableObject {
    @Published var fps: Double = 0
    @Published var frameDrops: Int = 0
    
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    
    func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }
        
        CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
            let monitor = Unmanaged<PerformanceMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.tick()
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        
        CVDisplayLinkStart(displayLink)
    }
    
    private func tick() {
        let now = CACurrentMediaTime()
        frameCount += 1
        
        if now - lastTimestamp >= 1.0 {
            fps = Double(frameCount) / (now - lastTimestamp)
            if fps < 55 { frameDrops += 1 }
            frameCount = 0
            lastTimestamp = now
        }
    }
    
    func stop() {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}

// Usage in your app:
struct DebugOverlay: View {
    @StateObject private var monitor = PerformanceMonitor()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("FPS: \(monitor.fps, specifier: "%.1f")")
            Text("Drops: \(monitor.frameDrops)")
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.7))
        .foregroundColor(monitor.fps < 55 ? .red : .green)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
```

---

## 2. Optimizing UI Rendering and Lists

### Why This Matters
SwiftUI's `List` on macOS is **NOT lazy by default** before macOS 13. This means 10,000 items = 10,000 views created upfront.

### 2.1 The List Problem on macOS

#### ❌ Problem: Non-Lazy List
```swift
// BAD - Creates ALL 10,000 views immediately
struct BadListView: View {
    let items: [Item] // 10,000 items
    
    var body: some View {
        List(items) { item in
            ItemRow(item: item) // 10,000 ItemRow views created!
        }
    }
}
```

#### ✅ Solution 1: Use Table (macOS 12+)
```swift
// GOOD - Table is lazy on macOS
struct GoodTableView: View {
    let items: [Item]
    
    var body: some View {
        Table(items) {
            TableColumn("Name", value: \.name)
            TableColumn("Value") { item in
                Text(item.value)
            }
        }
    }
}
```
**Performance gain:** 10-100x faster initial load for large datasets.

#### ✅ Solution 2: ScrollView + LazyVStack
```swift
// GOOD - Explicit lazy loading
struct LazyListView: View {
    let items: [Item]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    ItemRow(item: item)
                        .frame(height: 44) // CRITICAL: Fixed height!
                }
            }
        }
    }
}
```
**Performance gain:** 5-50x improvement depending on item count.

### 2.2 Fixed Frame Heights (Critical!)

#### Why Fixed Heights Matter
Without fixed heights, SwiftUI must:
1. Create the view
2. Measure it
3. Layout it
4. Potentially re-measure on scroll

```swift
// ❌ BAD - Variable height causes measurement overhead
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item) // Height unknown until rendered
    }
}

// ✅ GOOD - Fixed height skips measurement
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item)
            .frame(height: 60) // SwiftUI knows height without rendering
    }
}
```

**For variable content, use estimated heights:**
```swift
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item)
            .frame(minHeight: 44, maxHeight: 120) // Bounded range
    }
}
```

### 2.3 Minimize View Hierarchy Depth

#### ❌ Deep Hierarchies (Slow)
```swift
// Each wrapper adds layout passes
var body: some View {
    VStack {
        HStack {
            VStack {
                HStack {
                    VStack {
                        Text("Deep!")
                    }
                }
            }
        }
    }
}
```

#### ✅ Flattened Hierarchy (Fast)
```swift
var body: some View {
    HStack {
        Text("Shallow!")
        Spacer()
        Text("Fast!")
    }
}
```

**Measurement:** Each nesting level adds ~0.1-0.5ms. 10 levels = 1-5ms per view.

### 2.4 Avoid Expensive Modifiers

#### Slow Modifiers (Use Sparingly)
```swift
// ❌ These trigger expensive layout passes
ViewThatFits { ... }           // Measures ALL children
GeometryReader { ... }         // Forces layout pass
.fixedSize()                   // Overrides lazy sizing
.alignmentGuide { ... }        // Custom alignment calculations
```

#### Fast Alternatives
```swift
// ✅ Pre-compute sizes when possible
struct OptimizedView: View {
    let precomputedWidth: CGFloat = 200
    
    var body: some View {
        Text("Fast")
            .frame(width: precomputedWidth) // No measurement needed
    }
}
```

### 2.5 Prevent Unnecessary Re-renders

#### Use @StateObject for View Models
```swift
// ❌ BAD - Recreated on every parent update
struct ParentView: View {
    var body: some View {
        ChildView(viewModel: ViewModel()) // New instance each render!
    }
}

// ✅ GOOD - Single instance, stable identity
struct ParentView: View {
    @StateObject private var viewModel = ViewModel()
    
    var body: some View {
        ChildView(viewModel: viewModel)
    }
}
```

#### Use .id() for Forced Updates Only
```swift
// ❌ BAD - Changing ID destroys and recreates view
ForEach(items) { item in
    ItemRow(item: item)
        .id(UUID()) // NEW ID EVERY RENDER = TERRIBLE
}

// ✅ GOOD - Stable IDs
ForEach(items) { item in
    ItemRow(item: item)
        .id(item.id) // Stable, only changes when item changes
}
```

#### Equatable Views
```swift
// Force SwiftUI to use value comparison
struct ItemRow: View, Equatable {
    let item: Item
    
    static func == (lhs: ItemRow, rhs: ItemRow) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.item.lastModified == rhs.item.lastModified
    }
    
    var body: some View {
        HStack {
            Text(item.name)
            Spacer()
            Text(item.value)
        }
    }
}

// Usage
ForEach(items) { item in
    ItemRow(item: item)
        .equatable() // Uses our == comparison
}
```

**Performance gain:** 2-10x fewer re-renders.

### 2.6 Canvas for Complex Graphics

```swift
// ❌ BAD - Many SwiftUI views for chart
struct SlowChart: View {
    let dataPoints: [CGFloat]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<dataPoints.count, id: \.self) { i in
                Circle()
                    .frame(width: 4, height: 4)
                    .position(x: ..., y: ...)
            }
        }
    }
}

// ✅ GOOD - Single Canvas draw call
struct FastChart: View {
    let dataPoints: [CGFloat]
    
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for (index, point) in dataPoints.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(dataPoints.count - 1)
                let y = size.height * (1 - point)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(.blue), lineWidth: 2)
        }
    }
}
```

**Performance gain:** 10-100x for complex graphics (charts, graphs, visualizations).

---

## 3. Offloading Work from the Main Thread

### Why This Matters
The main thread handles ALL UI updates. Any work >16ms blocks the next frame, causing visible lag.

### 3.1 Identify Main Thread Blockers

Common culprits:
- JSON parsing
- Image decoding
- Database queries
- File I/O
- Complex calculations
- Network response processing

### 3.2 Using async/await (Recommended)

```swift
class DataViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    
    // ✅ GOOD - Work happens off main thread
    func loadData() async {
        await MainActor.run { isLoading = true }
        
        // This runs on a background thread
        let data = await fetchDataFromNetwork()
        let parsed = await parseJSON(data) // Heavy work off main thread
        
        // Only UI update on main thread
        await MainActor.run {
            self.items = parsed
            self.isLoading = false
        }
    }
    
    private func parseJSON(_ data: Data) async -> [Item] {
        // Explicitly run on background
        await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode([Item].self, from: data)
        }.value ?? []
    }
}
```

### 3.3 Using DispatchQueue

```swift
class LegacyViewModel: ObservableObject {
    @Published var processedData: [ProcessedItem] = []
    
    func processHeavyData(_ rawData: [RawData]) {
        // Move to background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Heavy processing
            let processed = rawData.map { item -> ProcessedItem in
                // Complex transformation
                ProcessedItem(transformed: item)
            }
            
            // Return to main thread for UI update
            DispatchQueue.main.async {
                self?.processedData = processed
            }
        }
    }
}
```

### 3.4 @MainActor for UI-bound Classes

```swift
// Entire class runs on main thread (safe for @Published)
@MainActor
class UIViewModel: ObservableObject {
    @Published var displayItems: [Item] = []
    
    func updateUI(with items: [Item]) {
        // Guaranteed main thread
        displayItems = items
    }
    
    nonisolated func backgroundProcess() async -> [Item] {
        // This CAN run off main thread
        await heavyComputation()
    }
}
```

### 3.5 Task Priority Selection

```swift
// High priority - user is waiting
Task(priority: .userInitiated) {
    await loadVisibleContent()
}

// Low priority - prefetching
Task(priority: .utility) {
    await prefetchNextPage()
}

// Background - analytics, cleanup
Task(priority: .background) {
    await uploadAnalytics()
}
```

**Performance gain:** 2-10x perceived responsiveness.

---

## 4. Handling Images and Assets Efficiently

### Why This Matters
Images are often the #1 memory consumer and can cause massive lag if loaded/decoded on the main thread.

### 4.1 Image Loading Pipeline

```swift
// Complete efficient image loading system
actor ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSString, NSImage>()
    private var loadingTasks: [String: Task<NSImage?, Never>] = [:]
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    func image(for url: URL, targetSize: CGSize? = nil) async -> NSImage? {
        let key = url.absoluteString as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[url.absoluteString] {
            return await existingTask.value
        }
        
        // Start new load
        let task = Task<NSImage?, Never> {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = NSImage(data: data) else {
                return nil
            }
            
            // Resize if needed (OFF MAIN THREAD)
            let finalImage: NSImage
            if let targetSize = targetSize {
                finalImage = await resizeImage(image, to: targetSize)
            } else {
                finalImage = image
            }
            
            // Cache it
            cache.setObject(finalImage, forKey: key)
            return finalImage
        }
        
        loadingTasks[url.absoluteString] = task
        let result = await task.value
        loadingTasks[url.absoluteString] = nil
        
        return result
    }
    
    private func resizeImage(_ image: NSImage, to size: CGSize) async -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
```

### 4.2 Efficient Image View

```swift
struct CachedAsyncImage: View {
    let url: URL?
    let targetSize: CGSize
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipped()
        .task(id: url) {
            guard let url = url else { return }
            isLoading = true
            image = await ImageCache.shared.image(for: url, targetSize: targetSize)
            isLoading = false
        }
    }
}
```

### 4.3 Image Best Practices

```swift
// ✅ ALWAYS specify display size
Image(nsImage: myImage)
    .resizable()
    .aspectRatio(contentMode: .fill)
    .frame(width: 100, height: 100) // Prevents full-size decode
    .clipped()

// ✅ Use thumbnails for lists
struct ImageRow: View {
    let fullImageURL: URL
    
    var body: some View {
        CachedAsyncImage(
            url: thumbnailURL(for: fullImageURL), // 100x100 thumbnail
            targetSize: CGSize(width: 50, height: 50)
        )
    }
    
    func thumbnailURL(for url: URL) -> URL {
        // Many CDNs support size parameters
        // e.g., Cloudinary: .../w_100,h_100/image.jpg
        url.appendingPathComponent("?size=thumbnail")
    }
}
```

### 4.4 Prefetching for Scroll Performance

```swift
class ImagePrefetcher: ObservableObject {
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    
    func prefetch(urls: [URL], targetSize: CGSize) {
        for url in urls {
            guard prefetchTasks[url] == nil else { continue }
            
            prefetchTasks[url] = Task(priority: .utility) {
                _ = await ImageCache.shared.image(for: url, targetSize: targetSize)
            }
        }
    }
    
    func cancelPrefetch(for url: URL) {
        prefetchTasks[url]?.cancel()
        prefetchTasks[url] = nil
    }
}

// Usage in list
struct ImageList: View {
    let items: [ImageItem]
    @StateObject private var prefetcher = ImagePrefetcher()
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(items) { item in
                    ImageRow(item: item)
                        .onAppear {
                            // Prefetch next 10 images
                            let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                            let nextURLs = items[index..<min(index + 10, items.count)]
                                .map { $0.imageURL }
                            prefetcher.prefetch(urls: Array(nextURLs), targetSize: CGSize(width: 100, height: 100))
                        }
                }
            }
        }
    }
}
```

**Performance gain:** 3-10x smoother scrolling with images.

---

## 5. Managing Memory and Avoiding Leaks

### Why This Matters
Memory leaks cause gradual slowdown, and high memory usage triggers system throttling. Target: <100MB for typical apps.

### 5.1 The [weak self] Rule

```swift
// ❌ BAD - Strong reference cycle
class ViewModel: ObservableObject {
    var timer: Timer?
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.tick() // Strong reference to self!
        }
    }
}

// ✅ GOOD - Weak reference
class ViewModel: ObservableObject {
    var timer: Timer?
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick() // Weak reference, no cycle
        }
    }
    
    deinit {
        timer?.invalidate() // Clean up!
        print("ViewModel deallocated") // Verify this prints
    }
}
```

### 5.2 Closure Capture Patterns

```swift
// Pattern 1: [weak self] with guard
someAsyncOperation { [weak self] result in
    guard let self = self else { return }
    self.handleResult(result)
}

// Pattern 2: Capture specific properties
let localProperty = self.importantValue
someAsyncOperation { result in
    // Uses localProperty, not self
    process(result, with: localProperty)
}

// Pattern 3: [unowned self] when you KNOW self outlives closure
class Parent {
    lazy var child: Child = {
        Child(parent: self) // Child can't exist without parent
    }()
}
```

### 5.3 Memory Monitoring

```swift
struct MemoryMonitor {
    static var currentUsageMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }
    
    static func logMemoryUsage(label: String) {
        print("[\(label)] Memory: \(String(format: "%.1f", currentUsageMB)) MB")
    }
}

// Usage
MemoryMonitor.logMemoryUsage(label: "Before loading images")
await loadImages()
MemoryMonitor.logMemoryUsage(label: "After loading images")
```

### 5.4 View Cleanup

```swift
struct HeavyView: View {
    @StateObject private var viewModel = HeavyViewModel()
    
    var body: some View {
        ContentView(data: viewModel.data)
            .onDisappear {
                viewModel.cleanup() // Release resources
            }
    }
}

class HeavyViewModel: ObservableObject {
    var images: [NSImage] = []
    var cache = NSCache<NSString, NSData>()
    
    func cleanup() {
        images.removeAll()
        cache.removeAllObjects()
    }
    
    deinit {
        cleanup()
    }
}
```

### 5.5 Finding Leaks with Instruments

```
1. Product → Profile → Leaks
2. Run app, navigate to suspected leak area
3. Look for:
   - Growing memory graph
   - Purple leak indicators
   - Retain cycles in the detail view
```

**Common leak sources:**
- Closures capturing `self` strongly
- NotificationCenter observers not removed
- Timers not invalidated
- Delegates not set to `weak`

**Performance gain:** Stable memory = stable performance over time.

---

## 6. Tuning Animations and Effects

### Why This Matters
Animations run every frame (60-120fps). Complex animations can consume 100% of frame budget.

### 6.1 Animation Performance Rules

```swift
// ❌ BAD - Animating expensive properties
withAnimation(.easeInOut(duration: 2.0)) {
    // These trigger full re-renders
    viewModel.items = newItems
    viewModel.showComplexView = true
}

// ✅ GOOD - Animate only transforms
withAnimation(.easeInOut(duration: 0.3)) {
    // These are GPU-accelerated
    offset = newOffset
    scale = newScale
    opacity = newOpacity
    rotation = newRotation
}
```

### 6.2 Optimal Animation Durations

```swift
struct AnimationDurations {
    // User-triggered (feels responsive)
    static let quick = 0.15      // Button taps
    static let normal = 0.25     // Navigation
    static let slow = 0.35       // Modal presentations
    
    // System animations
    static let hover = 0.1       // Hover states
    static let loading = 0.8     // Loading spinners
    
    // ❌ Avoid
    static let tooSlow = 1.0+    // Feels laggy
}

// Usage
withAnimation(.spring(response: AnimationDurations.normal, dampingFraction: 0.8)) {
    isExpanded.toggle()
}
```

### 6.3 Reduce Animation Complexity

```swift
// ❌ BAD - Multiple simultaneous animations
struct OverAnimatedCard: View {
    @State private var isHovered = false
    
    var body: some View {
        CardContent()
            .scaleEffect(isHovered ? 1.1 : 1.0)       // Animation 1
            .shadow(radius: isHovered ? 20 : 5)        // Animation 2 (expensive!)
            .rotation3DEffect(...)                      // Animation 3 (very expensive!)
            .blur(radius: isHovered ? 0 : 2)           // Animation 4 (extremely expensive!)
    }
}

// ✅ GOOD - Single, efficient animation
struct EfficientCard: View {
    @State private var isHovered = false
    
    var body: some View {
        CardContent()
            .scaleEffect(isHovered ? 1.02 : 1.0)      // Only one, subtle animation
            .animation(.spring(response: 0.2), value: isHovered)
    }
}
```

### 6.4 Hardware Testing Matrix

Test animations on:
| Device | Expected FPS | Notes |
|--------|--------------|-------|
| M1/M2 Mac | 120fps | Baseline |
| Intel Mac (2018+) | 60fps | Common target |
| Intel Mac (2015-2017) | 30-60fps | Reduce complexity |
| External displays | Varies | Test different refresh rates |

### 6.5 Disable Animations When Needed

```swift
struct AdaptiveAnimations {
    // Check for reduced motion preference
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    // System load detection
    static var shouldReduceAnimations: Bool {
        ProcessInfo.processInfo.thermalState == .critical ||
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    static func animation(_ base: Animation) -> Animation? {
        if shouldReduceAnimations {
            return nil // No animation
        }
        return base
    }
}

// Usage
withAnimation(AdaptiveAnimations.animation(.spring())) {
    isExpanded = true
}
```

**Performance gain:** 2-5x improvement on lower-end hardware.

---

## 7. Optimizing Data Flow and Loading

### Why This Matters
How data flows through your app directly impacts re-renders and perceived performance.

### 7.1 MVVM Architecture for SwiftUI

```swift
// Model - Plain data
struct Transaction: Identifiable, Codable {
    let id: UUID
    let amount: Decimal
    let date: Date
    let description: String
}

// ViewModel - Business logic, @Published for UI binding
@MainActor
class TransactionViewModel: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let repository: TransactionRepository
    
    init(repository: TransactionRepository = .shared) {
        self.repository = repository
    }
    
    func loadTransactions() async {
        isLoading = true
        error = nil
        
        do {
            transactions = try await repository.fetchTransactions()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    // Computed property - no @Published needed
    var totalAmount: Decimal {
        transactions.reduce(0) { $0 + $1.amount }
    }
}

// View - Only UI
struct TransactionListView: View {
    @StateObject private var viewModel = TransactionViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
            } else if let error = viewModel.error {
                ErrorView(error: error, retry: { Task { await viewModel.loadTransactions() } })
            } else {
                TransactionList(transactions: viewModel.transactions)
            }
        }
        .task {
            await viewModel.loadTransactions()
        }
    }
}
```

### 7.2 Pagination for Large Data Sets

```swift
@MainActor
class PaginatedViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoadingMore = false
    
    private var currentPage = 0
    private var hasMorePages = true
    private let pageSize = 50
    
    func loadInitial() async {
        currentPage = 0
        hasMorePages = true
        items = await fetchPage(0)
    }
    
    func loadMoreIfNeeded(currentItem: Item) async {
        // Load more when user reaches last 5 items
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }),
              index >= items.count - 5,
              hasMorePages,
              !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        let newItems = await fetchPage(currentPage)
        if newItems.isEmpty {
            hasMorePages = false
        } else {
            items.append(contentsOf: newItems)
        }
        
        isLoadingMore = false
    }
    
    private func fetchPage(_ page: Int) async -> [Item] {
        // Fetch from API with offset
        try? await Task.sleep(nanoseconds: 500_000_000) // Simulate network
        return (0..<pageSize).map { Item(id: page * pageSize + $0) }
    }
}

// Usage in View
LazyVStack {
    ForEach(viewModel.items) { item in
        ItemRow(item: item)
            .onAppear {
                Task { await viewModel.loadMoreIfNeeded(currentItem: item) }
            }
    }
    
    if viewModel.isLoadingMore {
        ProgressView()
    }
}
```

### 7.3 Efficient Caching

```swift
// UserDefaults for small data
class SettingsCache {
    @AppStorage("lastSyncDate") var lastSyncDate: Date = .distantPast
    @AppStorage("cachedUserName") var userName: String = ""
}

// File-based cache for larger data
actor DataCache {
    private let cacheDirectory: URL
    
    init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppCache")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func save<T: Encodable>(_ data: T, key: String) async throws {
        let url = cacheDirectory.appendingPathComponent(key)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: url)
    }
    
    func load<T: Decodable>(key: String, as type: T.Type) async throws -> T? {
        let url = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
    
    func invalidate(key: String) async {
        let url = cacheDirectory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: url)
    }
}

// Repository with caching
class TransactionRepository {
    static let shared = TransactionRepository()
    private let cache = DataCache()
    private let cacheKey = "transactions"
    private let cacheValidDuration: TimeInterval = 300 // 5 minutes
    
    func fetchTransactions() async throws -> [Transaction] {
        // Try cache first
        if let cached: CachedData<[Transaction]> = try? await cache.load(key: cacheKey, as: CachedData.self),
           Date().timeIntervalSince(cached.timestamp) < cacheValidDuration {
            return cached.data
        }
        
        // Fetch from network
        let transactions = try await api.fetchTransactions()
        
        // Update cache
        try? await cache.save(CachedData(data: transactions, timestamp: Date()), key: cacheKey)
        
        return transactions
    }
}

struct CachedData<T: Codable>: Codable {
    let data: T
    let timestamp: Date
}
```

### 7.4 Loading States with Skeleton UI

```swift
struct TransactionListView: View {
    @StateObject private var viewModel = TransactionViewModel()
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    // Skeleton placeholders
                    ForEach(0..<10, id: \.self) { _ in
                        TransactionRowSkeleton()
                    }
                } else {
                    ForEach(viewModel.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
            .padding()
        }
    }
}

struct TransactionRowSkeleton: View {
    @State private var opacity: Double = 0.3
    
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 16)
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                opacity = 0.6
            }
        }
    }
}
```

**Performance gain:** Perceived instant loading, 2-3x better user experience metrics.

---

## 8. Quick Wins Checklist

### Immediate Actions (< 5 minutes each)

#### ✅ Replace VStack with LazyVStack
```swift
// Before
ScrollView {
    VStack {
        ForEach(items) { ... }
    }
}

// After
ScrollView {
    LazyVStack {
        ForEach(items) { ... }
    }
}
```
**Gain:** 5-50x for large lists

#### ✅ Add Fixed Heights to List Rows
```swift
ForEach(items) { item in
    ItemRow(item: item)
        .frame(height: 60) // Add this!
}
```
**Gain:** 2-3x scrolling performance

#### ✅ Update to Latest SDKs
```swift
// Package.swift
platforms: [
    .macOS(.v14) // Use latest stable
]
```
**Gain:** Free performance improvements from Apple

#### ✅ Use Release Builds for Testing
```bash
# Always test with:
swift build -c release
# Or in Xcode: Product → Scheme → Edit Scheme → Run → Release
```
**Gain:** 2-5x faster than Debug

#### ✅ Remove Debug Logging
```swift
#if DEBUG
print("Debug info: \(data)")
#endif
```
**Gain:** Eliminates I/O overhead in production

### Short-Term Actions (< 30 minutes each)

#### ✅ Implement Image Caching
Use the `ImageCache` actor from Section 4.

#### ✅ Add [weak self] to All Closures
Search your codebase:
```bash
grep -r "{ self\." --include="*.swift"
```

#### ✅ Move JSON Parsing Off Main Thread
Wrap all `JSONDecoder` calls in `Task.detached`.

#### ✅ Use Canvas for Charts
Replace SwiftUI view-based charts with `Canvas`.

#### ✅ Add Loading States
Implement skeleton views for all async content.

### Medium-Term Actions (< 2 hours each)

#### ✅ Implement Pagination
For any list > 100 items.

#### ✅ Profile with Instruments
Spend 2 hours identifying your specific bottlenecks.

#### ✅ Set Up Memory Monitoring
Ensure memory stays < 100MB during normal use.

#### ✅ Implement Proper MVVM
Separate concerns for easier optimization.

---

## Performance Targets

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Frame Rate** | 60fps (120fps on ProMotion) | FPS overlay / Instruments |
| **Initial Load** | < 1 second | Stopwatch / Console logs |
| **List Scroll** | No dropped frames | Visual inspection + Instruments |
| **Memory** | < 100MB baseline | Activity Monitor / Instruments |
| **Main Thread Block** | < 16ms | Time Profiler |
| **App Size** | < 50MB | Xcode Organizer |

---

## Summary

### Priority Order for Maximum Impact

1. **Profile First** - Don't guess, measure
2. **Fix List Performance** - Usually the biggest win
3. **Offload Heavy Work** - JSON, images, calculations
4. **Cache Aggressively** - Network, images, computed values
5. **Simplify Animations** - Reduce complexity, not remove
6. **Monitor Memory** - Prevent gradual degradation

### Expected Total Improvement

Following this roadmap completely typically yields:
- **5-20x** improvement in list scrolling
- **2-5x** improvement in initial load time
- **3-10x** reduction in memory usage
- **Consistent 60fps** during normal use

---

## Resources

- [Apple: Improving app performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [WWDC 2023: Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/)
- [WWDC 2022: Improve app size and runtime performance](https://developer.apple.com/videos/play/wwdc2022/110363/)
- [SwiftUI Performance Tips](https://www.hackingwithswift.com/quick-start/swiftui/swiftui-tips-and-tricks)

---

*Last Updated: December 2024*
*Applicable to: macOS 13+, Swift 5.9+, Xcode 15+*
