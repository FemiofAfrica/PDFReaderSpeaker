import Foundation

// MARK: - Speech Engine

/// Common interface for all TTS engines (system, Piper, Kokoro).
///
/// Each concrete engine has its own `start()` signature since the
/// parameters differ (segments vs text+rate+voice). The shared surface
/// covers transport control and state that the UI layer needs.
@MainActor
protocol SpeechEngine: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var currentChunkIndex: Int { get }
    var totalChunks: Int { get }
    var status: String { get }

    func pauseOrContinue()
    func stop()
}

// MARK: - Voice Synthesizer

/// Low-level voice synthesis — turns a single text segment into a WAV file.
///
/// Separates the *what* (synthesis) from the *how* (playback orchestration
/// in `KokoroSpeechReader`). Both Kokoro and Piper adapters satisfy this seam.
protocol VoiceSynthesizer {
    var availability: VoiceEngineAvailability { get }
    func synthesize(segment: PlannedSpeechSegment, outputURL: URL) throws
}

/// Lightweight value type carrying availability info.
/// `VoiceEngineAvailability` is already defined in `VoiceEngines.swift`.
