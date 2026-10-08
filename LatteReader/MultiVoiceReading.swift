import CryptoKit
import Foundation

enum ReadingSegmentKind: String, Codable, CaseIterable, Identifiable {
    case narrator
    case dialogue
    case explicitSpeaker
    case heading
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .narrator: return "Narrator"
        case .dialogue: return "Dialogue"
        case .explicitSpeaker: return "Speaker label"
        case .heading: return "Heading"
        case .unknown: return "Unknown"
        }
    }
}

struct ReadingSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let pageNumber: Int
    let characterRange: Range<Int>?
    let parserBackend: String
    let kind: ReadingSegmentKind
    var speakerID: String
    var confidence: Double
}

struct VoiceProfile: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var aliases: [String]
    var confidence: Double
    var voiceIdentifier: String?
    var kokoroVoiceID: String?
    var piperModelPath: String?
    var isEnabled: Bool

    static let narratorID = "narrator"
}

struct DocumentVoicePlan: Codable, Hashable {
    var documentID: String
    var documentName: String
    var createdAt: Date
    var updatedAt: Date
    var parserBackend: String
    var profiles: [VoiceProfile]
    var segments: [ReadingSegment]

    var narratorProfile: VoiceProfile? {
        profiles.first { $0.id == VoiceProfile.narratorID }
    }

    var enabledProfileCount: Int {
        profiles.filter(\.isEnabled).count
    }

    func profile(for speakerID: String) -> VoiceProfile? {
        profiles.first { $0.id == speakerID && $0.isEnabled }
    }
}

struct PlannedSpeechSegment: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let voiceIdentifier: String?
    let kokoroVoiceID: String?
    let piperModelPath: String?
    let speakerName: String
}

enum MultiVoicePlaybackMode: String, CaseIterable, Identifiable {
    case singleVoice = "Single voice"
    case multiVoice = "Multi-voice"

    var id: String { rawValue }
}

enum SpeakerFallbackPolicy: String, CaseIterable, Identifiable {
    case narrator = "Narrator fallback"
    case bestGuess = "Best guess"

    var id: String { rawValue }
}

struct MultiVoiceAnalyzer {
    private let parserBackend: String

    init(parserBackend: String = "PDFKit/Liteparse") {
        self.parserBackend = parserBackend
    }

    func analyze(pdf: LoadedPDF) -> DocumentVoicePlan {
        let segments = buildSegments(from: pdf)
        let detectedSpeakers = detectSpeakers(in: segments)
        let profiles = buildProfiles(from: detectedSpeakers, kokoroVoices: Self.availableKokoroVoices(), piperModels: Self.availablePiperModels())
        let assignedSegments = assignSpeakers(to: segments, profiles: profiles)
        let now = Date()

        return DocumentVoicePlan(
            documentID: Self.documentID(for: pdf),
            documentName: pdf.fileName,
            createdAt: now,
            updatedAt: now,
            parserBackend: parserBackend,
            profiles: profiles,
            segments: assignedSegments
        )
    }

    func playbackSegments(
        for text: String,
        pageNumber: Int? = nil,
        using plan: DocumentVoicePlan?,
        defaultVoiceIdentifier: String?,
        fallbackPolicy: SpeakerFallbackPolicy
    ) -> [PlannedSpeechSegment] {
        guard let plan else {
            return Self.chunk(text: text, maxLength: AppConfig.chunkMaxLength).map {
                PlannedSpeechSegment(
                    text: $0,
                    voiceIdentifier: defaultVoiceIdentifier,
                    kokoroVoiceID: "af_heart",
                    piperModelPath: Self.availablePiperModels().first,
                    speakerName: "Narrator"
                )
            }
        }

        // Use page number for direct segment lookup instead of fragile
        // substring matching. Full-document mode passes nil (all segments).
        let sourceSegments: [ReadingSegment]
        if let pageNumber {
            sourceSegments = plan.segments.filter { $0.pageNumber == pageNumber }
        } else {
            sourceSegments = plan.segments
        }

        // If no segments match (e.g. selection from a different document),
        // fall back to building segments from the raw text.
        let activeSegments = sourceSegments.isEmpty ? buildSegments(from: text) : sourceSegments
        let narratorVoice = plan.narratorProfile?.voiceIdentifier ?? defaultVoiceIdentifier

        return activeSegments.flatMap { segment -> [PlannedSpeechSegment] in
            let profile = plan.profile(for: segment.speakerID)
            let voiceIdentifier: String?
            let speakerName: String

            if let profile, segment.confidence >= 0.45 || fallbackPolicy == .bestGuess {
                voiceIdentifier = profile.voiceIdentifier ?? narratorVoice
                speakerName = profile.displayName
            } else {
                voiceIdentifier = narratorVoice
                speakerName = "Narrator"
            }

            return Self.chunk(text: segment.text, maxLength: AppConfig.chunkMaxLength).map {
                PlannedSpeechSegment(text: $0, voiceIdentifier: voiceIdentifier, kokoroVoiceID: profile?.kokoroVoiceID, piperModelPath: profile?.piperModelPath, speakerName: speakerName)
            }
        }
    }

    private func buildSegments(from pdf: LoadedPDF) -> [ReadingSegment] {
        pdf.pages.flatMap { page in
            buildSegments(from: page.text, pageNumber: page.pageNumber)
        }
    }

    private func buildSegments(from text: String) -> [ReadingSegment] {
        buildSegments(from: text, pageNumber: 1)
    }

    private func buildSegments(from text: String, pageNumber: Int) -> [ReadingSegment] {
        var segments: [ReadingSegment] = []
        var cursor = 0
        let blocks = text
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\u{2029}")))
            .flatMap { $0.components(separatedBy: "  ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for block in blocks {
            let kind = classify(block)
            let range = cursor..<(cursor + block.count)
            cursor += block.count + 1
            segments.append(ReadingSegment(
                id: UUID(),
                text: block,
                pageNumber: pageNumber,
                characterRange: range,
                parserBackend: parserBackend,
                kind: kind,
                speakerID: VoiceProfile.narratorID,
                confidence: kind == .narrator ? 0.9 : 0.35
            ))
        }

        if segments.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(ReadingSegment(
                id: UUID(),
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageNumber: pageNumber,
                characterRange: 0..<text.count,
                parserBackend: parserBackend,
                kind: .narrator,
                speakerID: VoiceProfile.narratorID,
                confidence: 0.8
            ))
        }

        return segments
    }

    private func classify(_ text: String) -> ReadingSegmentKind {
        if explicitSpeakerName(in: text) != nil { return .explicitSpeaker }
        if text.contains("\"") || text.contains("“") || text.contains("”") || text.hasPrefix("—") || text.hasPrefix("-") { return .dialogue }
        if text.count < 90, text == text.uppercased(), text.rangeOfCharacter(from: .letters) != nil { return .heading }
        return .narrator
    }

    private func detectSpeakers(in segments: [ReadingSegment]) -> [String: (aliases: Set<String>, score: Double)] {
        var speakers: [String: (aliases: Set<String>, score: Double)] = [:]

        for segment in segments {
            if let explicitName = explicitSpeakerName(in: segment.text) {
                addSpeaker(explicitName, score: 1.0, into: &speakers)
            }

            for name in dialogueAttributions(in: segment.text) {
                addSpeaker(name, score: segment.kind == .dialogue ? 0.7 : 0.45, into: &speakers)
            }
        }

        return speakers.filter { $0.value.score >= 1.2 }
    }

    private func buildProfiles(
        from speakers: [String: (aliases: Set<String>, score: Double)],
        kokoroVoices: [KokoroVoice],
        piperModels: [String]
    ) -> [VoiceProfile] {
        var profiles = [VoiceProfile(
            id: VoiceProfile.narratorID,
            displayName: "Narrator",
            aliases: [],
            confidence: 1.0,
            voiceIdentifier: nil,
            kokoroVoiceID: kokoroVoices.first?.id ?? "af_heart",
            piperModelPath: piperModels.first,
            isEnabled: true
        )]

        for (offset, speaker) in speakers.keys.sorted().prefix(12).enumerated() {
            let kokoroVoice = kokoroVoices.dropFirst(offset + 1).first ?? kokoroVoices.dropFirst(offset % max(kokoroVoices.count, 1)).first
            let piperModel = piperModels.dropFirst(offset + 1).first ?? piperModels.dropFirst(offset % max(piperModels.count, 1)).first
            let data = speakers[speaker]
            profiles.append(VoiceProfile(
                id: stableSpeakerID(for: speaker),
                displayName: speaker,
                aliases: Array(data?.aliases ?? [speaker]).sorted(),
                confidence: min(0.98, data?.score ?? 0.5),
                voiceIdentifier: nil,
                kokoroVoiceID: kokoroVoice?.id ?? defaultKokoroVoiceID(offset: offset),
                piperModelPath: piperModel,
                isEnabled: true
            ))
        }

        return profiles
    }

    private func assignSpeakers(to segments: [ReadingSegment], profiles: [VoiceProfile]) -> [ReadingSegment] {
        segments.map { segment in
            var updated = segment
            if let explicitName = explicitSpeakerName(in: segment.text), let profile = matchProfile(named: explicitName, in: profiles) {
                updated.speakerID = profile.id
                updated.confidence = 0.95
            } else if segment.kind == .dialogue,
                      let name = dialogueAttributions(in: segment.text).first,
                      let profile = matchProfile(named: name, in: profiles) {
                updated.speakerID = profile.id
                updated.confidence = 0.65
            } else if segment.kind == .dialogue {
                updated.speakerID = VoiceProfile.narratorID
                updated.confidence = 0.3
            }
            return updated
        }
    }

    private func matchProfile(named name: String, in profiles: [VoiceProfile]) -> VoiceProfile? {
        let canonical = canonicalName(name)
        return profiles.first { profile in
            canonicalName(profile.displayName) == canonical || profile.aliases.contains { canonicalName($0) == canonical }
        }
    }

    private func addSpeaker(_ rawName: String, score: Double, into speakers: inout [String: (aliases: Set<String>, score: Double)]) {
        guard isLikelyCharacterName(rawName) else { return }
        let name = normalizeSpeakerName(rawName)
        let key = canonicalName(name)
        var existing = speakers[key] ?? (aliases: [], score: 0)
        existing.aliases.insert(name)
        existing.score += score
        speakers[key] = existing
    }

    private func explicitSpeakerName(in text: String) -> String? {
        let pattern = #"^\s*([A-Z][A-Z0-9 .'-]{1,38}|[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\s*[:—-]\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func dialogueAttributions(in text: String) -> [String] {
        let verbs = "said|asked|replied|cried|whispered|shouted|answered|muttered|called|continued|added|exclaimed"
        let patterns = [
            #"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\s+(?:said|asked|replied|cried|whispered|shouted|answered|muttered|called|continued|added|exclaimed)\b"#,
            #"\b(?:said|asked|replied|cried|whispered|shouted|answered|muttered|called|continued|added|exclaimed)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b"#
        ]
        _ = verbs
        return patterns.flatMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [String]() }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private func normalizeSpeakerName(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":—-.,;!?\"“”")))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func canonicalName(_ name: String) -> String {
        normalizeSpeakerName(name).lowercased()
    }

    private func stableSpeakerID(for name: String) -> String {
        canonicalName(name)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func isLikelyCharacterName(_ rawName: String) -> Bool {
        let name = normalizeSpeakerName(rawName)
        let blocked = Set([
            "I", "Me", "My", "Mine", "We", "Us", "Our", "You", "Your", "He", "Him", "His", "She", "Her", "They", "Them",
            "The", "A", "An", "This", "That", "There", "Then", "When", "Where", "Why", "How", "From", "Into", "Onto",
            "Chapter", "Page", "Figure", "Table", "Act", "Scene", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
        ])
        guard !blocked.contains(name), (2...40).contains(name.count) else { return false }
        let words = name.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            let rest = word.dropFirst()
            return first.isUppercase && word.count > 1 && !rest.allSatisfy(\.isUppercase)
        }
    }

    private func defaultKokoroVoiceID(offset: Int) -> String {
        ["af_heart", "af_bella", "am_adam", "bf_emma", "bm_george"][(offset + 1) % 5]
    }

    static func availablePiperModels() -> [String] {
        LocalVoiceAssetLocator.onnxFiles(in: LocalVoiceAssetLocator.piperRoots).map(\.path).sorted()
    }

    static func availableKokoroVoices() -> [KokoroVoice] {
        KokoroVoiceEngine().availableVoices
    }

    static func documentID(for pdf: LoadedPDF) -> String {
        let seed = "\(pdf.url.path)|\(pdf.fileName)|\(pdf.pageCount)|\(pdf.totalCharacterCount)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func chunk(text: String, maxLength: Int = 3_500) -> [String] {
        // Collapse arbitrary line breaks into spaces so PDF word-wrapping
        // doesn't create sentence boundaries.
        let normalized = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        let cleanText = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }

        var output: [String] = []
        var current = ""
        let sentences = cleanText.components(separatedBy: CharacterSet(charactersIn: ".!?"))

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

final class DocumentVoicePlanStore {
    private let folderURL: URL

    init(folderURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PDFReaderSpeaker/VoicePlans", isDirectory: true)) {
        self.folderURL = folderURL
    }

    func load(documentID: String) -> DocumentVoicePlan? {
        let url = fileURL(for: documentID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DocumentVoicePlan.self, from: data)
    }

    func save(_ plan: DocumentVoicePlan) {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            var updatedPlan = plan
            updatedPlan.updatedAt = Date()
            let data = try JSONEncoder.prettyVoicePlanEncoder.encode(updatedPlan)
            try data.write(to: fileURL(for: plan.documentID), options: .atomic)
        } catch {
            NSLog("Voice plan save failed: \(error.localizedDescription)")
        }
    }

    private func fileURL(for documentID: String) -> URL {
        folderURL.appendingPathComponent("\(documentID).json")
    }
}

private extension JSONEncoder {
    static var prettyVoicePlanEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
