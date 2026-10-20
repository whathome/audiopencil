# Audio Pencil

Private, fully on-device dictation and summarisation for Mac (and later iPhone). See [docs/PRD.md](docs/PRD.md).

**Status:** milestone 8 (guided setup, storage without Obsidian, models ready in the background). Phase 1 (Mac) is feature-complete in English, French and Spanish; phase 2 (iPhone) is next. Double-tap Fn (or your chosen key) and talk: the text lands where you're typing, transcribed by Whisper and optionally rewritten in a style by a small MLX model, all on this Mac. Long recordings become Markdown notes with their audio in an Obsidian vault or any folder, on Nextcloud, WebDAV or this Mac, and styles, vocabulary and per-device settings sync through `Audio Pencil/Settings.md` there.

## Build and run

Requirements: Xcode 26.3+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), macOS 15+, Apple silicon, and Xcode's Metal toolchain for MLX (`xcodebuild -downloadComponent MetalToolchain`, once).

MLX is pinned to `mlx-swift-lm` 3.31.4 / `mlx-swift` 0.31.4, the last versions that build with Swift 6.2. Newer `mlx-swift` needs Swift tools 6.3, so move up after updating Xcode.

```bash
xcodegen generate          # creates AudioPencil.xcodeproj (not committed)
open AudioPencil.xcodeproj # then Run, or:
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData -allowProvisioningUpdates build
```

### Signing (do this once)

Without a team the app is ad-hoc signed, and macOS treats every rebuild as a new app: you'd have to grant Accessibility again after each build. To fix that for free:

1. Xcode › Settings › Accounts › add your Apple ID (a free Personal Team is fine). If no "(Personal Team)" appears, accept the agreement at developer.apple.com/account, then sign out and back in.
2. Open the project and pick the team under the AudioPencil target › Signing & Capabilities. Note the `DEVELOPMENT_TEAM` value Xcode writes into the project.
3. Run `scripts/set-team.sh <TEAMID>`. It writes the gitignored `Config/Signing.local.xcconfig`, which survives `xcodegen generate`.
4. `xcodegen generate`, then build with `-allowProvisioningUpdates` (Xcode creates the Apple Development certificate on the first build).
5. Remove the old Audio Pencil entry under Accessibility and grant it one last time.

### First run

On a Mac that has never run Audio Pencil, a setup window opens instead of the main window. It has six steps:

1. **Welcome**.
2. **Dictation key and permissions**: Fn, Right ⌥ or Right ⌘, double-tap or single tap; Microphone, Accessibility, and (for Fn) "Press 🌐 key to" set to **Do Nothing**. The model for your default language starts downloading and preparing here.
3. **Languages**: English plus this Mac's own languages to tick, any other Whisper language to add, and which one new apps start in.
4. **Storage**: Obsidian vaults found in Obsidian's own vault list, any folder (local, iCloud Drive), Nextcloud or WebDAV, or skip. Nothing is written to storage until setup ends. Vaults in iCloud Drive or other cloud folders aren't checked before you pick one, so macOS only asks for access when you choose it.
5. **Models**: what this Mac needs for the chosen languages, with download sizes and preparation times, plus a switch for the writing model that powers styles and long-form notes.
6. **Getting ready**: live download and preparation progress, and a "Try it here" box. You can close the window at any step; work carries on in the background, and a notification says when preparation is done.

Settings › General › **Run Setup Again…** walks through it again without resetting anything. A Mac that already has Audio Pencil settings counts as set up. Models go to `~/Library/Application Support/AudioPencil/Models`, and Core ML prepares each one for this Mac once (about 1.5 min for Small, about 12 min for Large v3 Turbo on an M1).

Input Monitoring is shown in Settings › Permissions for diagnosis but isn't requested: the active event tap works under Accessibility.

## Using it

| Action | Keys |
| --- | --- |
| Raw transcript (push to talk) | Hold **Fn**, talk, release. Another key while holding cancels, so Fn still works as a modifier |
| Dictate in a style | Double-tap **Fn** (or ⌃⌥Space). Starts in the style last used in this app |
| Switch style while talking | Click the style name in the recording indicator for a menu, or press **1–9** (**0** for raw). The indicator and the menu show each style's number |
| Stop and paste | Single tap **Fn** or **Return** (configurable: double-tap Fn; Return can be turned off) |
| Cancel | **Esc**, at any point, including during a rewrite; nothing is pasted |

Styles (Styles page): **Raw** (0), **Polished** (1, the default: cleaned-up text in your words), **Diary** (2, filler removed, wording kept), **Professional** (3, summary plus key points), and **Like me** (4, milestone 6). Edit their instructions, renumber them, or add your own. Optionally (Settings), a picker appears after stop with this app's style preselected; it picks automatically after a second unless you press a number.

The writing model (default SmolLM3 3B, 1.7 GB, downloaded once from the Styles page) never sits in memory alongside Whisper. A styled dictation swaps Whisper out, rewrites, then swaps Whisper back in the background. On the M1 Air a styled quick note takes about 5–7 s from stop to paste; raw is about 0.5 s. See [docs/benchmarks](docs/benchmarks) for the model comparison.

Recording starts about 0.05 s after the second Fn tap: the mic comes on at the first tap and goes off again within a second if no second tap follows. Turn this off in Settings if the brief mic-indicator flash on a lone Fn tap bothers you.

Settings (⌘,) also has:

- **Microphones**: a priority list. The first connected one is used, otherwise the system default. Unplugged entries stay in the list.
- **Dictation languages**: any of Whisper's 100 languages, one per recording. Each app starts in the language you last spoke there (remembered on this Mac only); new apps start in the language chosen here. When more than one language is in the list, the recording indicator shows a badge such as **FR**; click it to switch, and what you've said so far is transcribed again in the new language. English uses the English model (Small (English) by default); every other language uses the multilingual model set in Settings › Models. Languages the writing model can't write (SmolLM3: English, French, Spanish, German, Italian, Portuguese) are marked "Raw only" and paste the raw transcript.
- **Hotkey**: choose the key (Fn, Right ⌥ or Right ⌘), how to start (double-tap or tap) and stop (tap or double-tap; a tap start always stops with a tap), hold-for-raw, Return-also-stops, and a backup shortcut you record yourself (⌃⌥Space by default).
- **Try it here** (Dictation page): a text box to dictate into without leaving the app, showing the style, language and model a dictation will use.
- **Models in the background**: other languages use a quick starter model (Whisper Small) within about 90 s, while the more accurate one (Large v3 Turbo) prepares in the background without holding up dictation; the switch happens between recordings. First-time preparation shows its step, a clock and an estimate.
- **Interface language**: English, French or Spanish, following macOS (System Settings › General › Language & Region, which can also set Audio Pencil's language on its own). Preset style names and descriptions are shown translated while a preset keeps its default name; the instructions the writing model reads stay as written.
- **Custom vocabulary**: one term per line, passed to Whisper as spelling hints. In a test, "next cloud / web dev / whisker kit" became "Nextcloud / WebDAV / WhisperKit". One list applies to every language; each language can add its own (the List picker), and a recording uses both.
- **Menu bar only** (hides the Dock icon) and **Launch at login**.

### Notes

A hotkey recording longer than the long-form threshold (5 minutes by default; Settings › General › Notes) doesn't paste. While you talk, the indicator shows the elapsed time after 30 s, counts down "Note in 0:25" for the last 30 s, then shows "Note" and plays one soft cue when the recording crosses over. Instead, Audio Pencil:

1. Keeps the audio (`Audio Pencil/Recordings/*.m4a`, AAC mono, about 1.2 MB for 5 minutes).
2. Writes it up in the recording's style. Long transcripts go section by section, and summaries are combined from per-section notes.
3. Suggests a title and tags (preferring the tag list in the settings file).
4. Sends a notification. The review window lets you edit the title, tags and folder, then **Approve** (`status: reviewed`) or **Skip** (`status: needs-review`). Pending reviews wait on the Mac, and the Notes page lists them.

Notes are `YYYY-MM-DD HHmm Title.md` in the style's folder (Styles page), or `Audio Pencil/Notes`. They carry the PRD frontmatter (`type`, `style`, `status`, `recorded`, `duration`, `device`, `mode`, `tags`, `audio`), with the transcript folded in a callout under rewritten text. Uploads go through the offline queue. Optionally, quick dictations are saved too (no audio, no review).

On first connecting a vault the app adds `Audio Pencil/Audio Pencil.base` (Kanban "Professional review" by status, "Diary", "All recordings"), `Audio Pencil guide.md`, and three sample notes tagged `sample`. The board and guide are recreated if missing; the samples never are.

### Like me

The **My writing** page holds samples of your own writing: the PRD's 11 interview prompts (typed, 100–300 words) and anything you paste in. For each note, the two samples most similar to what you said go to the writing model as examples of your voice. The Like me style switches on at three samples. Samples sync through the vault settings file.

### Model suggestions

Settings › Model suggestions shows this Mac's chip and memory, and how much room that leaves for each kind of model (a third of RAM for writing, an eighth for transcription; 8 GB → 2.8 GB / 1.0 GB). Weekly, the app looks on Hugging Face for MLX chat models that MLX can load and that fit, plus English WhisperKit models Argmax supports on this chip. **Try** downloads one and runs it next to your current model on the same material (word error rate for transcription), and **Switch** adopts it. Nothing changes on its own.

### Retention

Every note has `retention: regular | archive | delete`, shown as the **Retention** view on the board. At least every 5 minutes, and whenever you switch to the app, Audio Pencil applies it:

- **delete:** the note and its audio are removed.
- **archive:** kept forever.
- **regular:** the audio is removed a year after recording (Settings › General › Notes, on by default, shared by all devices). The note stays and gets `audio_expired`.

Removed files go to Nextcloud's trash, or the macOS Trash for a local vault. Recordings expiring within 30 days are listed on the Notes page with **Keep forever**. Older notes without the property are marked `regular`.

### Keeping the board and settings working

The board's own views (Professional review, Diary, All recordings, Retention) are re-added whenever one goes missing. Your own views, filters and view settings are kept.

If the board or `Settings.md` stops parsing, the app leaves it alone (Obsidian saves while you type, so this can be momentary), pauses syncing that file, and offers **Repair…**. A repair keeps every section, style, writing sample or view that still parses, so valid edits made elsewhere in the file survive. Only the broken parts come back from the last good version. The broken file is saved to `Audio Pencil/Backups/` first.

### Sounds

Settings › Sounds offers Tricorder (default), Soft, Chime, Click, macOS sounds or None, with a volume slider and a preview button. The choice is per device and synced in its section of the settings file.

### Storage: Obsidian vault or any folder

The Storage page offers Nextcloud, any WebDAV server (URL, user name and password, kept in the Keychain), or a folder on this Mac such as iCloud Drive. Obsidian isn't required. A folder with a `.obsidian` folder gets the Obsidian extras: the review board, the guide, samples, `[[wiki]]` audio embeds and a collapsed transcript callout. Any other folder gets plain Markdown: a standard relative link to the recording, a `## Transcript` heading, and an `About these notes.md` explaining the files. If a plain folder later becomes an Obsidian vault, the Notes page offers to add the board; nothing is added without asking. The Notes page's recent list has **Keep forever** and **Delete** for each note, so retention works without the board.

### Vault settings file

Once storage is connected (Storage page), the app keeps `Audio Pencil/Settings.md` in it: a short note with one `yaml` block holding the shared styles, vocabulary and tags, plus a section per device (microphones, hotkey options, models). Edit it in Obsidian and the app picks the changes up within a minute, or when you switch to it. Changes made on both sides merge field by field against the last synced version. If both sides changed the same style, the vault's version wins. If the YAML has a mistake, syncing pauses until you fix it, and the file is never overwritten. Per-app style memory and stats stay on the device.

**Keep what's on my clipboard** (Settings › General › Pasting, on by default) pastes through the clipboard without losing what you'd copied:

- Your clipboard is saved first: every item and format, in memory only. Items marked concealed (passwords from a password manager) are never kept, and clipboards over 32 MB are left alone.
- The dictation goes on the clipboard marked transient, so clipboard managers skip it, and it's handed over only when an app asks for it.
- After ⌘V, the paste counts as confirmed when the app asks for the text and, where Accessibility can read the field, the text shows up there. Typical checks take 0.05–0.3 s (TextEdit, Safari, Firefox).
- Confirmed: your clipboard goes back. Not confirmed, or the focus clearly isn't a text field: the dictation stays on the clipboard and the indicator says "On clipboard: press ⌘V". Your clipboard comes back once you've pasted the dictation, or after two minutes, unless you copy something else first.
- **Copy Last Dictation** in the menu bar, and **Copy** on the Last dictation card, put the last dictation back on the clipboard at any time.

With the setting off, each dictation stays on the clipboard after pasting, as before. If macOS is set to deny Audio Pencil clipboard access (Privacy & Security › Paste from Other Apps), dictations stay on the clipboard.

The hotkey doesn't work while macOS Secure Input is on: password fields, Terminal with Secure Keyboard Entry, some password managers.

## Layout

```
project.yml                   XcodeGen definition (app target, signing, schemes)
Config/Signing.xcconfig       ad-hoc by default; includes Signing.local.xcconfig if present
App/macOS/Sources             thin macOS app: event tap, paste, indicator panel, windows
Packages/AudioPencilKit       shared Swift package (reused by iOS in phase 2)
  APCore                      settings, Fn tap/hold detection, styles, prompt builder, per-app memory, stats
  APAudio                     16 kHz mono capture (off the main thread), mic catalogue, levels, cues
  APModels                    ModelCoordinator (one large model resident at a time), catalogue
  APTranscription             WhisperKit wrapper, streaming transcriber
  APSummary                   MLX writing model (SmolLM3 by default), Hugging Face download, benchmark
  APStorage                   storage: Nextcloud (Login Flow v2) or any WebDAV server, local folder (iCloud Drive), Keychain
  APSync                      shared settings file (YAML in Markdown), three-way merge, offline upload queue
```

Memory rule: every model load goes through `ModelCoordinator.ensureLoaded`, which unloads whatever else is resident first. Whisper and the writing model are both `ManagedModel`s, so they can't be loaded at the same time.

## Tests

```bash
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData test
```

There's also an opt-in end-to-end WhisperKit test. It synthesises speech with `say`, streams it through the real model, and prints stop-to-text latency:

```bash
cd Packages/AudioPencilKit && AUDIOPENCIL_INTEGRATION=1 swift test --filter WhisperIntegration
```

Debug builds can be driven without key presses, for end-to-end timing. These dictations never paste; the transcript goes to the log. Use `say` to talk to the mic:

```bash
scripts/debug-dictation.sh tap-start   # or: start (cold), warm (a lone first tap), stop, cancel
scripts/debug-dictation.sh key:fnDown 0.6 key:fnUp   # simulated keys: fnDown, fnUp, other, escape, return, 0–9
```

Writing-model benchmark (downloads each candidate; must run through xcodebuild for Metal):

```bash
cd Packages/AudioPencilKit && TEST_RUNNER_AUDIOPENCIL_BENCH=1 TEST_RUNNER_AUDIOPENCIL_BENCH_OUT=$PWD/../../docs/benchmarks/run.md xcodebuild test -scheme AudioPencilKit-Package -destination platform=macOS -only-testing:APSummaryTests
```

Logs: `log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'`. Each dictation logs its stop→text and stop→paste times.

## Milestones

1. **Bare loop** (done): hotkey, record, live transcription, stop, paste raw text.
2. **Dictation polish** (done): instant start, mic priority list, Dock/menu-bar mode, launch at login, custom vocabulary.
3. **Styles** (done): hold-for-raw, MLX writing model with swapping, presets, number keys and clickable style menu, picker, per-app defaults, Styles page.
4. **Vault and sync** (done): Nextcloud (Login Flow v2) or a local/iCloud folder, folder selection, shared YAML settings file with three-way merge and ETag retries, offline upload queue.
5. **Notes in Obsidian** (done): long-form promotion (5 min, configurable), m4a audio, sectioned summaries, suggested title and tags, review prompt and notification, notes and frontmatter via the offline queue, optional saving of quick dictations, Bases board, guide and samples. One-year audio retention moves to milestone 6.
6. **Like me, discovery, retention** (done): My writing page and interview, machine-aware model suggestions with on-device trials, Retention board (regular / archive / delete) with one-year audio expiry, board and settings-file repair, sound themes.
7. **Multilingual** (done): 7a spoken languages (per-app language memory, language badge and menu in the indicator, English and multilingual Whisper models, prompts and notes in the spoken language, per-language vocabulary, Like me samples by language, layout-aware paste); 7b the interface in French and Spanish (String Catalogs in the app and each package target; the vault guide and sample notes are written in the interface language when a vault is first set up; board view names and properties stay English).
8. **Setup and storage** (done): 8a models prepared in the background (dictation never waits; Small first for other languages, then Large v3 Turbo), configurable dictation key (Fn, Right ⌥ or Right ⌘; double-tap or single tap; a recordable shortcut) and a Try it here box; 8b storage without Obsidian (plain Markdown in any folder, any WebDAV server, Keep forever and Delete on the Notes page, Vault renamed Storage); 8c the six-step setup window.
