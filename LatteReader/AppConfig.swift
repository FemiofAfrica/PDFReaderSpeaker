import Foundation

/// Centralized configuration for LatteReader.
///
/// Resolves paths to bundled resources first, then falls back to
/// system-wide or user-local installations. Never hardcodes machine-specific paths.
enum AppConfig {
    // MARK: - Voice Engine Paths
    
    /// Kokoro worker executable candidates, checked in order
    static let kokoroWorkerPaths: [String] = [
        // Bundled first (for packaged .app)
        Bundle.main.resourceURL?.appendingPathComponent("kokoro/kokoro-worker").path,
        // User-local support directory
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LatteReader/kokoro/kokoro-worker").path,
        // User bin
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/kokoro-worker").path,
        // System paths
        "/opt/homebrew/bin/kokoro-worker",
        "/usr/local/bin/kokoro-worker"
    ].compactMap { $0 }
    
    /// Piper executable candidates
    static let piperExecutablePaths: [String] = [
        Bundle.main.resourceURL?.appendingPathComponent("piper/piper").path,
        "/opt/homebrew/bin/piper",
        "/usr/local/bin/piper"
    ].compactMap { $0 }
    
    // MARK: - Playback
    
    static let progressTimerInterval: TimeInterval = 0.25
    static let chunkMaxLength = 3_500
    static let prebufferCount = 8
    static let workerProcessTimeout: TimeInterval = 30.0
    
    // MARK: - Transport
    
    static let skipBackwardSeconds: TimeInterval = 15.0
    static let skipForwardSeconds: TimeInterval = 15.0
    
    // MARK: - Helpers
    
    /// Find first executable file in the candidate list
    static func findExecutable(in paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile)
    }
}
