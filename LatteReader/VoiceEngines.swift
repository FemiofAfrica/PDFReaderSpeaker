import Foundation
import OSLog

struct CancellationError: Error {}

struct VoiceEngineAvailability: Hashable {
    let isAvailable: Bool
    let message: String
}

struct KokoroVoice: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let path: String
}

enum LocalVoiceAssetLocator {
    static var kokoroRoots: [URL] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LatteReader/kokoro", isDirectory: true)
        let legacySupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kokoro-voices", isDirectory: true)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("kokoro", isDirectory: true)
        return [support, legacySupport, bundled].compactMap { $0 }
    }

    static var piperRoots: [URL] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/piper-voices", isDirectory: true)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("piper-voices", isDirectory: true)
        return [support, bundled].compactMap { $0 }
    }

    static func onnxFiles(in roots: [URL]) -> [URL] {
        roots.flatMap { root -> [URL] in
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { item in
                guard let url = item as? URL, url.pathExtension.lowercased() == "onnx" else { return nil }
                return url
            }
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

final class KokoroWorker {
    static let shared = KokoroWorker()

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private let logger = Logger(subsystem: "com.femiofafrica.lattereader", category: "timing")

    private var executablePath: String? {
        AppConfig.findExecutable(in: AppConfig.kokoroWorkerPaths)
    }

    var isAvailable: Bool { executablePath != nil }

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL, isStillCurrent: () -> Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureStarted()
        
        // Check generation AFTER acquiring lock to drop stale work
        guard isStillCurrent() else {
            logger.notice("Stale job dropped after lock (segment no longer current)")
            throw CancellationError()
        }
        
        guard let input, let output else { throw CocoaError(.executableLoad) }

        let payload: [String: Any] = [
            "text": Self.prepareTextForSpeech(segment.text),
            "output": outputURL.path,
            "voice": segment.kokoroVoiceID ?? "af_heart",
            "speed": 1.0,
            "lang": "en-us"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        logger.notice("Job written to worker stdin (\(segment.text.prefix(50), privacy: .public)...)")
        input.write(data)
        input.write(Data("\n".utf8))
        
        // Job is now in flight at the worker

        guard let line = output.readLine(),
              let responseData = line.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              response["ok"] as? Bool == true,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            logger.log(level: .error, "Worker response failed, restarting")
            restart(reason: "Bad response or missing output file")
            throw CocoaError(.executableLoad)
        }
        
        logger.notice("Audio ready from worker")
    }

    private static func prepareTextForSpeech(_ text: String) -> String {
        // Collapse consecutive newlines into a single paragraph break.
        // Single newlines (word-wrapping) become a space so Kokoro
        // doesn't insert a prosodic pause at every PDF line break.
        text
            .replacingOccurrences(of: "\n\n\n+", with: ". ", options: .regularExpression)
            .replacingOccurrences(of: "\n\n", with: ". ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    func warmUp() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            do {
                try ensureStarted()
                // Send a tiny ping render to force model loading and keep worker warm.
                guard let input, let output else { return }
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("kokoro-warmup-\(UUID().uuidString).wav")
                let ping: [String: Any] = [
                    "text": "Warming up.",
                    "output": outputPath.path,
                    "voice": "af_heart",
                    "speed": 1.0,
                    "lang": "en-us",
                ]
                let data = try JSONSerialization.data(withJSONObject: ping)
                input.write(data)
                input.write(Data("\n".utf8))
                
                // Wait for response to ensure model is loaded
                if let response = output.readLine() {
                    NSLog("Kokoro worker warmed up: \(response)")
                }
                try? FileManager.default.removeItem(at: outputPath)
            } catch {
                NSLog("Kokoro warm-up failed: \(error)")
            }
        }
    }
    
    /// Keep worker warm by preventing it from shutting down
    func keepWarm() {
        // The worker stays persistent as long as the process is running
        // This just ensures it's started
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            _ = try? ensureStarted()
        }
    }

    private     func ensureStarted() throws {
        if let process, process.isRunning { return }
        guard let executablePath else { throw CocoaError(.fileNoSuchFile) }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        // Use DispatchGroup for timeout instead of process.waitUntilExit
        let startGroup = DispatchGroup()
        startGroup.enter()
        
        try process.run()

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading

        // Read ready line with timeout
        var readyLine: String?
        DispatchQueue.global().async {
            readyLine = self.output?.readLine()
            startGroup.leave()
        }
        
        // Increased timeout from 5s to 30s for cold model loading on busy CPU
        if startGroup.wait(timeout: .now() + 30.0) == .timedOut || !(readyLine?.contains("ready") ?? false) {
            let reason = startGroup.wait(timeout: .now()) == .timedOut ? "Ready timeout (30s)" : "No ready line"
            logger.log(level: .error, "Worker startup failed: \(reason, privacy: .public)")
            restart(reason: reason)
            throw CocoaError(.executableLoad)
        }
        
        logger.notice("Worker started and ready")
    }

    private func restart(reason: String) {
        logger.notice("Restarting worker: \(reason, privacy: .public)")
        try? input?.close()
        if let process, process.isRunning {
            process.terminate()
            // Wait briefly for graceful termination
            let terminateGroup = DispatchGroup()
            terminateGroup.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                terminateGroup.leave()
            }
            // Force kill if it doesn't terminate within 2 seconds
            if terminateGroup.wait(timeout: .now() + 2.0) == .timedOut {
                process.interrupt()
            }
        }
        process = nil
        input = nil
        output = nil
    }
    
    /// Terminate the worker process immediately without waiting for the lock.
    /// The blocked read will fail, then we relaunch under the lock.
    func terminateWorkerProcess() {
        // Terminate process directly (non-blocking)
        if let process = process, process.isRunning {
            process.terminate()
            logger.notice("Terminated worker process PID \(process.processIdentifier, privacy: .public)")
        }
        
        // Relaunch in background after brief delay to ensure termination completes
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.lock.lock()
            defer { self?.lock.unlock() }
            self?.restart(reason: "Relaunch after process termination")
        }
    }
}

private extension FileHandle {
    func readLine() -> String? {
        var data = Data()
        while true {
            let byte = readData(ofLength: 1)
            if byte.isEmpty { return data.isEmpty ? nil : String(data: data, encoding: .utf8) }
            if byte[0] == 10 { return String(data: data, encoding: .utf8) }
            data.append(byte)
        }
    }
}

struct KokoroVoiceEngine: VoiceSynthesizer {
    private var workerPath: String? {
        AppConfig.findExecutable(in: AppConfig.kokoroWorkerPaths)
    }

    private var modelURL: URL? {
        LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.kokoroRoots)
            .first { $0.lastPathComponent.lowercased().contains("kokoro") }
    }

    var availableVoices: [KokoroVoice] {
        let knownVoices = ["af_heart", "af_bella", "am_adam", "bf_emma", "bm_george"]
        if modelURL != nil {
            return knownVoices.map { KokoroVoice(id: $0, displayName: $0.replacingOccurrences(of: "_", with: " ").capitalized, path: "kokoro://\($0)") }
        }
        return []
    }

    var availability: VoiceEngineAvailability {
        guard workerPath != nil else {
            return VoiceEngineAvailability(isAvailable: false, message: "Install the Kokoro worker and place Apache-2.0 Kokoro ONNX assets in ~/Library/Application Support/LatteReader/kokoro/.")
        }
        guard modelURL != nil else {
            return VoiceEngineAvailability(isAvailable: false, message: "Place Kokoro ONNX model and voice assets in ~/Library/Application Support/LatteReader/kokoro/. LatteReader does not bundle third-party weights.")
        }
        return VoiceEngineAvailability(isAvailable: true, message: "Kokoro worker ready.")
    }

    var isAvailable: Bool { availability.isAvailable }

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL, isStillCurrent: () -> Bool) throws {
        try KokoroWorker.shared.synthesize(segment: segment, outputURL: outputURL, isStillCurrent: isStillCurrent)
    }
}

struct PiperVoiceEngine: VoiceSynthesizer {
    var availability: VoiceEngineAvailability {
        guard AppConfig.findExecutable(in: AppConfig.piperExecutablePaths) != nil else {
            return VoiceEngineAvailability(isAvailable: false, message: "Piper not found. Install via Homebrew or place in bundle.")
        }
        guard !LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.piperRoots).isEmpty else {
            return VoiceEngineAvailability(isAvailable: false, message: "Place a Piper .onnx voice in ~/Library/Application Support/piper-voices/.")
        }
        return VoiceEngineAvailability(isAvailable: true, message: "Piper fallback ready.")
    }

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL, isStillCurrent: () -> Bool) throws {
        // Check if stale before launching piper
        guard isStillCurrent() else {
            throw CancellationError()
        }
        
        guard let modelPath = segment.piperModelPath ?? LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.piperRoots).first?.path else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard let executable = AppConfig.findExecutable(in: AppConfig.piperExecutablePaths) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--model", modelPath, "--output-file", outputURL.path]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        
        try process.run()
        inputPipe.fileHandleForWriting.write(Data(segment.text.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        
        // Wait with timeout to prevent hanging
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            waitGroup.leave()
        }
        
        if waitGroup.wait(timeout: .now() + AppConfig.workerProcessTimeout) == .timedOut {
            process.terminate()
            // Force kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    process.interrupt()
                }
            }
            throw CocoaError(.executableLoad)
        }
        
        if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: outputURL.path) {
            throw CocoaError(.executableLoad)
        }
    }
}
