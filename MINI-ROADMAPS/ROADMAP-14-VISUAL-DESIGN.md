# ROADMAP-14 — Visual Design & Theming

**Theme:** Visual Design / UI Polish  
**Priority:** P2 (Medium)  
**Target Outcome:** Polished, consistent visual design with proper theming, spacing, and accessibility

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Dark Mode Contrast Issues** (Section 3.13)
- **[Medium] Icon Style Inconsistency** (Section 3.13)
- **[Medium] Font Sizes Not Following Dynamic Type** (Section 3.13)
- **[Medium] Color Palette Not Systematic** (Section 3.13)
- **[Low] No Animation Guidelines** (Section 3.13)
- **[Low] Border Radius Inconsistent** (Section 3.13)
- **Phase 2 P2-3** — Complete dark mode audit
- **Blueprint** — Design System implicitly referenced
- **Edge Case #53** — User enables high contrast mode
- **Edge Case #58** — VoiceOver navigation
- **Microcopy Pack** — Visual terminology consistency

---

## 2) User Impact

**Before:**
- Dark mode has poor contrast
- Icons from different sets
- Font sizes don't respect system settings
- Inconsistent visual language

**After:**
- WCAG AA contrast throughout
- Consistent SF Symbols iconography
- Dynamic Type support
- Cohesive design system

---

## 3) Scope

**Included:**
- Dark mode contrast audit + fixes
- Icon standardization (SF Symbols)
- Dynamic Type support
- Color palette systematization
- Spacing system (4pt grid)
- Border radius standardization
- Animation guidelines
- High contrast mode support

**Not Included:**
- Complete UI redesign
- Custom illustrations
- Motion design overhaul

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Contrast audit | Check all text/bg combos | Document failures | WCAG AA (4.5:1) |
| D2: Color palette | Define semantic colors | Primary, secondary, etc. | Named colors |
| D3: Icon audit | List all icons | Identify non-SF Symbols | Replace list |
| D4: Spacing system | 4pt grid system | Document margins/padding | Consistent spacing |
| D5: Border radius | Define standard radii | 4/8/12/16pt options | Named values |
| D6: Animation specs | Timing, easing | Document standards | SwiftUI defaults |
| D7: Typography scale | Define sizes | 12/14/16/18/22/28 | Semantic names |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Color asset catalog | Define all colors | Light/dark variants | Assets.xcassets |
| E2: Semantic colors | Named color tokens | `Color.hawalaBackground` | Extension on Color |
| E3: Dark mode fixes | Fix contrast issues | All pass WCAG AA | Per-component |
| E4: SF Symbol migration | Replace custom icons | Use SF Symbols | System icons |
| E5: Dynamic Type | `.font(.body)` etc. | Respects system setting | @ScaledMetric |
| E6: Spacing tokens | Define spacing scale | 4/8/12/16/24/32 | Constants |
| E7: Apply spacing | Use tokens everywhere | Consistent look | Refactor |
| E8: Border radius tokens | 4/8/12/16pt | Named constants | CornerRadius enum |
| E9: Apply corner radius | Use tokens everywhere | Consistent look | Refactor |
| E10: Animation presets | Standard durations | 0.2s, 0.3s, 0.5s | Animation constants |
| E11: High contrast support | Check accessibilityContrast | Adjust colors | Environment check |
| E12: VoiceOver labels | All interactive elements | Accessible names | `.accessibilityLabel()` |
| E13: Reduce motion | Check accessibilityReduceMotion | Skip animations | Environment check |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Contrast check | All screens in dark mode | 4.5:1 minimum | Color contrast tool |
| Q2: Icon consistency | Visual audit | All SF Symbols | Manual review |
| Q3: Dynamic Type | Largest setting | Layout doesn't break | Accessibility setting |
| Q4: Spacing | Visual audit | Consistent 4pt grid | Design review |
| Q5: High contrast | Enable setting | Colors adjust | macOS setting |
| Q6: VoiceOver | Navigate app | All elements labeled | Accessibility audit |

---

## 5) Acceptance Criteria

- [ ] All text/background combinations meet WCAG AA (4.5:1)
- [ ] Color palette defined with semantic names
- [ ] All icons use SF Symbols
- [ ] Dynamic Type supported throughout
- [ ] Layout doesn't break at largest text size
- [ ] Spacing follows 4pt grid
- [ ] Spacing tokens used consistently
- [ ] Border radius standardized
- [ ] Animation timing consistent
- [ ] High contrast mode supported
- [ ] VoiceOver fully navigable
- [ ] Reduce motion respected

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Extreme Dynamic Type | Size check | Layout adapts, doesn't clip |
| High contrast mode | Environment check | Colors intensify |
| Reduce motion | Environment check | No animations |
| Color blindness | Design choice | Redundant indicators (not color alone) |
| Dark mode + high contrast | Both enabled | Combined adjustments |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `appearance_changed` | `mode` (light/dark) | Success |
| `dynamic_type_setting` | `size_category` | Info |
| `high_contrast_enabled` | - | Info |
| `reduce_motion_enabled` | - | Info |
| `voiceover_active` | - | Info |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Switch to dark mode → all text readable
- [ ] Use contrast analyzer → all pass 4.5:1
- [ ] Check all icons → SF Symbols only
- [ ] Set largest Dynamic Type → layout works
- [ ] Set smallest Dynamic Type → layout works
- [ ] Check spacing → consistent 4pt grid
- [ ] Check border radius → consistent
- [ ] Enable high contrast → colors adjust
- [ ] Enable VoiceOver → full navigation possible
- [ ] Enable reduce motion → no animations

**Automated Tests:**
- [ ] Unit test: Color contrast calculations
- [ ] Unit test: Dynamic Type scaling
- [ ] UI test: Layout at extreme text sizes
- [ ] Accessibility audit: VoiceOver labels

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Design system documentation
- SF Symbols library

**Risks:**
- Design changes may require stakeholder approval
- Large-scale token adoption takes time

**Rollout Plan:**
1. Color palette + contrast fixes (Day 1)
2. Icon migration + spacing (Day 2)
3. Dynamic Type + border radius (Day 3)
4. Accessibility + QA (Day 4)

---

## 10) Definition of Done

- [ ] WCAG AA contrast throughout
- [ ] Semantic color tokens defined and used
- [ ] All icons are SF Symbols
- [ ] Dynamic Type supported
- [ ] 4pt spacing grid applied
- [ ] Border radius standardized
- [ ] Animation timing consistent
- [ ] High contrast mode works
- [ ] VoiceOver navigable
- [ ] Reduce motion respected
- [ ] Design system documented
- [ ] PR reviewed and merged
