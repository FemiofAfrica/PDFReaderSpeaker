import Foundation
import AVFoundation

/// Tracks speech progress for both system and neural voice engines
@MainActor
protocol SpeechProgressDelegate: AnyObject {
    func speechDidStartChunk(_ index: Int, text: String, approximatePage: Int?)
    func speechDidUpdateWordRange(_ range: NSRange, in text: String)
    func speechDidFinish()
}

/// Wrapper around AVSpeechSynthesizer that provides word-level tracking
@MainActor
final class SystemVoiceSpeechTracker: NSObject {
    weak var delegate: SpeechProgressDelegate?
    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [String] = []
    private var currentChunkIndex = 0
    private var currentFullText = ""
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func startTracking(chunks: [String]) {
        self.chunks = chunks
        self.currentChunkIndex = 0
        self.currentFullText = chunks.joined(separator: " ")
    }
    
    func chunkDidStart(_ index: Int) {
        guard index < chunks.count else { return }
        currentChunkIndex = index
        delegate?.speechDidStartChunk(index, text: chunks[index], approximatePage: nil)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        chunks.removeAll()
        currentChunkIndex = 0
        currentFullText = ""
    }
}

extension SystemVoiceSpeechTracker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Calculate the range in the current chunk
            let text = utterance.speechString
            delegate?.speechDidUpdateWordRange(characterRange, in: text)
        }
    }
    
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            currentChunkIndex += 1
            if currentChunkIndex >= chunks.count {
                delegate?.speechDidFinish()
            }
        }
    }
}

/// Extension to SpeechReader for tracking integration
extension SpeechReader {
    func setupTracking(delegate: SpeechProgressDelegate, tracker: SystemVoiceSpeechTracker) {
        tracker.delegate = delegate
        // System speech reader already has delegate set up
    }
}
