# LatteReader

A warm, premium macOS app that opens PDFs and reads them aloud using **Kokoro character voices** with **Piper neural TTS** as the lightweight fallback.

Built with native SwiftUI + PDFKit. Wrapped in a cozy chocolate-brown aesthetic — like your favorite coffee shop, but for documents.

## Features

- **Open any PDF** via the macOS file picker (`⌘O`)
- **Dual reading modes**: Full document continuous scroll or page-by-page
- **Rich speech output**:
  - **Kokoro local TTS** — default multi-voice engine for narrator and character playback
  - **Piper neural TTS** — lightweight single-voice path and fallback when Kokoro is unavailable
- **Smart text extraction** — picks up selectable text via PDFKit with automatic fallback
- **Selection-aware reading** — reads selected text if you've highlighted something, otherwise reads the current page or entire document
- **AI-assisted multi-voice reading** — locally analyzes text for narrator, dialogue, explicit speaker labels, and likely character attributions
- **Per-document voice plans** — detected speakers and voice assignments are saved locally and restored when the same PDF is opened again
- **Play / Pause / Stop** controls with spacebar shortcut
- **Page navigation** — jump to any page, zoom in/out (`⌘+` / `⌘−`), fit to width (`⌘0`)
- **Large document handling** — splits speech into manageable chunks
- **Image-only / scanned PDF detection** — warns when no selectable text is found
- **Parser abstraction** — architecture is ready for alternative PDF parsers

## Parser Options

| Mode | Behaviour |
|------|-----------|
| **Auto: PDFKit, then Liteparse** | Uses PDFKit first; falls back to Liteparse CLI for scanned/image PDFs (if installed) |
| **PDFKit** | Apple's built-in PDF text extraction — fast, no dependencies |
| **Liteparse CLI** | Calls `lit parse` directly; requires the `lit` command from [run-llama/liteparse](https://github.com/run-llama/liteparse) |

> Liteparse is optional. If not installed, the app gracefully falls back to PDFKit.

## Build & Run

```bash
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

Then select the `LatteReader` scheme and press **Run**.

## System Requirements

- macOS 13 (Ventura) or later
- Xcode 14+ or Swift 5.9+ toolchain

## Voice Engines

### Kokoro (default for character voices)

Kokoro is the default local multi-voice engine for narrator and character playback. LatteReader discovers Kokoro ONNX assets from `~/Library/Application Support/LatteReader/kokoro/`, `~/Library/Application Support/kokoro-voices/`, or the app bundle's `Resources/kokoro/` folder.

The app does not ship third-party Kokoro weights by default. Place Apache-2.0-compatible Kokoro model and voice assets locally, and install a `kokoro-tts` CLI at `/opt/homebrew/bin/kokoro-tts`, `/usr/local/bin/kokoro-tts`, `~/.local/bin/kokoro-tts`, or the local Application Support wrapper.

### Piper (fallback and simple reading)

Piper remains the lightweight local fallback and simple single-voice path. Place Piper `.onnx` models in `~/Library/Application Support/piper-voices/` or the app bundle's `Resources/piper-voices/` folder.

## AI Multi-Voice Reading

The **AI Multi-Voice** panel implements the local MVP described in `docs/ai-multi-voice-pdf-reading-prd.md`:

- **Analyze Characters** segments extracted PDF text into narrator, dialogue, heading, explicit-speaker, and unknown blocks.
- The local heuristic detector recognizes script-style speaker labels (`ELIZABETH:`), quoted dialogue, em-dash dialogue, and common attribution patterns such as “Elizabeth said”.
- A narrator profile is always created, and up to 12 detected speakers receive Kokoro voice IDs first, plus Piper model paths for fallback.
- **Single voice** mode remains available at all times; **Multi-voice** mode reads planned segments through Kokoro and automatically falls back to Piper when Kokoro is unavailable.
- **Narrator fallback** uses the narrator voice for low-confidence dialogue; **Best guess** allows lower-confidence speaker assignments during playback.
- Voice plans are persisted as JSON in the app's Application Support folder, keyed by a stable document fingerprint.

Current MVP limits: multi-voice quality depends on local Kokoro assets being installed or placed in Application Support. Piper can keep playback local when Kokoro is missing, but it is less expressive. Character detection is intentionally heuristic and private by default; the code is structured so a future LLM provider can replace or augment the local analyzer.

## Standalone App Bundle

Create a launchable macOS app bundle with:

```bash
./scripts/build_app.sh
```

The output is `dist/LatteReader.app`. Drag it into `/Applications` to run it independently from Xcode, Terminal, or the source checkout. For sharing outside your own Mac, use Apple Developer ID signing and notarization; the script currently creates a local development bundle.

See `docs/voice-and-distribution-plan.md` for the voice quality and distribution plan.

## Local Signing Note

This is a local development app and is not notarized. If you export or run a built app bundle outside Xcode, macOS Gatekeeper may warn that it is unsigned. For local testing, open it from Xcode/Swift Package Manager or use macOS's standard **Open Anyway** flow in **System Settings > Privacy & Security**.

## Project Structure

```
LatteReader/
├── Package.swift                  # SwiftPM manifest
├── README.md
├── .gitignore
└── LatteReader/
    ├── LatteReaderApp.swift       # App entry point
    ├── ContentView.swift          # Main UI (sidebar, PDF view, controls)
    ├── Theme.swift                # Color palette & ambient background
    ├── PDFKitView.swift           # PDFKit NSViewRepresentable wrapper
    ├── PDFDocumentReader.swift    # Text parsing protocol & implementations
    ├── MultiVoiceReading.swift    # Character analysis, voice profiles, plans, persistence
    ├── SpeechReader.swift         # AVSpeechSynthesizer wrapper
    ├── PiperSpeechReader.swift    # Piper neural TTS integration
    └── WindowResizeEnforcer.swift # Window resize utility
```

## Troubleshooting

If `swift build` fails with a missing `BuildServerProtocol.framework`, the installed Xcode Command Line Tools are incomplete or mismatched. Fix by selecting a full Xcode install:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If Xcode is not installed, install or reinstall Command Line Tools:

```bash
xcode-select --install
```

## License

MIT — see [LICENSE](LICENSE).
