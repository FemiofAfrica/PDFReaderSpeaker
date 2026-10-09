import XCTest
@testable import LatteReader

final class TextRepairTests: XCTestCase {
    
    // MARK: - Ligature Tests
    
    func testLigatureFi() {
        // Missing 'fi' ligatures
        XCTAssertTrue(TextRepair.repair("police o cers").contains("officers"))
        XCTAssertTrue(TextRepair.repair("they  nd on the ground").contains("find"))
        XCTAssertTrue(TextRepair.repair("tropical  sh").contains("fish"))
        XCTAssertTrue(TextRepair.repair("to  gure out how we can a ord").contains("figure"))
        XCTAssertTrue(TextRepair.repair("in ation rates").contains("inflation"))
        XCTAssertTrue(TextRepair.repair("the  rst door").contains("first"))
        XCTAssertTrue(TextRepair.repair(" tness").contains("fitness"))
        XCTAssertTrue(TextRepair.repair("classi ed").contains("classified"))
        XCTAssertTrue(TextRepair.repair("her  ngers").contains("fingers"))
        XCTAssertTrue(TextRepair.repair("past  fteen").contains("fifteen"))
    }
    
    func testLigatureFf() {
        // Missing 'ff' ligatures
        XCTAssertTrue(TextRepair.repair("to o er").contains("offer"))
        XCTAssertTrue(TextRepair.repair("drift o  and").contains("off"))
        XCTAssertTrue(TextRepair.repair("idiotically di cult").contains("difficult"))
        XCTAssertTrue(TextRepair.repair("to  gure out how we can a ord").contains("afford"))
    }
    
    func testLigatureFl() {
        // Missing 'fl' ligatures
        XCTAssertTrue(TextRepair.repair("bank robber  ed").contains("fled"))
        XCTAssertTrue(TextRepair.repair("the top  oor").contains("floor"))
    }
    
    func testLigatureFfi() {
        // Missing 'ffi' ligatures
        XCTAssertTrue(TextRepair.repair("tra c").contains("traffic") || TextRepair.repair("tra c").contains("trafic"))
        XCTAssertTrue(TextRepair.repair("o cial").contains("official"))
    }
    
    func testLigatureFfl() {
        // Missing 'ffl' ligatures
        XCTAssertTrue(TextRepair.repair("ba ed").contains("baffled") || TextRepair.repair("ba ed").contains("bafled"))
        XCTAssertTrue(TextRepair.repair("sca old").contains("scaffold"))
    }
    
    // MARK: - Apostrophe Tests
    
    func testApostrophes() {
        XCTAssertEqual(TextRepair.repair("it' s"), "it's")
        XCTAssertEqual(TextRepair.repair("you 're"), "you're")
        XCTAssertEqual(TextRepair.repair("there ' s"), "there's")
        XCTAssertEqual(TextRepair.repair("we 're"), "we're")
        XCTAssertEqual(TextRepair.repair("he ' s"), "he's")
        XCTAssertEqual(TextRepair.repair("don 't"), "don't")
        XCTAssertEqual(TextRepair.repair("I 'm"), "I'm")
        XCTAssertEqual(TextRepair.repair("they 'll"), "they'll")
        XCTAssertEqual(TextRepair.repair("we 've"), "we've")
        XCTAssertEqual(TextRepair.repair("he 'd"), "he'd")
    }
    
    // MARK: - Quote Tests
    
    func testQuotes() {
        XCTAssertEqual(TextRepair.repair("\" amortization levels \""), "\"amortization levels\"")
        XCTAssertEqual(TextRepair.repair("rates. \" That"), "rates. \"That")
        XCTAssertTrue(TextRepair.repair("he said \" hello \"").contains("\"hello\""))
    }
    
    // MARK: - Combined Tests
    
    func testCombinedIssues() {
        // Test sentence with both ligature and apostrophe issues
        let input = "The police o cers couldn 't  nd the  rst clue on the top  oor."
        let output = TextRepair.repair(input)
        XCTAssertTrue(output.contains("officers"))
        XCTAssertTrue(output.contains("couldn't"))
        XCTAssertTrue(output.contains("find"))
        XCTAssertTrue(output.contains("first"))
        XCTAssertTrue(output.contains("floor"))
    }
    
    func testPreservesCorrectText() {
        // Ensure repair doesn't break already correct text
        let correct = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(TextRepair.repair(correct), correct)
    }
}
