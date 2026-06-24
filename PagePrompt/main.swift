import AppKit

/// Themed Go-to-Page dialog matching LatteReader's coffee aesthetic.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let totalPages = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 100 : 100
        let currentPage = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1

        // ---- Build panel ----
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Go to Page"
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false

        // ---- Background gradient view ----
        let bgView = GradientView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = bgView

        // ---- Coffee mark ----
        let logoSize: CGFloat = 36
        let logoContainer = NSView(frame: NSRect(
            x: (bgView.bounds.width - logoSize) / 2,
            y: bgView.bounds.height - logoSize - 24,
            width: logoSize, height: logoSize
        ))
        let outerRing = NSView(frame: NSRect(x: 0, y: 0, width: logoSize, height: logoSize))
        outerRing.wantsLayer = true
        outerRing.layer?.cornerRadius = logoSize / 2
        // dark gradient
        let outerGradient = CAGradientLayer()
        outerGradient.frame = outerRing.bounds
        outerGradient.colors = [
            CGColor(red: 0.25, green: 0.20, blue: 0.15, alpha: 1),
            CGColor(red: 0.18, green: 0.14, blue: 0.11, alpha: 1),
        ]
        outerGradient.startPoint = CGPoint(x: 0, y: 1)
        outerGradient.endPoint = CGPoint(x: 1, y: 0)
        outerRing.layer?.addSublayer(outerGradient)
        outerRing.shadow = NSShadow()
        outerRing.shadow?.shadowColor = .black.withAlphaComponent(0.5)
        outerRing.shadow?.shadowBlurRadius = 4
        outerRing.shadow?.shadowOffset = NSSize(width: 0, height: 2)

        let innerDot = NSView(frame: NSRect(x: 9, y: 9, width: 18, height: 18))
        innerDot.wantsLayer = true
        innerDot.layer?.cornerRadius = 9
        let innerGradient = CAGradientLayer()
        innerGradient.frame = innerDot.bounds
        innerGradient.colors = [
            CGColor(red: 0.88, green: 0.73, blue: 0.43, alpha: 1),
            CGColor(red: 0.78, green: 0.60, blue: 0.37, alpha: 1),
        ]
        innerGradient.startPoint = CGPoint(x: 0, y: 1)
        innerGradient.endPoint = CGPoint(x: 1, y: 0)
        innerDot.layer?.addSublayer(innerGradient)
        innerDot.shadow = NSShadow()
        innerDot.shadow?.shadowColor = NSColor(red: 0.78, green: 0.60, blue: 0.37, alpha: 0.5)
        innerDot.shadow?.shadowBlurRadius = 6

        outerRing.addSubview(innerDot)
        logoContainer.addSubview(outerRing)
        bgView.addSubview(logoContainer)

        // ---- Title ----
        let titleField = NSTextField(labelWithString: "Go to Page")
        titleField.frame = NSRect(x: 0, y: 122, width: bgView.bounds.width, height: 22)
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = NSColor(red: 0.91, green: 0.87, blue: 0.82, alpha: 1)  // foam
        titleField.alignment = .center
        bgView.addSubview(titleField)

        // ---- Subtitle ----
        let subtitle = NSTextField(labelWithString: "Enter a page number (1–\(totalPages)):")
        subtitle.frame = NSRect(x: 30, y: 100, width: bgView.bounds.width - 60, height: 16)
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = NSColor(red: 0.65, green: 0.55, blue: 0.48, alpha: 1)  // muted
        subtitle.alignment = .center
        bgView.addSubview(subtitle)

        // ---- Text field (LCD-style) ----
        let textField = NSTextField(frame: NSRect(x: 50, y: 60, width: 200, height: 28))
        textField.stringValue = "\(currentPage)"
        textField.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        textField.textColor = NSColor(red: 0.91, green: 0.77, blue: 0.43, alpha: 1)  // butter
        textField.bezelStyle = .roundedBezel
        textField.alignment = .center
        textField.drawsBackground = true
        textField.backgroundColor = NSColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1)  // screen inset
        textField.isEditable = true
        textField.isSelectable = true
        textField.target = self
        textField.action = #selector(submit)
        bgView.addSubview(textField)

        // ---- Buttons ----
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: 50, y: 20, width: 90, height: 28)
        cancelBtn.keyEquivalent = "\u{1b}"
        styleButton(cancelBtn, primary: false)

        let goBtn = NSButton(title: "Go", target: self, action: #selector(submit))
        goBtn.frame = NSRect(x: 160, y: 20, width: 90, height: 28)
        goBtn.keyEquivalent = "\r"
        styleButton(goBtn, primary: true)

        bgView.addSubview(cancelBtn)
        bgView.addSubview(goBtn)

        // ---- Center on screen ----
        if let screen = NSScreen.main {
            let sr = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: sr.midX - panel.frame.width / 2,
                y: sr.midY - panel.frame.height / 2
            ))
        }

        panel.initialFirstResponder = textField
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.textField = textField
        self.totalPages = totalPages

        // Focus the text field after panel is visible
        DispatchQueue.main.async {
            panel.makeFirstResponder(textField)
        }
    }

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var totalPages: Int = 0

    @objc private func submit() {
        guard let textField else { return }
        let raw = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let num = Int(raw), num > 0, num <= totalPages else {
            textField.stringValue = ""
            textField.placeholderString = "1–\(totalPages)"
            return
        }
        print(num)
        NSApp.stop(self)
        panel?.close()
    }

    @objc private func cancel() {
        NSApp.stop(self)
        panel?.close()
    }
}

// MARK: - Themed Button

private func styleButton(_ btn: NSButton, primary: Bool) {
    btn.wantsLayer = true
    btn.isBordered = false
    btn.layer?.cornerRadius = 8
    btn.font = .systemFont(ofSize: 12, weight: .semibold)

    if primary {
        btn.layer?.backgroundColor = CGColor(red: 0.78, green: 0.60, blue: 0.37, alpha: 1)
        btn.contentTintColor = NSColor(red: 0.18, green: 0.14, blue: 0.11, alpha: 1)
        btn.layer?.shadowColor = CGColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 0.5)
        btn.layer?.shadowRadius = 4
        btn.layer?.shadowOffset = NSSize(width: 0, height: 2)
        btn.layer?.shadowOpacity = 1
    } else {
        let bgGradient = CAGradientLayer()
        bgGradient.colors = [
            CGColor(red: 0.32, green: 0.24, blue: 0.18, alpha: 1),
            CGColor(red: 0.22, green: 0.18, blue: 0.14, alpha: 1),
        ]
        bgGradient.startPoint = CGPoint(x: 0.5, y: 1)
        bgGradient.endPoint = CGPoint(x: 0.5, y: 0)
        bgGradient.frame = btn.bounds
        // Can't easily add sublayers to NSButton's layer, use backgroundColor instead
        btn.layer?.backgroundColor = CGColor(red: 0.25, green: 0.20, blue: 0.15, alpha: 1)
        btn.contentTintColor = NSColor(red: 0.91, green: 0.87, blue: 0.82, alpha: 1)
        btn.layer?.shadowColor = CGColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 0.6)
        btn.layer?.shadowRadius = 3
        btn.layer?.shadowOffset = NSSize(width: 0, height: 2)
        btn.layer?.shadowOpacity = 1
    }
}

// MARK: - Gradient Background View

class GradientView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let colors: [CGColor] = [
            CGColor(red: 0.20, green: 0.16, blue: 0.12, alpha: 1),
            CGColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1),
            CGColor(red: 0.13, green: 0.10, blue: 0.08, alpha: 1),
        ]
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: colors as CFArray,
            locations: [0, 0.5, 1]
        )!
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: bounds.height),
            end: CGPoint(x: bounds.width, y: 0),
            options: []
        )
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
