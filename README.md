# Audio Pencil

Private, fully on-device dictation and summarisation for Mac (and later iPhone). See [docs/PRD.md](docs/PRD.md).

**Status:** milestone 6 (Like me, model discovery, retention). Phase 1 (Mac) feature-complete; phase 2 (iPhone) next. Milestone 5 (notes in Obsidian): Long recordings become reviewed notes with audio in your vault; a Bases board, guide and sample notes are created on first run. Milestone 4 (vault and sync): Connect your Obsidian vault on Nextcloud or in a folder on this Mac (e.g. iCloud Drive); styles, vocabulary and per-device settings sync through `Audio Pencil/Settings.md` in the vault. Hold Fn for a raw transcript, or double-tap Fn to dictate in a style (Polished, Diary, Professional, or your own), rewritten on this Mac by a small MLX language model.

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

The main window is a setup checklist:

- **Microphone**: needed to record.
- **Accessibility**: needed to watch the Fn key and to paste. After granting it, the hotkey starts within a second without a relaunch.
- **Fn key free**: System Settings › Keyboard › "Press 🌐 key to" must be **Do Nothing**, and the Dictation shortcut must not be "Press 🌐 twice". Otherwise macOS acts on the same key.
- **Model**: the first launch downloads Whisper small.en (~480 MB) to `~/Library/Application Support/AudioPencil/Models`. Core ML then compiles it for this Mac, which takes a minute or two once.

Input Monitoring is shown for diagnosis but isn't requested: the active event tap works under Accessibility.

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

### Vault settings file

Once a vault is connected (Vault page), the app keeps `Audio Pencil/Settings.md` in it: a short note with one `yaml` block holding the shared styles, vocabulary and tags, plus a section per device (microphones, hotkey options, models). Edit it in Obsidian and the app picks the changes up within a minute, or when you switch to it. Changes made on both sides merge field by field against the last synced version. If both sides changed the same style, the vault's version wins. If the YAML has a mistake, syncing pauses until you fix it, and the file is never overwritten. Per-app style memory and stats stay on the device.

The text is left on the clipboard as well. If the focused element clearly isn't a text field, nothing is pasted and the indicator shows "On clipboard".

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
  APStorage                   vault storage: Nextcloud WebDAV + Login Flow v2, local folder (iCloud Drive), Keychain
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
7. **Multilingual** (this): 7a spoken languages (per-app language memory, language badge and menu in the indicator, English and multilingual Whisper models, prompts and notes in the spoken language, per-language vocabulary, Like me samples by language, layout-aware paste); 7b the interface in French and Spanish (String Catalogs in the app and each package target; the vault guide and sample notes are written in the interface language when a vault is first set up; board view names and properties stay English).
