import SwiftUI

@main
struct PDFReaderSpeakerApp: App {
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
