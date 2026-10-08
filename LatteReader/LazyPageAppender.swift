import Foundation

/// Helper to append pages lazily during playback
extension ContentView {
    /// Append the next page when playback approaches the end of current segments
    func appendNextPageIfNeeded() {
        guard isPlaying,
              let pdf = documentForContinuation,
              let lastPage = lastPlayedPageIndex,
              lastPage + 1 < pdf.pageCount else {
            return
        }
        
        // Check if we're near the end of current segments (last 2 chunks)
        let currentChunkIndex: Int
        let totalChunks: Int
        
        switch selectedVoiceEngine {
        case .kokoro:
            currentChunkIndex = kokoroReader.currentChunkIndex
            totalChunks = kokoroReader.totalChunks
        case .piper:
            currentChunkIndex = piperReader.currentChunkIndex
            totalChunks = piperReader.totalChunks
        }
        
        // If we're within 2 chunks of the end, append next page
        guard totalChunks - currentChunkIndex <= 2 else {
            // Not near end yet, check again in 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.appendNextPageIfNeeded()
            }
            return
        }
        
        NSLog("[LatteTiming] Appending page \(lastPage + 2) lazily (chunk \(currentChunkIndex + 1)/\(totalChunks))")
        let nextPageStartTime = CFAbsoluteTimeGetCurrent()
        
        // Get next page text
        let nextPageText = textFromPage(lastPage + 1, through: lastPage + 1, in: pdf)
        guard !nextPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Page is empty, try next one
            lastPlayedPageIndex = lastPage + 1
            appendNextPageIfNeeded()
            return
        }
        
        NSLog("[LatteTiming] Next page text extracted (\(nextPageText.count) chars) in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - nextPageStartTime))s")
        
        // Build segments for next page
        let segments = buildSegments(for: nextPageText, pdf: pdf, startPage: lastPage + 1)
        
        NSLog("[LatteTiming] Next page segments built (\(segments.count) segments) in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - nextPageStartTime))s")
        
        // Append to engine
        switch selectedVoiceEngine {
        case .kokoro:
            kokoroReader.append(segments: segments)
        case .piper:
            piperReader.append(segments: segments)
        }
        
        NSLog("[LatteTiming] Next page appended in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - nextPageStartTime))s")
        
        // Update last played page
        lastPlayedPageIndex = lastPage + 1
        
        // Continue checking for more pages
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.appendNextPageIfNeeded()
        }
    }
}
