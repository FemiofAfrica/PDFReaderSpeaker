import Foundation

public enum PagePromptLocator {
    /// Returns PagePrompt beside the running LatteReader executable.
    /// SwiftPM build products and app-bundle helper executables both use this layout.
    public static func executableURL(relativeTo mainExecutableURL: URL? = Bundle.main.executableURL) -> URL? {
        mainExecutableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("PagePrompt", isDirectory: false)
    }
}