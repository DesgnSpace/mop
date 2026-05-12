import SwiftUI

extension Color {
    // ── Surfaces (fallback when materials aren't used) ──
    static let surfaceBase      = Color(red: 0.0108, green: 0.0133, blue: 0.0163)  // oklch(10% 0.004 250)
    static let surfaceElevated  = Color(red: 0.0248, green: 0.0290, blue: 0.0340)  // oklch(13% 0.004 250)
    static let surfaceHighest   = Color(red: 0.0457, green: 0.0527, blue: 0.0602)  // oklch(16% 0.005 250)
    static let surfaceField     = Color(red: 0.0152, green: 0.0175, blue: 0.0202)  // oklch(11% 0.003 250)

    // ── Borders ───────────────────────────────────
    static let borderSubtle     = Color(red: 0.0638, green: 0.0695, blue: 0.0757)  // oklch(18% 0.004 250)
    static let borderAccent     = Color(red: 0.0975, green: 0.1050, blue: 0.1132)  // oklch(22% 0.005 250)

    // ── Text ──────────────────────────────────────
    static let textPrimary      = Color(red: 0.8919, green: 0.8962, blue: 0.9009)  // oklch(92% 0.002 250)
    static let textSecondary    = Color(red: 0.5557, green: 0.5616, blue: 0.5680)  // oklch(65% 0.003 250)
    static let textTertiary     = Color(red: 0.3292, green: 0.3346, blue: 0.3405)  // oklch(45% 0.003 250)

    // ── Accent (bg washes; keep Color.accentColor for text/icons) ──
    static let accentBg         = Color(red: 0.0732, green: 0.0880, blue: 0.1039)  // oklch(20% 0.01 250)
    static let accentBgHover    = Color(red: 0.0552, green: 0.0670, blue: 0.0799)  // oklch(15% 0.01 250)
    static let accentMuted      = Color(red: 0.1661, green: 0.2361, blue: 0.3090)  // oklch(35% 0.04 250)
    static let accentStroke     = Color(red: 0.1363, green: 0.1934, blue: 0.2531)  // oklch(30% 0.04 250)

    // ── Semantic ──────────────────────────────────
    static let semanticSuccess  = Color(red: 0.3048, green: 0.3931, blue: 0.3206)  // oklch(48% 0.04 150)
    static let semanticWarning  = Color(red: 0.4485, green: 0.3777, blue: 0.2596)  // oklch(50% 0.05 80)
    static let semanticError    = Color(red: 0.4338, green: 0.2920, blue: 0.2792)  // oklch(45% 0.05 25)
    static let semanticInfo     = Color(red: 0.2685, green: 0.3422, blue: 0.4196)  // oklch(45% 0.04 250)

    // ── Badge Backgrounds ─────────────────────────
    static let badgeSuccessBg   = Color(red: 0.1124, green: 0.1401, blue: 0.1170)  // oklch(25% 0.015 150)
    static let badgeWarningBg   = Color(red: 0.1468, green: 0.1291, blue: 0.1003)  // oklch(25% 0.015 80)
    static let badgeErrorBg     = Color(red: 0.1587, green: 0.1213, blue: 0.1175)  // oklch(25% 0.015 25)
    static let badgeInfoBg      = Color(red: 0.1109, green: 0.1345, blue: 0.1595)  // oklch(25% 0.015 250)

    // ── Engine ────────────────────────────────────
    static let engineWhisperKit = Color(red: 0.3734, green: 0.4359, blue: 0.6304)  // oklch(55% 0.08 270)
    static let engineWhisperKitBg = Color(red: 0.0948, green: 0.1092, blue: 0.1550)  // oklch(18% 0.03 270)
    static let engineParakeet   = Color(red: 0.1713, green: 0.5037, blue: 0.4857)  // oklch(55% 0.08 190)
    static let engineParakeetBg = Color(red: 0.0527, green: 0.1124, blue: 0.1068)    // oklch(18% 0.03 190)

    // ── Tier ──────────────────────────────────────
    static let tierDefault      = Color(red: 0.1661, green: 0.2361, blue: 0.3090)  // oklch(35% 0.04 250)
    static let tierDefaultBg    = Color(red: 0.0552, green: 0.0670, blue: 0.0799)  // oklch(15% 0.015 250)
    static let tierHighAccuracy = Color(red: 0.2873, green: 0.3993, blue: 0.3086)  // oklch(48% 0.05 150)
    static let tierLowMemory    = Color(red: 0.4485, green: 0.3777, blue: 0.2596)  // oklch(50% 0.05 80)
    static let tierFast         = Color(red: 0.2344, green: 0.3939, blue: 0.4440)  // oklch(48% 0.05 220)
}
