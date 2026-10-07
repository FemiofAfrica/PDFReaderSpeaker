# PRD: AI-Assisted Multi-Voice PDF Reading

## 1. Problem Statement

PDFReaderSpeaker currently reads extracted PDF text aloud with a single selected voice. This works for factual documents, but it feels flat for novels, scripts, plays, transcripts, interviews, educational stories, and any document containing multiple characters or speakers. Users want the app to recognize distinct characters in a loaded PDF and read dialogue using separate voices, while preserving a narrator voice for non-dialogue text.

The product problem is to make PDF listening feel closer to an audiobook or table read without requiring users to manually annotate the entire document.

## 2. Product Goals

1. Detect likely characters, speakers, and narrator passages from a loaded PDF.
2. Assign a distinct synthesized voice to each detected character by default.
3. Let users review, rename, merge, split, disable, and override detected character voices before or during playback.
4. Persist character and voice assignments per document so users do not repeat setup work.
5. Preserve the existing single-voice reading experience as a simple fallback.
6. Keep the architecture modular so PDFKit and Liteparse extraction backends can both feed the same speaker-attribution pipeline.
7. Prefer private, on-device analysis where feasible, while allowing an optional cloud or external LLM mode for higher accuracy on complex documents.

## 3. Non-Goals

1. Do not guarantee perfect literary character detection in the first release.
2. Do not require every PDF to use AI analysis before reading.
3. Do not build a full audiobook production suite with timeline editing, effects, music, or exports in the first release.
4. Do not clone real people's voices or infer protected characteristics from text.
5. Do not require internet access for the baseline app experience.
6. Do not replace PDFKit or Liteparse; this feature should consume parsed text from either backend.
7. Do not perform OCR as part of this PRD beyond using existing or future parser outputs.

## 4. User Personas

### 4.1 Fiction Reader

A user listening to novels, short stories, or fan fiction PDFs who wants characters to sound distinct and easier to follow.

### 4.2 Student or Research Reader

A user listening to plays, case studies, interviews, oral histories, or dialogue-heavy learning material who wants speaker changes to improve comprehension.

### 4.3 Accessibility-Focused Listener

A user relying on audio playback because reading long PDFs visually is difficult, tiring, or inaccessible. They need clear speaker cues, reliable controls, and predictable fallback behavior.

### 4.4 Power User / Creator

A user who wants to tune voice assignments, fix character detection mistakes, and reuse settings for long documents.

## 5. Primary Use Cases

1. A user opens a novel PDF and asks the app to detect characters.
2. The app identifies a narrator plus named characters and assigns distinct voices.
3. The user previews each character voice before playback.
4. The user merges duplicate detections such as "Elizabeth", "Lizzy", and "Miss Bennet".
5. The user overrides a character's voice and saves the assignment for the document.
6. The user starts playback and hears narrator text in one voice and dialogue in character-specific voices.
7. The user sees when the app is uncertain about a speaker and can decide whether to use narrator voice or a best guess.
8. The user switches back to single-voice reading at any time.
9. The user loads the same PDF later and the app restores previous character and voice settings.

## 6. Feature Overview

The feature adds a new analysis layer between PDF text extraction and speech playback:

1. PDF text is extracted using the selected parser backend, currently PDFKit, Liteparse CLI, or automatic fallback.
2. The extracted text is segmented into narratable units such as paragraphs, dialogue turns, page spans, and speaker-labeled blocks.
3. A speaker attribution engine identifies likely speakers, narrator passages, aliases, confidence scores, and ambiguous sections.
4. A voice assignment engine maps each detected speaker to a Kokoro voice first, with Piper model paths saved as fallback.
5. A review UI presents detected characters and confidence levels.
6. A multi-voice playback engine reads each segment with the assigned voice.

## 7. Detailed Functional Requirements

### 7.1 Document Analysis Entry Points

1. The app must offer an "Analyze Characters" action after a PDF is loaded.
2. The app should optionally offer automatic analysis for dialogue-heavy documents, but automatic analysis must be user-controllable.
3. The app must show analysis progress for long documents.
4. The user must be able to cancel analysis without closing the PDF.
5. The app must preserve the existing ability to start reading without analysis.

### 7.2 Text Segmentation

1. The system must convert extracted PDF text into ordered reading segments.
2. Each segment must retain source metadata: page number, character range where available, parser backend, and surrounding context.
3. Segment types should include narrator, dialogue, explicit speaker label, heading, footnote, unknown, and skipped/non-readable.
4. Dialogue segmentation must recognize common quotation styles, including curly quotes, straight quotes, em dashes, and script-like speaker labels.
5. The segmentation layer must be independent of PDFKit and Liteparse implementation details.

### 7.3 Character and Speaker Detection

1. The system must detect likely named characters or speakers in the document.
2. The system must support explicit speaker formats such as "JOHN:", "Mary said", interview labels, and play/script formatting.
3. The system must infer dialogue speakers from nearby attribution phrases where confidence is high enough.
4. The system must group likely aliases for the same character.
5. The system must maintain a narrator identity separate from detected characters.
6. The system must support an "Unknown Speaker" bucket for dialogue that cannot be confidently attributed.
7. The system must store confidence scores for detected characters, aliases, and segment-level speaker attribution.

### 7.4 Speaker Attribution Confidence

1. Each segment should have a speaker attribution confidence value: high, medium, low, or unknown.
2. High-confidence dialogue may use the assigned character voice automatically.
3. Medium-confidence dialogue may use the assigned character voice but should be visible as uncertain in the review UI.
4. Low-confidence dialogue should default to narrator voice or unknown-speaker voice unless the user opts into best-guess playback.
5. The user must be able to choose the ambiguity policy: conservative, balanced, or expressive.
6. The app must make it clear that speaker detection is automated and may be wrong.

### 7.5 Voice Assignment Defaults

1. The narrator must have a default narrator voice.
2. Each detected character should receive a distinct default voice when enough voices are available.
3. Voice assignment should avoid assigning the same voice to multiple prominent characters unless necessary.
4. Default voice assignment should consider voice availability, language, current TTS engine, and user preferences.
5. The system must support Kokoro voices as the default character path and Piper voices as fallback where installed.
6. If only one suitable voice is available, the system should still show character detection but explain that distinct playback requires more voices.

### 7.6 User Overrides

1. The user must be able to change the voice assigned to any character.
2. The user must be able to preview a short sample for each character voice.
3. The user must be able to rename detected characters.
4. The user must be able to merge duplicate characters.
5. The user must be able to split incorrectly merged characters.
6. The user must be able to mark a detected character as narrator, unknown, or ignored.
7. The user must be able to reset all assignments to defaults.
8. The user must be able to disable multi-voice playback for the current document.

### 7.7 Persistence Per Document

1. Character detections, aliases, voice assignments, user corrections, and ambiguity settings must persist per PDF.
2. Persistence should key documents using a stable document identifier, such as file URL plus file metadata hash, with a fallback content fingerprint.
3. If a PDF moves on disk but appears to be the same document, the app should attempt to restore prior settings.
4. If a PDF changes materially, the app should warn that prior analysis may be stale and offer re-analysis.
5. Persistence data should be stored locally by default.

### 7.8 Narration Versus Dialogue Handling

1. Non-dialogue prose must use narrator voice by default.
2. Dialogue attributed to a known character must use that character's assigned voice.
3. Dialogue with unknown attribution must follow the user's ambiguity policy.
4. Speaker-labeled script blocks must switch voices at label boundaries.
5. Short attribution phrases such as "he said" or "Mary replied" should usually remain with the narrator voice unless the playback model intentionally merges them with dialogue for naturalness.
6. The app should avoid disruptive voice switching within very short fragments where the result would sound worse.

### 7.9 Playback Requirements

1. Multi-voice playback must support play, pause, resume, stop, and seek behavior consistent with existing controls.
2. The playback engine must know which segment is currently being spoken.
3. The app should show the active speaker or narrator during playback.
4. The user must be able to switch between multi-voice and single-voice modes without reloading the PDF.
5. The user must be able to restart playback after changing voice assignments.
6. The app should pre-generate or queue audio carefully enough to avoid long gaps between speakers.
7. The existing Piper flow should be preserved for lightweight fallback while multi-voice playback routes through the voice-engine abstraction.

### 7.10 Document Types and Edge Cases

1. For image-only or scanned PDFs with no extracted text, the app must show the existing no-readable-text state and explain that character detection needs text.
2. For nonfiction documents with no characters, the app should report that no distinct speakers were detected and keep single-voice mode.
3. For documents with hundreds of speakers, the app should limit the default review list to prominent speakers and group the rest as minor speakers or unknown.
4. For documents in unsupported languages, the app should still allow single-voice reading and explain that character detection may be limited.
5. For malformed PDFs or parser failures, the app must fail gracefully and keep the current document state stable.

## 8. UX Flows

### 8.1 Load PDF and Analyze

1. User opens a PDF.
2. App extracts text using the selected parser backend.
3. App shows the normal reading interface.
4. User clicks "Analyze Characters".
5. App shows progress: extracting structure, detecting speakers, assigning voices.
6. App opens a character review panel when analysis completes.

### 8.2 Preview Detected Characters

1. User sees narrator plus detected characters sorted by prominence.
2. Each row shows character name, assigned voice, confidence, approximate dialogue count, and preview button.
3. User previews voices and changes assignments.
4. User merges duplicates or marks uncertain entries as unknown.
5. User saves and starts multi-voice playback.

### 8.3 Playback With Multiple Voices

1. User presses play.
2. Narrator passages use narrator voice.
3. Character dialogue uses assigned character voices.
4. Current speaker is shown in the playback area.
5. User can pause, seek, change speed where supported, and stop.

### 8.4 Switch Back to Single Voice

1. User opens reading mode settings.
2. User switches from "Multi-voice" to "Single voice".
3. App stops or restarts playback using the selected single voice.
4. Character analysis remains saved but inactive.

### 8.5 Re-Analyze Document

1. User opens the character review panel.
2. User clicks "Re-analyze".
3. App asks whether to preserve manual voice overrides.
4. App runs analysis again and shows changes.

## 9. Architecture Outline

### 9.1 Proposed Pipeline

```text
PDF source
  -> PDF text extraction backend
  -> ReadingSegmentBuilder
  -> SpeakerAttributionEngine
  -> VoiceAssignmentEngine
  -> DocumentVoiceProfileStore
  -> MultiVoicePlaybackPlanner
  -> Speech engine adapter
```

### 9.2 Core Domain Concepts

1. Loaded document: the existing PDF metadata and extracted page text.
2. Reading segment: an ordered chunk of text that can be spoken with one voice.
3. Speaker profile: narrator, detected character, unknown speaker, or ignored speaker.
4. Speaker attribution: the predicted speaker for a segment plus confidence and evidence.
5. Voice assignment: the selected TTS voice for a speaker profile.
6. Document voice profile: persisted analysis and user overrides for one PDF.
7. Playback plan: the sequence of segments and voice instructions consumed by speech engines.

### 9.3 Backend Option A: On-Device Heuristics

This should be the baseline MVP path.

Capabilities:

1. Parse quoted dialogue and script labels.
2. Detect common attribution patterns such as "said Mary", "John replied", and "asked the professor".
3. Extract candidate names using lightweight NLP heuristics.
4. Group simple aliases using exact and near-exact matching.
5. Run fully offline and keep all document text local.

Advantages:

1. Private by default.
2. No API keys or cloud cost.
3. Predictable latency and easier rollout.
4. Works with current local-first app positioning.

Limitations:

1. Lower accuracy for complex fiction.
2. Harder pronoun resolution.
3. Weaker alias detection.
4. May struggle with unconventional formatting.

### 9.4 Backend Option B: Optional External LLM Service

This should be an opt-in enhancement, not the required MVP path.

Capabilities:

1. Higher-quality character extraction.
2. Better alias grouping.
3. Better dialogue attribution across paragraphs.
4. Better handling of complex narratives and scripts.
5. Ability to summarize confidence and explain ambiguous cases.

Privacy requirements:

1. User must explicitly enable cloud analysis.
2. App must explain that document text may be sent to an external service.
3. App should support analyzing limited excerpts or page ranges where possible.
4. App must not send documents silently.
5. App should allow users to delete stored analysis.

### 9.5 Backend Option C: Hybrid Mode

The recommended long-term architecture is hybrid:

1. Run on-device segmentation and heuristic speaker detection first.
2. Use cloud LLM only for ambiguous sections, alias resolution, or documents where user requests higher accuracy.
3. Cache results locally per document.
4. Preserve a consistent output schema regardless of analysis backend.

### 9.6 Modular Parser Compatibility

The speaker pipeline should not depend directly on PDFKit or Liteparse. Both parser backends should produce a shared intermediate representation containing:

1. Page number.
2. Extracted text.
3. Optional block or line ordering.
4. Optional layout hints.
5. Optional confidence or extraction quality metadata.

This keeps the feature compatible with current parser abstraction and future OCR or structured parsers.

### 9.7 Speech Engine Compatibility

The playback planner should output voice instructions without caring whether the final engine is Kokoro or Piper. Speech engines should expose capabilities such as:

1. Available voices.
2. Language or locale.
3. Supports rate control.
4. Supports pause/resume.
5. Supports audio pre-generation.
6. Supports per-segment voice switching.

Kokoro needs local model management for ONNX assets and per-segment voice IDs. Piper remains the fallback adapter for lightweight local synthesis.

## 10. Non-Functional Requirements

### 10.1 Performance

1. Analysis should start quickly after text extraction.
2. For a normal book-length PDF, the UI must remain responsive during analysis.
3. Analysis should run off the main thread.
4. Playback should avoid noticeable pauses between short dialogue turns.
5. Large documents should support incremental or page-range analysis.

### 10.2 Privacy

1. Local analysis must be the default.
2. Cloud analysis must be opt-in.
3. The app must disclose what text is sent externally before sending it.
4. Persisted document profiles must remain local unless the user enables sync in a future release.
5. Users must be able to delete analysis data for a document.

### 10.3 Accessibility

1. All character review controls must be keyboard accessible.
2. Voice assignment UI must work with VoiceOver.
3. Confidence indicators must not rely only on color.
4. Playback mode changes must be announced clearly.
5. Users must be able to use single-voice mode if multi-voice output is distracting.

### 10.4 Latency

1. Small documents should produce initial character suggestions quickly.
2. Long documents should show progress and allow cancellation.
3. Playback should not require full-document audio generation before starting.
4. Optional LLM mode should handle network delays with clear states and retry options.

### 10.5 Offline Behavior

1. On-device analysis and local TTS should work offline.
2. If cloud analysis is enabled but unavailable, the app should offer local analysis fallback.
3. Previously saved document voice profiles should remain usable offline.

### 10.6 Reliability

1. Analysis failure must not prevent normal PDF reading.
2. Speech playback failure for one segment should not corrupt the playback state.
3. The app should recover from missing voices by substituting safe defaults and notifying the user.
4. Persisted profiles should be versioned so future schema changes can migrate safely.

## 11. Error States

1. No readable text found: character detection unavailable until OCR or better extraction exists.
2. No characters detected: continue in narrator-only mode.
3. Too many possible speakers: show prominent speakers and group the rest.
4. Low confidence: use narrator or unknown voice depending on user setting.
5. Missing assigned voice: substitute narrator voice and mark the character row.
6. Kokoro model or CLI unavailable: show the missing-model prompt and fall back to Piper if a model is available.
7. Cloud analysis unavailable: offer retry or local analysis.
8. Cloud analysis disabled: explain that only local analysis is being used.
9. Analysis canceled: keep any previous saved profile and return to normal reading.
10. Profile stale after document change: offer re-analysis or continue with existing settings.

## 12. Observability and Metrics

If app telemetry exists or is added later, metrics should be privacy-preserving and avoid storing document content.

Useful product metrics:

1. Percentage of loaded PDFs where users run character analysis.
2. Analysis completion, cancellation, and failure rates.
3. Average analysis duration by page count and backend.
4. Number of detected speakers per document.
5. Percentage of documents switched to multi-voice playback.
6. Frequency of user overrides, merges, and resets.
7. Playback start latency in multi-voice mode.
8. Frequency of fallback from multi-voice to single-voice mode.
9. Cloud analysis opt-in rate if cloud mode ships.
10. Error counts for missing voices, parser failures, and speech engine failures.

Privacy rule: metrics must not include raw PDF text, character names, document titles, or extracted dialogue unless the user explicitly opts into diagnostic sharing.

## 13. Rollout Plan

### Phase 0: Technical Spike

1. Prototype reading segment generation from existing extracted page text.
2. Prototype simple quoted-dialogue and script-label detection.
3. Verify Kokoro can synthesize assigned voices cleanly per segment.
4. Verify Piper fallback works when Kokoro CLI or model assets are missing.
5. Measure playback gaps when switching voices.

### Phase 1: Local MVP

1. Add local on-device speaker detection heuristics.
2. Add narrator, character, and unknown-speaker profiles.
3. Add default voice assignment using available Kokoro voices, with Piper model fallback paths.
4. Add basic character review panel.
5. Add per-document local persistence.
6. Add multi-voice playback mode with single-voice fallback.

### Phase 2: Quality and Controls

1. Add alias merge/split workflows.
2. Add ambiguity policy settings.
3. Improve confidence display and active speaker UI.
4. Add re-analysis and preserve-overrides flow.
5. Improve Piper multi-voice support if multiple models are available.

### Phase 3: Optional AI Enhancement

1. Add opt-in cloud analysis provider interface.
2. Define strict request/response schema for LLM speaker attribution.
3. Add privacy disclosure and consent UI.
4. Add hybrid local-first analysis flow.
5. Add diagnostics for cloud latency and failure modes.

### Phase 4: Broader Document Support

1. Improve support for plays, transcripts, interviews, and educational scripts.
2. Add language-specific heuristics if needed.
3. Consider integration with OCR pipeline if scanned PDFs become a priority.
4. Consider exportable multi-voice audio only after playback quality is strong.

## 14. Implementation Decisions

1. Build the feature as a pipeline after text extraction, not inside the parser backends.
2. Use a shared reading-segment representation so PDFKit, Liteparse, and future OCR backends can all feed the same analysis layer.
3. Start with a local heuristic engine for MVP because it aligns with the app's local-first voice positioning.
4. Treat optional LLM analysis as a provider behind a protocol, not as a hard dependency.
5. Keep narrator as a first-class speaker profile rather than a special string.
6. Store segment attribution confidence separately from character detection confidence.
7. Persist user corrections as overrides layered on top of analysis output.
8. Keep single-voice reading mode available at all times.
9. Use Kokoro for the multi-voice path and Piper as the local fallback; do not depend on macOS system voices for character playback.
10. Version the document voice profile schema from the beginning.

## 15. Testing Decisions

Good tests should verify behavior at stable seams instead of internal implementation details.

Recommended test seams:

1. Given extracted page text, the segment builder produces ordered narrator/dialogue/script-label segments.
2. Given segments, the speaker attribution engine produces speaker profiles, aliases, confidence, and unknown buckets.
3. Given speaker profiles and available voices, the voice assignment engine assigns distinct voices with sensible fallbacks.
4. Given a document voice profile and reading segments, the playback planner produces the correct sequence of text plus voice instructions.
5. Given saved user overrides, reloading the same document restores assignments and corrections.
6. Given missing voices or low confidence, the planner falls back according to the selected policy.

Manual QA should include:

1. A normal prose PDF with no dialogue.
2. A dialogue-heavy novel excerpt.
3. A script or play with speaker labels.
4. An interview transcript.
5. A scanned or image-only PDF.
6. A document with duplicate aliases for the same character.
7. Offline mode.
8. Missing Kokoro CLI/model, missing Piper fallback model, or missing assigned voice.

## 16. Open Questions

1. Which Kokoro ONNX voice pack should be recommended as the default local download?
2. Should analysis run automatically for every PDF or only after the user clicks "Analyze Characters"?
3. Should cloud analysis be included in the first implementation or delayed until after local MVP feedback?
4. How much manual editing should be supported in v1: rename and voice assignment only, or merge/split too?
5. Should voice profiles be global preferences reusable across documents, or only per-document in v1?
6. Should users be allowed to create custom character profiles before detection finds them?
7. What minimum confidence should trigger automatic character voice playback?

## 17. Suggested Implementation Breakdown

1. Define domain models for reading segments, speaker profiles, attribution confidence, voice assignments, and document voice profiles.
2. Build the segment builder that consumes existing extracted PDF page text.
3. Build a local speaker attribution engine for quoted dialogue and script labels.
4. Build a voice assignment service using available Kokoro voices first and Piper model paths as fallback.
5. Build a playback planner that converts segments and assignments into speech instructions.
6. Extend the existing speech layer to support per-segment voice switching.
7. Add a character review panel with preview, voice override, and mode toggle.
8. Add per-document persistence and stale-profile handling.
9. Add tests around segmentation, attribution, assignment, planning, and persistence.
10. Add optional LLM provider interface after the local MVP is stable.

## 18. Decision Summary

This feature is worth prototyping if the goal is to make PDFReaderSpeaker feel more like an expressive audiobook reader. The recommended path is a local-first MVP: segment extracted text, detect obvious speakers, assign Kokoro voices with Piper fallback, let users correct mistakes, and persist settings per document. Optional LLM analysis can come later as an accuracy upgrade once the user experience and playback pipeline are proven.

### 9.4 Voice Engine Abstraction

1. Character playback uses a voice-engine abstraction with Kokoro as the primary engine and Piper as fallback.
2. The abstraction must expose availability checks, missing-model messages, local synthesis, and per-segment voice IDs.
3. The app must not require macOS system voices for character analysis or playback.
4. Model acquisition should be local/offline friendly: users may download or place ONNX assets under Application Support, and the app discovers cached assets there.
5. Redistribution must be license-gated: Kokoro assets require Apache-2.0 verification; any future Chatterbox reference requires MIT verification; prohibited weights must not be shipped.
