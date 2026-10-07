import Foundation

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

    private var executablePath: String? {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/LatteReader/kokoro/kokoro-worker").path,
            Bundle.main.resourceURL?.appendingPathComponent("kokoro/kokoro-worker").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/kokoro-worker").path,
            "/opt/homebrew/bin/kokoro-worker",
            "/usr/local/bin/kokoro-worker"
        ].compactMap { $0 }.first(where: FileManager.default.isExecutableFile)
    }

    var isAvailable: Bool { executablePath != nil }

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureStarted()
        guard let input, let output else { throw CocoaError(.executableLoad) }

        let payload: [String: Any] = [
            "text": Self.prepareTextForSpeech(segment.text),
            "output": outputURL.path,
            "voice": segment.kokoroVoiceID ?? "af_heart",
            "speed": 1.0,
            "lang": "en-us"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        input.write(data)
        input.write(Data("\n".utf8))

        guard let line = output.readLine(),
              let responseData = line.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              response["ok"] as? Bool == true,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            restart()
            throw CocoaError(.executableLoad)
        }
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
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            do {
                try ensureStarted()
                // Send a tiny ping render to force model loading.
                guard let input, let output else { return }
                let ping: [String: Any] = [
                    "text": "Hello.",
                    "output": FileManager.default.temporaryDirectory
                        .appendingPathComponent("kokoro-warmup-\(UUID().uuidString).wav").path,
                    "voice": "af_heart",
                    "speed": 1.0,
                    "lang": "en-us",
                ]
                let data = try JSONSerialization.data(withJSONObject: ping)
                input.write(data)
                input.write(Data("\n".utf8))
                _ = output.readLine()
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: ping["output"] as! String))
            } catch {
                // Warm-up is best-effort; swallow errors silently.
            }
        }
    }

    private func ensureStarted() throws {
        if let process, process.isRunning { return }
        guard let executablePath else { throw CocoaError(.fileNoSuchFile) }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading

        guard let readyLine = output?.readLine(), readyLine.contains("ready") else {
            restart()
            throw CocoaError(.executableLoad)
        }
    }

    private func restart() {
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
        output = nil
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
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/LatteReader/kokoro/kokoro-worker").path,
            Bundle.main.resourceURL?.appendingPathComponent("kokoro/kokoro-worker").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/kokoro-worker").path,
            "/opt/homebrew/bin/kokoro-worker",
            "/usr/local/bin/kokoro-worker"
        ].compactMap { $0 }.first(where: FileManager.default.isExecutableFile)
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

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL) throws {
        try KokoroWorker.shared.synthesize(segment: segment, outputURL: outputURL)
    }
}

struct PiperVoiceEngine: VoiceSynthesizer {
    var availability: VoiceEngineAvailability {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/piper")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/piper") else {
            return VoiceEngineAvailability(isAvailable: false, message: "Install Piper and place a .onnx voice in ~/Library/Application Support/piper-voices/.")
        }
        guard !LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.piperRoots).isEmpty else {
            return VoiceEngineAvailability(isAvailable: false, message: "Place a Piper .onnx voice in ~/Library/Application Support/piper-voices/.")
        }
        return VoiceEngineAvailability(isAvailable: true, message: "Piper fallback ready.")
    }

    func synthesize(segment: PlannedSpeechSegment, outputURL: URL) throws {
        guard let modelPath = segment.piperModelPath ?? LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.piperRoots).first?.path else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard let executable = ["/opt/homebrew/bin/piper", "/usr/local/bin/piper"].first(where: FileManager.default.isExecutableFile) else {
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
        process.waitUntilExit()
        if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: outputURL.path) {
            throw CocoaError(.executableLoad)
        }
    }
}
