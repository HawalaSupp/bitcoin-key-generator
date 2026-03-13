# Hawala Website Design Spec

## 1. Purpose and Scope

This document translates Hawala's production app design language into a web system you can implement for a marketing site or product website.

Primary goals:
- Preserve Hawala's visual identity: monochrome, monumental, mechanical.
- Keep the site premium and security-forward, not generic fintech.
- Define enough concrete rules that design and frontend can implement consistently.

Canonical style references in app code:
- `swift-app/Sources/swift-app/UI/HawalaTheme.swift`
- `swift-app/Sources/swift-app/UI/HawalaMainView.swift`
- `swift-app/Sources/swift-app/UI/AnimatedBackgrounds.swift`
- `swift-app/Sources/swift-app/UI/SwapCryptoView.swift`
- `swift-app/Sources/swift-app/UI/BackupOverlay.swift`
- `swift-app/Sources/swift-app/UI/TokensOverlay.swift`
- `swift-app/Sources/swift-app/UI/GaslessTxOverlay.swift`
- `swift-app/Sources/swift-app/UI/CopywritingKit.swift`

## 2. Brand Expression

### 2.1 Brand Pillars
- Monochrome: grayscale-first surfaces, restrained color use.
- Monumental: oversized headlines and number-first visual hierarchy.
- Mechanical: intentional interactions, friction for risky actions, precise microcopy.

### 2.2 Emotional Target
- Secure
- Deliberate
- Technical but elegant
- Calm under pressure

### 2.3 Do and Don't
Do:
- Use dark layered surfaces and glass treatment.
- Use sparse typography with strong hierarchy.
- Use accent color as signal, not decoration.
- Make critical actions feel intentional.

Don't:
- Use rainbow gradients as primary styling.
- Fill every surface with color.
- Use playful/bouncy motion for core flows.
- Use verbose, marketing-heavy copy.

## 3. Visual Tokens (Web)

Use these CSS custom properties as source of truth.

```css
:root {
  /* Core backgrounds */
  --hw-bg: #0d0d0d;
  --hw-bg-2: #1a1a1a;
  --hw-bg-3: #252525;
  --hw-bg-hover: #2d2d2d;

  /* Text */
  --hw-text-1: #ffffff;
  --hw-text-2: #a0a0a0;
  --hw-text-3: #8e8e8e;

  /* Accent */
  --hw-accent: #14b8a6;
  --hw-accent-hover: #2dd4bf;
  --hw-accent-subtle: rgba(20, 184, 166, 0.15);

  /* Semantic status */
  --hw-success: #32d74b;
  --hw-warning: #ffd60a;
  --hw-error: #ff453a;
  --hw-info: #64d2ff;

  /* Borders and dividers */
  --hw-border: rgba(255, 255, 255, 0.08);
  --hw-border-hover: rgba(255, 255, 255, 0.15);
  --hw-divider: rgba(255, 255, 255, 0.06);

  /* Radii */
  --hw-r-sm: 6px;
  --hw-r-md: 10px;
  --hw-r-lg: 14px;
  --hw-r-xl: 20px;
  --hw-r-full: 9999px;

  /* Spacing */
  --hw-s-1: 4px;
  --hw-s-2: 8px;
  --hw-s-3: 12px;
  --hw-s-4: 16px;
  --hw-s-5: 24px;
  --hw-s-6: 32px;
  --hw-s-7: 48px;

  /* Shadows */
  --hw-shadow-card: 0 12px 30px rgba(0, 0, 0, 0.30);
  --hw-shadow-elevated: 0 20px 50px rgba(0, 0, 0, 0.50);

  /* Motion */
  --hw-fast: 150ms;
  --hw-normal: 250ms;
  --hw-slow: 400ms;
}
```

### 3.1 High Contrast Overrides

```css
@media (prefers-contrast: more) {
  :root {
    --hw-text-3: #b0b0b0;
    --hw-border: rgba(255, 255, 255, 0.20);
    --hw-divider: rgba(255, 255, 255, 0.15);
  }
}
```

## 4. Typography System

### 4.1 Font Roles
- Display and flagship labels: Clash Grotesk (or nearest licensed web equivalent).
- Body and utility copy: system sans (SF-like fallback stack).
- Addresses, hashes, numeric technical values: monospaced family.

### 4.2 Suggested Web Stack
```css
--hw-font-display: "Clash Grotesk", "Sora", "Space Grotesk", sans-serif;
--hw-font-body: "Inter", "SF Pro Text", "Segoe UI", sans-serif;
--hw-font-mono: "JetBrains Mono", "SF Mono", "Menlo", monospace;
```

### 4.3 Type Scale and Usage
- Hero title: 64-96px, display family, weight 600-700, tighter line-height.
- Section title: 36-52px, display family, weight 600.
- Eyebrow labels: 10-12px, uppercase, 2-4px letter-spacing.
- Body: 15-18px, regular/medium.
- Caption/metadata: 11-13px, muted text.
- Ledger values: 12-16px mono.

### 4.4 Tracking Rules
- Use wide tracking for labels and controls: 1.2-3px.
- Avoid wide tracking on long paragraph text.

## 5. Background and Atmosphere

### 5.1 Base Scene
- Primary page background should never be flat.
- Use a silk-like animated noise/fabric shader or a subtle moving gradient mesh.
- Overlay a dark veil for readability (`rgba(0,0,0,0.35-0.45)`).

### 5.2 Glass Layers
- Place content on floating translucent panels.
- Panel recipe:
  - Fill: rgba(255,255,255,0.03-0.08)
  - Border: 1px low-opacity white gradient
  - Backdrop blur: 14-24px
  - Corner radius: 14-20px

## 6. Layout Blueprint (Website)

## 6.1 Page Structure
1. Hero
2. Product pillars
3. Feature modules
4. Security and control section
5. Workflow section (how actions happen safely)
6. Ecosystem/chains section
7. Final CTA and footer

### 6.2 Hero Specification
- Left: monumental headline and short trust-forward subcopy.
- Right: product-like floating card mockups.
- Add subtle shimmer sweep every 6-10 seconds.
- Include one primary CTA and one secondary CTA.

### 6.3 Content Density
- Use large vertical rhythm and breathing room.
- Prefer concise blocks with strong headings over long paragraphs.

## 7. Component Anatomy

### 7.1 Navigation Capsule
- Shape: pill/capsule.
- Background: ultra-thin glass.
- Border: subtle top-left to bottom-right gradient stroke.
- Height: compact (36-44px visual rhythm).

### 7.2 Primary Button
- Style: restrained fill or glass with clear border.
- Label style: uppercase or title case with medium tracking.
- Hover: slight brighten and scale 1.02-1.05.
- Press: tiny compress to 0.98.

### 7.3 Card
- Dark translucent fill.
- Hairline border.
- Optional accent edge only when selected or active.

### 7.4 Data Row
- Left: icon + label.
- Right: value + status.
- Divider between rows uses `--hw-divider`.

### 7.5 Tag/Chip
- Monochrome by default.
- Accent tint only for active/selected state.

### 7.6 Search Field
- Compact, dark fill, low-contrast border.
- Icon-led input style.
- Focus should move border toward accent but keep subtle.

## 8. Signature Interaction Patterns (Web Adaptation)

### 8.1 Intentional Confirmation
Hawala's app uses hold-to-confirm for sensitive actions. On website:
- For demo interactions, use press-and-hold confirmation.
- For real web actions, use one of:
  - press-and-hold,
  - slide-to-confirm,
  - two-step explicit confirmation.

### 8.2 Mechanical Feedback
- Progress fill should move linearly and reset if released early.
- Labels can switch states: `HOLD TO CONFIRM` to `CONFIRMING...`.

### 8.3 Hover Behavior
- Calm, low-amplitude movement.
- Prioritize opacity, border, and glow shifts over large movement.

## 9. Motion Spec

### 9.1 Duration and Easing
- Fast: 120-180ms for hover/focus.
- Normal: 220-280ms for state swaps.
- Slow: 320-420ms for section transitions.
- Spring-like easing for key element entrances.

### 9.2 Staggering
- For card lists and feature blocks: 40-90ms stagger between items.

### 9.3 Background Motion
- Keep movement slow and atmospheric.
- Never distract from text readability.

### 9.4 Reduced Motion
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

## 10. Copy and Voice Guide

### 10.1 Tone
- Confident, concise, technical clarity.
- Reassuring without hype.
- Verbs are direct and operational.

### 10.2 Preferred Style
- Short command labels.
- Explicit outcomes.
- Human-readable error and state copy.

### 10.3 Example Voice
Good:
- "Control your keys."
- "Confirm with intent."
- "Review before execution."

Avoid:
- "Revolutionary future of finance"
- "Unstoppable moon-ready platform"

## 11. Accessibility Requirements

- Meet WCAG AA contrast minimums.
- Keep text readable over dynamic backgrounds via dark overlays.
- Provide visible focus rings for keyboard users.
- Do not encode important meaning by color alone.
- Ensure icon-only controls include labels/tooltips.

## 12. Responsive Behavior

### 12.1 Breakpoints
- Desktop: 1280+
- Laptop/tablet landscape: 1024-1279
- Tablet/large mobile: 768-1023
- Mobile: <768

### 12.2 Mobile Adaptation Rules
- Keep monumental style but reduce headline sizes proportionally.
- Collapse nav capsule into compact top bar + menu.
- Stack hero visual cards beneath copy.
- Preserve spacing rhythm and avoid cramped dense lists.

## 13. Implementation Starter (CSS Skeleton)

```css
body {
  margin: 0;
  color: var(--hw-text-1);
  background: var(--hw-bg);
  font-family: var(--hw-font-body);
}

.hw-page-bg {
  position: fixed;
  inset: 0;
  z-index: -1;
  background:
    radial-gradient(1200px 800px at 10% -10%, rgba(255,255,255,0.06), transparent 60%),
    radial-gradient(900px 700px at 90% 110%, rgba(20,184,166,0.08), transparent 60%),
    linear-gradient(135deg, #0d0d0d, #1a1a1a 45%, #0d0d0d);
}

.hw-glass {
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid var(--hw-border);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
  border-radius: var(--hw-r-lg);
  box-shadow: var(--hw-shadow-card);
}

.hw-eyebrow {
  font-size: 11px;
  letter-spacing: 2px;
  text-transform: uppercase;
  color: var(--hw-text-2);
}

.hw-display {
  font-family: var(--hw-font-display);
  font-weight: 700;
  line-height: 0.95;
}
```

## 14. QA Checklist for Design Fidelity

- Hero feels dark-premium and deliberate.
- Accent color appears as controlled signal, not wash.
- Typography hierarchy is obvious in 3 seconds.
- Surfaces feel layered and tactile (glass + border + depth).
- Motion is smooth and restrained.
- At least one interaction demonstrates intentional confirmation.
- Mobile keeps identity without becoming generic template UI.

## 15. Recommended Asset Pack to Prepare Before Build

- Webfont files and license for Clash Grotesk (or approved substitute).
- Silk/atmospheric background implementation (shader or CSS fallback).
- Icon policy (SF-like equivalents for web icon set).
- Figma token file matching this document.
- Motion snippets for:
  - nav hover
  - card entrance stagger
  - shimmer sweep
  - confirm-progress interaction

---

If this spec conflicts with implementation constraints, preserve these in order:
1. Brand pillars (monochrome, monumental, mechanical)
2. Readability/accessibility
3. Interaction intentionality
4. Atmospheric styling details
