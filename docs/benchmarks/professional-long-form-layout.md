# Professional long-form layout on SmolLM3-3B

The [Qwen3-4B-Instruct benchmark](qwen3-4b-instruct-vs-smollm3.md) found that SmolLM3-3B (the default
writing model) ignored the Professional long-form layout: one paragraph, no key-point bullets, no
"Action items" list, in 3 of 3 runs. This note covers the prompt change that fixes that.

**Result:** in 17 of 17 runs, the long-form Professional output now has a Summary, Key points and
Action items. Before the change, 0 of 7 runs had that structure. The quick-note cases and Diary are
unchanged. The cost is about 52 more prompt tokens (+0.3–0.4 s to first token) and longer output:
a long-form rewrite of the benchmark fixture now takes 8.8–9.6 s.

## The change

`PromptBuilder.prompt` (only for long-form styles that extract action items and rewrite heavily,
which today means Professional):

- The system rule now reads `End with an "Action items" list of what I committed to.` It used to
  read `…of what the speaker committed to, if anything.`
- After `</transcript>` in the user message, it adds:

  ```
  Write it as me, in three sections, in this order:
  **Summary**: 2–3 sentences.
  **Key points**: bullets, grouped under a bold heading per theme.
  **Action items**: a bullet for each thing I said I'd do, or just "None".
  ```

`Style.swift` is unchanged. Saved styles keep their own instructions, so a fix in the Professional
preset's text would only reach new installs and reset styles. The fix in `PromptBuilder` reaches
everyone. Quick dictation still gets `No action items list.` and no layout block, and so do
long-form Polished and Diary.

## Before / after (work ramble → Professional, long-form)

Before. Every run was one paragraph like this one (19 Oct, run 1):

> I'm considering improving the backup system for our home server. Currently, everything is backed
> up to an external drive nightly, but it's located in the same room, posing a risk if there's a
> fire. Options include … To test restoring, I'll set up the cottage sync this weekend, ask Dave if
> the router there can provide a static IP, and perform a test restore of the photos folder next week.

When the old prompt did produce a list, it produced only the list and invented a commitment
(20 Oct, same-session "before" run):

> Action items:
>
> - Swap external drive monthly with parents' drive.
> - Set up Nextcloud backup at cottage this weekend.
> - …

After (20 Oct, run 3):

> **Summary**: I'm considering three backup options: swapping drives monthly with my parents, using
> Nextcloud at the cottage, or paying for cloud storage. I'm leaning towards the cottage because it's
> automatic, but the slow upload speed (10Mbps) means the first sync would take a week. I'll test
> restoring the photos folder next week and ask Dave if the cottage router can provide a static IP.
>
> **Key points**:
> - **Backup Options**: Monthly swap with parents, Nextcloud at the cottage, or cloud storage.
> - **Cottage Backup**: Automatic, slow upload (10Mbps), first sync will take a week.
> - **Testing**: Test restore of photos folder next week.
> - **Router Configuration**: Ask Dave if cottage router can provide static IP.
>
> **Action items**:
> - Test restore of photos folder next week.
> - Ask Dave if cottage router can provide static IP.
> - Set up cottage sync this weekend.

## Quality across runs

The final prompt ran 17 times on the work-ramble fixture: 3 benchmark runs plus 14 prompt-lab runs
with the same prompt. The old prompt ran 7 times: 3 benchmark runs on 19 Oct, 1 on 20 Oct, and 3
lab runs.

| | Old prompt (7 runs) | New prompt (17 runs) |
|---|---|---|
| Summary + Key points + Action items | 0 | 17 |
| Key points grouped under theme labels | 0 | 16 (1 flat list) |
| Action items as a bulleted list | 2 (list only, nothing else) | 16 (1 written inline) |
| Invented commitment ("swap drives monthly", an option the speaker only weighed) | 2 | 1 |
| Second person / "the speaker" | 0 | 0 |

Diary transcript through long-form Professional, which has no real commitments (4 runs): every run
listed only "Run three times a week". The speaker did say "I want to keep the running going, maybe
three times a week", so that is an intention turned into an action item, not an invention.

The run that invented a commitment (benchmark run 2) also asked "if Nextcloud at cottage can have
static IP" where the speaker said the router. One distortion appears with both prompts: the summary sometimes merges "I should test restoring" with
"set up the cottage sync this weekend" into "test restoring … this weekend".

## Timings

Benchmark (`SummaryBenchmarkTests`, SmolLM3-3B-4bit only), 20 Oct, 01:58–02:03. Runs in order: after,
after, before, after.

| Run | Load | Polished | Quick Prof. | Diary | Long-form Prof. | Section notes | Gen tok/s | Peak MLX | Process peak |
|---|---|---|---|---|---|---|---|---|---|
| after 1 | 2.7 s | 3.1 s | 3.0 s | 6.0 s | 9.6 s | 6.8 s | 30 | 2.21 GB | 2.38 GB |
| after 2 | 2.6 s | 3.2 s | 3.0 s | 5.5 s | 8.8 s | 6.6 s | 30 | 2.21 GB | 2.38 GB |
| before | 2.6 s | 3.1 s | 2.9 s | 5.8 s | 4.2 s ¹ | 7.5 s | 29 | 2.18 GB | 2.32 GB |
| after 3 | 2.6 s | 3.2 s | 3.1 s | 5.7 s | 9.0 s | 6.7 s | 30 | 2.21 GB | 2.38 GB |

¹ The "before" long-form run wrote only a 46-token Action items list. The old prompt's normal
one-paragraph output is 142 tokens: 8.6–9.1 s on 19 Oct at 21–24 tok/s, or about 7.3 s at today's
30 tok/s.

Long-form Professional, old → new:

- Prompt: 416 → 468 tokens. First token 2.4 → 2.8 s.
- Output: 142 → 175–208 tokens (+1.1–2.2 s at 30 tok/s).
- Total: about 7.3 s (estimated at today's speed) → 8.8–9.6 s.
- Peak MLX memory: +0.03 GB.

The quick-note prompts are byte-for-byte unchanged, and so are their times.

## Long recordings (section notes → final pass)

Recordings over 2,000 words are summarised section by section, and the long-form prompt then runs on
the joined bullet notes. No benchmark fixture is that long, so a scratch test built this input from
two real section-notes passes: the work ramble as part 1 of 2 and the diary as part 2 of 2. It then
ran the final pass on the joined notes, 18 times in all:

| | Old prompt (6 runs) | New prompt (12 runs) |
|---|---|---|
| Summary + Key points + Action items | 1 (3 more had Summary + Action items; 2 were plain paragraphs) | 11 (1 put the actions inside Key points) |
| Correct Action items list | 4 | 10 (one of them ends with a stray "None"); plus 1 inline and 1 wrongly "None" |
| Kept the second, unrelated section (the diary) | 2 | 3 |
| Total time | 6.4–12.0 s | 7.9–11.2 s |

The layout carries over to notes input, though less reliably than on a transcript. One new failure
appeared: "Action items: None" despite three clear commitments. Both prompts usually drop the
unrelated second section. This was already the case with the old prompt, most likely because of
the Professional style's "drop rambling" instruction. Real long recordings that stay on one subject
may behave differently. The next section fixes the dropped topics.

## Long recordings: keeping every part's topics

The final pass now gets the section notes labelled by part, and the layout block names the parts:

- `PromptBuilder.joinSectionNotes` joins the notes as `Part 1:\n…\n\nPart 2:\n…`. The app used to
  join them with blank lines only.
- A new context, `.sectionNotes(count:)`, is used only for this final pass. It adds a sentence before
  the layout block and extends the Key points line:

  ```
  These are my notes from 2 parts of one recording. Write it as me, in three sections, in this order:
  **Summary**: 2–3 sentences.
  **Key points**: bullets, grouped under a bold heading per theme, with themes from Part 1 and Part 2.
  **Action items**: a bullet for each thing I said I'd do, or just "None".
  ```

The system rules are unchanged, including "drop rambling" and "Make it shorter than the transcript".
A single-transcript long-form prompt (`.longForm`), quick notes and Diary are byte-for-byte unchanged.

**Result:** on the same scratch input as above (work ramble as part 1, diary as part 2, fresh
section notes each round), the diary topic appeared in Key points in 11 of 12 final passes, against
0 of 12 with the old prompt. The prompts ran interleaved on one loaded SmolLM3-3B-4bit, 20 Oct
13:28–13:35, with 6 rounds of section notes and 2 runs per prompt per round.

| | Old prompt (12 runs) | New prompt (12 runs) |
|---|---|---|
| Second part (diary) in Key points | 0 | 11 |
| Summary + Key points + Action items | 12 | 11 (1 had no Action items list) |
| Stray "None" after real action items | 0 (1 inline "; none") | 3 |
| Prompt tokens | 453–524 (avg 480) | 484–555 (avg 511) |
| Generated tokens | avg 208 | avg 228 |
| Total time | 10.4–18.8 s (avg 12.7) | 10.5–16.9 s (avg 13.9) |

The cost is 31 more prompt tokens (about 0.2 s) and about 20 more output tokens, the diary's
bullets (about 0.8 s at 25 tok/s). Generation ran at 15–30 tok/s in this lab (average 25), so these
times are slower than the benchmark below. The new prompt doesn't add any new kind of mistake. It
gets the same distortions as before: "test restoring … this weekend" merged from two plans, and once
"I also asked Dave", in the past tense. The diary's "want to keep running three times a week" stays
a Key point. It never reached Action items in these 12 runs, but did in 1 earlier lab run.

Single-transcript check (`SummaryBenchmarkTests`, SmolLM3-3B-4bit only, 20 Oct 13:44–13:46, 2 runs):
the long-form prompt is still 468 tokens and took 9.3 s and 9.4 s (8.8–9.6 s before), with Summary,
Key points and Action items both times. The other cases were 2.9–3.5 s for quick notes, 5.8 s for
Diary and 7.3–7.6 s for section notes, all at 29 tok/s, with peak MLX memory 2.21 GB, as before.

What else was tried (lab batches of 6–9 runs per variant, counts are runs with the diary in Key points):

- **Wording only, no part labels**: telling it the input is "notes from 2 parts" and that "every
  topic in the notes gets one" kept the diary in 3 of 6 runs. Adding "2–3 sentences that mention
  every topic" to the Summary line got 3 of 9. Replacing "Make it shorter than the transcript" with
  "keep every topic" in the system rules got 0 of 6. Dropping that rule as well as changing the
  wording got 1 of 6.
- **Part labels with no other change**: 2 of 9. Labels plus the lead sentence: 5 of 9.
- **Labels plus "Every part's topics get one"**: 16 of 24 over three batches, from 3 of 9 to 9 of 9.
  Results swing a lot with the section notes of each round, which is why only variants that held
  up across batches were kept.
- **Naming the parts in Key points** (the change above): 9 of 9 and 7 of 8 in the lab, then 11 of 12
  in the final comparison. That's 27 of 29 overall.
- **"Going through Part 1, then Part 2"** and **"a sentence or two per part"** kept the diary 8 of 8
  each, but lost the Action items list in 2 of 8. The per-part summary also copied "Part 1:" and
  "Part 2:" into the note as headings. **"A bold heading for each part's main topic"**: 4 of 8, and
  only 4 of 8 had the layout.

Raw outputs, the lab test and run-condition logs are kept outside the repo with the earlier lab
files. Run conditions as in Method below: Audio Pencil running and idle, normal memory pressure,
≥ 25% free memory, no compiler processes, ≥ 50% CPU idle for the variant batches, ≥ 60% for the
final comparison and ≥ 70% for the benchmark.

## What didn't work

From 10 prompt-lab batches, 3–8 runs per variant, all on one loaded SmolLM3:

- **Layout in the system rules**, however phrased (prose, a skeleton, or a bold-heading template):
  0 of 15 runs had the structure. SmolLM3 writes the summary paragraph, which already mentions every
  plan, and stops. Moving the same instructions after the transcript was the change that mattered.
- **A literal skeleton with `<Theme>` placeholders**: the model copies them ("**<Theme> Backup
  Options**"). With `…` or "First theme" placeholders it ignores the themes or copies the label.
- **"Leave out Action items if I committed to nothing"**: the model stops before the list.
  **A required list with no "None" option**: it invents items to fill the list (2 runs added "swap
  drives monthly").
- **Limiting the summary** ("1–2 sentences: the gist", "without the plans"): ignored. Removing the
  layout sentence from the style's own instructions made the summary drop the options.
- **Without the system-side Action items rule** the after-transcript block gets Action items only
  2/5 times. With it: 5/5.
- **"Write three sections"** without "as me" (with the system rule) slipped into "You're considering…" in 2 of 11 runs. Adding
  "as me" removed that.
- **Adding "(not options)" or "only what I said I'll do"** to the Action items line made it worse:
  one invented commitment, and two runs with no Action items.

## Method

- Benchmark: `Packages/AudioPencilKit/Tests/APSummaryTests/SummaryBenchmarkTests.swift` with the
  first-token, section-notes and process-peak additions from the Qwen benchmark branch
  (`claude/bench-qwen3-4b-instruct-c46037`). Those additions were used for these runs but aren't
  part of this change. Command as in that note, with
  `TEST_RUNNER_AUDIOPENCIL_BENCH_MODELS=mlx-community/SmolLM3-3B-4bit`. The "before" run rebuilt
  with `PromptBuilder.swift` from `HEAD`.
- Prompt lab: a throwaway opt-in test that loaded SmolLM3 once and ran prompt variants back to back.
  It was not committed. Temperature 0.3 and top-p 0.9, as in the app.
- Run conditions: MacBookAir10,1 (M1, 8 GB), macOS 15.8.1, Xcode 26.3, mlx-swift-lm 3.31.4.
  Before each benchmark run, a preflight required Audio Pencil (running, from another session) at
  < 15% CPU, free memory ≥ 25%, normal memory pressure, no compiler processes and ≥ 70% CPU idle.
  Free memory was 47–55% and generation held at 29–30 tok/s in every run. Lab runs used a 50% idle
  bar instead, because an `ANECompilerService` job and other sessions were busy. Lab timings are
  therefore noisy (13–30 tok/s), and only the benchmark runs above are used for timing.
