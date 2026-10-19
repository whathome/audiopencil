# Writing-model benchmark

Machine: MacBookAir10,1, 8 GB, macOS Version 15.8.1 (Build 24H32)
Run: Oct 19, 2026 at 4:52 PM. Speeds are this run only; the first generation after a load includes MLX kernel compilation.

## Summary

| Model | Load | Quick note → Polished | Quick note → Professional | Diary → Diary | Work ramble → Professional (long-form) | Avg gen tok/s | Peak MLX memory |
|---|---|---|---|---|---|---|---|
| SmolLM3-3B-4bit | 2.6 s | 3.1 s | 2.9 s | 5.7 s | 10.3 s | 30 | 2.16 GB |
| Qwen3.5-2B-4bit | 2.6 s | 2.2 s | 3.8 s | 4.2 s | 5.4 s | 45 | 1.61 GB |

## mlx-community/SmolLM3-3B-4bit

Load: 2.6 s, footprint after load 1.68 GB

### Quick note → Polished

3.1 s total · prompt 226 tokens at 144 tok/s · generated 46 tokens at 30 tok/s

> Hey Sarah, the quarterly report will be a day late. The finance numbers came in yesterday, so it'll be ready for you Thursday morning instead of Wednesday. No other changes. Let me know if that affects the board pack.

### Quick note → Professional

2.9 s total · prompt 232 tokens at 156 tok/s · generated 41 tokens at 30 tok/s

> Sarah, the quarterly report will be a day late, arriving on Thursday morning instead of Wednesday, due to late finance numbers. No other changes are anticipated. Let me know if this affects the board pack.

### Diary → Diary

5.7 s total · prompt 325 tokens at 159 tok/s · generated 111 tokens at 30 tok/s

> Today was a pretty good day. I got up early and went for a run along the river, which I hadn't done in two weeks, and it felt really good. Work was mostly meetings, the usual. The server migration finally finished, so that's a weight off. In the afternoon, I picked up the kids and we made pizza, and Maya put way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week.

### Work ramble → Professional (long-form)

10.3 s total · prompt 394 tokens at 164 tok/s · generated 241 tokens at 30 tok/s

> Summary:
> The user is considering backup options for their home server, given that the current setup involves daily backups to an external drive in the same room, which is vulnerable to fires. The user is weighing three options: storing backups with family members, using an encrypted backup on the cottage Nextcloud box, or using cloud storage. The user prefers the cottage option due to its automatic nature, but is concerned about the slow upload speed, which could take a week to complete. The user plans to set up the cottage backup this weekend, test restoring photos next week, and ask Dave if the cottage router can provide a static IP. 
> 
> Key Points:
> - Current backup method: external drive in the same room, vulnerable to fires.
> - Options considered:
>   - Second drive at parents' place, swapped monthly.
>   - Encrypted backups to Nextcloud box at cottage.
>   - Cloud storage, avoided due to dependency.
> - Preference: cottage Nextcloud box for automatic backups.
> - Concerns about slow upload speed (10Mbps), which could take a week.
> - Plan to set up cottage backup this weekend.
> - Test restore of photos folder next week.
> - Ask Dave if cottage router can provide static IP.

Peak MLX memory 2.16 GB; footprint after unload 181.4 MB

## mlx-community/Qwen3.5-2B-4bit

Load: 2.6 s, footprint after load 1.09 GB

### Quick note → Polished

2.2 s total · prompt 200 tokens at 230 tok/s · generated 60 tokens at 45 tok/s

> Hey Sarah, I just wanted to let you know that the quarterly report will be a day late. The numbers from finance came in late yesterday, so I'll have them to you Thursday morning instead of Wednesday. Nothing else has changed. Let me know if that causes a problem with the board pack.

### Quick note → Professional

3.8 s total · prompt 208 tokens at 246 tok/s · generated 136 tokens at 45 tok/s

> Sarah, I'm writing to inform you that our quarterly report will be a day late due to late submissions from finance. I will have the updated numbers to you by Thursday morning. Please let me know if this delay impacts the board pack.
> 
> **Key Points**
> 
> *   **Delays & Timelines**
>     *   The quarterly report is delayed by one day.
>     *   Finance data submission occurred yesterday.
>     *   Finance data will be delivered to Sarah by Thursday morning.
> 
> *   **Communication & Coordination**
>     *   Sarah was notified of the delay.
>     *   Sarah must confirm if the delay affects the board pack.

### Diary → Diary

4.2 s total · prompt 299 tokens at 251 tok/s · generated 136 tokens at 45 tok/s

> Okay, so today was, actually, a pretty good day. I got up early, went for a run along the river, which I haven't done in like two weeks, and it felt, it felt really good. Then work was, mostly meetings, the usual. The server migration finally finished though, so that's, that's a weight off. In the afternoon I picked up the kids and we made pizza, and Maya put, like, way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. Yeah, that's about it.

### Work ramble → Professional (long-form)

5.4 s total · prompt 370 tokens at 260 tok/s · generated 180 tokens at 45 tok/s

> I am currently evaluating three backup strategies for my home server: keeping everything on an external drive in the same room, moving to a second drive at my parents' location, or encrypting backups on a Nextcloud box at the cottage. While I initially preferred the cottage for its automatic nature, the slow upload speed there—approximately ten megabits per second—means the initial sync could take up to a week, which is unacceptable. I am leaning toward the cottage because it is automatic, but I must first verify if Dave can provide a static IP address for the router. I will set up the cottage sync this weekend and plan to test restoring the photos folder next week.
> 
> **Action items**
> *   Confirm with Dave that the router can be configured with a static IP address.
> *   Schedule the cottage sync for this weekend.
> *   Test restoring the photos folder next week.

Peak MLX memory 1.61 GB; footprint after unload 320.2 MB
