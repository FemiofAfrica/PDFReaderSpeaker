import Foundation
import XCTest
@testable import PagePromptSupport

final class PagePromptLocatorTests: XCTestCase {
    func testResolvesHelperBesideRelocatedMainExecutable() throws {
        let mainExecutable = URL(fileURLWithPath: "/Volumes/External/Latte Reader/LatteReader.app/Contents/MacOS/LatteReader")

        let helper = try XCTUnwrap(PagePromptLocator.executableURL(relativeTo: mainExecutable))

        XCTAssertEqual(
            helper.path,
            "/Volumes/External/Latte Reader/LatteReader.app/Contents/MacOS/PagePrompt"
        )
        XCTAssertFalse(helper.path.contains(NSHomeDirectory()))
    }

    func testReturnsNilWithoutMainExecutable() {
        XCTAssertNil(PagePromptLocator.executableURL(relativeTo: nil))
    }
}