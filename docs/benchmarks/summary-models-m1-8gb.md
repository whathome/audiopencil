# Writing-model benchmark

Machine: MacBookAir10,1, 8 GB, macOS Version 15.8.1 (Build 24H32)
Run: Oct 19, 2026 at 4:42 PM. Speeds are this run only; the first generation after a load includes MLX kernel compilation.

## Summary

| Model | Load | Quick note → Polished | Quick note → Professional | Diary → Diary | Work ramble → Professional (long-form) | Avg gen tok/s | Peak MLX memory |
|---|---|---|---|---|---|---|---|
| Qwen3-4B-4bit | 1.9 s | 4.6 s | 4.0 s | 8.6 s | 13.9 s | 23 | 2.68 GB |
| Llama-3.2-3B-Instruct-4bit | 2.3 s | 3.5 s | 3.9 s | 5.0 s | 8.7 s | 29 | 2.21 GB |
| SmolLM3-3B-4bit | 2.3 s | 3.3 s | 3.5 s | 6.1 s | 9.5 s | 29 | 2.2 GB |
| Qwen3.5-2B-4bit | 3.0 s | 2.5 s | 2.4 s | 4.1 s | 6.0 s | 44 | 1.71 GB |

## mlx-community/Qwen3-4B-4bit

Load: 1.9 s, footprint after load 2.18 GB

### Quick note → Polished

4.6 s total · prompt 252 tokens at 124 tok/s · generated 58 tokens at 23 tok/s

> Hi Sarah, I wanted to let you know the quarterly report will be a day late. The numbers from finance came in late yesterday, so I'll have it to you Thursday morning instead of Wednesday. Nothing else has changed. Let me know if that causes a problem with the board pack.

### Quick note → Professional

4.0 s total · prompt 255 tokens at 130 tok/s · generated 47 tokens at 23 tok/s

> Sarah, the quarterly report will be delayed by one day. Finance provided the numbers late yesterday, so I'll have it to you Thursday morning instead of Wednesday. Nothing else has changed. Let me know if this affects the board pack.

### Diary → Diary

8.6 s total · prompt 324 tokens at 121 tok/s · generated 135 tokens at 23 tok/s

> Today was, actually, a pretty good day. I got up early, went for a run along the river, which I haven't done in like two weeks, and it felt, it felt really good. Then work was, uh, mostly meetings, the usual. The server migration finally finished though, so that's, that's a weight off. In the afternoon I picked up the kids and we made pizza, and Maya put, like, way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. Yeah, that's about it.

### Work ramble → Professional (long-form)

13.9 s total · prompt 423 tokens at 124 tok/s · generated 240 tokens at 23 tok/s

> I’m addressing the backup strategy for the home server. Currently, data is backed up nightly to an external drive in the same room, which poses a risk if a fire or disaster occurs. Options include a second drive at my parents’ place, encrypted backups to the Nextcloud box at the cottage, or cloud storage. I prefer the cottage solution for its automation, though the upload speed is slow (10 Mbps), which could result in a week-long initial sync. I need to test restoration, as I’ve never done so. I’ll set up the cottage sync this weekend, check with Dave about the router’s static IP capability, and perform a test restore of the photos folder next week.  
> 
> - Backup Strategy: Current setup uses an external drive in the same room, which is insufficient for disaster recovery.  
> - Backup Options: Consider a second drive at parents’ place, encrypted Nextcloud backup to cottage, or cloud storage.  
> - Preference: Cottage Nextcloud for automation, despite slow upload speed.  
> - Testing: Need to test restoration process, as it has never been done.  
> - Next Steps: Set up cottage sync this weekend, verify router’s static IP, and perform

Peak MLX memory 2.68 GB; footprint after unload 726.4 MB

## mlx-community/Llama-3.2-3B-Instruct-4bit

Load: 2.3 s, footprint after load 1.76 GB

### Quick note → Polished

3.5 s total · prompt 270 tokens at 252 tok/s · generated 72 tokens at 29 tok/s

> Hey Sarah, just a heads up that the quarterly report is going to be a day late. The numbers from finance came in late yesterday, so I'll have it to you by Thursday morning instead of Wednesday. That's the only change, so everything else remains the same. If the board pack is affected, let me know and we can discuss it further.

### Quick note → Professional

3.9 s total · prompt 273 tokens at 270 tok/s · generated 83 tokens at 29 tok/s

> I wanted to inform you that the quarterly report will be delayed by a day. The finance department provided the numbers late yesterday, so I'll have the report ready for you on Thursday morning instead of Wednesday. This change does not affect any other aspects of the report. If you have any concerns about the board package, please let me know.

### Diary → Diary

5.0 s total · prompt 342 tokens at 278 tok/s · generated 110 tokens at 29 tok/s

> Today was actually a pretty good day. I got up early and went for a run along the river, which I haven't done in two weeks. It felt really good. Then work was mostly meetings, the usual. The server migration finally finished, so that's a weight off. In the afternoon I picked up the kids and we made pizza. Maya put way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week.

### Work ramble → Professional (long-form)

8.7 s total · prompt 441 tokens at 282 tok/s · generated 206 tokens at 28 tok/s

> As I evaluate my home server's backup situation, I've identified several options to consider. I currently rely on an external drive stored in the same room as the server, which poses a risk in the event of a fire. To mitigate this, I'm exploring alternatives.
> 
> Key Points:
> 
> * Options for backup include:
> 	+ Storing a second drive at my parents' place and swapping it every month
> 	+ Encrypting backups to the Nextcloud box at the cottage
> 	+ Paying for cloud storage, which I'm hesitant to do due to my desire for self-sufficiency
> * I'm leaning towards the cottage option, which offers automatic backups, but may result in slower initial sync times
> * I'll test restoring my data, including the photos folder, to ensure the process is working as expected
> * I'll ask Dave about the router's capabilities to assign a static IP address for the cottage sync
> * I'll set up the cottage sync this weekend and conduct a test restore of the photos folder next week

Peak MLX memory 2.21 GB; footprint after unload 267.8 MB

## mlx-community/SmolLM3-3B-4bit

Load: 2.3 s, footprint after load 1.69 GB

### Quick note → Polished

3.3 s total · prompt 286 tokens at 165 tok/s · generated 47 tokens at 30 tok/s

> Hey Sarah, the quarterly report will be a day late. The numbers from finance came in late yesterday, so I'll send it over Thursday morning instead of Wednesday. No other changes. Let me know if that affects the board pack.

### Quick note → Professional

3.5 s total · prompt 289 tokens at 155 tok/s · generated 45 tokens at 28 tok/s

> Hey Sarah, the quarterly report will be a day late. The numbers from finance came in yesterday, so it'll be ready Thursday morning instead of Wednesday. No other changes. Let me know if this affects the board pack.

### Diary → Diary

6.1 s total · prompt 358 tokens at 160 tok/s · generated 116 tokens at 29 tok/s

> Today was a pretty good day. I got up early, went for a run along the river, which I hadn't done in two weeks, and it felt really good. Work was mostly meetings, the usual. The server migration finally finished, so that's a weight off. In the afternoon, I picked up the kids and we made pizza, with Maya putting way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. That's about it.

### Work ramble → Professional (long-form)

9.5 s total · prompt 457 tokens at 164 tok/s · generated 188 tokens at 27 tok/s

> Summary: The speaker is considering backup options for their home server. They are leaning towards using Nextcloud at the cottage due to its automatic nature, but are concerned about the slow upload speed, which could take a week to complete. They plan to set up the backup this weekend, test restoring photos next week, and ask Dave if the cottage's router can provide a static IP.
> 
> Key Points:
> - Backups currently stored on an external drive in the same room, posing fire risk.
> - Options: 
>   - Second drive at parents' place, swapped monthly.
>   - Encrypted backups to Nextcloud box at cottage.
>   - Cloud storage, avoided due to dependency.
> - Leaning towards cottage option due to automatic nature.
> - Slow upload speed at cottage, estimated to take a week.
> - Plan to set up backup this weekend.
> - Test restoring photos next week.
> - Need to ask Dave if cottage router can provide static IP.

Peak MLX memory 2.2 GB; footprint after unload 194.8 MB

## mlx-community/Qwen3.5-2B-4bit

Load: 3.0 s, footprint after load 1.08 GB

### Quick note → Polished

2.5 s total · prompt 260 tokens at 230 tok/s · generated 59 tokens at 44 tok/s

> Hey Sarah, I wanted to let you know that the quarterly report will be a day late. The numbers from finance came in late yesterday, so I'll have them to you Thursday morning instead of Wednesday. Nothing else has changed. Let me know if that causes a problem with the board pack.

### Quick note → Professional

2.4 s total · prompt 265 tokens at 246 tok/s · generated 56 tokens at 44 tok/s

> Sarah, I'm reaching out to inform you that the quarterly report will be a day late due to late financial data submission. I will have the figures available to you Thursday morning rather than Wednesday. Everything else remains unchanged. Please let me know if this delay impacts the board pack.

### Diary → Diary

4.1 s total · prompt 332 tokens at 255 tok/s · generated 124 tokens at 45 tok/s

> Okay, so today was actually a pretty good day. I got up early, went for a run along the river, which I haven't done in like two weeks, and it felt really good. Then work was mostly meetings, the usual. The server migration finally finished though, so that's a weight off. In the afternoon I picked up the kids and we made pizza, and Maya put way too much cheese on hers, which was funny. I'm a bit tired now, but in a good way. I want to keep the running going, maybe three times a week. Yeah, that's about it.

### Work ramble → Professional (long-form)

6.0 s total · prompt 433 tokens at 261 tok/s · generated 192 tokens at 44 tok/s

> I am currently evaluating backup strategies for my home server. My current setup sends everything to an external drive nightly, but since it resides in the same room, it is vulnerable to fire. I have three options: swapping drives monthly, encrypting backups on a Nextcloud box at the cottage, or using cloud storage. I prefer the cottage solution because it is automatic, though the upload speed is slow—approximately ten megabits per minute, which means the initial sync could take a week. I also need to verify if Dave can provide a static IP address at the cottage. Additionally, I have never restored any data, which is a significant gap in my current setup. I will proceed with setting up the cottage sync this weekend and plan to test restoring the photos folder next week.
> 
> Action items:
> *   Confirm with Dave that the cottage router can provide a static IP address.
> *   Schedule a test restore of the photos folder for next week.

Peak MLX memory 1.71 GB; footprint after unload 330.3 MB
