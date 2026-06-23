import PDFKit
import SwiftUI

/// Observable proxy that lets SwiftUI controls drive PDFView zoom
/// without needing direct access to the NSViewRepresentable's coordinator.
final class PDFViewProxy: ObservableObject {
    @Published var scalePercent: Int = 100
    @Published var currentPageNumber: Int = 0
    fileprivate weak var pdfView: PDFView? {
        didSet {
            syncScale()
            observeScaleChanges()
            observePageChanges()
        }
    }

    private var scaleObserver: NSObjectProtocol?
    private var pageObserver: NSObjectProtocol?

    deinit {
        if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
    }

    // MARK: - Zoom actions

    func zoomIn() {
        pdfView?.zoomIn(nil)
        syncScale()
    }

    func zoomOut() {
        pdfView?.zoomOut(nil)
        syncScale()
    }

    func zoomToFit() {
        guard let pdfView else { return }
        pdfView.autoScales = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        syncScale()
    }

    // MARK: - Internal

    fileprivate func syncScale() {
        guard let pdfView else { return }
        scalePercent = max(10, min(Int(pdfView.scaleFactor * 100), 3200))
    }

    private func observeScaleChanges() {
        if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
        guard let pdfView else { return }
        scaleObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.syncScale()
        }
    }

    private func observePageChanges() {
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
        guard let pdfView else { return }
        // Read the initial page
        syncPageNumber()
        pageObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.syncPageNumber()
        }
    }

    private func syncPageNumber() {
        guard let pdfView else { return }
        // The PDFView's currentPage gives the visible page.
        // Convert to 1-based page number for display.
        if let page = pdfView.currentPage,
           let index = pdfView.document?.index(for: page) {
            currentPageNumber = index + 1
        }
    }

    /// Navigate to a specific page number (1-based).
    func goToPage(_ number: Int) {
        guard let document = pdfView?.document else { return }
        let index = number - 1
        guard index >= 0, index < document.pageCount else { return }
        if let page = document.page(at: index) {
            pdfView?.go(to: page)
        }
    }

    // MARK: - Selection

    /// Returns the text the user has selected in the PDF view,
    /// or nil if nothing is selected.
    func currentSelectionText() -> String? {
        pdfView?.currentSelection?.string
    }
}

// MARK: - PDFKit View

/// An NSViewRepresentable wrapping PDFKit's PDFView.
///
/// Each instance is created with a **fixed display mode** — it never
/// switches modes at runtime. For multi-mode UIs, place two instances
/// in a ZStack and toggle visibility. This avoids PDFView's expensive
/// page re-layout when changing displayMode.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let displayMode: PDFDisplayMode
    /// When `true`, this view's PDFView is registered on the proxy
    /// (so zoom controls operate on it). Only one view per proxy
    /// should be active at a time.
    let isActive: Bool
    let proxy: PDFViewProxy

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = displayMode
        pdfView.backgroundColor = NSColor(red: 0.290, green: 0.208, blue: 0.157, alpha: 1.0) // chocolateMedium

        if isActive { proxy.pdfView = pdfView }
        context.coordinator.lastPage = currentPage
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Update document reference when a new PDF is loaded
        if nsView.document !== document {
            nsView.document = document
            context.coordinator.lastPage = currentPage
            if let page = nsView.document?.page(at: currentPage) {
                nsView.go(to: page)
            }
            return
        }

        // Handle proxy activation changes
        if isActive { proxy.pdfView = nsView }

        // Handle page navigation
        guard context.coordinator.lastPage != currentPage else { return }
        context.coordinator.lastPage = currentPage

        guard currentPage >= 0,
              currentPage < (nsView.document?.pageCount ?? 0)
        else { return }
        if let page = nsView.document?.page(at: currentPage) {
            nsView.go(to: page)
        }
    }
}

extension PDFKitView {
    final class Coordinator {
        var lastPage: Int = 0
    }
}
