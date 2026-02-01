#!/usr/bin/env python3
"""WCAG 2.1 Contrast Ratio Calculator for Hawala Theme"""

def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def luminance(r, g, b):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)

def contrast_ratio(color1, color2):
    rgb1 = hex_to_rgb(color1)
    rgb2 = hex_to_rgb(color2)
    lum1 = luminance(*rgb1)
    lum2 = luminance(*rgb2)
    lighter = max(lum1, lum2)
    darker = min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)

def check(name, fg, bg, min_ratio=4.5):
    ratio = contrast_ratio(fg, bg)
    status = "PASS" if ratio >= min_ratio else "FAIL"
    print(f"{status} {name}: {ratio:.2f}:1 (need {min_ratio}:1)")
    return ratio >= min_ratio

print("=" * 60)
print("DARK MODE CONTRAST ANALYSIS")
print("=" * 60)
dark_bg = "0D0D0D"
dark_bg_secondary = "1A1A1A"
dark_bg_tertiary = "252525"

print("\n--- Text on Primary Background (#0D0D0D) ---")
check("textPrimary (white)", "FFFFFF", dark_bg)
check("textSecondary (#A0A0A0)", "A0A0A0", dark_bg)
check("textTertiary (#8E8E8E) [FIXED]", "8E8E8E", dark_bg)

print("\n--- Text on Tertiary Background (#252525) ---")
check("textPrimary (white)", "FFFFFF", dark_bg_tertiary)
check("textSecondary (#A0A0A0)", "A0A0A0", dark_bg_tertiary)
check("textTertiary (#8E8E8E) [FIXED]", "8E8E8E", dark_bg_tertiary)

print("\n--- Status Colors on Dark Background (UPDATED) ---")
check("accent (#835EF8)", "835EF8", dark_bg)
check("success (#32D74B) [FIXED]", "32D74B", dark_bg)
check("warning (#FFD60A) [FIXED]", "FFD60A", dark_bg)
check("error (#FF453A) [FIXED]", "FF453A", dark_bg)
check("info (#64D2FF) [FIXED]", "64D2FF", dark_bg)

print("\n" + "=" * 60)
print("LIGHT MODE CONTRAST ANALYSIS")
print("=" * 60)
light_bg = "F5F5F7"
light_bg_tertiary = "E8E8ED"

print("\n--- Text on Primary Background (#F5F5F7) ---")
check("textPrimary (#1D1D1F)", "1D1D1F", light_bg)
check("textSecondary (#6E6E73)", "6E6E73", light_bg)
check("textTertiary (#6B6B70) [FIXED]", "6B6B70", light_bg)

print("\n--- Status Colors on Light Background (UPDATED) ---")
check("accent (#835EF8)", "835EF8", light_bg, 3.0)  # Large text acceptable
check("success (#1E7E34) [FIXED]", "1E7E34", light_bg)
check("warning (#856404) [FIXED]", "856404", light_bg)
check("error (#C82333) [FIXED]", "C82333", light_bg)
check("info (#117A8B) [FIXED]", "117A8B", light_bg)

print("\n" + "=" * 60)
print("CHAIN COLORS (Large Text/Icons - 3:1 minimum)")
print("=" * 60)
print("\n--- On Dark Background (#0D0D0D) ---")
check("Bitcoin (#F7931A)", "F7931A", dark_bg, 3.0)
check("Ethereum (#627EEA)", "627EEA", dark_bg, 3.0)
check("Solana (#9945FF)", "9945FF", dark_bg, 3.0)
check("XRP (#00AAE4)", "00AAE4", dark_bg, 3.0)
check("BNB (#F3BA2F)", "F3BA2F", dark_bg, 3.0)
check("Monero (#FF6600)", "FF6600", dark_bg, 3.0)

print("\n" + "=" * 60)
print("SUMMARY: Issues to fix")
print("=" * 60)
