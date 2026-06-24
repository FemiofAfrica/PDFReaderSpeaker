import SwiftUI

// MARK: - Color Palette (coffee-theme, adapted from Lovable design)
//
// The palette uses warm chocolate/caramel tones with amber highlights,
// giving a tactile, premium coffee-shop feel.

extension Color {
    // --- Core backgrounds ---
    static let espresso  = Color(red: 0.133, green: 0.098, blue: 0.075)   // #221A13
    static let bean      = Color(red: 0.188, green: 0.149, blue: 0.114)   // #30261D
    static let roast     = Color(red: 0.247, green: 0.196, blue: 0.149)   // #3F3226

    // --- Accents ---
    static let crema     = Color(red: 0.380, green: 0.318, blue: 0.243)   // #61513E
    static let caramel   = Color(red: 0.784, green: 0.604, blue: 0.369)   // #C89A5E
    static let butter    = Color(red: 0.910, green: 0.773, blue: 0.431)   // #E8C56E
    static let ember     = Color(red: 0.780, green: 0.376, blue: 0.251)   // #C76040

    // --- Text / surfaces ---
    static let foam      = Color(red: 0.910, green: 0.867, blue: 0.816)   // #E8DDD0
    static let cream     = Color(red: 0.949, green: 0.918, blue: 0.871)   // #F2EADE
    static let mutedBg   = Color(red: 0.208, green: 0.173, blue: 0.141)   // #352C24

    // --- Legacy aliases (kept for backward compat) ---
    static let chocolate         = bean
    static let chocolateMedium   = roast
    static let chocolateLight    = Color(red: 0.361, green: 0.247, blue: 0.180)
    static let gold              = caramel
    static let goldMuted         = Color(red: 0.722, green: 0.580, blue: 0.314)
    static let creamMuted        = Color(red: 0.831, green: 0.769, blue: 0.690)
    static let chocolateDark     = espresso

    // --- Semantic ---
    static let surfaceBase  = espresso
    static let surfaceRaised = bean
    static let surfaceBezel = roast
    static let textPrimary  = cream
    static let textMuted    = Color(red: 0.588, green: 0.537, blue: 0.486)  // #96897C
    static let accent       = caramel
    static let accentGlow   = butter
    static let alertRed     = Color(red: 0.8, green: 0.25, blue: 0.2)
}

// MARK: - Shadows
// (Shadow constants defined inline where used)

// MARK: - Abstract Ambient Background

/// A subtle, non‑distracting background with floating organic shapes,
/// soft rings, and a gentle gradient — redesigned with coffee‑warm tones.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            // Base gradient — coffee warm
            LinearGradient(
                gradient: Gradient(colors: [
                    .bean,
                    .espresso,
                    Color(red: 0.18, green: 0.14, blue: 0.11),
                    Color(red: 0.13, green: 0.10, blue: 0.08),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Large warm ring (top right)
                Circle()
                    .stroke(Color.caramel.opacity(0.08), lineWidth: 2.5)
                    .frame(width: w * 0.45, height: w * 0.45)
                    .position(x: w * 0.78, y: h * 0.18)

                // Large warm ring (bottom left)
                Circle()
                    .stroke(Color.butter.opacity(0.05), lineWidth: 1.5)
                    .frame(width: w * 0.35, height: w * 0.35)
                    .position(x: w * 0.18, y: h * 0.72)

                // Soft organic blob (bottom centre)
                RoundedRectangle(cornerRadius: 90)
                    .fill(Color.roast.opacity(0.10))
                    .frame(width: w * 0.28, height: w * 0.18)
                    .rotationEffect(.degrees(22))
                    .position(x: w * 0.55, y: h * 0.88)

                // Soft organic blob (top left)
                RoundedRectangle(cornerRadius: 70)
                    .fill(Color.crema.opacity(0.06))
                    .frame(width: w * 0.2, height: w * 0.12)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.1, y: h * 0.12)

                // Small accent floaters
                Circle().fill(Color.caramel.opacity(0.055))
                    .frame(width: 10, height: 10)
                    .position(x: w * 0.08, y: h * 0.32)

                Circle().fill(Color.butter.opacity(0.04))
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.88, y: h * 0.55)

                Capsule()
                    .fill(Color.caramel.opacity(0.025))
                    .frame(width: w * 0.35, height: 1.5)
                    .position(x: w * 0.7, y: h * 0.45)

                Capsule()
                    .fill(Color.roast.opacity(0.04))
                    .frame(width: w * 0.25, height: 1)
                    .rotationEffect(.degrees(30))
                    .position(x: w * 0.25, y: h * 0.55)
            }
        }
        .ignoresSafeArea()
        .drawingGroup()
    }
}

// MARK: - Reusable background modifier
// (AmbientBackground is used directly in ContentView)
