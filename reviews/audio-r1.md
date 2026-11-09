# audio — review r1 (lead) — FAIL (architecture excellent; source material must get real weight)

Verified myself: check 19 files clean; test_audio PASS; manifest + credits read; your loudness/band analysis
read. The mixer (12 buses, sidechain ducking, distance classes, voice budget, snapshots, bar-synced
AudioStreamInteractive, event router over all Events + FEEL rows, real-clock-safe) is exactly right.
But all 260 SFX and all music are numpy synthesis. The dossier's rule 11 says synthesise what synthesises well
(UI, alarms, beams, charges, servo, saber, sub, whooshes) and **record or borrow metal, debris, explosions and
creature bases** — that is where weight comes from (rule 1: "sell mass with machinery").

## MUST-FIX
1. **Real recorded layers** (CC0 only, from the dossier §2.1 table): Kenney Sci-fi / Impact / Digital Audio,
   OGA "50 CC0 Sci-Fi SFX" + "100 CC0 SFX" #1/#2, OGA **Free Firearm Library** (CC0) for gatling transients /
   mechanics / tails, Freesound CC0 only if a direct download works without login. Download with curl into
   `art/audio_src/<pack>/` (untrusted: extract only audio files, flattened names, never execute anything), then
   LAYER them with your synthesis in the bank scripts: footsteps (metal slam + your sub), landings, all
   explosions (crack/body from recordings + your sub + tail), debris, gatling (firearm library transient +
   your mech loop), melee clangs, shield block, monster vocals (animal/insect recordings pitched/processed
   per dossier §1.4 — wet chitin, clicks, roars). Keep the manifest honest per layer.
2. **Music**: replace the synthesised score with real tracks — CC0 (OGA "CC0 music" collection battle/boss
   tracks, Tallbeard loop bundle — check the licence file inside the zip, HoliznaCC0) or CC-BY with credits
   (Scott Buckley — epic/cinematic; Kevin MacLeod "Cyborg Ninja"-style synth action). Pick explore / combat /
   boss / victory pieces that share a key/tempo family where possible; if they do not, use bar-synced
   crossfades between full mixes instead of stem layering. Stingers can stay synthesised. List every track in
   CREDITS_AUDIO.md exactly as the licence requires.
3. **CSV import**: Godot imported `audio_manifest.csv` as translations (`*.translation` files appeared). Set its
   `.import` to `importer="keep"` (or move the manifest outside `game/`) and delete the generated translations.
4. Add a 60–90 s **listening reel** `captures/audio_reel.avi` (movie mode) cycling: footsteps walk/run, dash, boost,
   assault, landing heavy, rifle + charge, gatling burst + vent, missile salvo + blasts, saber string, parry,
   shockcore, ripper pack, juggernaut roar + slam, cockpit voice lines, music explore→combat→boss transitions —
   so the lead and the user can listen in one file.
