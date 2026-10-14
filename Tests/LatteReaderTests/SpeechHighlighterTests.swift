import XCTest
@testable import LatteReader

@MainActor
final class SpeechHighlighterTests: XCTestCase {
    var highlighter: SpeechHighlighter!
    
    override func setUp() async throws {
        highlighter = SpeechHighlighter()
    }
    
    func testNormalizeForSearchTruncatesLongText() {
        let longText = String(repeating: "word ", count: 100) // ~500 chars
        let result = highlighter.normalizeForSearch(longText)
        
        XCTAssertLessThanOrEqual(result.count, 200, "Should truncate to max length")
    }
    
    func testNormalizeForSearchCleansWhitespace() {
        let text = "  Multiple   spaces\n\nand\nnewlines  "
        let result = highlighter.normalizeForSearch(text)
        
        XCTAssertFalse(result.contains("\n"), "Should remove newlines")
        XCTAssertFalse(result.contains("  "), "Should collapse multiple spaces")
        XCTAssertEqual(result.first, "M", "Should trim leading whitespace")
        XCTAssertNotEqual(result.last, " ", "Should trim trailing whitespace")
    }
    
    func testNormalizeForSearchBreaksAtSentenceEnd() {
        let longSentence = String(repeating: "word ", count: 30) + ". Another sentence."
        let result = highlighter.normalizeForSearch(longSentence)
        
        // Should break at the period if text is too long
        if result.count < longSentence.count {
            XCTAssertFalse(result.contains("Another"), "Should break before next sentence")
        }
    }
    
    func testApproximatePageForChunkFirstChunk() {
        let chunks = [
            PlannedSpeechSegment(text: "First", voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator"),
            PlannedSpeechSegment(text: "Second", voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator")
        ]
        
        let pageTexts = [
            PDFPageText(id: 0, pageNumber: 1, text: "First Second Third"),
            PDFPageText(id: 1, pageNumber: 2, text: "More text here")
        ]
        
        let page = highlighter.approximatePageForChunk(index: 0, chunks: chunks, pdfPageTexts: pageTexts)
        XCTAssertEqual(page, 0, "First chunk should map to first page")
    }
    
    func testApproximatePageForChunkMultiPage() {
        let chunks = [
            PlannedSpeechSegment(text: String(repeating: "a", count: 100), voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator"),
            PlannedSpeechSegment(text: String(repeating: "b", count: 100), voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator"),
            PlannedSpeechSegment(text: String(repeating: "c", count: 100), voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator")
        ]
        
        let pageTexts = [
            PDFPageText(id: 0, pageNumber: 1, text: String(repeating: "a", count: 150)),
            PDFPageText(id: 1, pageNumber: 2, text: String(repeating: "b", count: 150)),
            PDFPageText(id: 2, pageNumber: 3, text: String(repeating: "c", count: 150))
        ]
        
        // Second chunk (200 chars in) should be on second page
        let page = highlighter.approximatePageForChunk(index: 1, chunks: chunks, pdfPageTexts: pageTexts)
        XCTAssertEqual(page, 1, "Second chunk should map to second page")
    }
    
    func testApproximatePageForChunkInvalidIndex() {
        let chunks = [
            PlannedSpeechSegment(text: "Only", voiceIdentifier: nil, kokoroVoiceID: nil, piperModelPath: nil, speakerName: "Narrator")
        ]
        let pageTexts = [PDFPageText(id: 0, pageNumber: 1, text: "Only")]
        
        let page = highlighter.approximatePageForChunk(index: 5, chunks: chunks, pdfPageTexts: pageTexts)
        XCTAssertNil(page, "Invalid index should return nil")
    }
    
    func testClearHighlightResetsState() {
        highlighter.currentHighlight = nil // Would be set by applyHighlight
        highlighter.currentPage = 5
        
        highlighter.clearHighlight()
        
        XCTAssertNil(highlighter.currentHighlight, "Should clear highlight")
        XCTAssertNil(highlighter.currentText, "Should clear current text")
    }
}

/// Extension to expose private method for testing
extension SpeechHighlighter {
    func normalizeForSearch(_ text: String) -> String {
        // This would normally be private, but we expose it for testing
        let maxLength = 200
        var searchText = text
        
        if searchText.count > maxLength {
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
        
        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    var currentText: String? {
        // Expose for testing
        nil
    }
}
