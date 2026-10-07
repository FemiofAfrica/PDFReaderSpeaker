import XCTest
@testable import LatteReader

final class AppConfigTests: XCTestCase {
    func testFindExecutableReturnsFirstExecutableFile() {
        // Create temp directory with test files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let executable1 = tempDir.appendingPathComponent("exec1")
        let executable2 = tempDir.appendingPathComponent("exec2")
        let nonExecutable = tempDir.appendingPathComponent("notexec")
        
        FileManager.default.createFile(atPath: executable1.path, contents: Data())
        FileManager.default.createFile(atPath: executable2.path, contents: Data())
        FileManager.default.createFile(atPath: nonExecutable.path, contents: Data())
        
        // Make first two executable
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable1.path)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable2.path)
        
        let paths = [nonExecutable.path, executable1.path, executable2.path]
        let result = AppConfig.findExecutable(in: paths)
        
        XCTAssertEqual(result, executable1.path, "Should return first executable file")
    }
    
    func testFindExecutableReturnsNilWhenNoneExecutable() {
        let paths = ["/nonexistent/path1", "/nonexistent/path2"]
        let result = AppConfig.findExecutable(in: paths)
        XCTAssertNil(result, "Should return nil when no executable found")
    }
    
    func testConfigurationConstants() {
        XCTAssertEqual(AppConfig.progressTimerInterval, 0.25)
        XCTAssertEqual(AppConfig.chunkMaxLength, 3_500)
        XCTAssertEqual(AppConfig.prebufferCount, 8)
        XCTAssertEqual(AppConfig.skipBackwardSeconds, 15.0)
        XCTAssertEqual(AppConfig.skipForwardSeconds, 15.0)
    }
    
    func testKokoroWorkerPathsIncludeBundleFirst() {
        XCTAssertTrue(AppConfig.kokoroWorkerPaths.count > 0, "Should have kokoro worker paths")
        // Bundle path should be first priority if it exists
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("kokoro/kokoro-worker").path {
            XCTAssertEqual(AppConfig.kokoroWorkerPaths.first, bundlePath, "Bundle path should be first")
        }
    }
}
