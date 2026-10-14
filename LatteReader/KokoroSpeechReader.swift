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
    private var jobInFlight = false
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
        enqueue(segments, preserveFirstSegment: true)
        guard !queue.isEmpty else { return }
        isSpeaking = true
        isPaused = false
        logger.notice("Rendering chunk 0 (start)")
        playWhenReady(index: currentIndex, generationID: generationID)
        fillRenderPipeline()
    }

    /// Append more segments to the queue while playback is active.
    /// New segments are pre-buffered in the background and play
    /// seamlessly after the current queue finishes.
    func append(segments newSegments: [PlannedSpeechSegment]) {
        let merged = mergeConsecutiveSameVoice(
            newSegments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        guard !merged.isEmpty else { return }
        queue.append(contentsOf: merged)
        logger.notice("Appended \(merged.count, privacy: .public) segments (total \(self.queue.count, privacy: .public))")
        fillRenderPipeline()
    }

    /// Shared enqueue logic used by both start() and append().
    private func enqueue(_ segments: [PlannedSpeechSegment], preserveFirstSegment: Bool = false) {
        queue = mergeConsecutiveSameVoice(
            segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            preserveFirstSegment: preserveFirstSegment
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
        // Bump generation first to invalidate in-flight renders
        generationID = UUID()
        logger.notice("Stop: new generationID to drop stale work")
        
        // If there's a job in flight at the worker, terminate process immediately
        let hasJobInFlight = stateQueue.sync { jobInFlight }
        if hasJobInFlight {
            logger.notice("Killed in-flight stale job, terminating worker")
            KokoroWorker.shared.terminateWorkerProcess()
            stateQueue.sync { jobInFlight = false }
        }
        
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
        
        // Check if there's an in-flight job and if it's before the target
        let (hasJobInFlight, inFlightIndex) = stateQueue.sync { 
            (jobInFlight, renderingIndices.min())
        }
        
        if hasJobInFlight, let inFlightIdx = inFlightIndex, inFlightIdx < index {
            // In-flight job is before target, kill it
            logger.notice("Skip: in-flight job at chunk \(inFlightIdx, privacy: .public) is before target \(index, privacy: .public), killing worker")
            KokoroWorker.shared.terminateWorkerProcess()
            stateQueue.sync { jobInFlight = false }
            generationID = UUID()
        } else {
            logger.notice("Skip to chunk \(index, privacy: .public): keeping useful in-flight work")
        }
        
        // Enqueue target and read-ahead
        logger.notice("Rendering chunk \(index, privacy: .public) (skip target)")
        playWhenReady(index: index, generationID: generationID)
        fillRenderPipeline()
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
            logger.notice("Playback started: chunk \(index, privacy: .public)")
            // Fill the render pipeline to keep worker busy
            fillRenderPipeline()
        } catch {
            NSLog("Kokoro playback failed for segment \(index): \(error.localizedDescription)")
            currentIndex = index + 1
            playWhenReady(index: currentIndex, generationID: generationID)
        }
    }

    /// Merge adjacent segments with the same Kokoro voice, up to chunkMaxLength.
    /// This reduces render calls but prevents page-sized chunks that take 45+ seconds.
    private func mergeConsecutiveSameVoice(_ segments: [PlannedSpeechSegment], preserveFirstSegment: Bool = false) -> [PlannedSpeechSegment] {
        guard !segments.isEmpty else { return [] }
        var merged: [PlannedSpeechSegment] = []
        var current = segments[0]
        
        for i in 1..<segments.count {
            let next = segments[i]
            let sep = current.text.last.flatMap { ".!?".contains($0) } == true ? " " : ". "
            let combined = current.text + sep + next.text
            
            // Don't merge into or out of segment 0 when preserveFirstSegment is true (fast startup)
            let isFirstSegment = merged.isEmpty
            let canMergeFirst = !preserveFirstSegment || !isFirstSegment
            
            // Only merge if same voice AND within chunkMaxLength AND allowed to merge first
            if canMergeFirst && current.kokoroVoiceID == next.kokoroVoiceID && combined.count <= AppConfig.chunkMaxLength {
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

    /// Fill the render pipeline to keep the worker busy continuously.
    /// Renders up to 3 segments ahead of the playhead when the worker is idle.
    private func fillRenderPipeline() {
        let (rendered, rendering) = stateQueue.sync {
            (self.renderedAudio.keys.sorted(), self.renderingIndices.sorted())
        }
        
        // Count RENDERED (not in-flight) segments ahead of current position
        let renderedAhead = rendered.filter { $0 > self.currentIndex }.count
        
        // Keep rendering until we have 3 rendered segments ahead
        // Don't count in-flight work as "buffered" since it's not ready to play
        while renderedAhead < 3 {
            let allRenderedOrRendering = Set(rendered).union(rendering)
            
            // Find first unrendered segment starting from current index
            var foundSegment = false
            for i in self.currentIndex..<self.queue.count {
                if !allRenderedOrRendering.contains(i) {
                    self.renderSegment(at: i, generationID: self.generationID, completion: nil)
                    foundSegment = true
                    break
                }
            }
            
            // If no more segments to render, we're done
            if !foundSegment {
                break
            }
            
            // Re-check rendered count after starting a new render
            let newRendered = stateQueue.sync { self.renderedAudio.keys.sorted() }
            let newRenderedAhead = newRendered.filter { $0 > self.currentIndex }.count
            
            // If count didn't increase, we started an in-flight job, keep going
            if newRenderedAhead <= renderedAhead {
                continue
            } else {
                break
            }
        }
    }

    private func renderSegment(at index: Int, generationID expectedGenerationID: UUID, completion: (() -> Void)? = nil) {
        // Drop stale work immediately
        guard expectedGenerationID == generationID else {
            logger.notice("Stale job dropped before render (generation mismatch)")
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
                
                // Mark job in flight before calling worker
                self.stateQueue.sync { self.jobInFlight = true }
                
                if primarySynthesizer.availability.isAvailable {
                    try primarySynthesizer.synthesize(segment: segment, outputURL: outputURL, isStillCurrent: isStillCurrent)
                } else {
                    logger.notice("Kokoro unavailable, falling back to Piper")
                    try fallbackSynthesizer.synthesize(segment: segment, outputURL: outputURL, isStillCurrent: isStillCurrent)
                }
                
                // Job returned, clear in-flight flag
                self.stateQueue.sync { self.jobInFlight = false }
                
                // Re-check generation AFTER synthesize returns, before touching state
                guard expectedGenerationID == self.generationID else {
                    logger.notice("Stale job completed but generation changed, discarding result")
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
                    self.jobInFlight = false
                    self.renderingIndices.remove(index)
                }
            } catch {
                self.stateQueue.sync { self.jobInFlight = false }
                NSLog("Kokoro/Piper render failed for \(segment.speakerName): \(error.localizedDescription)")
                
                // Re-check generation before recording failure
                guard expectedGenerationID == self.generationID else {
                    logger.notice("Stale job failed but generation changed, discarding")
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
