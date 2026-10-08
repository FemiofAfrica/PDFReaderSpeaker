import AVFoundation
import Foundation
import OSLog

final class KokoroSpeechReader: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    // MARK: - SpeechEngine conformance

    /// 0-based index of the currently-playing segment.
    var currentChunkIndex: Int { currentIndex }
    /// Total segments in the queue (after merging).
    var totalChunks: Int { queue.count }
    /// Human-readable status.
    var status: String { isSpeaking ? "Reading chunk \(currentIndex + 1) of \(queue.count)" : isPaused ? "Paused" : "Ready" }

    private var queue: [PlannedSpeechSegment] = []
    private var currentIndex = 0
    private var player: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var tempDirectory: URL?
    private var renderedAudio: [Int: URL] = [:]
    private var renderingIndices = Set<Int>()
    private var failedIndices = Set<Int>()
    private var pendingCallbacks: [Int: [() -> Void]] = [:]
    private var generationID = UUID()
    private let renderQueue = DispatchQueue(label: "LatteReader.KokoroRender", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "LatteReader.KokoroState")
    private let primarySynthesizer: VoiceSynthesizer
    private let fallbackSynthesizer: VoiceSynthesizer
    private let logger = Logger(subsystem: "com.femiofafrica.lattereader", category: "timing")

    var availability: VoiceEngineAvailability { primarySynthesizer.availability }
    var voices: [KokoroVoice] { (primarySynthesizer as? KokoroVoiceEngine)?.availableVoices ?? [] }
    var fallbackAvailability: VoiceEngineAvailability { fallbackSynthesizer.availability }

    /// Pre-load the Kokoro model into memory so the first
    /// render call doesn't pay the model-loading penalty.
    func warmUp() {
        KokoroWorker.shared.warmUp()
    }

    init(primary: VoiceSynthesizer = KokoroVoiceEngine(), fallback: VoiceSynthesizer = PiperVoiceEngine()) {
        self.primarySynthesizer = primary
        self.fallbackSynthesizer = fallback
        super.init()
    }

    func start(segments: [PlannedSpeechSegment], rate _: Double = 1.0) {
        stop()
        enqueue(segments)
        guard !queue.isEmpty else { return }
        isSpeaking = true
        isPaused = false
        // Fast startup: only prebuffer first chunk, rest will buffer while playing
        prebuffer(from: currentIndex, count: AppConfig.initialPrebufferCount)
        playWhenReady(index: currentIndex, generationID: generationID)
    }

    /// Append more segments to the queue while playback is active.
    /// New segments are pre-buffered in the background and play
    /// seamlessly after the current queue finishes.
    func append(segments newSegments: [PlannedSpeechSegment]) {
        let merged = mergeConsecutiveSameVoice(
            newSegments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        guard !merged.isEmpty else { return }
        let startIndex = queue.count
        queue.append(contentsOf: merged)
        if isSpeaking || isPaused {
            // Prebuffer appended segments immediately to avoid gaps
            // Render at least the first segment of the new page
            let appendedCount = min(merged.count, 2)
            prebuffer(from: startIndex, count: appendedCount)
        } else {
            // Playback had finished — start playing the newly queued content.
            currentIndex = startIndex
            isSpeaking = true
            isPaused = false
            prebuffer(from: startIndex)
            playWhenReady(index: startIndex, generationID: generationID)
        }
    }

    /// Shared enqueue logic used by both start() and append().
    private func enqueue(_ segments: [PlannedSpeechSegment]) {
        queue = mergeConsecutiveSameVoice(
            segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        currentIndex = 0
        generationID = UUID()
    }

    func pauseOrContinue() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isSpeaking = false
            isPaused = true
        } else {
            player.play()
            isSpeaking = true
            isPaused = false
        }
    }

    func stop() {
        generationID = UUID()
        player?.stop()
        player = nil
        queue.removeAll()
        currentIndex = 0
        stateQueue.sync {
            renderedAudio.removeAll()
            renderingIndices.removeAll()
            failedIndices.removeAll()
            pendingCallbacks.removeAll()
        }
        isSpeaking = false
        isPaused = false
        currentTime = 0
        duration = 0
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func refreshProgress() {
        currentTime = player?.currentTime ?? 0
        duration = player?.duration ?? 0
    }
    
    /// Skip to a specific chunk index
    func skipToChunk(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        player?.stop()
        currentIndex = index
        // Bump generation to drop stale renders from old position
        generationID = UUID()
        logger.log(level: .info, "Skip: new generationID to drop stale work")
        playWhenReady(index: index, generationID: generationID)
    }
    
    /// Seek to a specific time within the current chunk
    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }

    private func playWhenReady(index: Int, generationID expectedGenerationID: UUID) {
        guard expectedGenerationID == generationID else { return }
        guard index < queue.count else {
            stop()
            return
        }

        let outputURL = stateQueue.sync { renderedAudio[index] }

        if let outputURL {
            startPlayer(outputURL: outputURL, index: index)
            return
        }

        renderSegment(at: index, generationID: expectedGenerationID) { [weak self] in
            DispatchQueue.main.async {
                self?.playWhenReady(index: index, generationID: expectedGenerationID)
            }
        }
    }

    private func startPlayer(outputURL: URL, index: Int) {
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: outputURL)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
            currentIndex = index
            duration = audioPlayer.duration
            currentTime = 0
            isSpeaking = true
            isPaused = false
            logger.log(level: .info, "Playback started (audio playing)")
            // Prebuffer next segment immediately while playing
            prebuffer(from: index + 1, count: 1)
        } catch {
            NSLog("Kokoro playback failed for segment \(index): \(error.localizedDescription)")
            currentIndex = index + 1
            playWhenReady(index: currentIndex, generationID: generationID)
        }
    }

    /// Merge adjacent segments with the same Kokoro voice, up to chunkMaxLength.
    /// This reduces render calls but prevents page-sized chunks that take 45+ seconds.
    private func mergeConsecutiveSameVoice(_ segments: [PlannedSpeechSegment]) -> [PlannedSpeechSegment] {
        guard !segments.isEmpty else { return [] }
        var merged: [PlannedSpeechSegment] = []
        var current = segments[0]
        
        for i in 1..<segments.count {
            let next = segments[i]
            let sep = current.text.last.flatMap { ".!?".contains($0) } == true ? " " : ". "
            let combined = current.text + sep + next.text
            
            // Only merge if same voice AND within chunkMaxLength
            if current.kokoroVoiceID == next.kokoroVoiceID && combined.count <= AppConfig.chunkMaxLength {
                current = PlannedSpeechSegment(
                    text: combined,
                    voiceIdentifier: current.voiceIdentifier,
                    kokoroVoiceID: current.kokoroVoiceID,
                    piperModelPath: current.piperModelPath ?? next.piperModelPath,
                    speakerName: current.speakerName
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private func prebuffer(from index: Int, count: Int? = nil) {
        let expectedGenerationID = generationID
        let bufferCount = count ?? AppConfig.backgroundPrebufferCount
        // Only prebuffer the next 1-2 segments to avoid stale work
        let limitedCount = min(bufferCount, 2)
        for nextIndex in index..<(min(index + limitedCount, queue.count)) {
            renderSegment(at: nextIndex, generationID: expectedGenerationID)
        }
    }

    private func renderSegment(at index: Int, generationID expectedGenerationID: UUID, completion: (() -> Void)? = nil) {
        // Drop stale work immediately
        guard expectedGenerationID == generationID else {
            logger.log(level: .info, "Stale job dropped before render (generation mismatch)")
            return
        }
        guard index < queue.count else { return }
        var shouldRender = false
        stateQueue.sync {
            if renderedAudio[index] == nil, !renderingIndices.contains(index), !failedIndices.contains(index) {
                renderingIndices.insert(index)
                shouldRender = true
            }
        }

        if !shouldRender {
            // Already being rendered — store the completion so it fires
            // when the render finishes, instead of busy-looping.
            if let completion {
                stateQueue.sync {
                    pendingCallbacks[index, default: []].append(completion)
                }
            }
            return
        }

        let segment = queue[index]
        renderQueue.async { [weak self] in
            guard let self else { return }
            
            do {
                let outputURL = try self.makeOutputURL(index: index)
                
                // Pass generation check closure to be evaluated AFTER lock acquisition
                let isStillCurrent = { [weak self] in
                    guard let self = self else { return false }
                    return expectedGenerationID == self.generationID
                }
                
                if primarySynthesizer.availability.isAvailable {
                    try primarySynthesizer.synthesize(segment: segment, outputURL: outputURL, isStillCurrent: isStillCurrent)
                } else {
                    logger.log(level: .info, "Kokoro unavailable, falling back to Piper")
                    try fallbackSynthesizer.synthesize(segment: segment, outputURL: outputURL, isStillCurrent: isStillCurrent)
                }
                
                // Re-check generation AFTER synthesize returns, before touching state
                guard expectedGenerationID == self.generationID else {
                    logger.log(level: .info, "Stale job completed but generation changed, discarding result")
                    self.stateQueue.sync {
                        self.renderingIndices.remove(index)
                    }
                    return
                }
                
                self.stateQueue.sync {
                    self.renderedAudio[index] = outputURL
                    self.renderingIndices.remove(index)
                    // Flush any pending callbacks that were waiting for this segment
                    let callbacks = self.pendingCallbacks.removeValue(forKey: index) ?? []
                    for cb in callbacks {
                        DispatchQueue.main.async(execute: cb)
                    }
                }
            } catch is CancellationError {
                // Job was cancelled (stale generation), don't log as failure
                self.stateQueue.sync {
                    self.renderingIndices.remove(index)
                }
            } catch {
                NSLog("Kokoro/Piper render failed for \(segment.speakerName): \(error.localizedDescription)")
                
                // Re-check generation before recording failure
                guard expectedGenerationID == self.generationID else {
                    logger.log(level: .info, "Stale job failed but generation changed, discarding")
                    self.stateQueue.sync {
                        self.renderingIndices.remove(index)
                    }
                    return
                }
                
                self.stateQueue.sync {
                    _ = self.renderingIndices.remove(index)
                    self.failedIndices.insert(index)
                    self.pendingCallbacks.removeValue(forKey: index)
                }
            }
            completion?()
        }
    }

    private func makeOutputURL(index: Int) throws -> URL {
        if tempDirectory == nil {
            tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LatteReader-Kokoro-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory!, withIntermediateDirectories: true)
        }
        return tempDirectory!.appendingPathComponent("segment-\(index).wav")
    }


}

extension KokoroSpeechReader: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        let nextIndex = currentIndex + 1
        currentIndex = nextIndex
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playWhenReady(index: nextIndex, generationID: self.generationID)
        }
    }
}
