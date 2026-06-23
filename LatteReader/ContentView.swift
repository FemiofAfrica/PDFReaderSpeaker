import AVFoundation
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum VoiceEngine: String, CaseIterable, Identifiable {
    case piper = "Piper (Neural)"
    case system = "System Voices"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var speechReader = SpeechReader()
    @StateObject private var piperReader = PiperSpeechReader()
    @StateObject private var pdfProxy = PDFViewProxy()
    @StateObject private var pdfProxyPage = PDFViewProxy()

    @State private var selectedVoiceEngine: VoiceEngine = .piper

    private var activeProxy: PDFViewProxy {
        selectedReadMode == .pageByPage ? pdfProxyPage : pdfProxy
    }

    @State private var loadedPDF: LoadedPDF?
    @State private var pdfDocument: PDFDocument?
    @State private var isParsingText = false
    @State private var selectedReadMode: PDFReadMode = .fullDocument
    @State private var selectedParser: PDFParserChoice = .automatic
    @State private var selectedPageID = 0
    @State private var selectedVoiceIdentifier = AVSpeechSynthesisVoice(language: Locale.current.identifier)?.identifier
    @State private var speechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @State private var errorMessage: String?
    @State private var isImporterPresented = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                header
                Divider()
                    .overlay(Color.creamMuted.opacity(0.15))
                content
                Divider()
                    .overlay(Color.creamMuted.opacity(0.15))
                controls
                    .background(.ultraThinMaterial)
            }
            .background(WindowResizeEnforcer())
        }
        .onChange(of: selectedVoiceIdentifier) { newVoice in
            guard speechReader.isSpeaking || speechReader.isPaused else { return }
            speechReader.restartCurrentChunk(rate: speechRate, voiceIdentifier: newVoice)
        }
        .onChange(of: speechRate) { newRate in
            guard speechReader.isSpeaking || speechReader.isPaused else { return }
            speechReader.restartCurrentChunk(rate: newRate, voiceIdentifier: selectedVoiceIdentifier)
        }
        .onChange(of: selectedVoiceEngine) { _ in
            // Stop whichever reader is active when switching engines
            if speechReader.isSpeaking || speechReader.isPaused { speechReader.stop() }
            if piperReader.isSpeaking || piperReader.isPaused { piperReader.stop() }
        }
        .onChange(of: pdfProxy.currentPageNumber) { pageNum in
            selectedPageID = pageNum - 1
        }
        .onChange(of: pdfProxyPage.currentPageNumber) { pageNum in
            selectedPageID = pageNum - 1
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LatteReader")
                    .font(.largeTitle.bold())
                    .foregroundColor(.cream)
                Text("Open a PDF, extract selectable text, and listen.")
                    .foregroundStyle(Color.creamMuted)
            }
            Spacer()
            Button {
                isImporterPresented = true
            } label: {
                Label("Open PDF", systemImage: "doc.badge.plus")
            }
            .controlSize(.large)
            .tint(Color.gold)
            .keyboardShortcut("o", modifiers: [.command])
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        if let loadedPDF {
            HStack(spacing: 0) {
                sidebar(for: loadedPDF)
                Divider()
                pdfView(for: loadedPDF)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.bubble.left")
                .font(.system(size: 54))
                .foregroundStyle(Color.gold)
            Text("Choose a PDF to begin")
                .font(.title2.bold())
                .foregroundColor(.cream)
            Text("Open a PDF, extract selectable text, and listen with Piper neural voices or macOS system voices.")
                .foregroundStyle(Color.creamMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 8)
            }
            Button("Open PDF") {
                isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gold)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.35))
                .padding(16)
        )
    }

    private func sidebar(for pdf: LoadedPDF) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("File") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pdf.fileName)
                        .font(.headline)
                        .foregroundColor(.cream)
                        .lineLimit(2)
                    infoRow("Pages", "\(pdf.pageCount)")

                    if pdfDocument != nil {
                        HStack {
                            Text("Page").foregroundStyle(Color.creamMuted)
                            Spacer()
                            Text("\(activeProxy.currentPageNumber)")
                                .fontWeight(.medium)
                                .foregroundColor(.cream)
                                .frame(minWidth: 30, alignment: .trailing)
                                .onTapGesture {
                                    promptForPage(in: pdf.pageCount)
                                }
                            Text("of \(pdf.pageCount)")
                                .foregroundStyle(Color.creamMuted)
                        }
                    }

                    infoRow("Readable pages", isParsingText ? "Parsing…" : "\(pdf.extractablePageCount)")
                    infoRow("Characters", isParsingText ? "Parsing…" : pdf.totalCharacterCount.formatted())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Reading") {
                VStack(alignment: .leading, spacing: 12) {
                    if isParsingText {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Extracting text…")
                                .foregroundStyle(Color.creamMuted)
                                .font(.caption)
                        }
                    }
                    Picker("Parser", selection: $selectedParser) {
                        ForEach(PDFParserChoice.allCases) { parser in
                            Text(parser.rawValue).tag(parser)
                        }
                    }
                    Text(parserHelpText)
                        .font(.caption)
                        .foregroundStyle(Color.creamMuted)
                    Picker("Mode", selection: $selectedReadMode) {
                        ForEach(PDFReadMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if selectedReadMode == .pageByPage {
                        Picker("Page", selection: $selectedPageID) {
                            ForEach(pdf.pages) { page in
                                Text("Page \(page.pageNumber)").tag(page.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Voice") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Engine", selection: $selectedVoiceEngine) {
                        ForEach(VoiceEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    if selectedVoiceEngine == .system {
                        Picker("Voice", selection: $selectedVoiceIdentifier) {
                            Text("System default").tag(Optional<String>.none)
                            ForEach(speechReader.voices, id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.language))")
                                    .tag(Optional(voice.identifier))
                            }
                        }
                        Slider(value: $speechRate, in: 0.35...0.65) {
                            Text("Rate")
                        } minimumValueLabel: {
                            Text("Slow")
                        } maximumValueLabel: {
                            Text("Fast")
                        }
                    } else {
                        Text("Piper neural voice (Ryan, en-US) — natural prosody with punctuation handling.")
                            .font(.caption)
                            .foregroundStyle(Color.creamMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 280)
        .background(.ultraThinMaterial.opacity(0.45))
    }

    @ViewBuilder
    private func pdfView(for pdf: LoadedPDF) -> some View {
        if let pdfDocument {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(previewTitle(for: pdf))
                        .font(.title3.bold())
                        .foregroundColor(.cream)
                    Spacer()
                    Text(selectedVoiceEngine == .piper ? piperReader.status : speechReader.status)
                        .foregroundStyle(Color.creamMuted)
                }

                ZStack {
                    // Full document — continuous scroll
                    PDFKitView(
                        document: pdfDocument,
                        currentPage: $selectedPageID,
                        displayMode: .singlePageContinuous,
                        isActive: selectedReadMode == .fullDocument,
                        proxy: pdfProxy
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(selectedReadMode == .fullDocument ? 1 : 0)
                    .allowsHitTesting(selectedReadMode == .fullDocument)

                    // Page by page — single page
                    PDFKitView(
                        document: pdfDocument,
                        currentPage: $selectedPageID,
                        displayMode: .singlePage,
                        isActive: selectedReadMode == .pageByPage,
                        proxy: pdfProxyPage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(selectedReadMode == .pageByPage ? 1 : 0)
                    .allowsHitTesting(selectedReadMode == .pageByPage)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial.opacity(0.25))
        } else {
            textPreview(for: pdf)
        }
    }

    @ViewBuilder
    private func textPreview(for pdf: LoadedPDF) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(previewTitle(for: pdf))
                    .font(.title3.bold())
                    .foregroundColor(.cream)
                Spacer()
                Text(speechReader.status)
                    .foregroundStyle(Color.creamMuted)
            }
            ScrollView {
                Text(textToRead(from: pdf))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .foregroundColor(.cream)
            }
            .background(Color.chocolateMedium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.25))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                guard let loadedPDF else { return }
                let selection = activeProxy.currentSelectionText()?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let text: String
                if let selection, !selection.isEmpty {
                    text = selection
                } else {
                    text = textToRead(from: loadedPDF)
                }
                switch selectedVoiceEngine {
                case .piper:
                    piperReader.start(text: text)
                case .system:
                    speechReader.start(text: text, rate: speechRate, voiceIdentifier: selectedVoiceIdentifier)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .disabled(loadedPDF == nil || isParsingText)
            .keyboardShortcut(.space, modifiers: [])
            .tint(Color.gold)

            Button {
                switch selectedVoiceEngine {
                case .piper: piperReader.pauseOrContinue()
                case .system: speechReader.pauseOrContinue()
                }
            } label: {
                let paused = selectedVoiceEngine == .piper ? piperReader.isPaused : speechReader.isPaused
                Label(paused ? "Continue" : "Pause", systemImage: paused ? "playpause.fill" : "pause.fill")
            }
            .disabled(
                selectedVoiceEngine == .piper
                    ? !piperReader.isSpeaking
                    : !speechReader.isSpeaking
            )

            Button(role: .destructive) {
                switch selectedVoiceEngine {
                case .piper: piperReader.stop()
                case .system: speechReader.stop()
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(
                selectedVoiceEngine == .piper
                    ? !piperReader.isSpeaking && !piperReader.isPaused
                    : !speechReader.isSpeaking && !speechReader.isPaused
            )

            if selectedVoiceEngine == .piper {
                Slider(
                    value: Binding(
                        get: { piperReader.currentTime },
                        set: { piperReader.seek(to: $0) }
                    ),
                    in: 0...max(piperReader.duration, 1)
                )
                .frame(maxWidth: 200)
                .controlSize(.small)
                .disabled(piperReader.duration == 0)
                .help("Drag to seek within the current chunk")

                Text(timeString(piperReader.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
                Text(timeString(piperReader.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .leading)
            }

            Spacer()
            if pdfDocument != nil {
                HStack(spacing: 4) {
                    Button {
                        activeProxy.zoomOut()
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom out (⌘−)")
                    .keyboardShortcut("-", modifiers: [.command])

                    Text("\(activeProxy.scalePercent)%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 40)
                        .foregroundStyle(.secondary)

                    Button {
                        activeProxy.zoomIn()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom in (⌘+)")
                    .keyboardShortcut("=", modifiers: [.command])

                    Button {
                        activeProxy.zoomToFit()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Fit to width (⌘0)")
                    .keyboardShortcut("0", modifiers: [.command])
                }
                .disabled(pdfDocument == nil)

                Divider()
                    .frame(maxHeight: 20)

                Text("Zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectedVoiceEngine == .piper {
                if piperReader.totalChunks > 0 {
                    Divider()
                        .frame(maxHeight: 20)
                    Text("Chunk \(min(piperReader.currentChunkIndex + 1, piperReader.totalChunks)) of \(piperReader.totalChunks)")
                        .foregroundStyle(.secondary)
                }
            } else {
                if speechReader.totalChunks > 0 {
                    Divider()
                        .frame(maxHeight: 20)
                    Text("Chunk \(min(speechReader.currentChunkIndex + 1, speechReader.totalChunks)) of \(speechReader.totalChunks)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.creamMuted)
            Spacer()
            Text(value).fontWeight(.medium).foregroundColor(.cream)
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func previewTitle(for pdf: LoadedPDF) -> String {
        switch selectedReadMode {
        case .fullDocument:
            return "Full document preview"
        case .pageByPage:
            let pageNumber = pdf.pages.first(where: { $0.id == selectedPageID })?.pageNumber ?? 1
            return "Page \(pageNumber) preview"
        }
    }

    private func textToRead(from pdf: LoadedPDF) -> String {
        switch selectedReadMode {
        case .fullDocument:
            return pdf.fullText
        case .pageByPage:
            return pdf.pages.first(where: { $0.id == selectedPageID })?.text ?? ""
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        speechReader.stop()
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()

            // 1. Load the PDF document for the visual reader — this is fast
            guard let document = PDFDocument(url: url) else {
                if canAccess { url.stopAccessingSecurityScopedResource() }
                throw PDFReaderError.cannotOpen
            }
            pdfDocument = document
            errorMessage = nil

            // 2. Show a placeholder so the PDF view + sidebar render immediately
            let pageCount = document.pageCount
            let placeholderPages = (0..<pageCount).map {
                PDFPageText(id: $0, pageNumber: $0 + 1, text: "")
            }
            loadedPDF = LoadedPDF(
                url: url,
                fileName: url.lastPathComponent,
                pageCount: pageCount,
                pages: placeholderPages
            )
            selectedPageID = 0

            // 3. Extract text on a background thread
            isParsingText = true
            let parserToUse = parser

            Task.detached(priority: .userInitiated) {
                defer {
                    if canAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let pdf = try parserToUse.loadPDF(from: url)
                    await MainActor.run {
                        loadedPDF = pdf
                        isParsingText = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Text extraction: \(error.localizedDescription)"
                        isParsingText = false
                    }
                }
            }
        } catch {
            loadedPDF = nil
            pdfDocument = nil
            isParsingText = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var parser: PDFTextParsing {
        switch selectedParser {
        case .automatic:
            let pdfKit = PDFKitTextParser()
            if LiteparseCLITextParser.isAvailable() {
                return FallbackPDFTextParser(preferredParser: pdfKit, fallbackParser: LiteparseCLITextParser())
            }
            return pdfKit
        case .pdfKit:
            return PDFKitTextParser()
        case .liteparse:
            return LiteparseCLITextParser()
        }
    }

    private var parserHelpText: String {
        switch selectedParser {
        case .automatic:
            return LiteparseCLITextParser.isAvailable()
                ? "PDFKit first, then Liteparse for scanned PDFs."
                : "Liteparse is not installed — using PDFKit."
        case .pdfKit:
            return "Uses Apple's built-in PDFKit text extraction."
        case .liteparse:
            return "Requires the local lit command from run-llama/liteparse."
        }
    }

    /// Native AppKit alert — works regardless of SwiftUI window quirks.
    private func promptForPage(in totalPages: Int) {
        let alert = NSAlert()
        alert.messageText = "Go to page"
        alert.informativeText = "Enter a page number (1–\(totalPages))"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = "\(activeProxy.currentPageNumber)"
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField

        textField.becomeFirstResponder()

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let input = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard let pageNum = Int(input),
                  pageNum > 0,
                  pageNum <= totalPages
            else { return }
            activeProxy.goToPage(pageNum)
        }
    }
}
