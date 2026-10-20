# Multilingual Whisper on the M1 MacBook Air (8 GB)

Which WhisperKit model should transcribe languages other than English? English keeps `openai_whisper-small.en`.
Candidates: `openai_whisper-small` and `openai_whisper-large-v3-v20240930_turbo_632MB` (Large v3 Turbo), the two
multilingual models in this Mac's transcription budget (12% of RAM, about 0.98 GB).

**Recommendation: Large v3 Turbo is the default for other languages.** It is as fast as Small in practice and far more
accurate: Small cut off the second half of the Spanish clip (61% word error rate) while Turbo got it nearly word-perfect.
The cost is a one-off 12.5-minute preparation on first use (Core ML compiling for the Neural Engine); after that it loads
in about 1.5 s like the English model.

## Method

- Speech from the system voices (Flo, French (France); Flo, Spanish (Spain); Anna, German), 20–23 s per clip, the same
  backup-plan script as the English tests. Synthetic speech is cleaner than a real voice, so real-world error rates will
  be higher for both models.
- Audio fed in half-second chunks with a streaming pass after each, then the tail transcribed at stop, as the app does.
  "Live passes" is the total time those passes took: above the audio length means the model falls slightly behind live
  and has more left to do at stop.
- Word error rate against the script, ignoring case and punctuation.
- `AUDIOPENCIL_WHISPER_BENCH=1 swift test --filter MultilingualWhisperBenchmark` in Packages/AudioPencilKit, Oct 19 2026,
  app idle.

## Results

| Model | French WER | Spanish WER | German WER | Live passes / audio | Stop → text | First load |
|---|---|---|---|---|---|---|
| Small (multilingual) | 14% | 61% (stopped mid-clip) | 5% | 17–26 s / 20–23 s | 0.7–2.7 s | 89 s |
| Large v3 Turbo | 11% | 1% | 3% | 29 s / 20–23 s | 0.9–1.2 s | 751 s |

Mistakes worth knowing about:

- Both models struggle with names in another language's sentence ("Dave" became "Téva", "Dev", "der"), which is what
  per-language vocabulary is for.
- Small turned "en cas d'inondation" into "en catinodation"; Turbo into "en cas d'innovation".
- Both garbled the first words of the German clip ("Kurzes Update" became "Kurzes Album" / "Kurzes Adunkzeit").

## Raw output

| Model | Lang | WER | Live passes / audio | Stop → text | Load | Footprint |
|---|---|---|---|---|---|---|
| openai_whisper-small | fr | 15% | 26.0 s / 20 s | 0.68 s | 89.02 s (first) | 47.5 MB |
| | | _petit point sur la sauvegarde du chalet. Aujourd'hui, je sauvegarde le serveur de la maison chaque nuit sur un disque externe dans la même pièce, ce qui ne sert à rien en catinodation. Ce week-end, je vais mettre en place des sauvegarde chiffres vers le serveur du chalet. Je dois demander une adresse suffisante à Téva Vansamdi et je testerai une restauration complètement dimanche._ | | | | |
| openai_whisper-small | es | 61% | 24.3 s / 22 s | 2.71 s | 89.02 s (first) | 47.5 MB |
| | | _una actualización rápida sobre la copia de seguridad de la casa de cambo. Ahora mismo hago una copia del servidor cada noche en un disco externo en la misma habitación,_ | | | | |
| openai_whisper-small | de | 5% | 17.0 s / 23 s | 0.69 s | 89.02 s (first) | 47.5 MB |
| | | _kurzes Album. Seltsur Datensicherung im Ferienhaus. Im Moment sichere ich den Server jede Nacht auf eine externe Festplatte im selben Raum, was bei einem Hochwasser nichts nützt. Am Wochenende richte ich verschlüsselte Sicherungen auf den Server im Ferienhaus ein. Ich muss der vor Samstag um eine feste IP-Adresse bitten und teste am Sonntag eine vollständige Wiederherstellung._ | | | | |
| openai_whisper-large-v3-v20240930_turbo_632MB | fr | 12% | 29.3 s / 20 s | 1.05 s | 751.36 s (first) | 52.1 MB |
| | | _Petit point sur la sauvegarde du chalet. Aujourd'hui, je sauvegarde le serveur de la maison chaque nuit sur un disque externe dans la même pièce, ce qui ne sert à rien en cas d'innovation. Ce week-end, je vais mettre en place des sauvegards chiffrés vers le serveur du chalet. Je dois demander une adresse IFRIX à Dev avant samedi, et je testerai une restauration pour le dimanche._ | | | | |
| openai_whisper-large-v3-v20240930_turbo_632MB | es | 1% | 29.3 s / 22 s | 1.15 s | 751.36 s (first) | 52.1 MB |
| | | _una actualización rápida sobre la copia de seguridad de la casa de campo. Ahora mismo hago una copia del servidor cada noche en un disco externo en la misma habitación, lo que no sirve de nada si hay una inundación. Este fin de semana voy a configurar copias cifradas al servidor de la casa de campo. Tengo que pedirle a Dave una dirección y fija antes del sábado y probaré una restauración completa el domingo._ | | | | |
| openai_whisper-large-v3-v20240930_turbo_632MB | de | 4% | 29.5 s / 23 s | 0.93 s | 751.36 s (first) | 52.1 MB |
| | | _Kurzes Adunkzeit zur Datensicherung im Ferienhaus. Im Moment sichere ich den Server jede Nacht auf eine externe Festplatte im selben Raum, was bei einem Hochwasser nichts nützt. Am Wochenende richte ich verschlüsselte Sicherungen auf den Server im Ferienhaus ein. Ich muss stell vor Samstag um eine feste IP-Adresse bitten und teste am Sonntag eine vollständige Wiederherstellung._ | | | | |
