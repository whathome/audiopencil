# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Native Apple: SwiftUI on a shared Swift package. The **macOS** app and universal **iPhone/iPad** app (with recording controls and a Live Activity) are implemented. Mac video-call capture remains a Debug preview pending live-call validation. Apple HIG governs structure and interaction across platforms.

## Users

The builder first: one person who dictates all day on an M1 MacBook Air, keeps a personal Obsidian vault on their own Nextcloud and a work vault in iCloud Drive, and records long walk-and-talk notes. Jobs:

- Quick dictation: talk into whatever text field is focused and get clean text pasted, without leaving the app they're in.
- Long-form thinking: diary entries, professional thinking and meetings, turned into reviewed notes in Obsidian.

It may be shared or distributed later, so copy, onboarding and settings must not assume the builder's particular server, vault paths or habits.

## Product Purpose

A private, fully on-device AudioPen: talk, get raw text or a styled rewrite, and have it pasted where you're working or filed in Obsidian. Success means speech becomes usable text faster than typing, with no audio or text ever leaving the user's devices except to storage they own.

## Positioning

Everything runs on the device: Whisper for transcription and a small local LLM for rewriting, with no cloud AI of any kind. Storage is the user's Nextcloud, any WebDAV server, or a local/iCloud folder. Obsidian or that Markdown folder is the permanent library; recent-note lists, the mobile writing queue and meeting review are bounded workflow surfaces. Styles, vocabulary and "Like me" writing samples live in a plain settings file in configured storage that the user can also edit by hand.

## Operating Context

- Mac quick dictation: double-tap Fn starts, tap Fn or Return stops, Esc cancels. A floating pill sits at the bottom of the screen; tricorder-style beeps confirm start and stop. Number keys switch style while recording, and the pill's Paste / Note / Meeting toggle decides what stopping does for this recording.
- Push-to-talk (hold Fn) pastes the raw text; while holding, its pill badge can also add the line to the Obsidian daily note or a chosen file.
- Recordings longer than the long-form threshold (default 5 min) become notes, filed straight away as needs-review with suggested title and tags; review happens on the Obsidian board, not in the app. Notes can be linked in the day's daily note.
- iPhone: a walk-and-talk recorder that keeps going with the phone locked in a pocket (Live Activity, Control Centre, Action Button, Siri). Transcription keeps up in the background, but the writing model needs the app on screen, so notes queue and are written while it's open. A recording can also be copied instead of filed and filed later.
- iPad: the same recorder and in-person Meetings, with adaptive sidebar/tab navigation, list/detail note reading, both orientations and compact multitasking layouts.
- Meetings: require a title beside Start Meeting on every platform; save audio to recoverable disk segments, then process and review Summary / Actions / Transcript. Mac call-app choices refresh when the dropdown opens; missing access links to Settings › Permissions rather than prompting from setup.
- Obsidian Bases board in the vault: Professional review (Kanban by status), Diary, All recordings, and Retention (Regular / Archive / Delete).
- The app runs mostly in the background (Dock or menu bar). The main window is for configuring, checking status and occasional review, not a place to spend time.
- Target hardware is 8 GB of RAM, so the transcription and writing models are never resident together. Styled output takes seconds; raw output is near-instant.

## Capabilities and Constraints

- Styles: Raw (0), Polished, Diary, Professional and Like me, plus user-defined styles with intensity, tone and length. Per-app style memory.
- My writing: interview prompts collect writing samples, which are used as few-shot examples for Like me.
- Model discovery on Hugging Face scales to the machine's RAM. Nothing switches without approval.
- Storage: one provider at a time (Nextcloud, any WebDAV server, or a local or iCloud folder), as an Obsidian vault or plain Markdown. Writes are offline-first, go through a queue, and are merged with ETags. Settings and board files can be repaired, with backups.
- Tasks: action items and task-keyword dictations become Obsidian Tasks lines with spoken due and start dates.
- Meeting mode labels speakers on device (Mac, iPhone and iPad).
- Mobile model switches wait for active recording/processing; synced engine changes are deferred safely. Queued notes can be skipped, resumed or deleted with confirmation without losing later work.
- Mac shortcuts require Microphone and Accessibility, not Input Monitoring. A timed-out keyboard event tap is removed and stays off until relaunch, with a visible status and menu-bar controls still available.
- Retention: quick dictations aren't saved by default; long-form audio is kept for 1 year unless archived; the board's Delete column removes the note and its audio.
- No network except the user's own storage and Hugging Face model downloads. Interface in English, French and Spanish; dictation in any of Whisper's languages. No app lock.
- Builds and runs locally from Xcode with a Personal Team, outside the App Store.

## Brand Commitments

- Name: **Audio Pencil**.
- Audio cues: double "tricorder" beep on start, single beep on stop. Sound themes are configurable, and tricorder is the default.
- AudioPen is the acknowledged reference for workflow, not for identity.

## Evidence on Hand

- `docs/PRD.md`: full product requirements.
- `docs/benchmarks/`: measured summary-model benchmarks on the M1 8 GB target.
- `docs/screenshots/dictation.png`: current Dictation page.
- First-run starter kit in the vault: guide note, sample notes and the board.
- There are no users other than the builder, and no testimonials, pricing, licensing or distribution claims. Do not invent any.

## Product Principles

1. **Private by construction.** On-device processing is the product, not a feature, and nothing should suggest otherwise.
2. **Out of the way.** The hotkey is the main interface. Every window, prompt or confirmation has to justify interrupting someone mid-thought.
3. **The user's storage is the library.** Don't rebuild general-purpose vault search or editing; keep recent-note, queue and meeting-review workflows bounded, write good files and make the Obsidian board work.
4. **Honest about the machine.** Show model state, memory limits and slow steps plainly rather than hiding them.
5. **Plain files the user owns.** Settings, notes and audio are readable, hand-editable and recoverable.

## Accessibility & Inclusion

Platform defaults: respect Dynamic Type or text size, VoiceOver, Reduce Motion, Increase Contrast and system appearance as macOS and iOS expect. No additional product-specific requirement.
