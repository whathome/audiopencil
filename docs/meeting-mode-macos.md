# macOS Meetings

Status: implementation specification; live-call release matrix remains to be verified  
Date: 2026-10-22

## Implementation status

The macOS workspace, disk-backed capture, source-aware processing, review and filing are implemented. Video-call capture is explicitly a Debug preview and remains unavailable in Release builds until the capture feasibility gate passes. Automated audio/core/streaming regressions pass, including repeated pause/stop recovery checks; the shared audio target also builds for iOS Simulator.

Choosing a call app starts a level-only preview in setup. Startup, switching and shutdown are serialized so a slow or cancelled start cannot leak an older stream; stale callbacks cannot update the current meter. Meeting recording waits for preview teardown. The preview saves no audio, plays nothing back and does not request microphone capture. It stops when leaving setup or starting dictation; source/permission errors stay visible with retry. The existing ScreenCaptureKit permission/indicator still applies while monitoring.

Interactive verification is incomplete: the debug-driving helper requires approval unavailable in the current session, so layout screenshots and the synthetic model-processing run could not be completed. Teams/Slack/browser calls, macOS 15 permission behavior, source drift, VoiceOver and the two-hour 8 GB benchmark remain release checks, not verified claims.

### Speaker echo reduction

New video-call recordings enable reference-based acoustic echo cancellation automatically. The unmodified MDF/KISS FFT subset of [SpeexDSP 1.2.1](https://github.com/xiph/speexdsp/tree/1b28a0f61bc31162979e1f26f3981fc3637095c8) is vendored as the `CSpeexDSP` target; source notices are preserved and the BSD notices ship in the audio resource bundle.

The archive queue feeds timestamp-aligned 16 kHz microphone/app frames to the adaptive filter, with a 250 ms microphone lookahead for callback ordering, 50 ms reference lead for converter latency differences and a 512 ms filter tail. Reference history is bounded to two seconds. No microphone gate is used during remote speech. A separate `localVoice` source drives the local meter, "You" transcript and playback mix; both raw sources remain in recovery storage. Pause/finish flush partial frames, and pause or microphone discontinuities reset adaptation. Failures stop capture through the existing error path, not a silent raw-microphone fallback. In-person capture and quick dictation do not opt in.

Before processing a saved call, incomplete or missing cleaned audio is reconstructed from the raw sources in bounded windows. New files replace the recovery index atomically only after successful completion; failures preserve the original index and delete the incomplete derived files. Already complete cleaned tracks are reused. Existing transcripts are not automatically rewritten.

Automated coverage includes delayed echo/reflections, double-talk, unequal chunks/late reference callbacks, silent remote audio, bounded buffers, invalid inputs, pause/tail recovery, atomic reconstruction from raw audio and exported playback using the cleaned source. Real speaker/interface/Bluetooth paths, nonlinear distortion, long delay and clock drift remain hardware acceptance checks. Headphones are still recommended; brief adaptation leakage and residual echo must not be represented as verified speakerphone separation.

## Outcome and scope

Add **Meetings** to the Mac app's left sidebar. A user can record an in-person conversation or a video call, then review a summary, decisions, action items and a speaker-labelled transcript. Everything is processed on device and filed through the existing storage queue.

The defining requirement for calls: **capture both the selected microphone and the other participants' app audio, even when the user wears headphones.** Recording the microphone alone does not satisfy call mode.

This is a recording-and-review workspace, not a meeting bot or a live collaboration tool. It inherits the existing macOS design: native controls, Pencil Amber for selection and primary actions, SF for controls, New York for written content, flat surfaces and the shared page alignment.

This proposal deliberately extends the PRD's current boundaries in two places: Mac call-audio capture and a bounded in-app meeting review. Obsidian or the user's notes folder remains the permanent library; there is no general-purpose in-app library, vault search or note editor.

## What already exists

| Existing capability | Reuse or limitation |
| --- | --- |
| Menu bar **Record a Meeting**, pill delivery toggle | Currently starts microphone-only dictation and marks its output as a meeting. |
| `SpeakerLabeler` and timed speech transcription | Reuse for speaker turns; labels do not identify real people. |
| `NoteMaker`, `Note`, Markdown rendering and storage outbox | Reuse filing, `mode: meeting`, review status, retention and offline delivery. |
| Microphone preference order and multichannel capture | Reuse device selection; unused interface inputs must not dilute the selected speech signal. |
| Model coordinator | Preserve sequential speech/writing model residency on 8 GB Macs. |
| Recent notes | Currently a small metadata list, not enough to reconstruct meeting detail or resume processing. |

The current recorder accumulates samples in memory. It is not the proposed durable long-meeting recording architecture. Meeting processing also currently falls back to an ordinary long-form note when labelling fails; the new flow must retain meeting identity and expose the failed stage.

## Navigation

- Add **Meetings**, using `person.2.wave.2`, immediately after **Dictation**.
- Sidebar order: Dictation, Meetings, Styles, My writing, Notes; then Storage and Settings.
- Keep the existing full sidebar and collapsed icon rail. A recording shows a labelled **Recording** status; the rail exposes the same state through its tooltip and VoiceOver value.
- Command-number navigation follows the new sidebar order, as it does today. Update menu commands and shortcut documentation together.
- The Meetings page is a persistent destination, never a button that starts recording merely because it is selected.
- Menu bar **Record a Meeting** opens this page and its prepared setup. Capture begins only after **Start meeting**, so source choice and consent are not bypassed.

## Page and flow

### 1. Ready

Use the existing page-header and leading-edge layout. The first screen has one clear action: **Start meeting**.

| Field | Behavior |
| --- | --- |
| Meeting title | Optional; defaults to a dated placeholder and can be renamed after recording. |
| Meeting type | **Video call** or **In person**. Remember the last choice on this Mac. |
| Microphone | Show the resolved device by name and an input meter. Allow a session-only override without changing global priority. |
| Call audio | Video call only: choose a running app, such as Teams, Slack or a browser. Show a separate meter and the precise capture scope. |
| Language | One language per meeting, using existing supported language choices. |
| Speakers | **Automatic** by default; optionally choose 2-6. This is a hint, not a claim of perfect speaker separation. |
| Note output | Use a meeting-specific summary format by default, not the frontmost app's dictation style. Show the filing destination and existing daily-note option. |

Readiness checks cover microphone access, call-audio access when applicable, source availability, writable local recording storage, and model availability. Model downloads happen before recording unless the user explicitly chooses **Record now, process later**. Missing vault configuration does not block recording: show **Saved on this Mac until storage is set up**.

Preflight meters run only while the setup view is visible and the user has granted the relevant access; they retain no audio. Stop them when leaving setup. Request call-audio permission only after the user chooses video-call capture.

Show a concise reminder: **Make sure everyone knows this meeting is being recorded.** Audio Pencil does not notify remote participants or satisfy a platform's recording-consent flow.

First-run empty copy: **Record a call or a conversation. Get a private summary, action items and a transcript.** Below setup, a compact recent-meetings list shows title, date, duration and processing/review status. Keep the existing recent-list scale of 50 items; do not scan or index the vault.

### 2. Recording

Replace setup with the meeting title, a monospaced elapsed recording time, and separately labelled source meters:

```text
Meetings

Weekly planning                         Recording  24:18
Microphone     Komplete Audio 6          [level]
Call audio     Microsoft Teams          [level]

[Pause]                                  [Stop meeting]
Discard recording...
```

- **Pause** stops retaining both sources; **Resume** resumes the same meeting. Paused time is excluded from captured duration, with a separate wall-clock start/end retained.
- **Stop meeting** finalizes the recording and starts processing. It never pastes into the frontmost application.
- **Discard recording...** is a secondary destructive action with confirmation. Escape must not silently erase a meeting, unlike quick dictation.
- Closing or navigating away from the window does not stop capture. The floating pill and menu bar show meeting status and provide Open, Pause/Resume and Stop.
- A meeting owns the capture session. Dictation hotkeys must not start another recorder, cancel the meeting or silently change its output mode. Meeting keyboard actions operate only with the meeting controls focused or through explicit menu commands.
- Preserve the selected source identity. If a microphone disappears, pause and offer a replacement; never silently switch to the laptop microphone.
- If the call app closes or capture access is revoked, pause and explain which source was lost. Offer explicit reconnection or continuation as microphone-only, marking the gap in the session.
- Quiet audio is not an error by itself. Show sustained low-input guidance, but never auto-stop a meeting because everyone is listening.
- Acquire an idle-sleep assertion while recording. Do not promise recording through system sleep or unsupported lid-close configurations; detect wake/interruption and expose the gap.

Live transcription is not part of v1. Meters and recording status provide feedback without competing with the user's call or promising final words before processing.

### 3. Processing

Make the durable recording visible immediately, before transcription or model loading. Present real stages, not an invented percentage:

**Recording saved -> Transcribing -> Labelling speakers -> Writing meeting note -> Filing**

For calls, transcription and speaker analysis operate on the separate sources as described below. Show the active stage and allow the window to close. A notification opens the completed meeting review, rather than immediately opening an external editor.

The capture state machine is `ready -> starting -> recording <-> paused -> stopping -> saved`; processing is a separate persisted job with queued, running, failed and complete stages. The recording device is released at `saved`, not held until writing or upload finishes.

A new meeting may be recorded while an earlier one waits for processing. Only one processing job uses the large models at a time. Recording takes priority over inference if the target Mac cannot sustain both safely.

### 4. Review

Open on **Summary**, with adjacent native sections **Actions** and **Transcript**. Use a single detail area rather than adding another permanent sidebar.

- Header: editable title, recorded date, duration, source type and filing state.
- Summary: concise overview, topics, explicit decisions and unresolved questions. Do not turn proposals into decisions or invent a section's content when none was heard.
- Actions: editable task text, owner and optional due date, using existing Markdown task/date conventions. Unknown owners and deadlines remain unset.
- Transcript: timestamped speaker turns, text selection and local audio playback. Selecting a turn seeks to its time in the saved recording.
- Speaker names can be assigned manually; maintain stable speaker IDs underneath. Rename updates the displayed transcript and generated speaker references without altering unrelated text.
- Local microphone speech is **You** in headphone call mode; remote voices start as **Speaker 1**, **Speaker 2**, etc. In-person recordings use neutral speaker numbers for everyone.
- Label uncertain attribution as uncertain. Do not claim identity recognition, cross-meeting speaker recognition or reliable separation of simultaneous speakers.
- Primary action: **Mark reviewed**, persisting `status: reviewed`. Secondary: **Open in Obsidian** or **Open file**, and **Copy summary**.
- Notes are already saved as `needs-review`; review is not required for durability or filing. Show **Saved on this Mac**, **Waiting to sync**, **Filed**, or an actionable filing error as distinct states.

Review edits are limited to the title, speaker names and extracted actions. The summary is selectable, not a general Markdown editor. Preserve edits across restart and retries. If the stored note changed externally, use the existing conflict-detection approach; never overwrite the external version silently.

## Audio and processing design

### Capture sources

- **In person:** selected microphone, with existing device-priority behavior. V1 supports one resolved microphone signal, not simultaneous independently labelled microphones from every soundcard input.
- **Video call:** microphone and selected-app audio as two independent timestamped sources. Do not feed them into the recorder's strongest-channel selector: that would discard one participant when both speak.
- Use Apple's public macOS audio-capture APIs, with ScreenCaptureKit as the initial implementation candidate for selected-app capture. No loopback-driver installation, accessibility scraping, meeting login or call-platform API integration.
- Explicitly exclude Audio Pencil's own playback from call capture. Do not retain screen frames.
- App capture must account for helper processes, app restarts and browser process ownership. A browser source may include other tabs; disclose that before capture. Do not promise per-tab isolation in v1.
- Do not silently broaden a selected-app filter to whole-system audio. If selected-app capture is unsupported for an app, report that limitation.
- Headphones are the recommended video-call setup. Speakerphone use can duplicate remote voices through the microphone. Test the public echo-cancellation options; do not ship a claim of deduplicated speakerphone capture without evidence. Otherwise show the limitation and recommend headphones or explicit in-person capture.

### Durable session

Introduce a disk-backed meeting session, not another growing `[Float]` recording:

- Stable session UUID, title, language, source identifiers, timestamps, pause/gap markers, speaker hints, processing stage, errors and final note path.
- Write source audio incrementally to recoverable local segments. Use a shared monotonic timeline, record source offsets and gaps, and handle drift before aligning turns or mixing playback.
- Bound memory by chunk size, not meeting duration. Never load every source plus a full mixed recording into memory.
- Persist recording checkpoints at least every five seconds. On restart, offer to process or discard a recoverable interrupted meeting; never resume capturing automatically.
- Store timed transcript segments, speaker IDs/name mappings and structured summary/actions alongside the manifest. The existing `RecentNote` record alone is insufficient.
- Preserve original captured audio through processing failures. Resampling, speaker naming and summary generation must be retryable without recording again.

### Transcription and speaker analysis

For in-person capture, reuse timed transcription and speaker diarization over the microphone recording.

For headphone calls, transcribe the microphone and remote sources separately, identify the local source as **You**, and diarize the remote source. Merge the resulting turns on the shared timeline, preserving overlaps rather than forcing every instant to one speaker. Do not run undifferentiated diarization over a mixed call and then guess which speaker is the user.

Reuse the active engine's timed-word protocol where supported; do not hard-code the old assumption that only Whisper can supply timings. Speaker-count hints apply to total people, with source-aware handling of the local participant.

Process long meetings in bounded overlapping windows with timestamp reconciliation and stable speaker mapping. Summarize the whole meeting through hierarchical chunk summaries, carrying decisions, owners, dates and unresolved questions forward. Never silently truncate the transcript to a writing model's context limit.

Speech and writing models remain sequentially resident under the existing model coordinator. Set an engineering target of a two-hour meeting on the 8 GB reference Mac without duration-proportional RAM growth; benchmark actual time to completion rather than promising real-time processing.

### Filing and retention

Reuse the existing `Note`, Markdown renderer, storage outbox and review statuses. Keep `mode: meeting` even when speaker labelling or summarization fails; surface the partial result and failed stage.

Export a readable summary, decisions, questions, Markdown action checkboxes and labelled transcript. Preserve existing frontmatter and add only optional, backward-compatible meeting metadata where required. Keep session identity and source type so the recent list can reopen the correct local review.

Attach one timeline-aligned playback recording through the existing note/audio link. For calls this is a derived mix of both sources, not a substitute for keeping the separate originals during processing. Prevent clipping when mixing.

Retain separate source segments locally for processing retries, along with the derived playback recording. Failed or interrupted sessions retain their recovery files. Both source and final audio follow regular/archive/delete retention; successfully processed regular recordings expire after one year unless kept forever. Deleting a local meeting removes its recovery files and review data; the UI explicitly distinguishes this from deleting an already filed note in external storage. A filed note deleted or moved externally leaves the local recent list and its local cache is removed at the next successful storage check.

No cloud inference or new telemetry. Audio and text leave the Mac only through the user's configured storage. Explain system privacy permissions without implying that app-level participant notification exists.

## Failure states

| Situation | Required response |
| --- | --- |
| Permission denied | Identify microphone vs call-audio access, provide the correct system-settings action, and preserve setup. |
| Selected source unavailable | Prevent a misleading start or pause the active session; let the user explicitly replace the source. |
| No speech detected | Preserve the recorded meeting, show the input status and offer playback or retry; do not generate fictional notes. |
| Model missing, download unavailable or inference fails | Keep audio; show the failed stage and retry/process-later actions. |
| Speaker analysis fails | Keep a transcript without confident labels, retain meeting mode, and offer retry. |
| Writing model fails | Keep the timed transcript and audio; expose that the summary is unavailable. |
| Storage offline/unconfigured | Keep a local review and queued output. Do not display **Filed**. |
| Disk full/write failure | Stop capture safely, preserve committed segments and show an urgent recording error. |
| Quit while recording | Ask to stop and save, or cancel quitting. Force quit/crash uses checkpoint recovery. |
| Sleep or audio route interruption | Record the gap and show the last durable capture time; never imply continuous capture. |

## Acceptance criteria

1. Meetings is reachable from the expanded sidebar, icon rail, keyboard navigation and menu bar.
2. Source names and permission readiness are visible before recording starts.
3. With headphones in a Teams or Slack call, the final playback and transcript contain both local and remote speech.
4. Selected-app capture excludes an unrelated app playing audio; any browser scope limitation is clearly disclosed.
5. In-person capture works with the built-in microphone and Komplete Audio 6 input 1, without unused-channel attenuation.
6. Simultaneous local/remote speech remains in both source recordings and is not eliminated by strongest-channel selection.
7. Pause excludes both sources, resume keeps the same meeting, and transcript seeking stays aligned after pauses.
8. Device disconnect, app exit, permission loss and sleep never silently substitute a source or erase a recording.
9. A two-hour session uses bounded capture memory and survives a forced restart with no more than five seconds of already received audio lost under normal writable-disk conditions.
10. Summary generation covers the beginning, middle and end of a long meeting; it does not silently drop late actions.
11. Speaker rename, action edits and reviewed status survive restart and export correctly without clobbering external note changes.
12. A failed processing stage can be retried without recapture, duplicate notes, or replacement of user edits.
13. Offline recordings are reviewable locally and file once storage returns. Local-save and remote-file states remain distinguishable.
14. VoiceOver exposes sources, recording state and controls; keyboard focus, narrow-window rail mode, Dark Mode, Increase Contrast and Reduce Motion remain usable.
15. Quick dictation and iPhone recording retain their existing behavior.

## Delivery sequence and gates

1. **Capture feasibility gate:** prove selected-app audio plus the explicitly selected microphone on the macOS 15 deployment target. Cover Teams, Slack and a browser call, headphones, helper processes, permission denial/revocation, app restart, source drift and simultaneous speech. Document the actual system permission behavior. Do not treat microphone-only recording as completion of this gate.
2. **Reliable recording foundation:** disk-backed sessions, shared timeline, pause, interruptions, checkpoints, recovery, retention and capture ownership.
3. **Meetings workspace:** sidebar entry, setup, recording controls, durable recent sessions and processing states, reusing the existing native page composition.
4. **Review and filing:** source-aware timed transcription, speaker naming, structured summary/actions, playback seeking and conflict-safe review persistence.
5. **Release gate:** complete the acceptance matrix and benchmark the 8 GB reference Mac. In-person mode may be delivered first, but call mode remains visibly unavailable until its capture gate passes.

Out of scope: automatic meeting detection, calendar integration, joining calls, platform recording bots, automatic participant names, live coaching, manual live notes, cross-meeting search, external task-system integration, cloud AI, multilingual code-switching, per-browser-tab capture guarantees, and arbitrary multi-microphone studio mixing.
