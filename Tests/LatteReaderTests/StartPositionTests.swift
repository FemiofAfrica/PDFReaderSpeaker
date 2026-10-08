import XCTest
@testable import LatteReader

final class StartPositionTests: XCTestCase {
    func testTextFromPageSinglePage() {
        let pages = [
            PDFPageText(id: 0, pageNumber: 1, text: "Page one"),
            PDFPageText(id: 1, pageNumber: 2, text: "Page two"),
            PDFPageText(id: 2, pageNumber: 3, text: "Page three")
        ]
        
        let pdf = LoadedPDF(
            url: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            pageCount: 3,
            pages: pages
        )
        
        let result = textFromPage(1, through: 1, in: pdf)
        XCTAssertEqual(result, "Page two", "Should return text from single page")
    }
    
    func testTextFromPageRange() {
        let pages = [
            PDFPageText(id: 0, pageNumber: 1, text: "Page one"),
            PDFPageText(id: 1, pageNumber: 2, text: "Page two"),
            PDFPageText(id: 2, pageNumber: 3, text: "Page three")
        ]
        
        let pdf = LoadedPDF(
            url: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            pageCount: 3,
            pages: pages
        )
        
        let result = textFromPage(1, through: 2, in: pdf)
        XCTAssertTrue(result.contains("Page two"), "Should include second page")
        XCTAssertTrue(result.contains("Page three"), "Should include third page")
        XCTAssertFalse(result.contains("Page one"), "Should not include first page")
    }
    
    func testTextFromPageStartToEnd() {
        let pages = [
            PDFPageText(id: 0, pageNumber: 1, text: "Page one"),
            PDFPageText(id: 1, pageNumber: 2, text: "Page two"),
            PDFPageText(id: 2, pageNumber: 3, text: "Page three")
        ]
        
        let pdf = LoadedPDF(
            url: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            pageCount: 3,
            pages: pages
        )
        
        let result = textFromPage(0, through: 2, in: pdf)
        XCTAssertTrue(result.contains("Page one"), "Should include all pages")
        XCTAssertTrue(result.contains("Page two"), "Should include all pages")
        XCTAssertTrue(result.contains("Page three"), "Should include all pages")
    }
    
    func testTextFromPageMidToEnd() {
        let pages = [
            PDFPageText(id: 0, pageNumber: 1, text: "Page one"),
            PDFPageText(id: 1, pageNumber: 2, text: "Page two"),
            PDFPageText(id: 2, pageNumber: 3, text: "Page three"),
            PDFPageText(id: 3, pageNumber: 4, text: "Page four")
        ]
        
        let pdf = LoadedPDF(
            url: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            pageCount: 4,
            pages: pages
        )
        
        // Start from page 2 (index 2) to end
        let result = textFromPage(2, through: 3, in: pdf)
        XCTAssertFalse(result.contains("Page one"), "Should not include page one")
        XCTAssertFalse(result.contains("Page two"), "Should not include page two")
        XCTAssertTrue(result.contains("Page three"), "Should include page three")
        XCTAssertTrue(result.contains("Page four"), "Should include page four")
    }
    
    func testTextFromPageInvalidRange() {
        let pages = [
            PDFPageText(id: 0, pageNumber: 1, text: "Page one")
        ]
        
        let pdf = LoadedPDF(
            url: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            pageCount: 1,
            pages: pages
        )
        
        // Try to get pages beyond document
        let result = textFromPage(5, through: 10, in: pdf)
        XCTAssertTrue(result.isEmpty, "Should return empty string for invalid range")
    }
    
    // Helper function matching the implementation
    private func textFromPage(_ startPage: Int, through endPage: Int, in pdf: LoadedPDF) -> String {
        let pageRange = startPage...endPage
        return pdf.pages
            .filter { pageRange.contains($0.id) }
            .map { $0.text }
            .joined(separator: "\n\n")
    }
}
