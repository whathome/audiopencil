# Audio Pencil reference

Detailed setup, usage and development notes. For a quick overview, see the [README](../README.md); for product requirements, see the [PRD](PRD.md). Run commands from the repository root unless shown otherwise.

**Status:** Mac, iPhone and iPad apps are implemented, in English, French and Spanish. Mac video-call capture remains a Debug preview pending live-call validation. Double-tap Fn (or your chosen key) and talk: the text lands where you're typing, transcribed by Whisper and optionally rewritten in a style by a small MLX model, all on this Mac. Long recordings become Markdown notes with their audio in an Obsidian vault or any folder, on Nextcloud, WebDAV or a local/iCloud folder, and styles, vocabulary and per-device settings sync through `Audio Pencil/Settings.md` there.

## Build and run

Requirements: Xcode 26.3+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), macOS 15+, Apple silicon, and Xcode's Metal toolchain for MLX (`xcodebuild -downloadComponent MetalToolchain`, once).

MLX is pinned to `mlx-swift-lm` 3.31.4 / `mlx-swift` 0.31.4, the last versions that build with Swift 6.2. Newer `mlx-swift` needs Swift tools 6.3, so move up after updating Xcode.

```bash
xcodegen generate          # creates AudioPencil.xcodeproj (not committed)
open AudioPencil.xcodeproj # then Run, or:
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData -allowProvisioningUpdates build
```

### Signing (do this once)

Quit the running development app before rebuilding into the same product path, then reopen the rebuilt app. Replacing a live app's signed executable can disrupt its existing keyboard event tap.

Without a team the app is ad-hoc signed, and macOS treats every rebuild as a new app: you'd have to grant Accessibility again after each build. To fix that for free:

1. Xcode › Settings › Accounts › add your Apple ID (a free Personal Team is fine). If no "(Personal Team)" appears, accept the agreement at developer.apple.com/account, then sign out and back in.
2. Open the project and pick the team under the AudioPencil target › Signing & Capabilities. Note the `DEVELOPMENT_TEAM` value Xcode writes into the project.
3. Run `scripts/set-team.sh <TEAMID>`. It writes the gitignored `Config/Signing.local.xcconfig`, which survives `xcodegen generate`.
4. `xcodegen generate`, then build with `-allowProvisioningUpdates` (Xcode creates the Apple Development certificate on the first build).
5. Remove the old Audio Pencil entry under Accessibility and grant it one last time.

#### Using another Xcode account

The checked-in bundle identifiers use `com.weshopkins.audiopencil`. Selecting your own team may be enough, but if Xcode says an identifier **cannot be registered** or **is not available**, choose a unique bundle identifier for your team, especially for physical iPhone/iPad builds:

1. Run `scripts/set-team.sh <YOUR_TEAM_ID>` with the new account's team ID. Pass it explicitly when you have certificates for multiple teams; automatic detection uses the first matching Apple Development certificate.
2. In **`project.yml`**, replace `com.weshopkins` with your own unique reverse-DNS prefix everywhere it appears. This changes `options.bundleIdPrefix` **and** the explicit `PRODUCT_BUNDLE_IDENTIFIER` settings; changing the prefix option alone does not override those settings.

   | Target | Example identifier |
   | --- | --- |
   | `AudioPencil` and `AudioPencilPhone` | `com.yourname.audiopencil` |
   | `AudioPencilWidgets` | `com.yourname.audiopencil.widgets` |
   | `AudioPencilDesktopTests` | `com.yourname.audiopencil.desktoptests` |
   | `AudioPencilMobileUITests` | `com.yourname.audiopencil.uitests` |

3. Run `xcodegen generate` again, reopen the project, and build with automatic signing and `-allowProvisioningUpdates`. Select your physical device when running the phone scheme; Xcode may need to register that device and create new provisioning profiles.
4. Recheck macOS privacy permissions after changing the signing team or bundle identifier; remove an obsolete Accessibility entry and allow the rebuilt app if needed.

Keep the widget identifier prefixed by the iOS app's identifier. Do not set one shared `PRODUCT_BUNDLE_IDENTIFIER` in `Signing.local.xcconfig`: the app and embedded widget need distinct identifiers. Make identifier changes in `project.yml`, not just Xcode's generated project, or regeneration will discard them. These are personal signing changes; keep the prefix edit out of shared commits unless intentionally changing the project's identity.

Other `com.weshopkins.audiopencil` strings used for logs, debug notifications and control kinds are not provisioning identifiers and do not need changing to use another account. Never delete existing app data to resolve an identifier-registration error.

### First run

On Mac, microphone preferences are tried in priority order; if none are connected, Audio Pencil uses the system default input. For multichannel audio interfaces, it preserves input levels and uses the strongest channel in each audio buffer rather than mixing unused inputs into the microphone signal. A failure to select the requested device is reported instead of silently recording another microphone.

On a Mac that has never run Audio Pencil, a setup window opens instead of the main window. It has six steps:

1. **Welcome**.
2. **Dictation key and permissions**: Fn, Right ⌥ or Right ⌘, double-tap or single tap; Microphone, Accessibility, and (for Fn) "Press 🌐 key to" set to **Do Nothing**. The model for your default language starts downloading and preparing here.
3. **Languages**: English plus this Mac's own languages to tick, any other Whisper language to add, and which one new apps start in.
4. **Storage**: Obsidian vaults found in Obsidian's own vault list, any folder (local, iCloud Drive), Nextcloud or WebDAV, or skip. Nothing is written to storage until setup ends. Vaults in iCloud Drive or other cloud folders aren't checked before you pick one, so macOS only asks for access when you choose it.
5. **Models**: what this Mac needs for the chosen languages, with download sizes and preparation times, plus a switch for the writing model that powers styles and long-form notes.
6. **Getting ready**: live download and preparation progress, and a "Try it here" box. You can close the window at any step; work carries on in the background, and a notification says when preparation is done.

Settings › General › **Run Setup Again…** walks through it again without resetting anything. A Mac that already has Audio Pencil settings counts as set up. Models go to `~/Library/Application Support/AudioPencil/Models`, and Core ML prepares each one for this Mac once (about 1.5 min for Small, about 12 min for Large v3 Turbo on an M1).

Settings › Permissions offers **Allow…** for Microphone, Accessibility and **Online meeting audio**. Online meeting audio opens macOS's Screen & System Audio Recording permission for capturing the call app; it is optional for ordinary dictation. The active hotkey event tap uses Accessibility, not Input Monitoring.

## Using it

| Action | Keys |
| --- | --- |
| Raw transcript (push to talk) | Hold **Fn**, talk, release. Another key while holding cancels, so Fn still works as a modifier |
| Dictate in a style | Double-tap **Fn** (or ⌃⌥Space). Starts in the style last used in this app |
| Switch style while talking | Click the style name in the recording indicator for a menu, or press **1–9** (**0** for raw). The indicator and the menu show each style's number |
| Stop and paste | Single tap **Fn** or **Return** (configurable: double-tap Fn; Return can be turned off) |
| Cancel | **Esc**, at any point, including during a rewrite; nothing is pasted |

Styles (Styles page): **Raw** (0), **Polished** (1, the default: cleaned-up text in your words), **Diary** (2, filler removed, wording kept), **Professional** (3, summary plus key points), and **Like me** (4, available after adding three writing samples). Edit their instructions, renumber them, or add your own. Optionally (Settings), a picker appears after stop with this app's style preselected; it picks automatically after a second unless you press a number.

On Mac, a new style is saved only when you choose **Save**; **Cancel** or Escape leaves no entry behind. Deleting a saved writing sample asks for confirmation before removing it locally and from synced settings. Dictation errors offer the relevant Permissions, microphone or Models settings; a failed rewrite keeps the raw transcript in **Last dictation** with a dismissible notice.

The writing model (default SmolLM3 3B, 1.7 GB, downloaded once from the Styles page) never sits in memory alongside Whisper. A styled dictation swaps Whisper out, rewrites, then swaps Whisper back in the background. On the M1 Air a styled quick note takes about 5–7 s from stop to paste; raw is about 0.5 s. See [benchmarks](benchmarks) for the model comparison.

Recording starts about 0.05 s after the second Fn tap: the mic comes on at the first tap and goes off again within a second if no second tap follows. Turn this off in Settings if the brief mic-indicator flash on a lone Fn tap bothers you.

Settings (⌘,) also has:

- **Microphones**: a priority list. The first connected one is used, otherwise the system default. Unplugged entries stay in the list.
- **Dictation languages**: any of Whisper's 100 languages, one per recording. Each app starts in the language you last spoke there (remembered on this Mac only); new apps start in the language chosen here. When more than one language is in the list, the recording indicator shows a badge such as **FR**; click it to switch, and what you've said so far is transcribed again in the new language. English uses the English model (Small (English) by default); every other language uses the multilingual model set in Settings › Models. Languages the writing model can't write (SmolLM3: English, French, Spanish, German, Italian, Portuguese) are marked "Raw only" and paste the raw transcript.
- **Settings categories**: General contains app behavior and sounds; Dictation contains recording, delivery, microphones, languages and vocabulary; Notes contains filing, retention, daily notes and task keywords; Storage contains the storage provider, account, folder and sync status. Models and Permissions keep their own categories. The same categories appear in the main window and the ⌘, Settings window.
- **Hotkey** (Settings › Dictation): choose the key (Fn, Right ⌥ or Right ⌘), how to start (double-tap or tap) and stop (tap or double-tap; a tap start always stops with a tap), hold-for-raw and Return-also-stops. **Timing and shortcuts** expands to show double-tap timing, microphone warm-up and a backup shortcut you record yourself (⌃⌥Space by default). **Push-to-talk delay** stays visible in its own section and adjusts the initial hold from 100–1,000 ms (default 350 ms), in 50 ms steps. Shorter delays start sooner but can trigger recordings during slower taps or modifier use; microphone startup time is additional. The delay is saved per device and syncs as `push_to_talk_delay` in seconds.
- **Try it here** (Dictation page): a text box to dictate into without leaving the app, showing the style, language and model a dictation will use.
- **Models in the background**: other languages use a quick starter model (Whisper Small) within about 90 s, while the more accurate one (Large v3 Turbo) prepares in the background without holding up dictation; the switch happens between recordings. First-time preparation shows its step, a clock and an estimate.
- **Interface language**: English, French or Spanish, following macOS (System Settings › General › Language & Region, which can also set Audio Pencil's language on its own). Preset style names and descriptions are shown translated while a preset keeps its default name; the instructions the writing model reads stay as written.
- **Custom vocabulary**: one term per line, passed to Whisper as spelling hints. In a test, "next cloud / web dev / whisker kit" became "Nextcloud / WebDAV / WhisperKit". One list applies to every language; each language can add its own (the List picker), and a recording uses both.
- **Try Phonon-2 for English** (trial, this Mac only, not synced): English goes through [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2) instead of Whisper, using [FluidAudio](https://github.com/FluidInference/FluidAudio) on the Neural Engine. This only happens while no custom vocabulary is set: Phonon-2 can't take spelling hints, so Whisper stays on whenever there is one. The live text works as before, and at stop the whole recording is transcribed again in one pass, which takes under 2 s for 5 minutes. On the first use it downloads 375 MB and prepares for this Mac, about 3–5 min on an M1. In tests it made fewer errors than Whisper Small (English) and was 5–6× faster; it hasn't been tested yet on a real dictation. See [the benchmark](benchmarks/phonon-2-vs-whisper-small.md).
- **Menu bar only** (hides the Dock icon) and **Launch at login**.

### Tasks

Notes and dictations become [Obsidian tasks](https://help.obsidian.md/syntax#Task+lists) in the [Tasks plugin](https://publish.obsidian.md/tasks/) format, with dates taken from what was said and worked out from when it was said:

- **Action items in notes:** each style has a **Find action items** switch (Styles page on the Mac, Settings › Styles on the iPhone; on for Professional). Its notes end with an "Action items" section whose bullets are written as `- [ ] …`. A deadline ("by Friday", "within two weeks", "at the end of the month", "le 3 novembre", "antes del viernes") becomes a due date `📅 2026-10-23`; a start ("starting next Monday", "à partir de lundi", "desde el lunes") becomes `🛫 2026-10-26`. Meeting notes keep the owner: `- [ ] Speaker 2: send the lease by Friday 📅 …`. "None" stays plain text.
- **Task keywords:** a dictation that starts with "new task", "action item" or "to do" (Settings › Task keywords; one phrase per line, shared through the settings file as `task_keywords`) skips the style and is pasted as one task line: "New task: call the landlord by Friday" → `- [ ] Call the landlord by Friday 📅 2026-10-23`. On the iPhone, such a recording is filed as a one-line task note.

Dates are read in English, French and Spanish: today, tomorrow, weekdays ("next Friday" said early in a week is the one after this week's), next week, end of the week or month, "in N days or weeks", and calendar dates.

### Daily note

When the vault has Obsidian's **Daily notes** core plugin on, notes can be linked in that day's daily note. Settings › Daily note (Mac and iPhone) turns this on by default and sets the heading the links go under (`## Audio Pencil`; blank adds them at the end) and whether each is a link (`- 21:44 [[…|Weekend Garden Tasks]]`) or an embed (`![[…]]`). Override it per recording: the pill's style menu on the Mac (**Link in today's daily note**), and on the iPhone the switch under **Make Note** after stopping. The iPhone can also **Add to Daily Note**: the text, written in the chosen style, goes into the daily note itself as `- 14:32 …` (a task-keyword recording as an untimed `- [ ] …`), with no note filed. The daily note is made if it doesn't exist yet, in the plugin's folder and date format, from its template. The app reads `.obsidian/core-plugins.json` and `.obsidian/daily-notes.json`; while Daily notes is off, these settings are greyed out and say why, and nothing is offered on the pill or the recorder. Additions wait in a queue on the device and are written when the vault is reachable.

**Push to talk** (hold Fn) only pastes, and makes no note. While holding, the pill shows a **Paste** badge in place of the Paste / Note toggle; click it to also add the text as a line to the daily note or to one file you choose (Settings › Notes › Push-to-talk filing: the file, such as `Inbox.md`, and the heading the lines go under, blank for the end). Lines read `- 21:47 Remember the parcel is at the front desk.`; a task-keyword dictation goes in as the task, without the time: `- [ ] Renew the car insurance 📅 2026-11-05`. The badge only appears when one of those is available, and push-to-talk always pastes, however long it's held.

### Meeting mode

On Mac, open **Meetings** in the sidebar (Command-2), or **Record a Meeting** in the menu bar. Choose **In person** for microphone-only capture. **Video call (preview)** is available in Debug builds for the selected microphone plus a running app's audio, including when wearing headphones; it remains unavailable in Release builds until the live-call acceptance matrix is verified. Allow **Online meeting audio** in **Settings › Permissions**; meeting setup links there when access is missing. The call-app list refreshes automatically when setup loads and each time its dropdown opens. Browser capture can include other tabs. New call recordings use the captured app audio as an echo-cancellation reference to reduce speaker leakage in the **You** track. Headphones remain the most reliable option. Audio Pencil does not notify participants; obtain their agreement before recording.

On Mac, iPhone and iPad, enter a meeting title beside **Start Meeting** before recording. Empty and whitespace-only titles cannot start a meeting; surrounding whitespace is removed from the saved title.

Echo cancellation runs locally on the archive queue, not the audio callback or main thread, using the bundled BSD-licensed SpeexDSP 1.2.1 MDF processor. The **You (echo reduced)** meter, local transcript and playback mix use the cleaned microphone; the original microphone and app sources remain available in local recovery files. A quarter-second microphone buffer accommodates callback ordering, and the adaptive filter covers about half a second of acoustic delay/reflections. It preserves simultaneous local speech rather than muting the microphone when someone else speaks. The filter resets across pauses and microphone discontinuities; leakage can remain while it learns a new path. It cannot remove sounds absent from the selected app's reference, and loud/distorted speakers or unusually long delays can leave residual echo. Processing a saved call rebuilds a missing or interrupted cleaned track from the raw sources, atomically updating its recovery index only after success. Existing transcripts are not automatically rewritten. Physical speaker/interface and Bluetooth validation is still outstanding; no guarantee of speakerphone separation is made.

The call-app picker lists normal foreground apps, excluding background services and widgets; minimized or hidden apps remain selectable. Choosing an app starts a live level preview below the picker so you can play meeting audio and verify the source before recording. It switches with your selection and stops on leaving setup, starting dictation or starting the meeting. Preview audio is neither saved nor replayed, and it does not start the microphone. A quiet app stays selectable; permission/capture errors offer a retry. The page also offers a microphone test, language and optional speaker-count hint (2–6), separate source meters, pause/resume and stop. Closing the window keeps recording; click the floating meeting pill or use the menu bar to return, pause or stop. A disconnected source pauses capture rather than silently switching microphones. While paused, choose a replacement microphone or explicitly continue without call audio. Quitting asks to stop and save.

Meeting audio is written incrementally to local five-second segments, with a recovery index. A crashed or interrupted session can be processed after reopening. **Process after recording** can be turned off when you want to record first and prepare models later. Jobs wait for earlier jobs and active recordings; large speech and writing models remain sequentially resident. Long meetings are transcribed in overlapping bounded windows and summarized hierarchically, not truncated to one model context. [SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift) labels remote/in-person voices; headphone-call microphone speech is labelled **You**. When a speaker cannot be matched between windows, the review warns that separate labels may be the same person.

While a meeting processes on Mac, writing samples, styles and unrelated settings remain usable. Dictation, model changes and model trials wait until processing finishes; a persistent status links back to progress. A disabled **Start Meeting** button explains the prerequisite that needs attention.

After processing, review **Summary**, **Actions** and the timestamped **Transcript**. Rename speakers, edit Markdown action items, click a timestamp for playback, and mark the meeting reviewed. Notes file through the existing offline queue as `mode: meeting`; local recordings remain available for playback and processing retries. Use **Update Filed Note** after editing. An externally changed note is never silently overwritten: review changes stay local for manual merging. **Delete local meeting** removes the local review/recovery files; filed notes must be deleted in their storage separately. Audio follows regular one-year retention or **Keep Audio Forever**.

The older microphone-only meeting toggle remains available during dictation on the Mac. On iPhone, meetings are recorded from the **Meetings** tab, with the same round controls, clock and level as the Record tab (which is for one person talking). A meeting's review has one main action, **File Note** (then **Update Filed Note**), with Transcribe Again, Keep Audio Forever and Delete in its ··· menu; filed meetings also appear in Notes › Filed, marked with a people icon. Every ordinary dictation still starts in single-speaker mode.

Labelling 18 s of two voices takes about 2.5 s on an M1 once the models are prepared. Very short turns (a lone "Good morning") are the hardest to attribute.

### Notes

A hotkey recording longer than the long-form threshold (5 minutes by default; Settings › Notes › Saving and retention) doesn't paste. While you talk, the indicator shows the elapsed time after 30 s and counts down "Note in 0:25" for the last 30 s, and its **Paste / Note** toggle switches to Note with one soft cue as the recording crosses over. Click the toggle (or choose under "When you stop" in the style menu) to decide for this recording only: make a short dictation into a note, or paste a long one. A note:

1. Keeps the audio (`Audio Pencil/Recordings/*.m4a`, AAC mono, about 1.2 MB for 5 minutes).
2. Writes it up in the recording's style. Long transcripts go section by section, and summaries are combined from per-section notes.
3. Suggests a title and tags (preferring the tag list in the settings file).
4. Is filed straight away as `status: needs-review`, with the suggested tags (new ones join the tag list), and a notification opens it in Obsidian. Review happens on the board, the same on Mac and iPhone.

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
- **regular:** the audio is removed a year after recording (Settings › Notes › Saving and retention, on by default, shared by all devices). The note stays and gets `audio_expired`.

Removed files go to Nextcloud's trash, or the macOS Trash for a local vault. Recordings expiring within 30 days are listed on the Notes page with **Keep forever**. Older notes without the property are marked `regular`.

### Keeping the board and settings working

The board's own views (Professional review, Diary, All recordings, Retention) are re-added whenever one goes missing. Your own views, filters and view settings are kept.

If the board or `Settings.md` stops parsing, the app leaves it alone (Obsidian saves while you type, so this can be momentary), pauses syncing that file, and offers **Repair…**. A repair keeps every section, style, writing sample or view that still parses, so valid edits made elsewhere in the file survive. Only the broken parts come back from the last good version. The broken file is saved to `Audio Pencil/Backups/` first.

### Sounds

Settings › Sounds offers Tricorder (default), Soft, Chime, Click, macOS sounds or None, with a volume slider and a preview button. The choice is per device and synced in its section of the settings file.

### Storage: Obsidian vault or any folder

Settings › Storage offers Nextcloud, any WebDAV server (URL, user name and password, kept in the Keychain), or a folder on this Mac such as iCloud Drive. Obsidian isn't required. A folder with a `.obsidian` folder gets the Obsidian extras: the review board, the guide, samples, `[[wiki]]` audio embeds and a collapsed transcript callout. Any other folder gets plain Markdown: a standard relative link to the recording, a `## Transcript` heading, and an `About these notes.md` explaining the files. If a plain folder later becomes an Obsidian vault, the Notes page offers to add the board; nothing is added without asking. The Notes page's recent list has **Keep forever** and **Delete** for each note, so retention works without the board.

### Vault settings file

Once storage is connected (Settings › Storage), the app keeps `Audio Pencil/Settings.md` in it: a short note with one `yaml` block holding the shared styles, vocabulary and tags, plus a section per device (microphones, hotkey options, models). Edit it in Obsidian and the app picks the changes up within a minute, or when you switch to it. Changes made on both sides merge field by field against the last synced version. If both sides changed the same style, the vault's version wins. If the YAML has a mistake, syncing pauses until you fix it, and the file is never overwritten. Per-app style memory and stats stay on the device.

**Keep what's on my clipboard** (Settings › Dictation › After recording, on by default) pastes through the clipboard without losing what you'd copied:

- Your clipboard is saved first: every item and format, in memory only. Items marked concealed (passwords from a password manager) are never kept, and clipboards over 32 MB are left alone.
- The dictation goes on the clipboard marked transient, so clipboard managers skip it, and it's handed over only when an app asks for it.
- After ⌘V, the paste counts as confirmed when the app asks for the text and, where Accessibility can read the field, the text shows up there. Typical checks take 0.05–0.3 s (TextEdit, Safari, Firefox).
- Confirmed: your clipboard goes back. Not confirmed, or the focus clearly isn't a text field: the dictation stays on the clipboard and the indicator says "On clipboard: press ⌘V". Your clipboard comes back once you've pasted the dictation, or after two minutes, unless you copy something else first.
- **Copy Last Dictation** in the menu bar, and **Copy** on the Last dictation card, put the last dictation back on the clipboard at any time.

With the setting off, each dictation stays on the clipboard after pasting, as before. If macOS is set to deny Audio Pencil clipboard access (Privacy & Security › Paste from Other Apps), dictations stay on the clipboard.

The hotkey doesn't work while macOS Secure Input is on: password fields, Terminal with Secure Keyboard Entry, some password managers.

The macOS keyboard event tap runs on a dedicated input thread. Its synchronous callback only classifies events and checks a small capture-policy snapshot; UI, audio and model actions are delivered asynchronously on the main actor. Ordinary typing is not forwarded to the UI, so a busy main window cannot stall the system keyboard. Escape, Return, style digits and the backup shortcut still suppress their matching key-up events when captured.

If macOS disables the tap for a timeout, Audio Pencil removes it immediately and does not automatically re-enable it. An in-progress dictation stops normally, the window and menu bar report that shortcuts are paused, and menu-bar dictation remains available. Quit and reopen the app to restore shortcuts.

The sidebar button restores the full sidebar and widens a narrowed window to fit it, without exceeding the page's useful width or the current screen. Manually narrowing the window still switches to the icon rail automatically.

## iPhone and iPad

The universal app (`AudioPencilPhone`, iOS/iPadOS 26) records on iPhone and iPad. Recordings can become notes, be added to the daily note, or be copied without filing. Filed notes use the same settings file and upload queue as the Mac.

On iPad, native adaptive navigation provides Record, Meetings, Notes and Settings in a sidebar or tab bar as the window changes size. Notes has a list-and-reading split view at regular widths; compact windows retain the phone layout. iPad supports portrait, landscape and resizable multitasking windows; iPhone remains portrait-first.

**Meetings** records in-person conversations through the current system microphone, including connected USB inputs and headsets. Enter a required title beside **Start Meeting**; at accessibility text sizes or compact height, these controls scroll with the setup form. Audio goes directly to bounded five-second disk segments, not an ever-growing in-memory recording. Pause, resume, stop/save and destructive discard are available in-app; Live Activity controls route to the current meeting. The saved meeting can be processed later, played back, and reviewed in Summary / Actions / Transcript, with editable titles, speaker names and Markdown tasks, review status, copying and conflict-safe filing. **Record** is the separate single-speaker workflow.

iPhone and iPad do **not** capture audio directly from another app. Meeting processing runs only while the app is active, pauses on leaving, and retries saved work on return. Download speech and writing models in Settings; without a writing model, the transcript remains available and the summary can be retried later. Recording itself continues in the background; audio interruptions and disconnected inputs pause it and require an explicit resume. Recovery retains completed audio segments after termination (up to the last five seconds may be lost). The Simulator cannot run the MLX writing model: validate summary quality, real microphone routes, Bluetooth, lock-screen recording and interruption recovery on physical devices.

Model and language settings wait while recording, saving or processing is active; unrelated settings remain usable. Synced model and vocabulary changes are saved immediately but applied to the engines only when active work finishes. The recording screen still supports deliberate language switching mid-recording. Starting a recording waits for interrupted note writing to stop before loading its speech model.

In Notes, each waiting recording's actions offer **Skip for Now**, **Resume Writing** and **Delete**. Skipping preserves the transcript and audio across relaunches and lets later recordings proceed; an active recording must finish stopping before it can be deleted. Queued and copied recordings both require deletion confirmation, and local deletion leaves text already copied elsewhere alone. Actions are available without swiping; full swipes never delete immediately.

- **Record:** live transcript as you talk, pause and resume, a language switch, then pick a style (it starts on the last one used). **Make Note** files it; If the writing model isn't on the iPhone yet, the sheet offers to download it. Discarding anything longer than 30 s asks first, with its length, both while recording and on this sheet. **Copy to Clipboard** writes it in the same style and only copies it; it waits under Notes › Copied, not filed, with its audio, where **File** files it as Make Note would have (or swipe to delete it).
- **Locked in a pocket:** recording carries on with the phone locked (background audio). A Live Activity on the Lock Screen and in the Dynamic Island shows the clock with Pause, Resume and Stop.
- **Without opening the app:** the Record a Note control (Control Centre, Lock Screen, Action Button via Settings › Action Button › Controls), and Siri or Shortcuts ("Start recording in Audio Pencil", Stop, Pause, Resume). Recordings stopped this way use the last style.
- **Feedback:** the Mac's start and stop cues with a haptic; an optional heartbeat tap (one or two taps every 1, 2 or 5 minutes) while the app isn't on screen; a distinct alert and an automatic pause when AirPods or another headset disconnects, or a call interrupts.
- **Quiet:** with no new words for the chosen time (1–5 minutes, default 5), the recording stops, drops the quiet end, and becomes a note as usual.
- **Noise:** "Reduce wind and traffic noise" (on by default) uses the iPhone's voice processing on the microphone.
- **Writing the note:** transcription runs on the Neural Engine and keeps up in the background. The writing model needs the GPU, which iOS only allows while the app is on screen (background GPU needs an entitlement a Personal Team can't have). So notes are written while Audio Pencil is open. Leaving stops the current one and it starts again on return, and a recording stopped from the Lock Screen is saved, with a notification, and written up next time the app opens. Writing shows its step, a progress bar where the share done is known (writing part 2 of 5, transcribing again for speaker labels) and the time so far. Notes → Waiting to be written lists them and says why they're waiting, and the Record screen offers **Write Now** when nothing is running; writing pauses while you record and carries on when you stop (the Record screen says so), and **Write them now** starts it by hand.
- **Filed:** Notes › Filed lists the recent notes, each with a copy button (the note's text as it is in the vault now, without frontmatter or transcript); in an Obsidian vault a tap opens one in Obsidian (`obsidian://open`, using the storage folder's name as the vault name, so the iPhone's Obsidian vault needs the same name). Each sync checks the vault, and notes deleted or moved there leave the list (the Mac's Recent list too).

Recording settings are on this iPhone only (Settings › Recording); sounds use the synced device section. Siri phrases are English for now.

## Layout

```
project.yml                   XcodeGen definition (app, widget and test targets, signing, schemes)
Config/Signing.xcconfig       ad-hoc by default; includes Signing.local.xcconfig if present
App/Shared/Sources            shared speech, writing, meetings, filing and sync controllers
App/macOS/Sources             thin macOS app: event tap, paste, indicator panel, windows
App/iOS/Sources               universal iPhone/iPad app: recording, meetings, notes and settings
App/iOSWidgets/Sources        Live Activity and recording controls
Packages/AudioPencilKit       shared Swift package used by both apps
  APCore                      settings, Fn tap/hold detection, styles, prompt builder, per-app memory, stats
  APAudio                     16 kHz mono capture (off the main thread), mic catalogue, levels, cues
  APModels                    ModelCoordinator (one large model resident at a time), catalogue
  APTranscription             WhisperKit wrapper, streaming transcriber, DictationEngine (what dictation needs from a speech model)
  APPhonon                    Phonon-2 through FluidAudio, English only (Mac only, a trial)
  APSummary                   MLX writing model (SmolLM3 by default), Hugging Face download, benchmark
  APStorage                   storage: Nextcloud (Login Flow v2) or any WebDAV server, local folder (iCloud Drive), Keychain
  APSync                      shared settings file (YAML in Markdown), three-way merge, offline upload queue
```

Memory rule: every model load goes through `ModelCoordinator.ensureLoaded`, which unloads whatever else is resident first. Whisper, Phonon-2 and the writing model are all `ManagedModel`s, so no two can be loaded at the same time.

## Tests

```bash
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData test
```

Mobile navigation and recovery tests run on either device class:

```bash
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencilPhone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/MobileDerivedData CODE_SIGNING_ALLOWED=NO test
```

Repeat with an available iPad destination. Simulator-only fixtures exercise required meeting titles, landscape and accessibility layouts, model-setting locks, deferred synced changes, recording rotation, confirmed deletion, skipped-queue persistence and background interruption without downloading models or accessing a microphone. A 390-point compact-size-class harness covers large-text queue actions; it does not emulate actual OS Split View or window resizing. Desktop regressions cover native call-app picker refresh/selection, required-title validation, keyboard event handling and timeout fail-open behavior, and sidebar/window restoration.

There's also an opt-in end-to-end WhisperKit test. It synthesises speech with `say`, streams it through the real model, and prints stop-to-text latency:

```bash
cd Packages/AudioPencilKit && AUDIOPENCIL_INTEGRATION=1 swift test --filter WhisperIntegration
```

The same for the Phonon-2 trial (Settings › Dictation › Try Phonon-2 for English). It runs the app's path, one pass over the whole recording at stop, against Whisper Small (English), on clean and room-like speech:

```bash
cd Packages/AudioPencilKit && AUDIOPENCIL_INTEGRATION=1 swift test --filter PhononIntegration
```

Debug builds can be driven without key presses, for end-to-end timing. These dictations never paste; the transcript goes to the log. Use `say` to talk to the mic:

```bash
scripts/debug-dictation.sh tap-start   # or: start (cold), warm (a lone first tap), stop, cancel
scripts/debug-dictation.sh phonon:on   # Phonon-2 trial on; phonon:force also ignores the vocabulary; phonon:off
scripts/debug-dictation.sh key:fnDown 0.6 key:fnUp   # simulated keys: fnDown, fnUp, other, escape, return, 0–9
```

Writing-model benchmark (downloads each candidate; must run through xcodebuild for Metal):

```bash
cd Packages/AudioPencilKit && TEST_RUNNER_AUDIOPENCIL_BENCH=1 TEST_RUNNER_AUDIOPENCIL_BENCH_OUT=$PWD/../../docs/benchmarks/run.md xcodebuild test -scheme AudioPencilKit-Package -destination platform=macOS -only-testing:APSummaryTests
```

Logs: `log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'`. Each dictation logs its stop→text and stop→paste times. The transcription silence gate matches the recording meter's -60 dBFS floor, so quiet external microphones still reach the speech model's own no-speech filter; skipped quiet tails are logged.

## Milestones

1. **Bare loop** (done): hotkey, record, live transcription, stop, paste raw text.
2. **Dictation polish** (done): instant start, mic priority list, Dock/menu-bar mode, launch at login, custom vocabulary.
3. **Styles** (done): hold-for-raw, MLX writing model with swapping, presets, number keys and clickable style menu, picker, per-app defaults, Styles page.
4. **Vault and sync** (done): Nextcloud (Login Flow v2) or a local/iCloud folder, folder selection, shared YAML settings file with three-way merge and ETag retries, offline upload queue.
5. **Notes in Obsidian** (done): long-form promotion (5 min, configurable), m4a audio, sectioned summaries, suggested title and tags, notification, notes and frontmatter via the offline queue, optional saving of quick dictations, Bases board, guide and samples. One-year audio retention moves to milestone 6.
6. **Like me, discovery, retention** (done): My writing page and interview, machine-aware model suggestions with on-device trials, Retention board (regular / archive / delete) with one-year audio expiry, board and settings-file repair, sound themes.
7. **Multilingual** (done): 7a spoken languages (per-app language memory, language badge and menu in the indicator, English and multilingual Whisper models, prompts and notes in the spoken language, per-language vocabulary, Like me samples by language, layout-aware paste); 7b the interface in French and Spanish (String Catalogs in the app and each package target; the vault guide and sample notes are written in the interface language when a vault is first set up; board view names and properties stay English).
8. **Setup and storage** (done): 8a models prepared in the background (dictation never waits; Small first for other languages, then Large v3 Turbo), configurable dictation key (Fn, Right ⌥ or Right ⌘; double-tap or single tap; a recordable shortcut) and a Try it here box; 8b storage without Obsidian (plain Markdown in any folder, any WebDAV server, Keep forever and Delete on the Notes page, Vault renamed Storage); 8c the six-step setup window.
9. **iPhone and iPad** (done): recorder and notes; walk-and-talk background recording, Live Activity, Control Centre / Action Button / Siri controls, cues and heartbeat, disconnect and silence handling, noise reduction and a recoverable writing queue; dedicated in-person Meetings with speaker labels; adaptive iPad navigation and note reading.
10. **Desktop Meetings** (implemented; call-capture release gate outstanding): disk-backed capture, recovery, source-aware processing, playback, speaker/action review and conflict-safe filing. Selected-app call audio is Debug-only pending the [live-call acceptance checks](meeting-mode-macos.md).
