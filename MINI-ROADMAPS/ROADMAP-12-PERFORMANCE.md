# ROADMAP-12 — Performance & Optimization

**Theme:** Performance / Optimization  
**Priority:** P1 (High)  
**Target Outcome:** 60fps UI, <2s cold start, efficient memory usage, and smooth scrolling

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Cold Start > 3 Seconds** (Section 3.11)
- **[High] Scrolling Jank in Token List** (Section 3.11)
- **[Medium] Image Assets Not Optimized** (Section 3.11)
- **[Medium] Network Requests Not Batched** (Section 3.11)
- **[Medium] No Memory Pressure Handling** (Section 3.11)
- **[Low] No Skeleton Loading States** (Section 3.11)
- **Top 10 Failures #4** — SwiftUI Performance Nightmare
- **Phase 1 P1-10** — Optimize token list scrolling
- **Phase 1 P1-11** — Reduce cold start time to < 2s
- **Edge Case #54** — Token list with 500+ assets
- **Edge Case #55** — Memory pressure causes eviction
- **Microcopy Pack** — Loading States

---

## 2) User Impact

**Before:**
- App takes > 3s to launch
- Token list stutters on scroll
- High memory usage
- No skeleton loading (blank screens)

**After:**
- App launches in < 2s
- 60fps smooth scrolling
- Memory-efficient image handling
- Professional skeleton loading states

---

## 3) Scope

**Included:**
- Cold start optimization
- Token list virtualization
- Image asset optimization
- Network request batching
- Memory pressure handling
- Skeleton loading states
- Profiling and metrics

**Not Included:**
- Background sync optimization
- Push notification performance
- Database migration optimization

---

## 4) Step-by-Step Tasks

### Analysis Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: Startup profile | Instrument cold start | Identify bottlenecks | Time Tool |
| A2: Scroll profile | Profile token list | Find jank sources | Core Animation |
| A3: Memory audit | Check allocations | Find leaks/bloat | Allocations |
| A4: Network audit | Review API calls | Find redundant calls | Network profiler |

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Skeleton screens | Portfolio, token list | Shimmer animation | Match layout |
| D2: Loading states | All data-dependent views | Consistent style | Design system |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Lazy initialization | Defer non-critical init | Faster launch | `lazy var` |
| E2: Startup task queue | Prioritize critical data | Background less important | MainActor priority |
| E3: Preload critical data | Cache last portfolio | Show immediately | UserDefaults cache |
| E4: Token list virtualization | Only render visible | 60fps scroll | LazyVStack |
| E5: Token row simplification | Reduce view complexity | Fewer subviews | Profile-guided |
| E6: Image downsampling | Resize before display | Lower memory | UIImage extensions |
| E7: Image caching | NSCache for images | Avoid re-download | ImageCache singleton |
| E8: Request batching | Combine API calls | Fewer round-trips | GraphQL or batch endpoint |
| E9: Memory warnings | Handle `didReceiveMemoryWarning` | Clear caches | NotificationCenter |
| E10: Skeleton views | Shimmer overlay | While loading | SkeletonModifier |
| E11: Prefetch images | Load images ahead | Smooth scroll | CollectionView prefetch |
| E12: Background thread work | Move parsing off main | Unblock UI | DispatchQueue.global |
| E13: Reduce @StateObject | Minimize state rebuilds | Less recomposition | ObservableObject audit |
| E14: Optimize animations | Remove expensive animations | Smooth 60fps | Animation audit |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Cold start | Time app launch | < 2s to usable | Stopwatch test |
| Q2: Scroll performance | 500 token scroll | No jank | Visual + profiler |
| Q3: Memory stability | Use app 30 min | No growth | Allocations |
| Q4: Memory pressure | Simulate pressure | Caches cleared | Low memory warning |
| Q5: Skeleton display | Block network | Skeletons shown | Loading state |

---

## 5) Acceptance Criteria

- [ ] Cold start to usable state < 2 seconds
- [ ] Token list scrolls at 60fps with 100+ tokens
- [ ] Token list scrolls at 60fps with 500+ tokens
- [ ] Images use appropriate resolution (no 4K icons)
- [ ] Image cache respects memory limits
- [ ] Network requests batched where possible
- [ ] Memory pressure handled (caches cleared)
- [ ] Skeleton loading states for all data-dependent views
- [ ] No memory leaks detected in extended use
- [ ] Main thread never blocked > 16ms

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| 500+ tokens | Count check | Virtualized list handles it |
| Memory warning | System notification | Clear image cache, continue |
| Slow network | Timeout | Show cached + skeleton |
| Image load fails | Error handler | Placeholder image |
| Scroll during load | Prefetch | Smooth experience |
| Cold start with large portfolio | Data size | Show cached immediately |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `app_cold_start` | `duration_ms`, `token_count` | Success |
| `app_warm_start` | `duration_ms` | Success |
| `token_list_scroll_fps` | `avg_fps`, `dropped_frames` | Success/Failure |
| `image_cache_hit` | `hit_rate_percent` | Success |
| `memory_warning_received` | `before_mb`, `after_mb` | Warning |
| `network_batch_request` | `request_count`, `duration_ms` | Success |
| `skeleton_displayed` | `view_name`, `duration_ms` | Loading |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Fresh install → cold start < 2s
- [ ] Subsequent launch → faster
- [ ] Scroll 100 tokens → smooth
- [ ] Scroll 500 tokens → still smooth
- [ ] Block network → skeletons appear
- [ ] Unblock network → content loads
- [ ] Use app 30 min → memory stable
- [ ] Simulate memory pressure → app continues
- [ ] Low-end device → acceptable performance

**Automated Tests:**
- [ ] Performance test: Cold start time
- [ ] Performance test: Scroll frame rate
- [ ] Unit test: Image downsampling
- [ ] Unit test: Cache eviction
- [ ] Integration test: Memory under pressure

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Instruments profiling
- Performance baselines

**Risks:**
- Optimization may require architecture changes
- Diminishing returns after initial gains

**Rollout Plan:**
1. Profile + identify bottlenecks (Day 1)
2. Startup optimization (Day 2)
3. Scroll + image optimization (Day 3)
4. Skeleton + memory + QA (Day 4)

---

## 10) Definition of Done

- [ ] Cold start < 2 seconds
- [ ] 60fps scroll with 100+ tokens
- [ ] 60fps scroll with 500+ tokens
- [ ] Image caching implemented
- [ ] Network batching where possible
- [ ] Memory pressure handled
- [ ] Skeleton loading states
- [ ] No memory leaks
- [ ] Performance metrics captured
- [ ] PR reviewed and merged
