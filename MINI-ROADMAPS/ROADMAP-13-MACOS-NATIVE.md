# ROADMAP-13 — macOS Native Experience

**Theme:** macOS Platform / Native UX  
**Priority:** P1 (High)  
**Target Outcome:** True macOS-native app with proper navigation, keyboard support, and platform conventions

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Not Using NavigationSplitView** (Section 3.12)
- **[High] No Keyboard Navigation** (Section 3.12)
- **[High] Window Not Restorable on Relaunch** (Section 3.12)
- **[Medium] No Minimum Window Size** (Section 3.12)
- **[Medium] Toolbar Doesn't Use Native Patterns** (Section 3.12)
- **[Medium] Right-Click Context Menus Missing** (Section 3.12)
- **[Low] No Touch Bar Support** (Section 3.12)
- **Phase 1 P1-8** — Full keyboard navigation
- **Phase 1 P1-9** — Native macOS toolbar + sidebars
- **Edge Case #51** — Window resize to extreme sizes
- **Edge Case #52** — Multiple windows (if supported)
- **Microcopy Pack** — macOS-specific terminology

---

## 2) User Impact

**Before:**
- App feels like iOS port on macOS
- No keyboard shortcuts for navigation
- Window state lost on relaunch
- No context menus

**After:**
- True macOS-native experience
- Full keyboard navigation
- Window position/size restored
- Rich context menus throughout

---

## 3) Scope

**Included:**
- NavigationSplitView implementation
- Full keyboard navigation (Tab, arrows, shortcuts)
- Window state restoration
- Minimum window size (900×600)
- Native toolbar styling
- Context menus throughout
- Drag and drop where appropriate
- Menu bar integration

**Not Included:**
- Touch Bar (deprecated)
- Catalyst-specific features
- Widget extensions

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Sidebar design | macOS sidebar layout | Accounts, Portfolio, etc. | Always visible |
| D2: Toolbar design | Native toolbar items | Actions appropriate to view | Context-aware |
| D3: Context menu audit | List all context menu locations | Right-click actions | Comprehensive |
| D4: Keyboard map | All shortcuts documented | Reference sheet | ⌘?  to view |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: NavigationSplitView | Replace NavigationStack | 3-column layout | macOS pattern |
| E2: Sidebar view | Accounts + navigation | Always visible | First column |
| E3: Content view | Main content area | Token list, etc. | Second column |
| E4: Detail view | Transaction detail, etc. | Optional third | Third column |
| E5: Keyboard navigation | Tab order | Logical flow | `.focusable()` |
| E6: Arrow key nav | Navigate lists | Up/down/enter | Focus management |
| E7: Shortcuts (⌘R, ⌘N, etc.) | Core actions | Work everywhere | `.keyboardShortcut()` |
| E8: Window restoration | Save position/size | Restore on launch | NSWindow delegate |
| E9: Minimum window | 900×600 minimum | Enforced | `.frame(minWidth:minHeight:)` |
| E10: Maximum window | Optional max or flexible | No layout breakage | Tested |
| E11: Native toolbar | `.toolbar` modifier | macOS styling | Context-aware items |
| E12: Context menus | Token row, NFT, address | Right-click actions | `.contextMenu()` |
| E13: Drag and drop | Drag tokens to send | Natural interaction | `.draggable()` |
| E14: Menu bar | File, Edit, View, etc. | Standard menus | SwiftUI commands |
| E15: Window title | Dynamic based on content | "Portfolio - Hawala" | `.navigationTitle()` |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Sidebar | Sidebar visible | Proper layout | Visual check |
| Q2: Navigation split | 3-column on wide screen | Collapses on narrow | Responsive |
| Q3: Keyboard | Tab through UI | Logical order | Focus test |
| Q4: Shortcuts | All documented shortcuts | Work correctly | Matrix test |
| Q5: Window restore | Quit, relaunch | Same position/size | State test |
| Q6: Minimum size | Resize below 900×600 | Stopped at minimum | Constraint test |
| Q7: Context menus | Right-click items | Menus appear | All locations |
| Q8: Menu bar | Standard menus work | Correct actions | macOS convention |

---

## 5) Acceptance Criteria

- [ ] NavigationSplitView used (3-column layout)
- [ ] Sidebar always visible with accounts/navigation
- [ ] Tab key navigates through UI logically
- [ ] Arrow keys navigate lists
- [ ] Enter key selects/activates
- [ ] Escape key cancels/closes
- [ ] ⌘,  opens Settings
- [ ] ⌘R refreshes
- [ ] ⌘N starts new transaction
- [ ] ⌘W closes window (not quits)
- [ ] Window position/size restored on relaunch
- [ ] Minimum window size 900×600
- [ ] Toolbar uses native macOS styling
- [ ] Right-click context menus throughout
- [ ] Menu bar has File, Edit, View, Help

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Very narrow window | Width check | Collapse to 2-column or 1-column |
| Very wide window | Width check | Content centered with max-width |
| Saved window offscreen | Screen bounds check | Reset to center of main screen |
| Multiple displays | Display detection | Restore to correct display |
| External display disconnected | Display change | Move to available display |
| Focus lost | Focus state | Clear focus indicator |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `keyboard_navigation_used` | `action` (tab/arrow/shortcut) | Success |
| `keyboard_shortcut` | `shortcut`, `context` | Success |
| `context_menu_opened` | `location`, `item_type` | Success |
| `context_menu_action` | `action`, `item_type` | Success |
| `window_restored` | `width`, `height`, `display` | Success |
| `window_resized` | `width`, `height` | Success |
| `sidebar_collapse` | `collapsed` (bool) | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Launch app → sidebar visible
- [ ] Wide window → 3-column layout
- [ ] Narrow window → columns collapse
- [ ] Tab through portfolio → logical order
- [ ] Arrow down in token list → next token
- [ ] Enter on token → opens detail
- [ ] Escape in modal → closes modal
- [ ] ⌘,  → Settings opens
- [ ] ⌘R → data refreshes
- [ ] ⌘N → new transaction
- [ ] ⌘W → window closes (app stays open)
- [ ] Quit, relaunch → same window position
- [ ] Resize below 900×600 → stopped
- [ ] Right-click token → context menu
- [ ] Context menu "Copy Address" → works
- [ ] Menu bar File > New → works
- [ ] Menu bar Edit > Copy → works

**Automated Tests:**
- [ ] Unit test: Window state serialization
- [ ] Unit test: Keyboard shortcut registration
- [ ] UI test: NavigationSplitView layout
- [ ] UI test: Context menu appearance

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- macOS 13+ for NavigationSplitView
- SwiftUI 4+ features

**Risks:**
- NavigationSplitView behavior differences from NavigationStack
- Window state restoration edge cases

**Rollout Plan:**
1. NavigationSplitView migration (Day 1)
2. Keyboard navigation + shortcuts (Day 2)
3. Window restoration + sizing (Day 3)
4. Context menus + toolbar + QA (Day 4)

---

## 10) Definition of Done

- [ ] NavigationSplitView implemented
- [ ] Sidebar functional
- [ ] Full keyboard navigation
- [ ] All shortcuts working
- [ ] Window restoration working
- [ ] Minimum size enforced
- [ ] Native toolbar
- [ ] Context menus throughout
- [ ] Menu bar complete
- [ ] macOS conventions followed
- [ ] Analytics events firing
- [ ] PR reviewed and merged
