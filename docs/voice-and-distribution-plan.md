# LatteReader Voice and Distribution Plan

## Voice Quality Direction

LatteReader should no longer depend on macOS system voices for character analysis or multi-character playback. The character voice path is Kokoro-first, with Piper as the lightweight local fallback when Kokoro is unavailable or its models are missing.

## Current Local Voice Stack

### Kokoro default for character voices

Kokoro is the default engine for narrator and character assignment. LatteReader discovers local Kokoro ONNX assets from:

- `~/Library/Application Support/LatteReader/kokoro/`
- `~/Library/Application Support/kokoro-voices/`
- `LatteReader.app/Contents/Resources/kokoro/`

The app expects a local Kokoro CLI named `kokoro-tts` at `/opt/homebrew/bin/kokoro-tts`, `/usr/local/bin/kokoro-tts`, `~/.local/bin/kokoro-tts`, or the local Application Support wrapper. If either the CLI or model assets are missing, the UI shows a user-facing prompt explaining where to place the assets.

Recommended starting voice mix:

- `af_heart` or another warm voice for narrator
- Two to four distinct character voices
- At least one lower-pitched and one higher-pitched voice

### Piper fallback and simple reading

Piper remains the lightweight fallback engine and the existing simple voice path. Piper models are discovered from:

- `~/Library/Application Support/piper-voices/`
- `LatteReader.app/Contents/Resources/piper-voices/`

When Kokoro is unavailable during multi-voice playback, LatteReader logs the missing Kokoro reason and attempts Piper synthesis per segment using assigned Piper model paths.

## Licensing and Model Policy

- Kokoro code and supported model assets should be verified as Apache-2.0 before distribution.
- If Chatterbox is referenced later, verify the relevant code/model license is MIT-compatible before use.
- Do not commit or ship third-party weights unless their license and redistribution terms have been reviewed.
- Prefer an acquisition flow where users install or place ONNX assets locally, and LatteReader caches/discovers those assets under Application Support.

## Expected Performance

- Kokoro should be suitable as the higher-quality local default for character voices on Apple Silicon Macs, with CPU generation acceptable for queued segment playback.
- Piper is faster and lighter, but less expressive; it is best as a fallback or simple single-voice path.
- Segment-level synthesis should be queued or pre-generated over time to reduce gaps between speakers.

## Migration Note

The old "System" character-voice option has been replaced by "Kokoro". Existing saved voice plans still load, but new analysis assigns Kokoro voice IDs first and Piper model paths as fallback. Users who already installed Piper can keep using it for simple reading and as backup when Kokoro assets are missing.

## Standalone App Distribution

Run:

```bash
./scripts/build_app.sh
```

The script builds a release binary and creates:

```text
dist/LatteReader.app
```

The app does not need to bundle Kokoro weights. For private local builds, Piper voices may be copied from Application Support by the existing script; review licenses before sharing a bundle containing any third-party voice weights.
