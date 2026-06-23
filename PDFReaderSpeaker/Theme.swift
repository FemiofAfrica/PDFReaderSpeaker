import SwiftUI

// MARK: - Color Palette
extension Color {
    /// Deep chocolate brown — primary background
    static let chocolate = Color(red: 0.235, green: 0.165, blue: 0.129)        // #3C2A21
    /// Medium brown — lighter surface / card
    static let chocolateMedium = Color(red: 0.290, green: 0.208, blue: 0.157)  // #4A3528
    /// Light brown — accent surface
    static let chocolateLight = Color(red: 0.361, green: 0.247, blue: 0.180)   // #5C3F2E
    /// Warm muted gold — accent highlights
    static let gold = Color(red: 0.784, green: 0.663, blue: 0.431)            // #C8A96E
    /// Subdued gold — secondary accent, rings
    static let goldMuted = Color(red: 0.722, green: 0.580, blue: 0.314)       // #B89450
    /// Warm cream — primary text on dark
    static let cream = Color(red: 0.910, green: 0.863, blue: 0.800)           // #E8DCCC
    /// Muted cream — secondary text
    static let creamMuted = Color(red: 0.831, green: 0.769, blue: 0.690)      // #D4C4B0
    /// Very deep brown — for borders / dividers
    static let chocolateDark = Color(red: 0.180, green: 0.125, blue: 0.098)   // #2E2018
}

// MARK: - Abstract Ambient Background
///
/// A subtle, non‑distracting background with floating organic shapes,
/// soft rings, and a gentle gradient — designed to feel calm, earthy,
/// and premium without competing with PDF content.
///
struct AmbientBackground: View {
    @State private var ringAnim1: CGFloat = 0
    @State private var ringAnim2: CGFloat = 0

    var body: some View {
        ZStack {
            // Base gradient — warm chocolate with subtle depth
            LinearGradient(
                gradient: Gradient(colors: [
                    .chocolate,
                    Color(red: 0.215, green: 0.145, blue: 0.112),
                    Color(red: 0.245, green: 0.170, blue: 0.130),
                    .chocolateDark,
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // --- Large floating ring 1 (top right) ---
                Circle()
                    .stroke(Color.goldMuted.opacity(0.07), lineWidth: 2.5)
                    .frame(width: w * 0.45, height: w * 0.45)
                    .position(x: w * 0.78, y: h * 0.18)

                // --- Large floating ring 2 (bottom left) ---
                Circle()
                    .stroke(Color.gold.opacity(0.045), lineWidth: 1.5)
                    .frame(width: w * 0.35, height: w * 0.35)
                    .position(x: w * 0.18, y: h * 0.72)

                // --- Soft organic blob (bottom centre) ---
                RoundedRectangle(cornerRadius: 90)
                    .fill(Color.chocolateLight.opacity(0.08))
                    .frame(width: w * 0.28, height: w * 0.18)
                    .rotationEffect(.degrees(22))
                    .position(x: w * 0.55, y: h * 0.88)

                // --- Soft organic blob (top left) ---
                RoundedRectangle(cornerRadius: 70)
                    .fill(Color.chocolateMedium.opacity(0.06))
                    .frame(width: w * 0.2, height: w * 0.12)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.1, y: h * 0.12)

                // --- Small accent dots / floaters ---
                Circle()
                    .fill(Color.gold.opacity(0.055))
                    .frame(width: 10, height: 10)
                    .position(x: w * 0.08, y: h * 0.32)

                Circle()
                    .fill(Color.goldMuted.opacity(0.04))
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.88, y: h * 0.55)

                Circle()
                    .fill(Color.chocolateLight.opacity(0.07))
                    .frame(width: 7, height: 7)
                    .position(x: w * 0.4, y: h * 0.38)

                Circle()
                    .fill(Color.gold.opacity(0.04))
                    .frame(width: 6, height: 6)
                    .position(x: w * 0.65, y: h * 0.7)

                // --- Soft horizontal curve (mid‑right) ---
                Capsule()
                    .fill(Color.goldMuted.opacity(0.025))
                    .frame(width: w * 0.35, height: 1.5)
                    .position(x: w * 0.7, y: h * 0.45)

                // --- Second softer curve (mid‑left) ---
                Capsule()
                    .fill(Color.chocolateLight.opacity(0.04))
                    .frame(width: w * 0.25, height: 1)
                    .rotationEffect(.degrees(30))
                    .position(x: w * 0.25, y: h * 0.55)
            }
        }
        .ignoresSafeArea()
        .drawingGroup() // offscreen render for performance
    }
}

// MARK: - Reusable background modifier
extension View {
    /// Wraps the view in a ZStack with the ambient chocolate‑brown background,
    /// preserving the original view's layout.
    func withAmbientBackground() -> some View {
        ZStack {
            AmbientBackground()
            self
        }
    }
}
