import AVFoundation
import Foundation

@MainActor
final class SpeechReader: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentChunkIndex = 0
    @Published private(set) var totalChunks = 0
    @Published private(set) var status = "Ready"

    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [String] = []
    private var selectedVoiceIdentifier: String?
    private var selectedRate: Float = AVSpeechUtteranceDefaultSpeechRate
    /// Set true during a restart so didCancel doesn't reset speaking state.
    private var isRestarting = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { lhs, rhs in
                if lhs.language == rhs.language {
                    return lhs.name < rhs.name
                }
                return lhs.language < rhs.language
            }
    }

    func start(text: String, rate: Double, voiceIdentifier: String?) {
        stop()
        selectedRate = Float(rate)
        selectedVoiceIdentifier = voiceIdentifier
        chunks = Self.chunk(text: text)
        totalChunks = chunks.count
        currentChunkIndex = 0

        guard !chunks.isEmpty else {
            status = "No text available to read."
            return
        }

        isSpeaking = true
        isPaused = false
        status = "Reading chunk 1 of \(totalChunks)"
        speakCurrentChunk()
    }

    /// Restart the **current** chunk with new voice/rate settings.
    /// Called when the user changes voice or speed while speech is active.
    func restartCurrentChunk(rate: Double, voiceIdentifier: String?) {
        guard isSpeaking || isPaused else { return }
        guard chunks.indices.contains(currentChunkIndex) else { return }

        selectedRate = Float(rate)
        selectedVoiceIdentifier = voiceIdentifier
        isRestarting = true
        synthesizer.stopSpeaking(at: .immediate)

        // Speak the current chunk again on the next cycle, after
        // didCancel has had a chance to fire and check the flag.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRestarting = false
            isSpeaking = true
            isPaused = false
            status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
            speakCurrentChunk()
        }
    }

    func pauseOrContinue() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
        } else if isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            status = "Paused"
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        chunks.removeAll()
        isSpeaking = false
        isPaused = false
        currentChunkIndex = 0
        totalChunks = 0
        status = "Ready"
    }

    private func speakCurrentChunk() {
        guard chunks.indices.contains(currentChunkIndex) else {
            finish()
            return
        }

        let utterance = AVSpeechUtterance(string: chunks[currentChunkIndex])
        utterance.rate = selectedRate
        if let selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    private func finish() {
        isSpeaking = false
        isPaused = false
        status = "Finished reading"
    }

    private static func chunk(text: String, maxLength: Int = 3_500) -> [String] {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }

        var output: [String] = []
        var current = ""
        let sentences = cleanText.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let candidate = current.isEmpty ? trimmed : current + ". " + trimmed

            if candidate.count > maxLength {
                if !current.isEmpty { output.append(current) }
                current = trimmed
            } else {
                current = candidate
            }
        }

        if !current.isEmpty { output.append(current) }
        return output
    }
}

extension SpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            currentChunkIndex += 1
            if currentChunkIndex < chunks.count {
                status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
                speakCurrentChunk()
            } else {
                finish()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Skip state reset during a restart — restartCurrentChunk
            // will set the correct state itself.
            guard !isRestarting else { return }
            if !chunks.isEmpty {
                isSpeaking = false
                isPaused = false
            }
        }
    }
}
