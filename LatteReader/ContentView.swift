import AppKit
import PDFKit
import PagePromptSupport
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Enums

enum VoiceEngine: String, CaseIterable, Identifiable {
    case kokoro = "Kokoro"
    case piper = "Piper (Fallback)"
    var id: String { rawValue }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var kokoroReader = KokoroSpeechReader()
    @StateObject private var piperReader = KokoroSpeechReader(
        primary: PiperVoiceEngine(),
        fallback: PiperVoiceEngine()
    )
    @StateObject private var pdfProxy = PDFViewProxy()
    @StateObject private var pdfProxyPage = PDFViewProxy()
    @StateObject private var playbackControls = PlaybackControls()
    @StateObject private var errorHandler = ErrorHandler()
    @StateObject private var speechHighlighter = SpeechHighlighter()
    
    private let voiceChangeDebouncer = Debouncer(delay: 0.5)

    @State private var selectedVoiceEngine: VoiceEngine = .kokoro
    @State private var currentChunks: [PlannedSpeechSegment] = []

    private var activeProxy: PDFViewProxy {
        selectedReadMode == .pageByPage ? pdfProxyPage : pdfProxy
    }

    @State private var loadedPDF: LoadedPDF?
    @State private var pdfDocument: PDFDocument?
    @State private var isParsingText = false
    @State private var selectedReadMode: PDFReadMode = .fullDocument
    @State private var selectedParser: PDFParserChoice = .automatic
    @State private var selectedPageID = 0
    @State private var selectedPlaybackMode: MultiVoicePlaybackMode = .singleVoice
    @State private var speakerFallbackPolicy: SpeakerFallbackPolicy = .narrator
    @State private var voicePlan: DocumentVoicePlan?
    @State private var isAnalyzingCharacters = false
    @State private var analysisProgress: Double = 0
    @State private var analysisMessage: String?
    @State private var errorMessage: String?
    @State private var isImporterPresented = false
    @State private var keyMonitor: Any?
    @State private var queueStatus: String?

    // Transport / playback state
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackSpeed: Double = 1.0
    private let timerPublisher = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let voicePlanStore = DocumentVoicePlanStore()

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
        .onChange(of: selectedVoiceEngine) { _ in
            if kokoroReader.isSpeaking || kokoroReader.isPaused { kokoroReader.stop() }
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
            case .kokoro where kokoroReader.duration > 0:
                kokoroReader.refreshProgress()
                playbackProgress = min(1, kokoroReader.currentTime / kokoroReader.duration)
                updateHighlightForKokoro()
            case .piper where piperReader.duration > 0:
                playbackProgress = min(1, piperReader.currentTime / piperReader.duration)
                updateHighlightForPiper()
            default:
                break
            }
            playbackControls.updateSkipCapabilities()
        }
        .onAppear {
            // Pre-warm the Kokoro worker so the model is loaded
            // before the user presses Play.
            kokoroReader.warmUp()
            // Set up playback controls
            playbackControls.setEngines(kokoro: kokoroReader, piper: piperReader)
            playbackControls.setActiveEngine(selectedVoiceEngine)
            
            // AppKit-level keyboard monitors for shortcuts
            // Must use a local monitor — SwiftUI shortcuts are unreliable
            // in debug builds and conflict with system ⌘Q / ⌘⇧Q.
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // ⌘⌥Q — Queue selection
                if event.modifierFlags.contains(.command),
                   event.modifierFlags.contains(.option),
                   event.charactersIgnoringModifiers?.lowercased() == "q" {
                    queueCurrentSelection()
                    return nil
                }
                
                // ⌘← — Skip backward sentence
                if event.modifierFlags.contains(.command),
                   event.keyCode == 123 { // Left arrow
                    playbackControls.skipBackwardSentence()
                    return nil
                }
                
                // ⌘→ — Skip forward sentence
                if event.modifierFlags.contains(.command),
                   event.keyCode == 124 { // Right arrow
                    playbackControls.skipForwardSentence()
                    return nil
                }
                
                // ⌥← — Skip backward 15s
                if event.modifierFlags.contains(.option),
                   event.keyCode == 123 { // Left arrow
                    playbackControls.skipBackwardTime()
                    return nil
                }
                
                // ⌥→ — Skip forward 15s
                if event.modifierFlags.contains(.option),
                   event.keyCode == 124 { // Right arrow
                    playbackControls.skipForwardTime()
                    return nil
                }
                
                return event
            }
            keyMonitor = monitor
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
        }
        .onChange(of: selectedVoiceEngine) { newEngine in
            if kokoroReader.isSpeaking || kokoroReader.isPaused { kokoroReader.stop() }
            if piperReader.isSpeaking || piperReader.isPaused { piperReader.stop() }
            playbackControls.setActiveEngine(newEngine)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .errorAlert(errorHandler: errorHandler)
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
                Text("Open a PDF, extract selectable text, and listen with\nKokoro character voices or Piper fallback.")
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
                // ── Queue status toast ──
                if let queueStatus {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                        Text(queueStatus)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(.butter)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.caramel.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

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
                                (id: VoiceEngine.kokoro.rawValue, label: "Kokoro"),
                                (id: VoiceEngine.piper.rawValue, label: "Piper"),
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

                        if selectedVoiceEngine == .kokoro {
                            Text(kokoroReader.availability.isAvailable ? "Kokoro multi-voice is ready for character playback." : kokoroReader.availability.message)
                                .font(.system(size: 10))
                                .foregroundColor(kokoroReader.availability.isAvailable ? .textMuted : .caramel)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Piper remains the lightweight single-voice fallback and backup character engine.")
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }

                // ── AI Multi-Voice Panel ──
                Bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader(label: "AI Multi-Voice")
                        CoffeeSegmentedControl(
                            options: [
                                (id: MultiVoicePlaybackMode.singleVoice.rawValue, label: "Single"),
                                (id: MultiVoicePlaybackMode.multiVoice.rawValue, label: "Multi"),
                            ],
                            selection: Binding(
                                get: { selectedPlaybackMode.rawValue },
                                set: { val in
                                    if let mode = MultiVoicePlaybackMode.allCases.first(where: { $0.rawValue == val }) {
                                        selectedPlaybackMode = mode
                                    }
                                }
                            )
                        )
                        CoffeeSegmentedControl(
                            options: [
                                (id: SpeakerFallbackPolicy.narrator.rawValue, label: "Narrator"),
                                (id: SpeakerFallbackPolicy.bestGuess.rawValue, label: "Guess"),
                            ],
                            selection: Binding(
                                get: { speakerFallbackPolicy.rawValue },
                                set: { val in
                                    if let policy = SpeakerFallbackPolicy.allCases.first(where: { $0.rawValue == val }) {
                                        speakerFallbackPolicy = policy
                                    }
                                }
                            )
                        )

                        KeyButton(label: isAnalyzingCharacters ? "Analyzing…" : "Analyze Characters") {
                            analyzeCharacters(for: pdf)
                        }
                        .disabled(isAnalyzingCharacters || isParsingText || pdf.totalCharacterCount == 0)

                        if isAnalyzingCharacters {
                            ProgressView(value: analysisProgress)
                                .tint(.caramel)
                            Text("Analyzing… \(Int(analysisProgress * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.textMuted)
                        }

                        if let voicePlan {
                            Text("\(voicePlan.enabledProfileCount) speakers · \(voicePlan.segments.count) segments")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.butter)
                            ForEach(voicePlan.profiles.prefix(6)) { profile in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(profile.id == VoiceProfile.narratorID ? Color.caramel : Color.textMuted)
                                        .frame(width: 7, height: 7)
                                    Text(profile.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.cream)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(profile.confidence * 100))%")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.textMuted)
                                }
                            }
                        } else {
                            Text(analysisMessage ?? "Analyze first, then use Kokoro for distinct character voices. Piper is the fallback if Kokoro assets are missing.")
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
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
                        proxy: pdfProxy,
                        highlighter: speechHighlighter
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedReadMode == .fullDocument ? 1 : 0)
                    .allowsHitTesting(selectedReadMode == .fullDocument)

                    PDFKitView(
                        document: pdfDocument,
                        currentPage: $selectedPageID,
                        displayMode: .singlePage,
                        isActive: selectedReadMode == .pageByPage,
                        proxy: pdfProxyPage,
                        highlighter: speechHighlighter
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

                // Skip backward (sentence)
                Button {
                    playbackControls.skipBackwardSentence()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.espresso)
                }
                .buttonStyle(TransportBtnStyle())
                .disabled(!playbackControls.canSkipBackward)
                .help("⌘← — Previous sentence")

                // Queue selection (test)
                Button { queueCurrentSelection() } label: {
                    Text("Q")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.espresso)
                        .frame(width: 22, height: 22)
                        .background(Color.butter.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(PlainButtonStyle())
                .help("⌘⌥Q — Queue selection")

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
                
                // Skip forward (sentence)
                Button {
                    playbackControls.skipForwardSentence()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.espresso)
                }
                .buttonStyle(TransportBtnStyle())
                .disabled(!playbackControls.canSkipForward)
                .help("⌘→ — Next sentence")
            }

            // Waveform
            WaveformView(playing: isPlaying, progress: $playbackProgress, onSeek: { progress in
                handleWaveformSeek(progress)
            })
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
        let hasSelection: Bool
        if let selection, !selection.isEmpty {
            text = selection
            hasSelection = true
        } else {
            text = textToRead(from: pdf)
            hasSelection = false
        }

        if hasSelection {
            // Selection active — read selected text directly.
            // Bypass the voice plan; the plan covers the full document.
            startEngine(text: text, rate: playbackSpeed)
        } else if selectedPlaybackMode == .multiVoice {
            let pageNum: Int?
            if selectedReadMode == .pageByPage {
                pageNum = selectedPageID + 1
            } else {
                pageNum = nil
            }
            let segments = MultiVoiceAnalyzer().playbackSegments(
                for: text,
                pageNumber: pageNum,
                using: voicePlan,
                defaultVoiceIdentifier: nil,
                fallbackPolicy: speakerFallbackPolicy
            )
            if !kokoroReader.availability.isAvailable {
                errorHandler.handleVoiceEngineError(engine: .kokoro, availability: kokoroReader.availability) {
                    // Fall back to Piper
                    selectedVoiceEngine = .piper
                    startEngine(text: text, rate: playbackSpeed)
                }
                return
            }
            selectedVoiceEngine = .kokoro
            currentChunks = segments
            kokoroReader.start(segments: segments, rate: playbackSpeed)
        } else {
            startEngine(text: text, rate: playbackSpeed)
        }
        isPlaying = true
    }

    /// Route playback to the engine the user selected.
    private func startEngine(text: String, rate: Double) {
        switch selectedVoiceEngine {
        case .kokoro:
            let segments = makeSegments(for: text, kokoroVoiceID: "af_heart")
            currentChunks = segments
            kokoroReader.start(segments: segments, rate: rate)
        case .piper:
            let segments = makeSegments(for: text, kokoroVoiceID: nil)
            currentChunks = segments
            piperReader.start(segments: segments, rate: rate)
        }
    }

    /// Queue the current text selection into the active engine's queue.
    private func queueCurrentSelection() {
        NSLog("⌘⌥Q fired")
        guard pdfDocument != nil,
              let selection = activeProxy.currentSelectionText()?
            .trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty else {
            NSLog("⌘⌥Q: no selection or no doc — pdfDoc=\(pdfDocument != nil), sel=\(activeProxy.currentSelectionText() ?? "nil")")
            return
        }
        NSLog("⌘⌥Q: selection='\(selection.prefix(80))' (\(selection.count) chars)")
        let count: Int
        switch selectedVoiceEngine {
        case .kokoro:
            kokoroReader.append(segments: makeSegments(for: selection, kokoroVoiceID: "af_heart"))
            count = kokoroReader.totalChunks
        case .piper:
            piperReader.append(segments: makeSegments(for: selection, kokoroVoiceID: nil))
            count = piperReader.totalChunks
        }
        analysisMessage = "Queued selection — \(count) total chunk(s)"
        queueStatus = "✓ Queued — \(count) chunk(s)"
        // Auto-clear the toast after 4 seconds
        let clearJob = DispatchWorkItem { [self] in
            if queueStatus?.hasPrefix("✓") == true { queueStatus = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: clearJob)
    }

    /// Build narration segments from raw text.
    private func makeSegments(for text: String, kokoroVoiceID: String?) -> [PlannedSpeechSegment] {
        MultiVoiceAnalyzer.chunk(text: text).map {
            PlannedSpeechSegment(text: $0, voiceIdentifier: nil, kokoroVoiceID: kokoroVoiceID, piperModelPath: MultiVoiceAnalyzer.availablePiperModels().first, speakerName: "Narrator")
        }
    }

    private func pausePlayback() {
        switch selectedVoiceEngine {
        case .kokoro: kokoroReader.pauseOrContinue()
        case .piper: piperReader.pauseOrContinue()
        }
        isPlaying = selectedVoiceEngine == .kokoro ? kokoroReader.isSpeaking : piperReader.isSpeaking
    }

    private func stopPlayback() {
        switch selectedVoiceEngine {
        case .kokoro: kokoroReader.stop()
        case .piper: piperReader.stop()
        }
        isPlaying = false
        playbackProgress = 0
        speechHighlighter.clearHighlight()
        currentChunks = []
    }
    
    private func handleWaveformSeek(_ progress: Double) {
        let reader = selectedVoiceEngine == .kokoro ? kokoroReader : piperReader
        let targetTime = progress * reader.duration
        reader.seek(to: targetTime)
        playbackProgress = progress
    }
    
    // MARK: - Highlighting
    
    private func updateHighlightForKokoro() {
        guard let loadedPDF else { return }
        let index = kokoroReader.currentChunkIndex
        guard index < currentChunks.count else { return }
        
        let chunk = currentChunks[index]
        let approximatePage = speechHighlighter.approximatePageForChunk(
            index: index,
            chunks: currentChunks,
            pdfPageTexts: loadedPDF.pages
        )
        
        highlightCurrentChunk(chunk.text, approximatePage: approximatePage)
    }
    
    private func updateHighlightForPiper() {
        guard let loadedPDF else { return }
        let index = piperReader.currentChunkIndex
        guard index < currentChunks.count else { return }
        
        let chunk = currentChunks[index]
        let approximatePage = speechHighlighter.approximatePageForChunk(
            index: index,
            chunks: currentChunks,
            pdfPageTexts: loadedPDF.pages
        )
        
        highlightCurrentChunk(chunk.text, approximatePage: approximatePage)
    }
    
    private func highlightCurrentChunk(_ text: String, approximatePage: Int?) {
        speechHighlighter.highlightChunk(text, searchFrom: approximatePage)
    }

    private var elapsedString: String {
        let total: TimeInterval
        let elapsed: TimeInterval
        switch selectedVoiceEngine {
        case .kokoro where kokoroReader.duration > 0:
            total = kokoroReader.duration
            elapsed = kokoroReader.currentTime
        case .piper where piperReader.duration > 0:
            total = piperReader.duration
            elapsed = piperReader.currentTime
        default:
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
        guard let helperURL = PagePromptLocator.executableURL() else {
            print("Unable to resolve PagePrompt relative to the LatteReader executable")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            print("Helper not found at: \(helperURL.path)")
            return
        }

        let process = Process()
        process.executableURL = helperURL
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
        kokoroReader.stop()
        piperReader.stop()
        voicePlan = nil
        analysisProgress = 0
        analysisMessage = nil
        let parser = self.parser

        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()

            guard let document = PDFDocument(url: url) else {
                if canAccess { url.stopAccessingSecurityScopedResource() }
                errorHandler.handlePDFError(.cannotOpen)
                return
            }
            pdfDocument = document
            errorMessage = nil
            
            // Set up highlighter with document
            speechHighlighter.setPDFDocument(document, view: nil)

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
                        let documentID = MultiVoiceAnalyzer.documentID(for: pdf)
                        voicePlan = voicePlanStore.load(documentID: documentID)
                        if voicePlan != nil {
                            selectedPlaybackMode = .multiVoice
                            analysisMessage = "Restored saved voice plan."
                        }
                        isParsingText = false
                        // Set document text for highlighter
                        speechHighlighter.setDocumentText(pdf.fullText)
                    }
                } catch {
                    await MainActor.run {
                        if let pdfError = error as? PDFReaderError {
                            errorHandler.handlePDFError(pdfError)
                        } else {
                            errorMessage = "Text extraction: \(error.localizedDescription)"
                        }
                        isParsingText = false
                    }
                }
            }
        } catch {
            loadedPDF = nil
            pdfDocument = nil
            isParsingText = false
            if let pdfError = error as? PDFReaderError {
                errorHandler.handlePDFError(pdfError)
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func analyzeCharacters(for pdf: LoadedPDF) {
        isAnalyzingCharacters = true
        analysisProgress = 0.1
        voicePlan = nil
        analysisMessage = "Preparing local document analysis…"
        Task {
            analysisProgress = 0.35
            analysisMessage = "Segmenting pages and dialogue…"
            try? await Task.sleep(nanoseconds: 120_000_000)
            analysisProgress = 0.7
            analysisMessage = "Scoring likely speakers…"
            let analyzer = MultiVoiceAnalyzer()
            let plan = await Task.detached(priority: .userInitiated) {
                analyzer.analyze(pdf: pdf)
            }.value
            await MainActor.run {
                voicePlan = plan
                voicePlanStore.save(plan)
                selectedPlaybackMode = .multiVoice
                selectedVoiceEngine = .kokoro
                analysisProgress = 1
                isAnalyzingCharacters = false
                analysisMessage = "Detected \(max(plan.enabledProfileCount - 1, 0)) likely character speakers. Kokoro enabled for character voices; Piper will be used if Kokoro is unavailable."
            }
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
