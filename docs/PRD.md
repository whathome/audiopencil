# Audio Pencil — PRD

Oct 18, 2026 · @Wes

## Overview

Audio Pencil is a private, fully on-device AudioPen equivalent for Mac and iPhone: talk, get clean text or a styled summary, and have it pasted where you're working or filed in Obsidian. No cloud AI; the only server is the user's own Nextcloud, used as plain WebDAV storage.

**Goals**

- Fast, zero-friction dictation on the Mac: hotkey, talk, text pasted into the active field within about 2 seconds.
- Long-form walk-and-talk recording on the iPhone (diary entries, professional thinking, in-room meetings), processed in the background.
- User-defined summary styles, including a "like me" style grounded in the user's own writing.
- Lean app: Obsidian is the library, search, tagging and review surface; Nextcloud is the storage and sync layer.

**Non-goals**

- Cloud transcription or cloud LLMs of any kind.
- An in-app library, search, or review screens beyond a minimal recent list.
- AudioPen extras: combining notes into one summary, importing audio files, rewriting old notes in a new style.
- Mixing languages within one recording (each recording has one language; see Languages).
- App lock (passcode or Face ID).
- A custom server on the Raspberry Pi.

## Platforms, phasing and stack

Phase 1 is the Mac app, built and run locally without a paid Apple Developer account, to prove every workflow. Phase 2 is the iPhone app and keyboard extension, after the user buys a developer account.

| Item | Decision |
| --- | --- |
| Mac target | M1 MacBook Air, 8 GB RAM (the binding constraint) |
| iPhone target | iPhone 17 Pro Max |
| Language / UI | Native Swift, SwiftUI; shared core package for Mac and iOS |
| Transcription | WhisperKit, streaming while recording: an English-only model for English, a multilingual model for every other language |
| Summarization | Open-weight LLM via MLX Swift, about 3B parameters, 4-bit quantised on Mac |
| Memory rule | Load transcription and summary models sequentially on 8 GB, never both at once |
| Repo | User's Forgejo instance, private |
| Name | Audio Pencil |

## Mac: quick dictation

The Mac app is a paste-and-forget workflow accelerator: hotkey, talk, hotkey, and text lands in the active field with no questions asked.

1. **Arm.** User presses the activation key (default: double-tap Fn; configurable). Requires Microphone, Accessibility and Input Monitoring permissions.
2. **Mic selection.** App walks the user's preferred-microphone priority list and uses the first available device.
3. **Confirm.** On a successful start, play a double "tricorder" beep and show a small floating indicator at bottom centre of the screen.
4. **Listening feedback.** Indicator animates with live mic level; if no audio is detected it shows a small red X.
5. **Live transcription.** Audio is transcribed while the user talks, so little work remains at stop.
6. **Stop.** User presses the activation key again; a single beep confirms. Escape at any point cancels and discards immediately, no confirmation.
7. **Style picker.** A compact picker appears with styles on number keys plus "Raw transcript". The per-app default for the frontmost app is preselected and auto-confirms after a short configurable delay (default about 1 s). The default style starts processing while the picker is shown.
8. **Deliver.** Result is copied to the clipboard and pasted into the active input. If there's no text field, it stays on the clipboard and a small clipboard icon appears.

**Per-app defaults:** the picker remembers the chosen style per frontmost app (e.g. raw in Mail, technical writing in Obsidian); unseen apps fall back to the last-used style.

**Promotion to long-form:** if a hotkey recording exceeds the long-form threshold (configurable, default 5 min), it does not paste. It is processed as a long-form entry (audio kept, note written to the vault straight away as needs-review) and the user is notified when done. A toggle on the recording indicator overrides this per recording: make any recording a note, or paste a long one.

**Saving quick dictations:** configurable; default is paste-and-forget (audio and text not saved).

**App presence:** Dock icon by default; menu bar mode as an option. Launch at login.

## iPhone (phase 2)

The iPhone is the long-form, walk-and-talk recorder, usually with the phone's own mic held like a speakerphone, sometimes AirPods.

**Recording**

- Transcribes live on device while recording; keeps recording with the phone locked in a pocket (background audio).
- Start, stop and pause through App Intents, exposing the Action Button, Lock Screen and Control Centre controls, Siri and Shortcuts. No single trigger is mandated.
- Pause and resume within one recording.
- Audio cues: same tricorder beeps as the Mac on start, pause and stop, plus a haptic.
- Heartbeat haptic while recording, only when the screen is off or the device is locked; pattern and interval configurable so it doesn't feel like a text message.
- If the active input (e.g. AirPods) disconnects, pause the recording and alert with a distinct haptic and sound.
- Auto-stop after no intelligible speech for a configurable period (max and default 5 min); trim the trailing silence and process as normal.
- Light noise suppression for outdoor wind and traffic.

**After recording**

- Choose a style when recording ends (defaults to last-used).
- Long-form processing runs in the background; the note is filed straight away as needs-review, with a notification when done (see Obsidian integration).

**Meeting mode**

- Chosen deliberately before (or during) a recording; enables on-device speaker detection (Speaker 1, Speaker 2…). Default mode assumes a single speaker, and every recording starts in it.
- Phone sits on the table and picks up the room, including video-call audio from speakers. Also on the Mac (Oct 2026): the recording indicator's Paste / Note / Meeting toggle and "Record a Meeting" in the menu bar; the Mac's microphone hears the room.
- The number of speakers is worked out, or chosen (2–6) when known, which helps accuracy.
- Implemented with Argmax SpeakerKit (pyannote, about 22 MB, downloaded on first use) and a second Whisper pass with word timings; the note keeps the labelled transcript and notes `speakers:` in its frontmatter.

**Keyboard extension**

- Follows the AudioPen / Wispr Flow pattern: first use hops to the main app to start a background mic session, then the keyboard signals the main app via a shared app group to record and transcribe, and inserts the returned text.
- Requires "Allow Full Access". Session keep-alive is configurable (default 15 min); after timeout, one more hop.
- Style defaults to last-used with a one-tap change (iOS can't reliably identify the host app, so no per-app defaults).

## Models, styles and voice

All inference runs on device; the user picks from a curated, swappable model list for both transcription and summarization.

**Models**

- App ships a curated catalogue of recommended models per device class; user can switch at any time.
- Model discovery is automatic: the app periodically searches Hugging Face for compatible WhisperKit and MLX models that fit the device's memory, ranks them, and suggests upgrades. Nothing switches without the user's approval, and there is no list for the user to maintain.
- Custom vocabulary list (names, places, tech terms) from the config file is fed to transcription as prompt context and to the LLM as spelling guidance. One list applies to every language, plus an optional list per language.

**Languages** (added Oct 2026)

- Dictation works in any language Whisper supports; several can be in use on one machine. One language per recording.
- Language is chosen from the recording indicator or Settings. The default is the language last spoken in the frontmost app, per machine (not synced); new apps start in the language last used anywhere on that machine.
- Styles write in the spoken language. Writing models declare which languages they handle; others fall back to the raw transcript, and model discovery favours models covering the languages in use.
- Like me samples record their language and same-language samples are used first.
- The interface follows the system language: English, French and Spanish.

**Styles**

- A style is a named prompt plus: picker shortcut key, landing folder, whether audio is kept, and whether it runs as quick or long-form. Each style also sets: rewrite intensity (light cleanup through heavy rewrite), voice or tone (e.g. business, professional, casual, like me), output length, whether tags are suggested, and whether action items are extracted.
- Built-in presets: **Raw transcript** (no rewriting), **Diary** (light tidying only: remove filler, fix punctuation, add paragraphs, never change wording), **Professional** (summary plus key points and themes; extracts action items by default on long-form recordings, never on quick dictation), **Like me**.
- Quick dictation styles never prompt for tags or filing.

**"Like me" writing reference**

- A "My writing" section where the user adds samples of their own writing.
- Interview mode: the app presents a set of writing prompts; the user types answers, which become the style reference. Samples are passed as few-shot examples, not used for fine-tuning.
- Starter prompt set: see the interview prompts below.

**Starter interview prompts**

Answers are typed, not dictated, at 100 to 300 words each, written the way the user normally writes. Each answer is labelled with its type of writing, so the "like me" style can pick the closest examples for each new note.

1. **Work email:** Tell a colleague or client that something is running late, why, and what happens next.
2. **Technical explanation:** Explain to a smart, non-technical friend why you run your own server instead of using cloud services.
3. **Instructions:** Write step-by-step instructions for a task you know well, around the house or on a computer.
4. **Opinion:** Pick a tool, product or habit you feel strongly about and argue for or against it.
5. **Problem story:** Describe something that broke or went wrong recently and how you worked it out.
6. **Diary:** Write a few honest paragraphs about how today actually went.
7. **Decision:** Lay out a decision you're weighing, the options, and which way you're leaning.
8. **Short messages:** Write three quick texts: making plans, turning something down, and thanking someone.
9. **Feedback:** Give honest feedback on someone's idea or piece of work, kind but direct.
10. **Place:** Describe a place you know well to someone who has never been there.
11. **Recap:** Summarise a recent conversation or meeting for someone who missed it.

**Tags**

- Model suggests tags from the master taxonomy in the vault; it may propose new tags, which require the user's approval before joining the list.

## Storage and sync

There is no app server: both apps read and write files directly to the user's publicly reachable Nextcloud over WebDAV, which is the source of truth. The storage layer sits behind an interface so another provider can be added later.

**Connection**

- Auth: user chooses Nextcloud Login Flow v2 (browser sign-in) or a manually entered app password. Credentials in the Keychain. No 2FA in use.
- Offline-first: every recording and note is written locally first and queued; uploads retry until the server is reachable, so dead zones never lose data.

**Vault layout**

- Landing zones: each style points to a folder chosen by browsing the WebDAV tree (e.g. a Diary folder and a Dictation folder inside the Obsidian vault).
- Long-form audio goes to a recordings folder in the vault and is linked from its note.
- One Markdown file per entry with YAML frontmatter. Filename: `YYYY-MM-DD HHmm <suggested title>.md`, with a `-2` suffix on the rare collision.
- Professional notes: summary first, raw transcript below in a collapsed callout in the same note.

**Retention**

| Recording type | Audio | Transcript and note |
| --- | --- | --- |
| Quick dictation (under threshold) | Deleted after transcription | Not saved by default (configurable) |
| Long-form (over threshold, default 5 min) | Kept 1 year, rolling | Kept permanently |

A view of audio about to expire is a low-priority nice-to-have.

**Configuration**

- One shared config file in a config folder in the vault holds styles, writing samples, master tag list, custom vocabulary, and per-device sections (mic priority, hotkey, keep-alive, haptic pattern). Each device reads its own section.
- Edited through an in-app settings UI, persisted to the vault, and also hand-editable in Obsidian. Writes must merge safely when both devices edit (use WebDAV ETags and re-read on conflict).

## Obsidian integration

Obsidian is the library and review surface: the app writes consistent frontmatter, and a Bases file (native Kanban view, Obsidian 1.14+) turns it into the review board.

**Frontmatter written on every note**

| Property | Example |
| --- | --- |
| `type` | `audio-pencil` |
| `style` | `diary`, `professional`, `like-me`, `raw` |
| `status` | `needs-review`, `reviewed`, `actioned` |
| `recorded` | ISO date-time |
| `duration` | seconds |
| `device` | `mac`, `iphone` |
| `mode` | `quick`, `long-form`, `meeting` |
| `tags` | from the master taxonomy |
| `audio` | link to the file in the recordings folder |

**Review flow (long-form only)** (changed Oct 2026)

- Notes are filed in the vault as soon as processing finishes, with `status: needs-review` and the suggested title and tags. There is no review window on either platform.
- Review happens on the board: drag a card to reviewed, then actioned.

**Bases file created by the app**

- "Professional review" view: Kanban grouped by `status` (Needs review, Reviewed, Actioned), filtered to `style: professional`. Dragging a card updates the note's frontmatter.
- "Diary" view: simple list filtered to `style: diary`, newest first.
- "All recordings" view: table across every style.

**First run**

- If the Bases file or config folder is missing, the app creates them and runs a brief walkthrough of how to use the board.

* On first run the app also writes an "Audio Pencil guide" note into the vault: Obsidian coaching on how to use properties, the Bases views and the review statuses, with worked examples.
* It also writes a few sample notes (one Diary, one Professional with action items and a collapsed transcript, one in needs-review) so the board shows real cards straight away. Samples are tagged `sample` and safe to delete.

## Defaults, open questions and future work

**Defaults chosen by Claude (change freely)**

- Long-form threshold 5 min; picker auto-confirm about 1 s; iOS keep-alive 15 min; silence auto-stop 5 min.
- Filename includes time to the minute; professional transcript in a collapsed callout.
- Notification and error wording, and graceful handling of model load failures, full storage and missing permissions.

**Open questions**

- [ ] Resolved: model suggestions come from automatic Hugging Face discovery (see Models).
- [ ] Resolved: style fields defined (see Styles).
- [ ] Resolved: Professional extracts action items by default on long-form only.
- [ ] Resolved: starter interview prompts drafted (see "Like me" writing reference).

**Future work**

- System-audio capture on the Mac for video calls (meeting mode there uses the microphone today).
- Storage providers beyond Nextcloud WebDAV.
- View of audio about to roll off the one-year archive.
