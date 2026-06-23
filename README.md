# PDF Reader Speaker

A premium macOS SwiftUI app that opens PDFs, extracts text, and reads them aloud using **Piper neural TTS** or **macOS system voices**.

Built with native SwiftUI + PDFKit, designed with a warm, earthy chocolate-brown aesthetic.

## Features

- **Open any PDF** via the macOS file picker (`⌘O`)
- **Dual reading modes**: Full document continuous scroll or page-by-page
- **Rich speech output**:
  - **Piper neural TTS** — natural prosody with punctuation handling (Ryan, en-US)
  - **macOS system voices** — with configurable speech rate
- **Smart text extraction** — picks up selectable text via PDFKit with automatic fallback
- **Selection-aware reading** — reads selected text if you've highlighted something, otherwise reads the current page or entire document
- **Play / Pause / Stop** controls with spacebar shortcut
- **Page navigation** — jump to any page, zoom in/out (`⌘+` / `⌘−`), fit to width (`⌘0`)
- **Large document handling** — splits speech into manageable chunks
- **Image-only / scanned PDF detection** — warns when no selectable text is found
- **Parser abstraction** — architecture is ready for alternative PDF parsers

## Parser Options

Three parser modes are available:

| Mode | Behaviour |
|------|-----------|
| **Auto: PDFKit, then Liteparse** | Uses PDFKit first; falls back to Liteparse CLI for scanned/image PDFs (if installed) |
| **PDFKit** | Apple's built-in PDF text extraction — fast, no dependencies |
| **Liteparse CLI** | Calls `lit parse` directly; requires the `lit` command from [run-llama/liteparse](https://github.com/run-llama/liteparse) |

> Liteparse is optional. If not installed, the app gracefully falls back to PDFKit.

## Build & Run

### From the command line

```bash
swift run
```

### From Xcode

```bash
open Package.swift
```

Then select the `PDFReaderSpeaker` scheme and press **Run**.

## System Requirements

- macOS 13 (Ventura) or later
- Xcode 14+ or Swift 5.9+ toolchain

## Voice Engines

### Piper (recommended)

The app bundles configuration for [Piper](https://github.com/rhasspy/piper), a fast neural text-to-speech system. It uses the **Ryan (en-US)** voice by default, which provides natural prosody, proper punctuation handling, and significantly more natural output than traditional system voices.

Piper runs locally — no internet connection or API keys needed.

### System Voices

macOS includes a range of built-in voices via `AVSpeechSynthesizer`. The app provides a rate slider and voice picker for full control.

## Local Signing Note

This is a local development app and is not notarized. If you export or run a built app bundle outside Xcode, macOS Gatekeeper may warn that it is unsigned. For local testing, open it from Xcode/Swift Package Manager or use macOS's standard **Open Anyway** flow in **System Settings > Privacy & Security**.

## Project Structure

```
PDFReaderSpeaker/
├── Package.swift                  # SwiftPM manifest
├── README.md
├── .gitignore
└── PDFReaderSpeaker/
    ├── PDFReaderSpeakerApp.swift  # App entry point
    ├── ContentView.swift          # Main UI (sidebar, PDF view, controls)
    ├── Theme.swift                # Color palette & ambient background
    ├── PDFKitView.swift           # PDFKit NSViewRepresentable wrapper
    ├── PDFDocumentReader.swift    # Text parsing protocol & implementations
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
