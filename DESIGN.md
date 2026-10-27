---
name: Audio Pencil
description: Private, on-device dictation for macOS, a pencil mark in the margin of whatever you're writing.
colors:
  pencil-amber: "#BA7517"
  pencil-amber-dark: "#EF9F27"
  window-ground: "#FFFFFF"
  window-ground-dark: "#252525"
  card-surface: "#F9F9F9"
  card-surface-dark: "#2D2D2D"
  pill-ink: "rgba(0, 0, 0, 0.82)"
  status-ready: "#32D74B"
  status-attention: "#FF9F0A"
  status-error: "#FF453A"
typography:
  display:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.1
  headline:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
  written:
    fontFamily: "New York, ui-serif, Georgia, serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
  subtitle:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.3
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  callout:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 600
    letterSpacing: "0.6px"
  figure:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.1
rounded:
  badge: "3px"
  keycap: "6px"
  nav: "7px"
  chip: "8px"
  banner: "10px"
  card: "12px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  card-gap: "10px"
  grid: "14px"
  md: "16px"
  section: "18px"
  page: "24px"
components:
  nav-item:
    textColor: "rgba(255, 255, 255, 0.85)"
    rounded: "{rounded.nav}"
    height: "30px"
    padding: "0 8px"
  nav-item-selected:
    backgroundColor: "{colors.pencil-amber-dark}"
    textColor: "#FFFFFF"
    rounded: "{rounded.nav}"
    height: "30px"
    padding: "0 8px"
  card:
    backgroundColor: "{colors.card-surface}"
    rounded: "{rounded.card}"
    padding: "16px"
  keycap:
    backgroundColor: "{colors.window-ground}"
    typography: "{typography.callout}"
    rounded: "{rounded.keycap}"
    height: "24px"
    padding: "0 8px"
  chip-on:
    backgroundColor: "rgba(239, 159, 39, 0.18)"
    rounded: "{rounded.chip}"
    padding: "6px 12px"
  button-primary:
    backgroundColor: "{colors.pencil-amber-dark}"
    textColor: "#FFFFFF"
    rounded: "{rounded.keycap}"
    padding: "3px 10px"
  recording-pill:
    backgroundColor: "{colors.pill-ink}"
    textColor: "#FFFFFF"
    rounded: "{rounded.full}"
    height: "34px"
    padding: "0 14px"
  style-chip:
    backgroundColor: "{colors.pencil-amber-dark}"
    textColor: "rgba(0, 0, 0, 0.8)"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  status-badge-ready:
    backgroundColor: "rgba(50, 215, 75, 0.14)"
    textColor: "{colors.status-ready}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  banner:
    backgroundColor: "rgba(255, 159, 10, 0.12)"
    rounded: "{rounded.banner}"
    padding: "12px"
---

# Design System: Audio Pencil

## Overview

**Creative North Star: "The Pencil in the Margin"**

Audio Pencil works in the margins. Its real interface is a hotkey and a small floating pill. Its job is done when your words land in someone else's app. The main window is where you configure and check things, not where you spend time, so it uses plain native macOS and saves its character for two marks: **Pencil Amber**, the trace the pencil leaves, and the **New York serif**, used for the written word. Everything else is a standard Mac control.

Density is calm and comfortable: generous 24 pt page margins, cards that group one thing each, and forms that read like System Settings. Depth comes from tonal layers, not shadows, so the window sits flat and quiet. The recording pill is the only element that floats, because it's the only one that has to sit above other apps.

The system rejects two looks outright. It must not look like a **SaaS dashboard** (rows of identical metric tiles and charts), and it must not look like **a web app on a Mac** (custom buttons, made-up navigation, hover-only actions). Where a stat or a card appears, it serves a decision. Where a control appears, it's the one macOS would use.

**Key Characteristics:**
- Native macOS controls, materials and semantic colours; brand shows through tint, type and a few signature components.
- One accent, Pencil Amber, used sparingly for selection, primary actions and the pencil's own marks.
- Serif for titles and for the user's words; SF for everything you operate.
- Flat, tonal layers with hairline edges; nothing in the window casts a shadow.
- Keycaps teach the hotkeys wherever gestures are explained.

### iPad adaptation

The universal iOS app keeps Pencil Amber, semantic system surfaces and New York for the written word. Native adaptive tabs become a sidebar where the window permits; Notes and Meetings use system list/detail split views, collapsing in compact windows. Recording has a bounded reading measure rather than stretching across the tablet. Forms, segmented review controls and toolbars remain standard SwiftUI controls with Dynamic Type. iPad supports both orientations and window resizing; microphone-only Meetings is distinct from the Mac's selected-app call capture.

## Colors

The palette is a single warm accent over neutral, appearance-aware system greys, with status colours kept to their system meanings.

### Primary
- **Pencil Amber** (light #BA7517, dark #EF9F27): the app's `AccentColor` asset, referenced in code as `Color.pencil`. Used for the selected sidebar row, switches, primary buttons, the current style chip in the recording pill, the "Note in 0:25" warning, card icons, and the one accented stat (Time saved). It's deeper in light mode to keep contrast against white, and brighter in dark mode against charcoal.

### Neutral
- **Window Ground** (#FFFFFF light, #252525 dark): the window and page background. In code it's the system background, never a hard-coded hex. Both values are renderings measured from the app, for reference.
- **Card Surface** (#F9F9F9 light, #2D2D2D dark): `background.secondary`, the fill for cards and stat tiles, one tonal step off the ground (darker in light mode, lighter in dark). Paired with a hairline `separator` edge at 60% opacity.
- **Pill Ink** (black at 82%): the recording pill's fill. It's the same in both appearances, because the pill floats over arbitrary content in other apps and must always read as a dark object.
- **Text:** the system `primary`, `secondary` and `tertiary` label colours. Secondary carries all descriptions and footers; tertiary is reserved for version strings and dismiss glyphs.

### Status
- **Ready** (system green): model ready, signed in, synced, "in use". Always paired with words or an icon, never colour alone.
- **Attention** (system orange): missing permissions, unconfigured vault, expiring audio, the setup banner.
- **Error** (system red): failures, and the "no audio" cross in the pill.

### Named Rules
**The Pencil Mark Rule.** Pencil Amber marks what is selected, primary or written by the pencil. It is never decoration, never a background wash behind content, and never more than a small fraction of any screen.

**The System Colour Rule.** Neutrals and status colours are the system's semantic colours, so Dark Mode and Increase Contrast work for free. Hex values in this file are reference renderings; code uses semantic colours.

## Typography

**Display Font:** New York (SF's serif design, `.system(design: .serif)`)
**Body Font:** SF Pro (system)
**Figure Font:** SF Pro Rounded (`.rounded` design), for numbers and keycaps

**Character:** A writer's pairing. The serif carries titles and the user's own words; SF carries every control, label and explanation. SF Rounded softens numbers and keycaps so they read as objects, not data.

### Hierarchy
- **Display** (New York bold, 30 pt): the page title on every main-window page. Exactly one per page.
- **Headline** (New York bold, 22–24 pt): sheet and walkthrough titles, such as "Your review board is ready" or a writing prompt. The sidebar wordmark uses New York semibold at 18 pt.
- **Written** (New York regular, 15 pt, 3 pt extra line spacing): the user's words: the last dictation, the note preview in the review sheet, and the writing-sample editor.
- **Subtitle** (SF regular, 15 pt, secondary): the single sentence under each page title.
- **Title** (SF semibold, 13 pt): item names within cards, such as gesture names, style names and prompt titles.
- **Body** (SF regular, 13 pt): form rows and values.
- **Callout** (SF regular, 12 pt, secondary): descriptions under titles and card explanations.
- **Label** (SF semibold, 10 pt, uppercase, 0.6 pt tracking, secondary): the card heading. It names the card, so it stands alone as the card's only heading and is never stacked above another one.
- **Figure** (SF Rounded semibold, 22 pt): stat values. Supporting figures, never the page's headline.

### Named Rules
**The Written Word Rule.** Serif is for titles and for what the user said or wrote. A control, label or system message in serif is wrong; a dictation preview in SF is also wrong.

**The System Size Rule.** Use system text styles (`.headline`, `.callout`, `.caption`) rather than point sizes, so text follows the platform's sizing. Fixed sizes are limited to the display title, headlines and the figure style.

## Layout

The main window is a two-column split: a sidebar of 220 pt, which becomes a 64 pt icon rail when collapsed or when the window is narrower than 760 pt, and a detail page. The window's minimum size is 520 × 560 pt. Its maximum width follows the useful page width plus the sidebar: 845 pt for Settings and 1,201 pt for content pages, reduced by 156 pt when the sidebar is explicitly collapsed. Height remains freely resizable.

Pages use a 24 pt margin and a 980 pt maximum content width, aligned to the leading edge, never centred. The stack rhythm is 18 pt between page sections and 16 pt between cards. Inside a card it's 16 pt of padding and 10 pt between elements. Grids of cards use 14 pt gutters.

Settings pages use grouped forms, pinned to the same 24 pt leading edge as every other page, with the page title in the first section header. Content pages (Dictation, Meetings, Styles, My writing, Notes) use cards and task-specific native controls; Storage is a Settings category.

Responsive behaviour is content-driven:
- The Dictation page puts stats beside the cards when there's room and moves them underneath in a two-column grid when narrow (`ViewThatFits`).
- Gesture and style grids are adaptive, with minimum columns of 185 pt and 300 pt.
- Keycaps and tags never wrap or squeeze.

### Named Rules
**The One Edge Rule.** Every page title, card and form section starts at the same 24 pt leading edge. A centred form or a page that starts elsewhere breaks the window into separate apps.

**The Two Containers Rule.** Preferences live in grouped forms; status and content live in cards. General preferences belong in Settings, not content cards. Task-specific meeting setup controls and Settings › Storage's connection steps (storage, account, folder) are the exceptions.

## Elevation & Depth

The window is flat. Depth comes from tonal layers: the window ground, then the card surface one step lighter, each card outlined by a 0.5 pt hairline in the separator colour at 60% opacity. The sidebar uses the system's translucent sidebar material. Nothing in the window casts a shadow.

Two things float, and both are system-like:
- the recording pill, a non-activating panel above all apps
- sheets, which use the system's own presentation

Keycaps carry a 1 pt hard bottom edge (black at 12%) so they read as physical keys. That's the only "shadow" in the window, and it's a key's edge, not elevation.

### Named Rules
**The Flat Window Rule.** Window content never casts a shadow. If something needs to stand apart, it gets a tonal step and a hairline, not a lift.

## Shapes

Corners are continuous (squircle), and the radius scales with the size of the object:
- 3 pt for number badges
- 6 pt for keycaps
- 7 pt for sidebar rows
- 8 pt for chips
- 10 pt for banners
- 12 pt for cards and style cards

Capsules are for things that are status or a single choice: tags, status badges, the recording pill and its style chip. Borders are hairlines only (0.5 pt). There are no thick rules and no coloured side borders.

## Components

### Buttons
Native and restrained: the macOS button styles, tinted by the accent.
- **Primary:** bordered prominent, filled with Pencil Amber. Used once per decision: Review…, Open board, the next writing prompt to answer.
- **Secondary:** standard bordered button, such as How it works, Skip or Sign out.
- **Inline:** link style for in-flow navigation, such as Change…, Edit or Note saving and audio retention…
- **Icon-only:** borderless SF Symbols (chevrons, minus, an `xmark.circle.fill` dismiss in tertiary). Each one has a VoiceOver label.
- Keyboard: the default action is bound to Return and cancel to Escape on every sheet.
- New styles stay drafts until Save; Cancel never adds an entry. Deleting a saved writing sample requires a confirmation showing an excerpt and explaining the local/synced consequence.

### Chips
- **Hotkey chip:** 8 pt radius, callout medium. When on, it has Pencil Amber at 18% fill with an 80% amber hairline. When off, it's clear with a 35% secondary hairline and secondary text.
- **Tags:** capsule, caption, 14% secondary fill. Informational, never interactive.

### Cards / Containers
- **Corner style:** 12 pt continuous.
- **Background:** card surface (`background.secondary`).
- **Shadow strategy:** none (see Elevation & Depth).
- **Border:** 0.5 pt separator hairline at 60% opacity.
- **Internal padding:** 16 pt; 10 pt between elements; an optional uppercase label heading with a trailing caption.
- **Style cards** are a fixed 158 pt tall. Descriptions reserve three lines and tags stay on one line, so the grid stays even. The whole card opens the editor, and a disabled style drops to 60% opacity.

### Inputs / Fields
These are the system controls inside grouped forms: switches, pop-up pickers, steppers, sliders with value read-outs in monospaced digits, and the text editor for vocabulary. Fields aren't restyled. A setting's explanation sits under its label as the second line of the control's label. A section's footer is callout size, secondary and left-aligned, so it reads as a note on the rows above rather than another setting.

Settings uses six categories in both the main page and the standalone window: **General** (app behavior and sounds), **Dictation** (hotkeys, push-to-talk timing, delivery, microphones, languages and vocabulary), **Notes** (saving, retention, daily notes, push-to-talk filing and task keywords), **Storage** (provider, account, folder and sync), **Models**, and **Permissions**. Categories are touch-friendly square buttons with an SF Symbol above the label, wrapping into extra rows at narrow widths. Selection uses an amber outline and a light amber fill with primary-colour text; Storage and Permissions carry attention badges when setup is needed. Common hotkey controls and push-to-talk delay stay visible; backup shortcuts, double-tap timing and mic warm-up sit under **Timing and shortcuts**. Links from Dictation and Notes open their corresponding category, not General.

### Navigation
- **Sidebar:** 30 pt rows with an SF Symbol fitted into a shared 16 × 16 pt icon slot and a title. The selected row fills Pencil Amber with white text and icon.
- **Grouping:** work pages, then Settings, separated by 14 pt. Storage lives inside Settings, not in the sidebar.
- **Badges:** a count capsule for pending reviews and an orange exclamation on Settings for missing permissions or unconfigured storage. Over an amber selection, the attention symbol uses black and white rather than orange; selected rail dots use the same contrast treatment.
- **Rail mode:** 40 × 34 pt icon targets with an 8 pt dot for attention; every rail item has a VoiceOver label and a tooltip.
- **Shortcuts:** ⌘1–⌘6 follow the sidebar order: Dictation, Meetings, Styles, My writing, Notes, Settings.
- **Meetings:** a task-focused recording and review page, not a second library. Setup uses native fields and pickers; the required title sits beside Start Meeting on every platform. On iOS, title/start controls scroll inside the form at accessibility sizes or compact height, rather than consuming the viewport as a fixed footer. The Mac call-app menu refreshes when opened; missing access is labelled with an Open Permissions link, while Allow… stays in Settings › Permissions. Recording leads with source names, separate meters and Pause/Stop. Review uses a segmented Summary / Actions / Transcript control, serif written content and timestamped speaker turns. A recording badge appears in the sidebar and its collapsed rail.
- **Processing:** a compact status strip links back to the processing meeting when another page or meeting is selected, including the standalone Settings window. Only conflicting actions are disabled; writing, style editing and unrelated settings stay available. Disabled meeting start explains its missing prerequisite.
- **Recovery:** dictation issues lead to the relevant Permissions, microphone or Models category. Rewrite fallback is an informational, dismissible notice; the delivered raw text stays available to copy.

### Keycap (signature)
How the app teaches its hotkeys. A rounded label (SF Rounded, callout medium) on the window ground, with a 6 pt radius, a separator hairline and a 1 pt bottom edge. It's at least 30 × 24 pt and never wraps. Gestures pair keycaps with a title and a one-line detail.

### Recording Pill (signature)
The product's main interface, floating 20 pt above the bottom of the screen, centred.
- **Shape:** a 34 pt capsule in Pill Ink with a white hairline at 12% and white content.
- **Level meter:** 14 bars, 3 pt wide.
- **Clock:** a monospaced elapsed time, which appears after 30 s.
- **Style chip:** a Pencil Amber capsule with the style's number badge, its name and a chevron. Raw uses white at 18% instead.
- **Controls:** what a click changes has an edge. The chip opens the style menu (its chevron says so). The **Paste / Note / Meeting** toggle and push-to-talk's **Paste / Paste + Daily note / Paste + Inbox** badge cycle on click: a white-at-12% capsule (28% once changed for this recording) with a 1 pt white-at-20% edge and a small cycle glyph, text amber when the outcome isn't a plain paste. A linked daily note is spelled out ("Note + Daily"), not an icon. Push-to-talk shows only its badge, never the toggle. The language badge ("EN") shares the edge. The pointer turns into a hand over any of them, since the panel never gets hover.
- **No audio:** a red `mic.slash` at the start of the meter, the same mark as "Nothing heard".
- **Approaching the long-form threshold:** the clock turns amber ("Note in 0:25"), then shows "Note · 5:03" with a document glyph once the recording will become a note.
- **Other states:** a progress bar while rewriting, "On clipboard" and "Nothing heard", each a single line in the same capsule. Errors and notices wrap to two lines (up to 440 pt) in the same shape with the same ends. An error stays until it's clicked or the next recording starts; a click dismisses it or does what it says ("Click to open Privacy & Security").

## Do's and Don'ts

### Do:
- **Do** use native macOS controls and grouped forms for anything configurable, pinned to the 24 pt page edge.
- **Do** reserve Pencil Amber for selection, primary actions and the pencil's own marks (the style chip, the long-form warning).
- **Do** set the user's words in New York; set everything you operate in SF.
- **Do** use system semantic colours and text styles so Dark Mode, Increase Contrast and text size work without extra code.
- **Do** show hotkeys as keycaps, and give every keycap group a spoken label ("Double-tap Fn").
- **Do** pair every status colour with a word or symbol.

### Don't:
- **Don't** make it look like a SaaS dashboard: no rows of identical metric tiles, charts or KPI hero numbers leading a page. Figures support; they never headline.
- **Don't** make it look like a web app on a Mac: no custom-drawn buttons, made-up navigation, hover-only actions or web-style link colours for primary actions.
- **Don't** add shadows to window content; use a tonal step and a hairline.
- **Don't** put general preferences inside content cards; they belong in Settings. Task-specific meeting setup controls and Settings › Storage's connection flow are the exceptions.
- **Don't** centre forms or start a page anywhere but the shared leading edge.
- **Don't** use Pencil Amber as a background wash, gradient or decorative fill.
