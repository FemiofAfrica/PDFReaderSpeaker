import AVFoundation
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Enums

enum VoiceEngine: String, CaseIterable, Identifiable {
    case piper = "Piper (Neural)"
    case system = "System Voices"
    var id: String { rawValue }
}

// MARK: - Content View

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

    // Transport / playback state
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackSpeed: Double = 1.0
    private let timerPublisher = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                // Deck chassis container
                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    // Main content area
                    HStack(spacing: 0) {
                        if let loadedPDF {
                            sidePanel(for: loadedPDF)
                            Divider()
                                .overlay(Color.border)
                            pdfContent(for: loadedPDF)
                        } else {
                            emptyState
                        }
                    }

                    // Transport bar
                    if loadedPDF != nil {
                        transportBar
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [.bean, .espresso, Color(red: 0.18, green: 0.14, blue: 0.11)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.55), radius: 60, x: 0, y: 40)
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(24)
            }
        }
        .onChange(of: selectedVoiceIdentifier) { newVoice in
            guard speechReader.isSpeaking || speechReader.isPaused else { return }
            speechReader.restartCurrentChunk(rate: speechRate, voiceIdentifier: newVoice)
        }
        .onChange(of: speechRate) { newRate in
            guard speechReader.isSpeaking || speechReader.isPaused else { return }
            speechReader.restartCurrentChunk(rate: newRate, voiceIdentifier: selectedVoiceIdentifier)
        }
        .onChange(of: playbackSpeed) { newSpeed in
            guard selectedVoiceEngine == .system,
                  speechReader.isSpeaking || speechReader.isPaused else { return }
            speechReader.restartCurrentChunk(rate: speechRate * newSpeed, voiceIdentifier: selectedVoiceIdentifier)
        }
        .onChange(of: selectedVoiceEngine) { _ in
            if speechReader.isSpeaking || speechReader.isPaused { speechReader.stop() }
            if piperReader.isSpeaking || piperReader.isPaused { piperReader.stop() }
        }
        .onChange(of: pdfProxy.currentPageNumber) { pageNum in
            selectedPageID = pageNum - 1
        }
        .onChange(of: pdfProxyPage.currentPageNumber) { pageNum in
            selectedPageID = pageNum - 1
        }
        .onReceive(timerPublisher) { _ in
            guard isPlaying else { return }
            switch selectedVoiceEngine {
            case .piper where piperReader.duration > 0:
                playbackProgress = min(1, piperReader.currentTime / piperReader.duration)
            default:
                break
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Logo + title
            HStack(spacing: 10) {
                // Coffee mark
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.bean, .espresso],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    Circle()
                        .fill(
                            LinearGradient(colors: [.caramel, .butter],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 18, height: 18)
                        .shadow(color: .caramel.opacity(0.4), radius: 4, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("LatteReader")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(.cream)
                    Text("Open a PDF \u{00B7} Extract \u{00B7} Listen")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(3)
                        .foregroundColor(.textMuted)
                }
            }

            Spacer()

            // Status + filename
            if let loadedPDF, pdfDocument != nil {
                HStack(spacing: 8) {
                    LED(color: isPlaying ? .green : .amber)
                    Text(isPlaying ? "Brewing" : "Ready")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundColor(.textMuted)
                    Divider()
                        .frame(height: 12)
                        .overlay(Color.border)
                    Text(loadedPDF.fileName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cream.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }

            // Open PDF button
            PrimaryButton("Open PDF", icon: "doc.badge.plus") {
                isImporterPresented = true
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(
            Rectangle()
                .fill(Color.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Coffee mark (large)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.bean, .espresso],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                Circle()
                    .fill(
                        LinearGradient(colors: [.caramel, .butter],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: .caramel.opacity(0.5), radius: 8, x: 0, y: 2)
            }

            VStack(spacing: 6) {
                Text("Choose a PDF to begin")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.cream)
                Text("Open a PDF, extract selectable text, and listen with\nPiper neural voices or macOS system voices.")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.ember)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            PrimaryButton("Open PDF", icon: "doc.badge.plus") {
                isImporterPresented = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Side Panel

    private func sidePanel(for pdf: LoadedPDF) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // ── Document Panel ──
                Bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        PanelHeader(label: "Document")

                        // Pages / Characters
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pages")
                                    .font(.system(size: 9, weight: .bold))
                                    .textCase(.uppercase)
                                    .tracking(2)
                                    .foregroundColor(.textMuted)
                                LCDText(text: "\(pdf.pageCount)", size: 20, weight: .semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Characters")
                                    .font(.system(size: 9, weight: .bold))
                                    .textCase(.uppercase)
                                    .tracking(2)
                                    .foregroundColor(.textMuted)
                                LCDText(
                                    text: isParsingText ? "…" : pdf.totalCharacterCount.formatted(),
                                    size: 16, weight: .semibold
                                )
                            }
                        }

                        // Page navigation
                        if pdfDocument != nil {
                            ScreenInset {
                                VStack(spacing: 10) {
                                    // Chevron + page number
                                    HStack(spacing: 12) {
                                        RoundBtn(
                                            systemImage: "chevron.left",
                                            action: { activeProxy.goToPage(activeProxy.currentPageNumber - 1) },
                                            disabled: activeProxy.currentPageNumber <= 1
                                        )

                                        HStack(spacing: 6) {
                                            LCDText(text: "\(activeProxy.currentPageNumber)", size: 26, weight: .bold)
                                            Text("/")
                                                .font(.system(size: 18, weight: .regular, design: .monospaced))
                                                .foregroundColor(.textMuted.opacity(0.5))
                                            Text("\(pdf.pageCount)")
                                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                                .foregroundColor(.textMuted)
                                        }

                                        RoundBtn(
                                            systemImage: "chevron.right",
                                            action: { activeProxy.goToPage(activeProxy.currentPageNumber + 1) },
                                            disabled: activeProxy.currentPageNumber >= pdf.pageCount
                                        )
                                    }

                                    // Progress bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.black.opacity(0.5))
                                                .frame(height: 6)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.caramel, .butter, .ember],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(
                                                    width: max(6, geo.size.width * CGFloat(activeProxy.currentPageNumber) / CGFloat(pdf.pageCount)),
                                                    height: 6
                                                )
                                        }
                                    }
                                    .frame(height: 6)

                                    // Go to Page
                                    KeyButton(label: "Go to Page") {
                                        promptPageNumber(totalPages: pdf.pageCount)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                // ── Parser Panel ──
                Bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader(label: "Parser")
                        CoffeeSegmentedControl(
                            options: [
                                (id: PDFParserChoice.automatic.rawValue, label: "Auto"),
                                (id: PDFParserChoice.pdfKit.rawValue, label: "PDFKit"),
                                (id: PDFParserChoice.liteparse.rawValue, label: "Liteparse"),
                            ],
                            selection: Binding(
                                get: { selectedParser.rawValue },
                                set: { val in
                                    if let p = PDFParserChoice.allCases.first(where: { $0.rawValue == val }) {
                                        selectedParser = p
                                    }
                                }
                            )
                        )
                        Text(parserHelpText)
                            .font(.system(size: 10))
                            .italic()
                            .foregroundColor(.textMuted)
                    }
                    .padding(16)
                }

                // ── Mode Panel ──
                Bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader(label: "Mode")
                        CoffeeSegmentedControl(
                            options: [
                                (id: PDFReadMode.fullDocument.rawValue, label: "Full"),
                                (id: PDFReadMode.pageByPage.rawValue, label: "Page"),
                            ],
                            selection: Binding(
                                get: { selectedReadMode.rawValue },
                                set: { val in
                                    if let m = PDFReadMode.allCases.first(where: { $0.rawValue == val }) {
                                        selectedReadMode = m
                                    }
                                }
                            )
                        )
                        if selectedReadMode == .pageByPage {
                            Picker("Page", selection: $selectedPageID) {
                                ForEach(pdf.pages) { page in
                                    Text("Page \(page.pageNumber)").tag(page.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.caramel)
                        }
                    }
                    .padding(16)
                }

                // ── Voice Panel ──
                Bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader(label: "Voice")
                        CoffeeSegmentedControl(
                            options: [
                                (id: VoiceEngine.piper.rawValue, label: "Piper"),
                                (id: VoiceEngine.system.rawValue, label: "System"),
                            ],
                            selection: Binding(
                                get: { selectedVoiceEngine.rawValue },
                                set: { val in
                                    if let v = VoiceEngine.allCases.first(where: { $0.rawValue == val }) {
                                        selectedVoiceEngine = v
                                    }
                                }
                            )
                        )

                        if selectedVoiceEngine == .system {
                            Picker("Voice", selection: $selectedVoiceIdentifier) {
                                Text("System default").tag(Optional<String>.none)
                                ForEach(speechReader.voices, id: \.identifier) { voice in
                                    Text("\(voice.name) (\(voice.language))")
                                        .tag(Optional(voice.identifier))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.caramel)

                            HStack {
                                Text("Rate")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                                Slider(value: $speechRate, in: 0.35...0.65)
                                    .tint(.caramel)
                            }
                        } else {
                            Text("Piper neural voice (Ryan, en-US) — natural prosody with punctuation handling.")
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(width: 300)
    }

    // MARK: - PDF Content

    private func pdfContent(for pdf: LoadedPDF) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview header
            HStack(spacing: 10) {
                Text("Preview")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundColor(.caramel)

                HStack(spacing: 4) {
                    Text(selectedReadMode == .fullDocument ? "Full document" : "Page \(selectedPageID + 1)")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    LCDText(text: "\(activeProxy.scalePercent)", size: 13, weight: .semibold)
                    Text("zoom")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1),
                alignment: .bottom
            )

            if let pdfDocument {
                ZStack {
                    PDFKitView(
                        document: pdfDocument,
                        currentPage: $selectedPageID,
                        displayMode: .singlePageContinuous,
                        isActive: selectedReadMode == .fullDocument,
                        proxy: pdfProxy
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedReadMode == .fullDocument ? 1 : 0)
                    .allowsHitTesting(selectedReadMode == .fullDocument)

                    PDFKitView(
                        document: pdfDocument,
                        currentPage: $selectedPageID,
                        displayMode: .singlePage,
                        isActive: selectedReadMode == .pageByPage,
                        proxy: pdfProxyPage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedReadMode == .pageByPage ? 1 : 0)
                    .allowsHitTesting(selectedReadMode == .pageByPage)
                }
                .background(
                    RadialGradient(
                        colors: [Color(red: 0.18, green: 0.14, blue: 0.11),
                                 Color(red: 0.12, green: 0.09, blue: 0.07)],
                        center: .top,
                        startRadius: 100,
                        endRadius: 600
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(12)
            } else {
                Text("Loading preview…")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
                .padding(4),
            alignment: .center
        )
    }

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            // Transport buttons
            HStack(spacing: 8) {
                // Stop
                Button {
                    stopPlayback()
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.78, green: 0.82, blue: 0.76).opacity(0.8))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(TransportBtnStyle())

                // Play/Pause
                Button {
                    togglePlayback()
                } label: {
                    if isPlaying {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.espresso)
                                .frame(width: 5, height: 22)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.espresso)
                                .frame(width: 5, height: 22)
                        }
                    } else {
                        Path { path in
                            path.move(to: .init(x: 4, y: 2))
                            path.addLine(to: .init(x: 4, y: 22))
                            path.addLine(to: .init(x: 20, y: 14))
                            path.closeSubpath()
                        }
                        .fill(Color.espresso)
                        .frame(width: 22, height: 24)
                    }
                }
                .buttonStyle(PrimaryTransportBtnStyle())

                // Pause
                Button {
                    pausePlayback()
                } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.78, green: 0.82, blue: 0.76).opacity(0.8))
                            .frame(width: 4, height: 16)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.78, green: 0.82, blue: 0.76).opacity(0.8))
                            .frame(width: 4, height: 16)
                    }
                }
                .buttonStyle(TransportBtnStyle())
            }

            // Waveform
            WaveformView(playing: isPlaying, progress: $playbackProgress)
                .frame(maxWidth: .infinity)

            // Time / chapter
            VStack(spacing: 1) {
                LCDText(text: elapsedString, size: 12, weight: .semibold)
                Text("Page \(selectedPageID + 1)")
                    .font(.system(size: 8, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }
            .frame(width: 120)

            // Dials
            HStack(spacing: 20) {
                CoffeeDial(
                    label: "Speed",
                    value: $playbackSpeed,
                    range: 0.5...2.0,
                    step: 0.05,
                    format: { String(format: "%.2f×", $0) }
                )

                CoffeeDial(
                    label: "Zoom",
                    value: Binding(
                        get: { Double(activeProxy.scalePercent) },
                        set: { activeProxy.setZoomPercent(Int($0)) }
                    ),
                    range: 10...200,
                    step: 1,
                    format: { "\(Int($0))%" }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(
            Rectangle()
                .fill(Color.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func togglePlayback() {
        guard let loadedPDF else { return }
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback(for: loadedPDF)
        }
    }

    private func startPlayback(for pdf: LoadedPDF) {
        let selection = activeProxy.currentSelectionText()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if let selection, !selection.isEmpty {
            text = selection
        } else {
            text = textToRead(from: pdf)
        }
        switch selectedVoiceEngine {
        case .piper:
            piperReader.start(text: text)
        case .system:
            speechReader.start(text: text, rate: speechRate * playbackSpeed, voiceIdentifier: selectedVoiceIdentifier)
        }
        isPlaying = true
    }

    private func pausePlayback() {
        switch selectedVoiceEngine {
        case .piper: piperReader.pauseOrContinue()
        case .system: speechReader.pauseOrContinue()
        }
        isPlaying = selectedVoiceEngine == .piper ? piperReader.isSpeaking : speechReader.isSpeaking
    }

    private func stopPlayback() {
        switch selectedVoiceEngine {
        case .piper: piperReader.stop()
        case .system: speechReader.stop()
        }
        isPlaying = false
        playbackProgress = 0
    }

    private var elapsedString: String {
        let total: TimeInterval
        let elapsed: TimeInterval
        switch selectedVoiceEngine {
        case .piper where piperReader.duration > 0:
            total = piperReader.duration
            elapsed = piperReader.currentTime
        default:
            // Fallback for system voices or when no progress data is available
            let estimatedTotal: TimeInterval = 12 * 60 + 45
            total = estimatedTotal
            elapsed = estimatedTotal * playbackProgress
        }
        let e = Int(elapsed)
        let t = Int(total)
        return "\(e / 60):\(String(format: "%02d", e % 60)) / \(t / 60):\(String(format: "%02d", t % 60))"
    }

    private func textToRead(from pdf: LoadedPDF) -> String {
        switch selectedReadMode {
        case .fullDocument:
            return pdf.fullText
        case .pageByPage:
            return pdf.pages.first(where: { $0.id == selectedPageID })?.text ?? ""
        }
    }

    /// Launches the standalone PagePrompt helper process for typed page entry.
    /// Uses a separate process so SwiftUI's broken TextField can't block input.
    private func promptPageNumber(totalPages: Int) {
        let projectRoot = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Projects/PDFReaderSpeaker"
        let helperPath = "\(projectRoot)/.build/helper/PagePrompt"

        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            print("Helper not found at: \(helperPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = ["\(totalPages)", "\(activeProxy.currentPageNumber)"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let input = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let pageNum = Int(input),
               pageNum > 0,
               pageNum <= totalPages {
                activeProxy.goToPage(pageNum)
            }
        } catch {
            print("Failed to launch helper: \(error)")
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        speechReader.stop()
        piperReader.stop()
        let parser = self.parser

        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()

            guard let document = PDFDocument(url: url) else {
                if canAccess { url.stopAccessingSecurityScopedResource() }
                throw PDFReaderError.cannotOpen
            }
            pdfDocument = document
            errorMessage = nil

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

            isParsingText = true

            Task.detached(priority: .userInitiated) {
                defer {
                    if canAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let pdf = try parser.loadPDF(from: url)
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
}

// MARK: - Transport Button Styles

struct TransportBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.24, blue: 0.18),
                        Color(red: 0.22, green: 0.18, blue: 0.14),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color(red: 0.12, green: 0.10, blue: 0.08).opacity(0.6),
                    radius: 3, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PrimaryTransportBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 60, height: 60)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.85, green: 0.70, blue: 0.45),
                        Color(red: 0.78, green: 0.60, blue: 0.37),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.caramel.opacity(0.4), radius: 8, x: 0, y: 4)
            .shadow(color: Color(red: 0.55, green: 0.40, blue: 0.25).opacity(0.5),
                    radius: 4, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
