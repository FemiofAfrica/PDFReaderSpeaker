import AVFoundation
import Foundation

/// Neural TTS engine backed by Piper (local, on-device).
///
/// Generates WAV audio via the `piper` CLI for each chunk and plays
/// it with `AVAudioPlayer`. Runs audio generation on a background
/// thread so the UI stays responsive.
@MainActor
final class PiperSpeechReader: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentChunkIndex = 0
    @Published private(set) var totalChunks = 0
    @Published private(set) var status = "Ready"

    // MARK: - Seek / progress
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    init(modelPath: String? = nil, lengthScale: Double = 1.1, noiseScale: Double = 0.5, noiseWScale: Double = 0.6) {
        self.modelPath = modelPath ?? Self.defaultModelPath
        self.lengthScale = lengthScale
        self.noiseScale = noiseScale
        self.noiseWScale = noiseWScale
        super.init()
    }

    private let modelPath: String
    private let lengthScale: Double
    private let noiseScale: Double
    private let noiseWScale: Double
    private var chunks: [String] = []
    private var player: AVAudioPlayer?
    private var isRestarting = false
    private var progressTimer: Timer?

    /// Path to the Piper ONNX voice model.
    private static let defaultModelPath = NSHomeDirectory()
        + "/Library/Application Support/piper-voices/en_US-lessac-medium.onnx"

    // MARK: - Public API

    func start(text: String, rate _: Double = 1.0, voiceIdentifier _: String? = nil) {
        stop()
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

    func pauseOrContinue() {
        if isPaused {
            player?.play()
            isPaused = false
            status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
            startProgressTimer()
        } else if isSpeaking {
            player?.pause()
            isPaused = true
            status = "Paused"
            stopProgressTimer()
        }
    }

    func stop() {
        stopProgressTimer()
        player?.stop()
        player = nil
        chunks.removeAll()
        isSpeaking = false
        isPaused = false
        currentChunkIndex = 0
        totalChunks = 0
        currentTime = 0
        duration = 0
        status = "Ready"
    }

    /// Seek to a time within the current chunk.
    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }

    /// Restart the current chunk — called when settings change mid-speech.
    func restartCurrentChunk(rate _: Double = 1.0, voiceIdentifier _: String? = nil) {
        guard isSpeaking || isPaused else { return }
        guard chunks.indices.contains(currentChunkIndex) else { return }

        isRestarting = true
        stopProgressTimer()
        player?.stop()
        player = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRestarting = false
            isSpeaking = true
            isPaused = false
            status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
            speakCurrentChunk()
        }
    }

    // MARK: - Internal

    private func speakCurrentChunk() {
        guard chunks.indices.contains(currentChunkIndex) else {
            finish()
            return
        }

        let text = chunks[currentChunkIndex]
        status = "Generating audio…"

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            guard let wavData = generateWav(for: text) else {
                DispatchQueue.main.async {
                    self.status = "Audio generation failed"
                    self.stop()
                }
                return
            }

            DispatchQueue.main.async {
                guard self.isSpeaking, !self.isPaused else { return }
                do {
                    let player = try AVAudioPlayer(data: wavData)
                    player.delegate = self
                    player.prepareToPlay()
                    player.play()
                    self.player = player
                    self.duration = player.duration
                    self.currentTime = 0
                    self.status = "Reading chunk \(self.currentChunkIndex + 1) of \(self.totalChunks)"
                    self.startProgressTimer()
                } catch {
                    self.status = "Playback error: \(error.localizedDescription)"
                    self.stop()
                }
            }
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, player.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private nonisolated func generateWav(for text: String) -> Data? {
        let tmp = FileManager.default.temporaryDirectory
        let inputURL = tmp.appendingPathComponent("piper_in_\(UUID().uuidString).txt")
        let outputURL = tmp.appendingPathComponent("piper_out_\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try text.write(to: inputURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Piper: failed to write input file: \(error.localizedDescription)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/piper")
        process.arguments = [
            "--model", modelPath,
            "--input-file", inputURL.path,
            "--output-file", outputURL.path,
            "--length-scale", "\(lengthScale)",
            "--noise-scale", "\(noiseScale)",
            "--noise-w-scale", "\(noiseWScale)",
            "--sentence-silence", "0.3",
        ]

        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()

            // Wait with a 30-second timeout so the app never hangs forever
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }

            if group.wait(timeout: .now() + 30) == .timedOut {
                process.terminate()
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    ?? "timed out after 30s"
                NSLog("Piper: \(err)")
                return nil
            }

            guard process.terminationStatus == 0 else {
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    ?? "exit \(process.terminationStatus)"
                NSLog("Piper error: \(err)")
                return nil
            }

            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                NSLog("Piper: no output file at \(outputURL.path)")
                return nil
            }

            return try Data(contentsOf: outputURL)
        } catch {
            NSLog("Piper process error: \(error.localizedDescription)")
            return nil
        }
    }

    private func finish() {
        stopProgressTimer()
        isSpeaking = false
        isPaused = false
        player = nil
        currentTime = 0
        duration = 0
        status = "Finished reading"
    }

    /// Same chunking strategy as SpeechReader.
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

// MARK: - AVAudioPlayerDelegate

extension PiperSpeechReader: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            guard !isRestarting else { return }
            stopProgressTimer()
            currentChunkIndex += 1
            if currentChunkIndex < chunks.count {
                status = "Reading chunk \(currentChunkIndex + 1) of \(totalChunks)"
                speakCurrentChunk()
            } else {
                finish()
            }
        }
    }
}
