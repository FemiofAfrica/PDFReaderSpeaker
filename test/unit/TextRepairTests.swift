import XCTest
@testable import LatteReader

final class TextRepairTests: XCTestCase {
    
    // MARK: - Ligature Tests (U+0000 = \u{0})
    
    func testLigatureFi() {
        // Real samples with U+0000 (NUL character)
        XCTAssertEqual(TextRepair.repair("police o\u{0}cers"), "police officers")
        XCTAssertEqual(TextRepair.repair("they \u{0}nd on the ground"), "they find on the ground")
        XCTAssertEqual(TextRepair.repair("tropical \u{0}sh"), "tropical fish")
        XCTAssertEqual(TextRepair.repair("to \u{0}gure out"), "to figure out")
        XCTAssertEqual(TextRepair.repair("in\u{0}ation rates"), "inflation rates")
        XCTAssertEqual(TextRepair.repair("the \u{0}rst door"), "the first door")
        XCTAssertEqual(TextRepair.repair("\u{0}tness"), "fitness")
        XCTAssertEqual(TextRepair.repair("classi\u{0}ed"), "classified")
        XCTAssertEqual(TextRepair.repair("her \u{0}ngers"), "her fingers")
        XCTAssertEqual(TextRepair.repair("past \u{0}fteen"), "past fifteen")
    }
    
    func testLigatureFf() {
        // Missing 'ff' ligatures
        XCTAssertEqual(TextRepair.repair("to o\u{0}er"), "to offer")
        XCTAssertEqual(TextRepair.repair("drift o\u{0} and"), "drift off and")
        XCTAssertEqual(TextRepair.repair("idiotically di\u{0}cult"), "idiotically difficult")
        XCTAssertEqual(TextRepair.repair("we can a\u{0}ord"), "we can afford")
    }
    
    func testLigatureFl() {
        // Missing 'fl' ligatures
        XCTAssertEqual(TextRepair.repair("bank robber \u{0}ed"), "bank robber fled")
        XCTAssertEqual(TextRepair.repair("the top \u{0}oor"), "the top floor")
    }
    
    func testLigatureFfi() {
        // Missing 'ffi' ligatures
        XCTAssertTrue(TextRepair.repair("tra\u{0}c").contains("traffic"))
        XCTAssertTrue(TextRepair.repair("o\u{0}cial").contains("official"))
    }
    
    func testLigatureFfl() {
        // Missing 'ffl' ligatures
        XCTAssertTrue(TextRepair.repair("ba\u{0}ed").contains("baffled"))
        XCTAssertTrue(TextRepair.repair("sca\u{0}old").contains("scaffold"))
    }
    
    // MARK: - Apostrophe Tests (U+2019 = ' and \n)
    
    func testApostrophesWithNewlines() {
        // Real samples with U+2019 (') and newlines
        XCTAssertEqual(TextRepair.repair("it'\ns always"), "it's always")
        XCTAssertEqual(TextRepair.repair("you\n're trying"), "you're trying")
        XCTAssertEqual(TextRepair.repair("there\n'\ns such"), "there's such")
        XCTAssertEqual(TextRepair.repair("New Year'\ns Eve"), "New Year's Eve")
        XCTAssertEqual(TextRepair.repair("he\n'\ns sighing"), "he's sighing")
        XCTAssertEqual(TextRepair.repair("you\n'\nve reached"), "you've reached")
    }
    
    // MARK: - Quote Tests
    
    func testQuotesWithNewlines() {
        // Real samples with newlines around quotes
        XCTAssertEqual(TextRepair.repair("\"\namortization levels\n\""), "\"amortization levels\"")
        XCTAssertEqual(TextRepair.repair("rates.\n\" That"), "rates. \"That")
        XCTAssertEqual(TextRepair.repair("question,\n\" he pleads"), "question, \"he pleads")
    }
    
    // MARK: - Combined Tests
    
    func testCombinedIssues() {
        // Test with both U+0000 ligatures and U+2019 apostrophes with newlines
        let input = "The police o\u{0}cers couldn\n't \u{0}nd the \u{0}rst clue."
        let output = TextRepair.repair(input)
        XCTAssertTrue(output.contains("officers"))
        XCTAssertTrue(output.contains("couldn't"))
        XCTAssertTrue(output.contains("find"))
        XCTAssertTrue(output.contains("first"))
    }
    
    func testPreservesCorrectText() {
        // Ensure repair doesn't break already correct text
        let correct = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(TextRepair.repair(correct), correct)
    }
}
