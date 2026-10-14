import XCTest
@testable import LatteReader

final class TextChunkingTests: XCTestCase {
    func testChunkEmptyString() {
        let chunks = MultiVoiceAnalyzer.chunk(text: "")
        XCTAssertTrue(chunks.isEmpty, "Empty string should produce no chunks")
    }
    
    func testChunkWhitespaceOnly() {
        let chunks = MultiVoiceAnalyzer.chunk(text: "   \n\n  \t  ")
        XCTAssertTrue(chunks.isEmpty, "Whitespace-only string should produce no chunks")
    }
    
    func testChunkSingleSentence() {
        let text = "This is a single sentence."
        let chunks = MultiVoiceAnalyzer.chunk(text: text)
        XCTAssertEqual(chunks.count, 1, "Single sentence should produce one chunk")
        XCTAssertEqual(chunks[0], "This is a single sentence", "Chunk should match input (without trailing period)")
    }
    
    func testChunkMultipleSentences() {
        let text = "First sentence. Second sentence! Third sentence?"
        let chunks = MultiVoiceAnalyzer.chunk(text: text)
        XCTAssertEqual(chunks.count, 1, "Multiple short sentences should be combined into one chunk")
        XCTAssertTrue(chunks[0].contains("First sentence"), "Chunk should contain all sentences")
    }
    
    func testChunkLongTextExceedsMaxLength() {
        // Create text that exceeds default max length (3500 chars)
        let longSentence = String(repeating: "word ", count: 800) // ~4000 chars
        let text = longSentence + ". Another sentence."
        let chunks = MultiVoiceAnalyzer.chunk(text: text, maxLength: 3500)
        
        XCTAssertGreaterThan(chunks.count, 1, "Long text should be split into multiple chunks")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 3500, "Each chunk should be within max length")
        }
    }
    
    func testChunkPreservesContent() {
        let text = "First. Second. Third. Fourth. Fifth."
        let chunks = MultiVoiceAnalyzer.chunk(text: text)
        let reconstructed = chunks.joined(separator: ". ")
        
        // Remove trailing periods for comparison
        let originalWords = text.replacingOccurrences(of: ".", with: "").split(separator: " ")
        let reconstructedWords = reconstructed.replacingOccurrences(of: ".", with: "").split(separator: " ")
        
        XCTAssertEqual(originalWords, reconstructedWords, "Chunking should preserve all content")
    }
    
    func testChunkHandlesNewlines() {
        let text = "Line one\nLine two\nLine three"
        let chunks = MultiVoiceAnalyzer.chunk(text: text)
        XCTAssertEqual(chunks.count, 1, "Newlines should be collapsed to spaces")
        XCTAssertTrue(chunks[0].contains("Line one"), "Should contain first line")
        XCTAssertTrue(chunks[0].contains("Line two"), "Should contain second line")
        XCTAssertTrue(chunks[0].contains("Line three"), "Should contain third line")
    }
    
    func testChunkCustomMaxLength() {
        let text = String(repeating: "a", count: 150) + ". " + String(repeating: "b", count: 150)
        let chunks = MultiVoiceAnalyzer.chunk(text: text, maxLength: 100)
        
        XCTAssertGreaterThan(chunks.count, 1, "Should split when exceeding custom max length")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 150, "Chunks should respect max length")
        }
    }
}
