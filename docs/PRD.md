# Audio Pencil — PRD

Updated Oct 27, 2026 · @Wes

## Overview

Audio Pencil is a private, fully on-device AudioPen equivalent for Mac, iPhone and iPad: talk, get clean text or a styled summary, and have it pasted where you're working or filed in Obsidian or any Markdown folder. No cloud AI; storage is a local/iCloud folder, the user's Nextcloud or another WebDAV server.

**Goals**

- Fast, zero-friction dictation on the Mac: hotkey, talk, text pasted into the active field within about 2 seconds.
- Long-form walk-and-talk recording on the iPhone (diary entries and professional thinking), including background capture, with writing queued until the app is active.
- Dedicated, recoverable meeting capture and review on Mac, iPhone and iPad.
- User-defined summary styles, including a "like me" style grounded in the user's own writing.
- Lean app: Obsidian or the user's Markdown folder is the permanent library; configured storage is also the settings-sync layer.

**Non-goals**

- Cloud transcription or cloud LLMs of any kind.
- A general-purpose in-app library, vault search or note editor. Recent-note lists, the mobile writing queue and bounded meeting review are workflow surfaces, not replacements for the user's library.
- AudioPen extras: combining notes into one summary, importing audio files, rewriting old notes in a new style.
- Mixing languages within one recording (each recording has one language; see Languages).
- App lock (passcode or Face ID).
- A custom server on the Raspberry Pi.

## Platforms and stack

The macOS app and universal iPhone/iPad app are implemented and build locally from Xcode with a free Personal Team; a paid Apple Developer account is not required for local development. Mac video-call capture is a Debug-only preview pending live-call acceptance checks.

| Item | Decision |
| --- | --- |
| Mac target | M1 MacBook Air, 8 GB RAM (the binding constraint) |
| iPhone target | iPhone 17 Pro Max |
| iPad support | Universal iOS target with adaptive navigation, all orientations and compact multitasking layouts |
| Deployment targets | macOS 15+ on Apple silicon; iOS/iPadOS 26+ |
| Language / UI | Native Swift, SwiftUI; shared core package for Mac and iOS |
| Transcription | WhisperKit, streaming while recording: an English-only model for English, a multilingual model for every other language |
| Summarization | Open-weight LLM via MLX Swift, about 3B parameters, 4-bit quantised on Mac |
| Memory rule | Load transcription and summary models sequentially on 8 GB, never both at once |
| Repo | `whathome/audiopencil` on GitHub |
| Name | Audio Pencil |

## Mac: quick dictation

The Mac app is a paste-and-forget workflow accelerator: hotkey, talk, hotkey, and text lands in the active field with no questions asked.

1. **Arm.** User presses the activation key (default: double-tap Fn; configurable). Requires Microphone and Accessibility permissions, not Input Monitoring. Optional **Online meeting audio** access is managed separately in Settings › Permissions.
2. **Mic selection.** App walks the user's preferred-microphone priority list and uses the first available device.
3. **Confirm.** On a successful start, play a double "tricorder" beep and show a small floating indicator at bottom centre of the screen.
4. **Listening feedback.** Indicator animates with live mic level; if no audio is detected it shows a small red X.
5. **Live transcription.** Audio is transcribed while the user talks, so little work remains at stop.
6. **Stop.** User presses the activation key again; a single beep confirms. Escape at any point cancels and discards immediately, no confirmation.
7. **Style selection.** The recording starts with the frontmost app's remembered style; number keys or the pill's style menu change it while talking. An optional post-stop picker preselects that style and auto-confirms after a short configurable delay (default about 1 s).
8. **Deliver.** Result is copied to the clipboard and pasted into the active input. If there's no text field, it stays on the clipboard and a small clipboard icon appears.

**Per-app defaults:** the picker remembers the chosen style per frontmost app (e.g. raw in Mail, technical writing in Obsidian); unseen apps fall back to the last-used style.

**Promotion to long-form:** if a hotkey recording exceeds the long-form threshold (configurable, default 5 min), it does not paste. It is processed as a long-form entry (audio kept, note written to the vault straight away as needs-review) and the user is notified when done. A toggle on the recording indicator overrides this per recording: make any recording a note, or paste a long one.

**Saving quick dictations:** configurable; default is paste-and-forget (audio and text not saved).

**App presence:** Dock icon by default; menu bar mode as an option. Launch at login.

**Keyboard reliability:** the native event tap classifies input on a dedicated thread without synchronous UI work. If macOS disables it for a timeout, remove it immediately and keep it disabled for the rest of that app run. Stop an active dictation normally, explain that shortcuts are paused, and retain menu-bar controls. Relaunch restores shortcuts; automatic retries must not create a timeout loop. Quit before replacing a running development app's executable.

## iPhone and iPad

The iOS target is universal. iPad uses adaptive native sidebar/tab navigation, regular-width list/detail note reading and all orientations, including compact multitasking windows. A dedicated Meetings workspace records in-person conversations to recoverable disk segments and reviews summaries, actions and speaker-labelled transcripts. It shares the Mac's processing and conflict-safe filing pipeline, but not macOS selected-app audio capture. Recording supports background audio; meeting inference is foreground-only and resumes saved processing on return.

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
- Choose **Make Note**, **Add to Daily Note** when available, or **Copy to Clipboard**. Copied recordings keep their audio and can be filed later from Notes.
- Writing runs only while the app is active because the MLX model needs the GPU. Leaving interrupts writing safely; saved work resumes on return, and background-stopped recordings wait in the queue. Completed notes file as needs-review (see Obsidian integration).
- Model and language settings are locked during recording, saving or processing; synced engine changes wait until work finishes. Unrelated settings remain usable, and the recording screen retains its deliberate language switch.
- Notes offers **Skip for Now**, **Resume Writing** and confirmed deletion. Skipping preserves audio and transcript across relaunches and lets later work proceed.

**Daily note** (Oct 2026)

- Notes can be linked (or embedded) in the day's Obsidian daily note under a configurable heading; on by default in Settings, overridable per recording. A missing daily note is created from the plugin's folder, format and template. Only offered while the Daily notes core plugin is on.
- Push to talk only pastes; during the hold the text can also be appended as a timed line to the daily note or a chosen file (under a heading or at the end). Task-keyword lines go in untimed as tasks.

**Meeting mode**

- **Meetings** is a dedicated workspace on all platforms; mobile **Record** is the separate single-speaker workflow. Meeting processing enables on-device speaker detection (Speaker 1, Speaker 2…).
- Require a nonblank meeting title beside **Start Meeting** on every platform. Trim surrounding whitespace, reject whitespace-only titles before capture, and allow renaming after recording.
- Phone or iPad sits on the table and picks up the room through the system microphone; neither captures another app's audio directly. On the Mac, **Meetings** in the sidebar provides in-person capture and Debug-preview selected-app call audio alongside the microphone, with headphone support. The dictation pill's older microphone-only meeting toggle remains available. See [macOS meeting specification](meeting-mode-macos.md).
- Call-app choices refresh automatically when setup loads and whenever the dropdown opens, only after access has been granted. Missing access is labelled and links to **Settings › Permissions**, where **Online meeting audio › Allow…** owns the permission request; setup does not request it automatically.
- Write meeting audio to bounded five-second disk segments with interruption recovery. Support pause/resume, explicit discard, processing later, playback and Summary / Actions / Transcript review. Keep local recovery files on processing or filing failures.
- Review edits titles, speaker names and Markdown actions; filing uses the offline queue and never silently overwrites external note changes. Deleting a local meeting does not delete a note already filed in storage.
- The number of speakers is worked out, or chosen (2–6) when known, which helps accuracy.
- Implemented with Argmax SpeakerKit (pyannote, about 22 MB, downloaded on first use) and a second Whisper pass with word timings; the note keeps the labelled transcript and notes `speakers:` in its frontmatter.

## Models, styles and voice

All inference runs on device; the user picks from a curated, swappable model list for both transcription and summarization.

**Models**

- App ships a curated catalogue of recommended models per device class; explicit model switches wait until conflicting recording or processing work finishes.
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
- Built-in presets: **Raw transcript** (no rewriting), **Polished** (default; cleaned-up text in the user's words), **Diary** (light tidying only: remove filler, fix punctuation, add paragraphs, never change wording), **Professional** (summary plus key points and themes; extracts action items by default on long-form recordings, never on quick dictation), **Like me**.
- Quick dictation styles never prompt for tags or filing.

**"Like me" writing reference**

- A "My writing" section where the user adds samples of their own writing.
- Interview mode: the app presents a set of writing prompts; the user types answers, which become the style reference. Like me becomes available after three samples; matching samples are passed as few-shot examples, not used for fine-tuning.
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

- Model suggests tags from the master taxonomy in configured storage. Suggested tags are used when filing; new ones join the shared tag list automatically.

## Storage and sync

There is no app server. One configured provider at a time stores notes, audio and shared settings: Nextcloud, any WebDAV server, or a local/iCloud folder. Obsidian is optional; plain folders receive standard Markdown and relative audio links rather than vault-specific syntax and board files.

**Connection**

- Nextcloud auth: browser sign-in through Login Flow v2 or a manually entered app password. Other WebDAV servers use a URL, username and password. Credentials stay in the Keychain; local folders use the platform's file-access permissions.
- Offline-first: every recording and note is written locally first and queued; uploads retry until the server is reachable, so dead zones never lose data.

**Vault layout**

- Landing zones: each style points to a folder chosen by browsing the WebDAV tree (e.g. a Diary folder and a Dictation folder inside the Obsidian vault).
- Long-form audio goes to a recordings folder in the vault and is linked from its note.
- One Markdown file per entry with YAML frontmatter. Filename: `YYYY-MM-DD HHmm <title>.md`, with a `-2` suffix on the rare collision. Ordinary notes use a suggested title; meetings use the required user-entered title.
- Professional notes: summary first, raw transcript below in a collapsed callout in the same note.

**Retention**

| Recording type | Audio | Transcript and note |
| --- | --- | --- |
| Quick dictation (under threshold) | Deleted after transcription | Not saved by default (configurable) |
| Long-form (over threshold, default 5 min) | Kept 1 year, rolling | Kept permanently |

The Retention board groups notes as regular, archive or delete. The Notes page lists audio expiring within 30 days and offers **Keep forever**; recent notes also offer deletion without requiring Obsidian.

**Configuration**

- `Audio Pencil/Settings.md` in configured storage holds a YAML block with styles, writing samples, master tags, vocabulary and per-device sections (mic priority, hotkeys, models and recording feedback). Each device reads its own section; per-app memory stays local.
- Edited through in-app settings or by hand. Merge against the last synced version, using WebDAV ETags and re-reading on conflict. Invalid settings pause sync instead of being overwritten; explicit repair backs up the broken file and preserves valid sections.

## Obsidian integration

Obsidian is the permanent library and review surface for configured vaults: the app writes consistent frontmatter, and a Bases file (native Kanban view, Obsidian 1.14+) turns it into the review board. Plain Markdown folders do not require Obsidian. In-app recent notes and meeting review remain bounded workflow surfaces.

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

- Ordinary notes file as soon as processing finishes, with `status: needs-review` and suggested titles and tags. Mobile recordings may instead be copied, added to a daily note or left in the writing queue. Meetings keep the user-entered title and have a dedicated local review on every platform.
- Review happens on the board: drag a card to reviewed, then actioned.

**Bases file created by the app**

- "Professional review" view: Kanban grouped by `status` (Needs review, Reviewed, Actioned), filtered to `style: professional`. Dragging a card updates the note's frontmatter.
- "Diary" view: simple list filtered to `style: diary`, newest first.
- "All recordings" view: table across every style.
- "Retention" view: regular, archive and delete, controlling audio expiry or deletion.

**First run**

- If the Bases file or config folder is missing, the app creates them and runs a brief walkthrough of how to use the board.

* On first run the app also writes an "Audio Pencil guide" note into the vault: Obsidian coaching on how to use properties, the Bases views and the review statuses, with worked examples.
* It also writes a few sample notes (one Diary, one Professional with action items and a collapsed transcript, one in needs-review) so the board shows real cards straight away. Samples are tagged `sample` and safe to delete.

## Defaults, decisions and remaining work

**Current defaults**

- Long-form threshold 5 min; optional picker auto-confirm about 1 s; mobile silence auto-stop 5 min. Meetings do not auto-stop on silence.
- Filename includes time to the minute; professional transcript in a collapsed callout.
- Notification and error wording, and graceful handling of model load failures, full storage and missing permissions.

**Resolved decisions**

- Model suggestions come from automatic Hugging Face discovery (see Models).
- Style fields are defined (see Styles).
- Professional extracts action items by default on long-form only.
- Starter interview prompts are defined above.

**Future work**

- Per-tab capture isolation and hardware-verified speakerphone separation for Mac video calls. The Debug preview includes reference-based echo reduction; real-room/device validation remains outstanding.
- Physical-device audio, Bluetooth, interruptions, lock-screen capture and GPU inference acceptance on iPhone/iPad, plus actual iPad multitasking/window-resize checks. Simulator coverage does not establish these behaviors on hardware.
