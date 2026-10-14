import Foundation
import AVFoundation

/// Manages transport controls (skip back/forward) for voice engines
@MainActor
final class PlaybackControls: ObservableObject {
    @Published private(set) var canSkipBackward = false
    @Published private(set) var canSkipForward = false
    
    private weak var kokoroReader: KokoroSpeechReader?
    private weak var piperReader: KokoroSpeechReader?
    private var activeEngine: VoiceEngine = .kokoro
    
    func setEngines(kokoro: KokoroSpeechReader, piper: KokoroSpeechReader) {
        self.kokoroReader = kokoro
        self.piperReader = piper
    }
    
    func setActiveEngine(_ engine: VoiceEngine) {
        self.activeEngine = engine
        updateSkipCapabilities()
    }
    
    func updateSkipCapabilities() {
        let reader = activeEngine == .kokoro ? kokoroReader : piperReader
        canSkipBackward = (reader?.currentChunkIndex ?? 0) > 0 || (reader?.currentTime ?? 0) > 0
        canSkipForward = (reader?.currentChunkIndex ?? 0) < (reader?.totalChunks ?? 0) - 1
    }
    
    /// Skip back one sentence (chunk)
    func skipBackwardSentence() {
        guard let reader = activeEngine == .kokoro ? kokoroReader : piperReader else { return }
        if reader.currentChunkIndex > 0 {
            reader.skipToChunk(reader.currentChunkIndex - 1)
        }
        updateSkipCapabilities()
    }
    
    /// Skip forward one sentence (chunk)
    func skipForwardSentence() {
        guard let reader = activeEngine == .kokoro ? kokoroReader : piperReader else { return }
        if reader.currentChunkIndex < reader.totalChunks - 1 {
            reader.skipToChunk(reader.currentChunkIndex + 1)
        }
        updateSkipCapabilities()
    }
    
    /// Skip backward by time (15 seconds)
    func skipBackwardTime() {
        guard let reader = activeEngine == .kokoro ? kokoroReader : piperReader else { return }
        let newTime = max(0, reader.currentTime - AppConfig.skipBackwardSeconds)
        reader.seek(to: newTime)
        updateSkipCapabilities()
    }
    
    /// Skip forward by time (15 seconds)
    func skipForwardTime() {
        guard let reader = activeEngine == .kokoro ? kokoroReader : piperReader else { return }
        let newTime = min(reader.duration, reader.currentTime + AppConfig.skipForwardSeconds)
        reader.seek(to: newTime)
        updateSkipCapabilities()
    }
}
