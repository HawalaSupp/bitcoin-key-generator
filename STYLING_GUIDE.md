# Hawala Overlay Styling Guide

> Canonical reference for the monochrome dark-glass design language used in Address Book Overlay and all future overlay windows. Every value below is extracted directly from working, compiled code in `AddressBookOverlay.swift` (3364 lines, 12 tabs).

---

## 1. Architecture Pattern

### Overlay Structure

Every overlay follows the same ZStack pattern:

```
ZStack {
    backdrop          // full-screen dimmed tap-to-dismiss
    cardContainer     // centered floating card
}
```

- **Backdrop**: `Color.black.opacity(0.75)` covering the entire screen with `.ignoresSafeArea()`. Tap gesture calls `dismissOverlay()`.
- **Card**: Fixed-size `VStack(spacing: 0)` containing `headerBar`, `tabBar`, `tabContent`.
- **Escape Key**: Always wire `EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)` via `.background()`.

### Binding Pattern

```swift
@Binding var isPresented: Bool
var onBackToSettings: (() -> Void)? = nil
var initialTab: ABTab? = nil
```

- Use `@Binding` for presentation state, not `@Environment(\.dismiss)`.
- Optional `onBackToSettings` callback for back-navigation to parent.
- Optional `initialTab` to deep-link into a specific tab on appear.

---

## 2. Card Container

### Dimensions

| Overlay | Width | Height |
|---------|-------|--------|
| Address Book | 700 | 650 |
| Network | 700 | 600 |
| Backup | 700 | 600 |

**Default for new overlays: `700 × 650`** (use 600 height if content is lighter).

### Background

```swift
private var cardBg: some View {
    ZStack {
        Color(red: 0.06, green: 0.06, blue: 0.07)    // near-black base
        // Silk shimmer — animated diagonal light streak
        LinearGradient(
            colors: [.clear, Color.white.opacity(0.015), .clear],
            startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
            endPoint:   UnitPoint(x: silkPhase + 0.3, y: 1)
        )
    }
}
```

- Base color: `rgb(15, 15, 18)` — `Color(red: 0.06, green: 0.06, blue: 0.07)`
- Silk shimmer: `0.015` white opacity, animated linearly over 4s repeating forever.

### Border Stroke

```swift
private var cardStroke: some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ), lineWidth: 1
        )
}
```

- Corner radius: **20** (`.continuous` style)
- Stroke: 1px gradient from `0.10` → `0.03` white, top-left to bottom-right.

### Shadow

```swift
.shadow(color: Color.black.opacity(0.5), radius: 50, y: 25)
```

### Clipping

```swift
.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
```

---

## 3. Animations

### Entry Animation

```swift
@State private var contentOpacity: Double = 0
@State private var cardScale: CGFloat = 0.92
@State private var silkPhase: CGFloat = 0

.onAppear {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
        cardScale = 1
        contentOpacity = 1
    }
    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
        silkPhase = 1
    }
}
```

- Card scales from `0.92` → `1.0` with spring.
- Content fades from `0` → `1` simultaneously.
- Silk shimmer loops continuously.

### Exit Animation

```swift
private func dismissOverlay() {
    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
        cardScale = 0.95
        contentOpacity = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        isPresented = false
    }
}
```

- Card shrinks to `0.95`, fades to `0`.
- Actual dismissal fires 200ms later.

### Standard Spring (used everywhere for state changes)

```swift
.spring(response: 0.3, dampingFraction: 0.85)
```

This is the canonical spring for:
- Tab switching
- Expanding/collapsing rows
- Filter changes
- Any state-driven view transitions

### Transitions

```swift
.transition(.opacity.combined(with: .move(edge: .top)))
```

Used on all expandable detail sections (contact details, address details, stealth key details, derivation rows).

---

## 4. Color Palette

### Base Colors (No HawalaTheme references inside overlay)

All colors are expressed as raw SwiftUI `Color.white.opacity(...)` values. **Never use HawalaTheme inside overlays** — keep the palette self-contained.

| Purpose | Color | Usage |
|---------|-------|-------|
| Card base | `Color(red: 0.06, green: 0.06, blue: 0.07)` | Card background |
| Primary text | `.white.opacity(0.85)` to `.white.opacity(0.9)` | Names, titles, selected tabs |
| Secondary text | `.white.opacity(0.5)` to `.white.opacity(0.7)` | Form labels, body text |
| Tertiary text | `.white.opacity(0.25)` to `.white.opacity(0.35)` | Addresses, timestamps, captions |
| Quaternary text | `.white.opacity(0.15)` to `.white.opacity(0.2)` | Hints, disabled text, chevrons |
| Ghost text | `.white.opacity(0.08)` | Empty state icons, inactive elements |

### Opacity Scale (The System)

This is the core of the design — everything is white at different opacities:

```
0.90 — Selected tab text, active chain pill text
0.85 — Contact names, primary labels
0.80 — Form submit button text, header title
0.70 — Sub-headers, setting titles
0.60 — Expanded detail text, monospaced addresses
0.50 — Form section headers, "Edit Contact" titles
0.40 — Secondary info text, action button labels, chain badges
0.35 — Truncated addresses, monospaced secondary
0.30 — Form field labels, feature list text, star outlines
0.25 — Timestamps, captions, filter pill inactive text
0.20 — Icon buttons (pencil, trash), timestamps, chevrons
0.15 — Inactive elements, checkmarks, derivation indices
0.10 — Card stroke start, selected chain bg, pill active bg
0.08 — Close button bg, tab selected bg, form button bg
0.06 — Stroke borders on cards, form card outlines, tab divider
0.05 — Row stroke borders (all content rows)
0.04 — Row bg default, search field bg, form input bg, badges
0.03 — Form card bg, expanded section inner bg, chain pill inactive
0.025 — Content row rest state background
0.02 — Statistics bar bg, info panels, education sections
0.015 — Silk shimmer peak
```

### Semantic Accent Colors

| Color | Usage |
|-------|-------|
| `.green.opacity(0.5-0.8)` | Valid, success, unspent, active whitelist, receive addresses |
| `.orange.opacity(0.5-0.7)` | Warning, multi-use addresses, pending, sent payments |
| `.red.opacity(0.7-0.8)` | Invalid, errors, scam flags, sanctions, multi-use stat |
| `.cyan.opacity(0.6-0.7)` | Active/default indicators (stealth DEFAULT badge, ACTIVE derivation path) |
| `.yellow` | Favorite star fill |
| `.blue` | Low risk level |

**Rule**: Semantic colors are always applied at reduced opacity (0.5-0.8 for text, 0.04-0.15 for backgrounds). Never use full-brightness colors.

---

## 5. Typography

### Font Hierarchy

| Level | Font | Usage |
|-------|------|-------|
| Window title | `.system(size: 15, weight: .semibold, design: .rounded)` | "Address Book" header |
| Tab labels | `.system(size: 10, weight: .semibold, design: .monospaced)` + `tracking(1)` | Tab bar items |
| Section headers | `.system(size: 12-13, weight: .semibold)` | Contact names, row titles |
| Body text | `.system(size: 11-12)` | Descriptions, feature lists |
| Addresses | `.system(size: 10-12, design: .monospaced)` | All crypto addresses, derivation paths |
| Captions | `.system(size: 9-10)` | Timestamps, filter pills, stats labels |
| Micro badges | `.system(size: 7-9, weight: .bold, design: .monospaced)` | CHANGE, DEFAULT, ACTIVE, FIRST badges |
| Stat values | `.system(size: 14, weight: .semibold)` | Statistics bar numbers |

### Key Rules

1. **Monospaced** (`.monospaced`) for: addresses, derivation paths, hex data, stats numbers, badge labels.
2. **Rounded** (`.rounded`) only for the window title.
3. **Tracking**: Only on tab labels — `tracking(1)`.
4. **No system text styles** (`.body`, `.caption`, etc.) — always explicit `.system(size:weight:design:)`.

---

## 6. Component Library

### 6.1 Content Row

The universal pattern for list items:

```swift
VStack(spacing: 0) {
    HStack(spacing: 8-10) {
        // Left indicator (circle, icon, or monogram)
        // Content VStack (title + subtitle)
        Spacer()
        // Right accessories (badges, buttons, chevron)
    }
    .contentShape(Rectangle())
    .onTapGesture { /* toggle expand */ }
    
    if expanded {
        // Detail content
        .padding(.top, 10)
        .padding(.leading, 15-42)   // indent to align past indicator
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
.padding(10-12)
.background(Color.white.opacity(expanded ? 0.04 : 0.025))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
)
```

**Specs:**
- Padding: `10` for compact rows, `12` for standard rows
- Background: `0.025` rest, `0.04` expanded
- Corner radius: `10` with `.continuous`
- Border: `0.05` white, 1px
- Content spacing: `8` compact, `10` standard

### 6.2 Form Card

Used for add/edit forms that appear inline:

```swift
VStack(spacing: 10) {
    HStack {
        Text("Form Title")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
        Spacer()
        // Close button (xmark)
    }
    // Form fields...
    HStack {
        Spacer()
        // Submit button
    }
}
.padding(14)
.background(Color.white.opacity(0.03))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
)
```

**Specs:**
- Title: size 12, semibold, `0.5` opacity
- Padding: `14`
- Background: `0.03` white (slightly brighter than row bg)
- Border: `0.06` (slightly brighter than row border)

### 6.3 Form Field

```swift
HStack(spacing: 8) {
    Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.3))
        .frame(width: 60, alignment: .leading)
    TextField(placeholder, text: $binding)
        .textFieldStyle(.plain)
        .font(.system(size: 12, design: monospaced ? .monospaced : .default))
        .foregroundColor(.white.opacity(0.7))
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
}
```

**Specs:**
- Label width: 60pt fixed
- Label color: `0.3` white
- Input text color: `0.7` white
- Input padding: `8`
- Input bg: `0.04` white
- Input corner radius: `6`
- Input border: `0.06` white, 1px

### 6.4 Search Field

```swift
HStack(spacing: 6) {
    Image(systemName: "magnifyingglass")
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.2))
    TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.8))
}
.padding(8)
.background(Color.white.opacity(0.04))
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
)
```

### 6.5 Chain/Filter Selector Pills

Horizontal scrolling pill bar:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 6) {
        ForEach(items) { item in
            Button {
                selected = item
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 10))
                    Text(item.name)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(selected == item ? .white.opacity(0.9) : .white.opacity(0.3))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected == item ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
```

**Specs:**
- Pill spacing: `6`
- Icon size: `10`
- Text: size 10, semibold
- Selected: `0.9` text, `0.1` bg
- Deselected: `0.3` text, `0.03` bg
- Corner radius: `6`
- Padding: `10` horizontal, `5` vertical

### 6.6 Filter Pills (smaller, non-scrolling)

```swift
HStack(spacing: 4) {
    ForEach(filters) { filter in
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(selected ? .white.opacity(0.8) : .white.opacity(0.25))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.white.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    Spacer()
}
```

**Specs:**
- Size 9 text (smaller than chain pills)
- `0.08` bg when selected, `Color.clear` when not
- Corner radius: `5`

### 6.7 Statistics Bar

```swift
HStack(spacing: 16) {
    addrStatBadge("Total", "\(stats.totalAddresses)", .white.opacity(0.4))
    addrStatBadge("Used", "\(stats.usedAddresses)", .orange)
    // ...
    Spacer()
}
.padding(10)
.background(Color.white.opacity(0.02))
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
```

Each badge:

```swift
VStack(spacing: 2) {
    Text(value)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(color)
    Text(title)
        .font(.system(size: 9))
        .foregroundColor(.white.opacity(0.25))
}
```

### 6.8 Action Button (icon-only)

```swift
Button(action: action) {
    Image(systemName: icon)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white.opacity(0.4))
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}
.buttonStyle(.plain)
.help(tooltip)
```

### 6.9 Small Text Button

```swift
Button(action: action) {
    Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
}
.buttonStyle(.plain)
```

### 6.10 Primary Submit Button

```swift
Button { action() } label: {
    Text("Submit")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
}
.buttonStyle(.plain)
.disabled(condition)
.opacity(condition ? 0.3 : 1)
```

### 6.11 Full-Width Action Button

```swift
Button { action() } label: {
    HStack(spacing: 6) {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 12))
        Text("Generate Receive Address")
            .font(.system(size: 12, weight: .semibold))
    }
    .foregroundColor(.white.opacity(0.8))
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color.white.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
    )
}
.buttonStyle(.plain)
```

### 6.12 Copy Button

```swift
Button {
    copyToClipboard(address)
} label: {
    Image(systemName: copiedAddress == address ? "checkmark" : "doc.on.doc")
        .font(.system(size: 10))
        .foregroundColor(copiedAddress == address ? .green.opacity(0.6) : .white.opacity(0.2))
}
.buttonStyle(.plain)
```

**Behavior**: Copied state auto-clears after 2 seconds via `Task.sleep`.

### 6.13 Close Button

```swift
Button { dismissOverlay() } label: {
    Circle()
        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.06))
        .frame(width: 28, height: 28)
        .overlay(
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
        )
}
.buttonStyle(.plain)
.onHover { closeHovered = $0 }
```

### 6.14 Monogram Circle

```swift
Circle()
    .fill(Color.white.opacity(0.06))
    .frame(width: 32, height: 32)
    .overlay(
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.5))
    )
```

### 6.15 Micro Badges

```swift
// CHANGE badge
Text("CHANGE")
    .font(.system(size: 8, weight: .bold, design: .monospaced))
    .foregroundColor(.white.opacity(0.25))
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.white.opacity(0.04))
    .cornerRadius(3)

// DEFAULT badge (accent color)
Text("DEFAULT")
    .font(.system(size: 8, weight: .bold, design: .monospaced))
    .foregroundColor(.cyan.opacity(0.7))
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.cyan.opacity(0.1))
    .cornerRadius(3)

// FIRST badge (warning color)
Text("FIRST")
    .font(.system(size: 8, weight: .bold, design: .monospaced))
    .foregroundColor(.orange)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.orange.opacity(0.12))
    .cornerRadius(3)

// ACTIVE badge
Text("ACTIVE")
    .font(.system(size: 7, weight: .bold, design: .monospaced))
    .foregroundColor(.cyan.opacity(0.6))
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.cyan.opacity(0.1))
    .cornerRadius(3)
```

### 6.16 Status Dot

```swift
Circle()
    .fill(statusColor)       // .green, .orange, .white.opacity(0.15)
    .frame(width: 7-8, height: 7-8)
```

### 6.17 Risk Badge

```swift
HStack(spacing: 3) {
    Circle()
        .fill(riskColor)
        .frame(width: 5, height: 5)
    Text(level.rawValue)
        .font(.system(size: 8, weight: .semibold))
        .foregroundColor(riskColor.opacity(0.8))
}
.padding(.horizontal, 5)
.padding(.vertical, 2)
.background(riskColor.opacity(0.1))
.cornerRadius(4)
```

### 6.18 Chain Badge

```swift
Text(chainName)
    .font(.system(size: 9, weight: .medium))
    .foregroundColor(.white.opacity(0.3))
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(Color.white.opacity(0.04))
    .cornerRadius(3)
```

### 6.19 Tag Pill

```swift
HStack(spacing: 3) {
    Circle()
        .fill(tag.color)
        .frame(width: 5, height: 5)
    Text(tag.name)
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.white.opacity(selected ? 0.8 : 0.35))
}
.padding(.horizontal, 6)
.padding(.vertical, 3)
.background(tag.color.opacity(selected ? 0.15 : 0.06))
.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 4, style: .continuous)
        .strokeBorder(tag.color.opacity(selected ? 0.3 : 0), lineWidth: 1)
)
```

### 6.20 Empty State

```swift
VStack(spacing: 8) {
    Image(systemName: icon)
        .font(.system(size: 28))
        .foregroundColor(.white.opacity(0.08))
    Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.white.opacity(0.25))
    Text(subtitle)
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.15))
        .multilineTextAlignment(.center)
}
.frame(maxWidth: .infinity)
.padding(30)
```

### 6.21 Toggle Settings Row

```swift
VStack(alignment: .leading, spacing: 10) {
    Toggle(isOn: $binding) {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }
    .toggleStyle(.switch)
    .tint(.white.opacity(0.3))
}
.padding(14)
.background(Color.white.opacity(0.03))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
)
```

### 6.22 Education/Info Panel

```swift
VStack(alignment: .leading, spacing: 10) {
    HStack(spacing: 6) {
        Image(systemName: "info.circle")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.2))
        Text("Section Title")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.3))
    }
    Text("Educational body text...")
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.2))
        .lineSpacing(3)
}
.padding(14)
.background(Color.white.opacity(0.02))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
```

### 6.23 Success Result Card

```swift
VStack(alignment: .leading, spacing: 10) {
    HStack {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green.opacity(0.6))
        Text("Success Title")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.green.opacity(0.7))
        Spacer()
    }
    // Result content...
}
.padding(14)
.background(Color.green.opacity(0.04))
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.green.opacity(0.12), lineWidth: 1)
)
```

### 6.24 Warning Banner

```swift
HStack(spacing: 6) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundColor(.orange)
    Text("Warning text...")
        .font(.system(size: 10))
        .foregroundColor(.orange.opacity(0.7))
}
.padding(8)
.background(Color.orange.opacity(0.06))
.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
```

---

## 7. Header Bar

```swift
HStack {
    // Optional back button
    if onBackToSettings != nil {
        Button {
            dismissOverlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onBackToSettings?()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color.white.opacity(backHovered ? 0.7 : 0.3))
        }
        .buttonStyle(.plain)
        .onHover { backHovered = $0 }
    }

    Spacer()

    Text("Window Title")
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundColor(.white.opacity(0.9))

    Spacer()

    // Close button (see 6.13)
}
.padding(.horizontal, 20)
.padding(.top, 18)
.padding(.bottom, 8)
```

---

## 8. Tab Bar

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 0) {
        ForEach(tabs) { tab in
            tabButton(tab)
        }
    }
}
.padding(.horizontal, 16)
.padding(.bottom, 4)
```

Individual tab button:

```swift
Text(tab.rawValue)
    .font(.system(size: 10, weight: .semibold, design: .monospaced))
    .tracking(1)
    .foregroundColor(selected ? .white : .white.opacity(0.25))
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(selected ? Color.white.opacity(0.08) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
```

**Tab enum naming**: ALL CAPS raw values: `"CONTACTS"`, `"STEALTH"`, `"DERIVATION"`, etc.

### Tab Group Divider

When tabs are logically grouped, use a visual separator:

```swift
if tab == .firstOfNewGroup {
    Rectangle()
        .fill(Color.white.opacity(0.06))
        .frame(width: 1, height: 16)
        .padding(.horizontal, 6)
}
```

---

## 9. Tab Content Area

```swift
ScrollView(showsIndicators: false) {
    VStack(spacing: 16) {
        switch selectedTab {
        case .tab1: tab1Content
        case .tab2: tab2Content
        // ...
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 20)
}
```

**Specs:**
- No scroll indicators
- Content spacing: `16` between top-level sections
- Horizontal padding: `20`
- Top padding: `8`
- Bottom padding: `20`

---

## 10. Corner Radius Reference

| Element | Radius | Style |
|---------|--------|-------|
| Card container | 20 | `.continuous` |
| Content rows | 10 | `.continuous` |
| Form cards | 10 | `.continuous` |
| Search fields | 8 | `.continuous` |
| Action buttons | 8 | `.continuous` |
| Form inputs | 6 | `.continuous` |
| Tab buttons | 6 | `.continuous` |
| Selector pills | 6 | `.continuous` |
| Small text buttons | 5 | `.continuous` |
| Filter pills | 5 | `.continuous` |
| Micro badges | 3 | standard |
| Tag pills | 4 | `.continuous` |
| Inner detail panels | 6 | `.continuous` |
| Risk badges | 4 | standard |
| Chain badges | 3 | standard |

**Rule**: Always use `.continuous` for anything ≥ radius 4. Use standard for ≤ 3.

---

## 11. Spacing Reference

| Context | Value |
|---------|-------|
| Card horizontal padding | 20 |
| Section vertical spacing | 16 |
| Row internal spacing | 8-10 |
| Form field spacing | 10 |
| Pill bar spacing | 6 |
| Filter pill spacing | 4 |
| Statistics badge spacing | 16 |
| Badge inner spacing | 3-4 |
| Icon-text inline spacing | 6-8 |
| Expanded detail top padding | 10 |
| Expanded detail left indent | 15-19 (align past indicator) |
| Form card padding | 14 |
| Empty state padding | 30 |

---

## 12. Swift Type-Checker Safety

For tabs with complex view bodies, **extract sub-views as `@ViewBuilder` computed properties**:

```swift
// BAD — will cause type-checker timeout
private var complexTab: some View {
    VStack { /* 200+ lines */ }
}

// GOOD — split into extracted sub-views
private var complexTab: some View {
    VStack(spacing: 12) {
        complexChainBar
        complexStatsBar
        complexContentList
        complexFooter
    }
}

@ViewBuilder
private var complexChainBar: some View { /* 20-30 lines */ }

@ViewBuilder
private var complexStatsBar: some View { /* 20-30 lines */ }
```

**Target**: Keep each `@ViewBuilder` property under 50 lines. The stealth tab needed 8 sub-views; derivation tab needed 5. Plan accordingly.

---

## 13. Interaction Patterns

### Expand/Collapse Rows

```swift
@State private var expandedId: UUID? = nil

.contentShape(Rectangle())
.onTapGesture {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
        expandedId = expandedId == item.id ? nil : item.id
    }
}
```

- Only one row expanded at a time per tab.
- Chevron rotates: `chevron.down` → `chevron.up`.
- Background brightens: `0.025` → `0.04`.

### Clipboard Copy

```swift
@State private var copiedAddress: String? = nil
@State private var copyTask: Task<Void, Never>? = nil

private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copiedAddress = text
    copyTask?.cancel()
    copyTask = Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !Task.isCancelled {
            await MainActor.run { copiedAddress = nil }
        }
    }
}
```

- Green checkmark replaces copy icon for 2 seconds.
- Previous timer is cancelled if a new copy occurs.

### Inline Editing

Fields inside expanded rows use `onChange(of:)` to save immediately:

```swift
TextField("Add label...", text: $editLabel)
    .onChange(of: editLabel) { val in
        manager.setLabel(val, for: item.address)
    }
```

### Hover States

Used sparingly — only on close button and back button:

```swift
@State private var closeHovered = false
.onHover { closeHovered = $0 }
.fill(Color.white.opacity(closeHovered ? 0.12 : 0.06))
```

---

## 14. Checklist for New Overlays

When building a new overlay window, verify:

- [ ] ZStack with `backdrop` + `cardContainer`
- [ ] `EscapeKeyHandler` wired
- [ ] `@Binding var isPresented: Bool`
- [ ] Card dimensions set (700 × 650 default)
- [ ] Card background uses `Color(red: 0.06, green: 0.06, blue: 0.07)` + silk shimmer
- [ ] Card stroke: gradient 0.10 → 0.03, 1px, corner radius 20
- [ ] Entry animation: scale 0.92→1, opacity 0→1, spring(0.35, 0.85)
- [ ] Exit animation: scale→0.95, opacity→0, 200ms delay before dismiss
- [ ] Silk shimmer: linear 4s repeat forever
- [ ] Header: back button (optional), centered title, close button 28×28
- [ ] Tab bar: horizontal scroll, monospaced 10pt, tracking(1), ALL CAPS
- [ ] Content: ScrollView(showsIndicators: false), 20px horizontal padding
- [ ] All rows follow content row pattern (0.025/0.04 bg, radius 10, 0.05 stroke)
- [ ] Forms follow form card pattern (0.03 bg, radius 10, 0.06 stroke)
- [ ] All buttons use `.buttonStyle(.plain)`
- [ ] No HawalaTheme references inside the overlay
- [ ] Complex tabs split into @ViewBuilder sub-views (< 50 lines each)
- [ ] Spring animation `(0.3, 0.85)` for all state changes
- [ ] Expand transitions: `.opacity.combined(with: .move(edge: .top))`
- [ ] Disabled states use `.opacity(condition ? 0.3 : 1)`

---

*Last updated: April 9, 2026. Source: AddressBookOverlay.swift (3364 lines, 12 tabs).*
