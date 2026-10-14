import Foundation
import PDFKit
import SwiftUI

/// Tracks current speech position and manages PDF highlighting
@MainActor
final class SpeechHighlighter: ObservableObject {
    @Published var currentHighlight: PDFSelection?
    @Published var currentPage: Int?
    
    private weak var pdfDocument: PDFDocument?
    private weak var pdfView: PDFView?
    private var currentText: String?
    private var documentText: String?
    
    func setPDFDocument(_ document: PDFDocument?, view: PDFView?) {
        self.pdfDocument = document
        self.pdfView = view
        self.documentText = nil
        clearHighlight()
    }
    
    func setDocumentText(_ text: String) {
        self.documentText = text
    }
    
    /// Highlight the chunk currently being spoken
    func highlightChunk(_ text: String, searchFrom pageNumber: Int? = nil) {
        guard let document = pdfDocument else { return }
        
        // Normalize text for searching
        let searchText = normalizeForSearch(text)
        guard !searchText.isEmpty else {
            clearHighlight()
            return
        }
        
        // Store for reference
        currentText = searchText
        
        // Search from specific page if provided, otherwise search all
        let startPage = pageNumber ?? 0
        let endPage = document.pageCount
        
        // Try to find the text in the document
        for pageIndex in startPage..<endPage {
            guard let page = document.page(at: pageIndex) else { continue }
            
            if let selection = findTextOnPage(searchText, page: page) {
                applyHighlight(selection, pageIndex: pageIndex)
                return
            }
        }
        
        // If not found from start page forward, try from beginning
        if startPage > 0 {
            for pageIndex in 0..<startPage {
                guard let page = document.page(at: pageIndex) else { continue }
                
                if let selection = findTextOnPage(searchText, page: page) {
                    applyHighlight(selection, pageIndex: pageIndex)
                    return
                }
            }
        }
        
        // Text not found - clear highlight
        clearHighlight()
    }
    
    /// Find text on a specific page and return a PDFSelection
    private func findTextOnPage(_ searchText: String, page: PDFPage) -> PDFSelection? {
        guard let pageString = page.string else { return nil }
        
        // Use NSString for case-insensitive search
        let nsString = pageString as NSString
        let range = nsString.range(of: searchText, options: .caseInsensitive)
        
        guard range.location != NSNotFound else { return nil }
        
        // Create selection from the found range
        return page.selection(for: range)
    }
    
    /// Highlight a specific word range (for system voice)
    func highlightRange(_ range: NSRange, in fullText: String, searchFrom pageNumber: Int? = nil) {
        guard range.location != NSNotFound,
              range.location + range.length <= fullText.count else {
            clearHighlight()
            return
        }
        
        let start = fullText.index(fullText.startIndex, offsetBy: range.location)
        let end = fullText.index(start, offsetBy: range.length)
        let text = String(fullText[start..<end])
        
        highlightChunk(text, searchFrom: pageNumber)
    }
    
    private func applyHighlight(_ selection: PDFSelection, pageIndex: Int) {
        guard let pdfView = pdfView else { return }
        
        // Update current page
        currentPage = pageIndex
        
        // Set the highlight
        currentHighlight = selection
        
        // Scroll to make the selection visible
        if let page = pdfDocument?.page(at: pageIndex) {
            // Go to the page first
            pdfView.go(to: page)
            
            // Then scroll to the selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pdfView] in
                if let bounds = selection.boundsForPage(page) {
                    pdfView?.go(to: bounds, on: page)
                }
            }
        }
        
        // Set visual highlight color
        selection.color = NSColor.systemYellow.withAlphaComponent(0.4)
        pdfView.currentSelection = selection
        pdfView.setCurrentSelection(selection, animate: true)
    }
    
    func clearHighlight() {
        currentHighlight = nil
        currentText = nil
        pdfView?.clearSelection()
    }
    
    /// Normalize text for more reliable searching
    private func normalizeForSearch(_ text: String) -> String {
        // Take first substantial part if text is very long
        let maxLength = 200
        var searchText = text
        
        if searchText.count > maxLength {
            // Find a good breaking point (sentence end)
            let truncated = String(searchText.prefix(maxLength))
            if let lastPeriod = truncated.lastIndex(of: "."),
               lastPeriod > truncated.startIndex {
                searchText = String(truncated[..<lastPeriod])
            } else if let lastSpace = truncated.lastIndex(of: " ") {
                searchText = String(truncated[..<lastSpace])
            } else {
                searchText = truncated
            }
        }
        
        // Clean up common issues
        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
}

/// Extension to map chunk index to approximate text position
extension SpeechHighlighter {
    /// Calculate approximate page number for a chunk based on character position
    func approximatePageForChunk(
        index: Int,
        chunks: [PlannedSpeechSegment],
        pdfPageTexts: [PDFPageText]
    ) -> Int? {
        guard index < chunks.count else { return nil }
        
        // Calculate total characters up to this chunk
        var charsSoFar = 0
        for i in 0..<index {
            charsSoFar += chunks[i].text.count
        }
        
        // Find which page contains this character position
        var currentPos = 0
        for pageText in pdfPageTexts {
            let pageLength = pageText.text.count
            if charsSoFar >= currentPos && charsSoFar < currentPos + pageLength {
                return pageText.pageNumber - 1 // Return 0-based index
            }
            currentPos += pageLength
        }
        
        return nil
    }
}

/// PDFSelection extension for bounds calculation
extension PDFSelection {
    func boundsForPage(_ page: PDFPage) -> CGRect? {
        // PDFSelection.bounds(for:) returns the bounds of the selection on the given page
        guard pages.contains(page) else { return nil }
        return bounds(for: page)
    }
}
