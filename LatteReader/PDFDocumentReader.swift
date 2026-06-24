import Foundation
import PDFKit

struct PDFPageText: Identifiable {
    let id: Int
    let pageNumber: Int
    let text: String
}

struct LoadedPDF {
    let url: URL
    let fileName: String
    let pageCount: Int
    let pages: [PDFPageText]

    var totalCharacterCount: Int {
        pages.reduce(0) { $0 + $1.text.count }
    }

    var extractablePageCount: Int {
        pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var fullText: String {
        pages
            .map { "Page \($0.pageNumber)\n\($0.text)" }
            .joined(separator: "\n\n")
    }
}

enum PDFReadMode: String, CaseIterable, Identifiable {
    case fullDocument = "Full document"
    case pageByPage = "Page by page"

    var id: String { rawValue }
}

enum PDFParserChoice: String, CaseIterable, Identifiable {
    case automatic = "Auto: PDFKit, then Liteparse"
    case pdfKit = "PDFKit"
    case liteparse = "Liteparse CLI"

    var id: String { rawValue }
}

enum PDFReaderError: LocalizedError {
    case cannotOpen
    case noExtractableText
    case liteparseFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "This PDF could not be opened."
        case .noExtractableText:
            return "No readable text was found. This PDF may be scanned or image-only, so it needs OCR before it can be read aloud."
        case .liteparseFailed(let message):
            return "Liteparse could not read this PDF: \(message)"
        }
    }
}

protocol PDFTextParsing {
    func loadPDF(from url: URL) throws -> LoadedPDF
}

final class PDFKitTextParser: PDFTextParsing {
    func loadPDF(from url: URL) throws -> LoadedPDF {
        guard let document = PDFDocument(url: url) else {
            throw PDFReaderError.cannotOpen
        }

        let pages = (0..<document.pageCount).map { index in
            let page = document.page(at: index)
            return PDFPageText(
                id: index,
                pageNumber: index + 1,
                text: page?.string?.normalisedForSpeech() ?? ""
            )
        }

        let loadedPDF = LoadedPDF(
            url: url,
            fileName: url.lastPathComponent,
            pageCount: document.pageCount,
            pages: pages
        )

        guard loadedPDF.extractablePageCount > 0 else {
            throw PDFReaderError.noExtractableText
        }

        return loadedPDF
    }
}

final class LiteparseCLITextParser: PDFTextParsing {
    private let executableURL: URL

    init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/env")) {
        self.executableURL = executableURL
    }

    static func isAvailable() -> Bool {
        // Avoid Process on macOS 26+ (known crash with waitUntilExit).
        // Just check common locations for the lit binary.
        let paths = [
            "/opt/homebrew/bin/lit",
            "/usr/local/bin/lit",
            "/usr/bin/lit",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/lit",
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func loadPDF(from url: URL) throws -> LoadedPDF {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["lit", "parse", url.path, "--format", "text"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PDFReaderError.liteparseFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.normalisedForSpeech() ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw PDFReaderError.liteparseFailed(errorOutput.isEmpty ? "the lit command exited with status \(process.terminationStatus)" : errorOutput)
        }

        guard !output.isEmpty else {
            throw PDFReaderError.noExtractableText
        }

        let pageCount = PDFDocument(url: url)?.pageCount ?? 1
        return LoadedPDF(
            url: url,
            fileName: url.lastPathComponent,
            pageCount: pageCount,
            pages: [PDFPageText(id: 0, pageNumber: 1, text: output)]
        )
    }
}

final class FallbackPDFTextParser: PDFTextParsing {
    private let preferredParser: PDFTextParsing
    private let fallbackParser: PDFTextParsing

    init(preferredParser: PDFTextParsing, fallbackParser: PDFTextParsing = PDFKitTextParser()) {
        self.preferredParser = preferredParser
        self.fallbackParser = fallbackParser
    }

    func loadPDF(from url: URL) throws -> LoadedPDF {
        do {
            return try preferredParser.loadPDF(from: url)
        } catch {
            return try fallbackParser.loadPDF(from: url)
        }
    }
}

private extension String {
    func normalisedForSpeech() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
