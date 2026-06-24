import SwiftUI

// MARK: - Bezel Container

struct Bezel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [.bean, .espresso],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Screen Inset

struct ScreenInset<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LCD Text

struct LCDText: View {
    let text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var color: Color = .butter

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 0)
    }
}

// MARK: - Key Button

struct KeyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundColor(.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.32, green: 0.24, blue: 0.18),
                                 Color(red: 0.22, green: 0.18, blue: 0.14)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color(red: 0.12, green: 0.10, blue: 0.08).opacity(0.6),
                        radius: 3, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        .padding(1)
                )
        }
        .buttonStyle(KeyButtonStyle())
    }
}

struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Primary Button

struct PrimaryButton: View {
    let label: String
    let icon: String?
    let action: () -> Void
    init(_ label: String, icon: String? = nil, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(label).font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.espresso)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.85, green: 0.70, blue: 0.45),
                             Color(red: 0.78, green: 0.60, blue: 0.37)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color(red: 0.55, green: 0.40, blue: 0.25).opacity(0.5),
                    radius: 4, x: 0, y: 3)
            .shadow(color: .caramel.opacity(0.3), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    .padding(1)
            )
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Round Button

struct RoundBtn: View {
    let systemImage: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(disabled ? .textMuted.opacity(0.3) : .cream)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.32, green: 0.24, blue: 0.18),
                                 Color(red: 0.22, green: 0.18, blue: 0.14)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color(red: 0.12, green: 0.10, blue: 0.08).opacity(0.6),
                        radius: 2, x: 0, y: 2)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5).padding(1)
                )
        }
        .buttonStyle(RoundBtnStyle())
        .disabled(disabled)
    }
}

struct RoundBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Segmented Control

struct CoffeeSegmentedControl: View {
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                let active = option.id == selection
                Button {
                    selection = option.id
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundColor(active ? .espresso : .textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(active ? nil : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .background(active ? activeOverlay : nil)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.45))
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        )
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    private var activeOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [.butter, .caramel],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .shadow(color: .caramel.opacity(0.3), radius: 3, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    .padding(1)
            )
    }
}

// MARK: - Panel Header

struct PanelHeader: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundColor(.caramel)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.border.opacity(0.5), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

// MARK: - LED

struct LED: View {
    var color: LEDColor = .green
    enum LEDColor { case green, amber, red
        var color: Color {
            switch self {
            case .green: return Color(red: 0.58, green: 0.82, blue: 0.38)
            case .amber: return Color(red: 0.91, green: 0.77, blue: 0.43)
            case .red:   return Color(red: 0.78, green: 0.38, blue: 0.25)
            }
        }
    }

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: 7, height: 7)
            .shadow(color: color.color.opacity(0.7), radius: 3, x: 0, y: 0)
            .overlay(
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5).padding(1)
            )
    }
}

// MARK: - Dial

struct CoffeeDial: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    @State private var isDragging = false
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartVal: Double = 0

    private var angle: Angle {
        let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return .degrees(-135 + pct * 270)
    }

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.40, green: 0.32, blue: 0.24),
                                 Color(red: 0.22, green: 0.18, blue: 0.14)],
                        center: .init(x: 0.3, y: 0.25),
                        startRadius: 2, endRadius: 28
                    )
                )
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .rotationEffect(angle)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.butter)
                        .frame(width: 2, height: 7)
                        .shadow(color: .butter.opacity(0.5), radius: 2)
                        .offset(y: -15)
                        .rotationEffect(angle)
                )
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                dragStartY = gesture.location.y
                                dragStartVal = value
                            }
                            let deltaY = dragStartY - gesture.location.y
                            let span = range.upperBound - range.lowerBound
                            let newVal = dragStartVal + (deltaY / 80) * span
                            let stepped = round(newVal / step) * step
                            value = min(range.upperBound, max(range.lowerBound, stepped))
                        }
                        .onEnded { _ in isDragging = false }
                )
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.push() }
                    else { NSCursor.pop() }
                }

            VStack(spacing: 1) {
                LCDText(text: format(value), size: 10, weight: .semibold)
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundColor(.textMuted)
            }
        }
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let playing: Bool
    @Binding var progress: Double

    private let bars: [CGFloat] = {
        var out: [CGFloat] = []
        var s = 7
        for i in 0..<48 {
            s = (s * 9301 + 49297) % 233280
            let r = CGFloat(s) / 233280
            let env: CGFloat = 0.4 + 0.6 * sin(CGFloat(i) / 48 * .pi * 3)
            out.append(0.15 + r * env * 0.85)
        }
        return out
    }()

    @State private var dragWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let barCount = bars.count
            let gap: CGFloat = 1.5
            let totalGap = gap * CGFloat(barCount - 1)
            let barW = max(1.5, (w - totalGap) / CGFloat(barCount))
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.5))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

                // Bars
                HStack(spacing: gap) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { i, height in
                        let played = CGFloat(i) / CGFloat(barCount) < progress
                        RoundedRectangle(cornerRadius: barW / 2)
                            .fill(played ? Color.butter : Color(red: 0.42, green: 0.34, blue: 0.26))
                            .frame(width: barW, height: height * h)
                    }
                }
                .padding(.horizontal, 6)

                // Playhead
                Rectangle()
                    .fill(Color.ember)
                    .frame(width: 2)
                    .shadow(color: .ember.opacity(0.6), radius: 3)
                    .position(x: progress * w, y: h / 2)
            }
            .onAppear { dragWidth = w }
            .onChange(of: w) { dragWidth = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let p = gesture.location.x / dragWidth
                        progress = min(1, max(0, p))
                    }
            )
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Color helpers

extension Color {
    static let border = Color.white.opacity(0.08)
}
