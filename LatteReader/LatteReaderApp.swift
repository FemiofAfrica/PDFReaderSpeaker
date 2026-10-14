import AppKit
import SwiftUI

@main
struct LatteReaderApp: App {
    init() {
        // Make sure the Dock shows the bundled Crema Waves icon even if macOS has a stale icon cache.
        if let url = Bundle.main.url(forResource: "LatteReader", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: 760, idealWidth: 960,
                    maxWidth: .infinity,
                    minHeight: 560, idealHeight: 700,
                    maxHeight: .infinity
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 700)
    }
}
