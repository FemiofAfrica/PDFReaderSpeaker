# LatteReader Updates and Low-Lag Voice Architecture

## The packaging problem

Today LatteReader is being built like a normal Mac app bundle: code changes are compiled into a new binary, then wrapped into `LatteReader.app`, then optionally compressed into `LatteReader.dmg`. A DMG is only an installer/share artifact. It should not be the everyday development loop.

For day-to-day testing, the best loop is:

1. Run a development build directly from the project.
2. Keep user data, downloaded models, voice plans, and settings in Application Support.
3. Rebuild a standalone `.app` only when a working milestone is ready.
4. Rebuild a `.dmg` only when the app needs to be shared or archived.

## How Clicky-style updates work

Clicky can feel like it updates in place because its app shell and agent runtime are separated from generated work. The installed app stays stable while agents modify project files, scripts, local assets, and previews. For a compiled Swift app like LatteReader, changes to Swift code still require recompilation, but not necessarily a new DMG.

The LatteReader equivalent should be:

- A stable installed app in `/Applications` or `dist/LatteReader.app`.
- Local model/assets stored outside the app bundle in `~/Library/Application Support/LatteReader/`.
- User settings and API keys stored in Keychain or Application Support.
- A built-in updater for future public releases.
- A developer “Reload Local Build” flow for testing, not a DMG workflow.

## Recommended update strategy

### Development mode

Add a lightweight developer script:

```bash
./scripts/dev_app.sh
```

It should:

1. Stop the running LatteReader process.
2. Run `swift build`.
3. Launch `.build/debug/LatteReader`.
4. Leave the standalone `.app` and `.dmg` untouched.

This is the fast loop for testing agents and voice changes.

### Release mode

Keep the current release script:

```bash
./scripts/build_app.sh
```

It should:

1. Run `swift build -c release`.
2. Build `dist/LatteReader.app`.
3. Build `dist/LatteReader.dmg`.
4. Include only approved redistributable assets.

### Future auto-updates

For a polished Mac app, use Sparkle for app updates. Sparkle lets users get “Update available” inside the app instead of downloading a new DMG manually. It still ships a new app build, but the user experience is in-app.

## The voice lag problem

Kokoro local ONNX is good quality, but the current integration shells out to a Python CLI per segment. That means every chunk can pay startup, model load, phonemization, inference, file write, and audio player setup costs. Piper felt smoother because the app already treated it as a longer continuous synthesis path.

The root issue is not “AI agent intelligence.” It is audio architecture.

For smooth playback, LatteReader needs a proper audio pipeline:

1. Plan the full reading sequence.
2. Generate audio ahead of the playhead.
3. Keep a rolling queue of ready audio.
4. Start playback only after enough buffered audio exists.
5. Continue synthesis in the background while audio plays.
6. Avoid tiny line-by-line synthesis unless the speaker truly changes.
7. Crossfade or gaplessly concatenate adjacent same-voice chunks.
8. Cache generated audio by document, page range, voice, speed, and text hash.

## Best voice stack for users

### Default local stack

Use Kokoro for local high-quality voices, but not through one new Python process per line. It should run as either:

- A persistent local voice worker process; or
- A Swift-native ONNX Runtime integration; or
- A local HTTP service that keeps the model warm.

The persistent worker is the best near-term path because it keeps the model loaded and avoids repeated startup cost.

### Piper fallback

Keep Piper as fallback because it is lightweight and predictable. Piper is useful when:

- Kokoro is not installed.
- The machine is slow.
- The user chooses speed over expressiveness.
- Background generation cannot keep up.

### Cloud voices

Cloud TTS should be optional, not required. It can give the best quality and speed if the user has a key, but it introduces cost, internet dependency, and privacy questions.

Good BYOK providers to support later:

- OpenAI for high-quality realtime/cloud TTS.
- ElevenLabs for premium character voices.
- Google Cloud TTS or Azure Speech for reliable production TTS.
- OpenRouter/Claude/DeepSeek for analysis, not speech, unless paired with a TTS provider.

## Important distinction: analysis AI versus voice AI

LLMs like GPT, Claude, DeepSeek, Codex, and OpenRouter models are useful for character analysis:

- Better speaker attribution.
- Alias merging.
- Character personality summaries.
- Voice style suggestions.
- Fixing ambiguous dialogue.

They do not automatically solve audio lag. Audio lag is solved by the TTS engine and buffering architecture.

So LatteReader should split settings into two sections:

### Character Analysis Provider

- Local heuristic, default and free.
- Bring your own OpenAI key.
- Bring your own Anthropic key.
- Bring your own OpenRouter key.
- Bring your own DeepSeek key.

### Voice Provider

- Kokoro local, default.
- Piper local, fallback.
- Bring your own OpenAI TTS key.
- Bring your own ElevenLabs key.
- Bring your own Google/Azure key later.

## Recommended next implementation

### Phase 1: make Kokoro smooth locally

1. Replace per-segment `kokoro-tts` process calls with a persistent `kokoro-worker` process. Implemented in the current build.
2. Send synthesis jobs to the worker over stdin/stdout JSON. Implemented in the current build.
3. Keep the Kokoro model warm in memory. Implemented in the current build.
4. Maintain a playback buffer target, for example 30–60 seconds ahead.
5. Cache rendered WAV files per document and voice plan.
6. Show “Preparing audio…” until at least the first few chunks are ready.
7. Fall back to Piper automatically if the buffer cannot keep up.

### Phase 2: add settings

1. Add a Settings window.
2. Add Voice Provider selection: Kokoro, Piper, Cloud TTS.
3. Add Character Analysis Provider selection: Local, OpenAI, Anthropic, OpenRouter, DeepSeek.
4. Store API keys in Keychain, not plain files.
5. Add a “Test voice” button per provider.
6. Add cost/privacy labels beside cloud options.

### Phase 3: app updates

1. Add `scripts/dev_app.sh` for fast local testing.
2. Keep `scripts/build_app.sh` for release app/DMG packaging.
3. Add Sparkle when LatteReader is ready for distributed releases.
4. Add a visible version number and “Check for Updates” menu item.

## Recommendation

Do not jump straight to cloud AI agents just to fix the lag. First fix Kokoro with a persistent warm worker and audio caching. Then add BYOK cloud providers as premium options for users who want sharper voices, better analysis, or faster remote generation.
