# Brief: audio — sound bank, synthesis, cockpit AI voice, adaptive music, mixing

## Goal
The demo sounds as heavy and powerful as it looks: every hero action layered with metal, mechanism and
servo; beams sizzle, gatlings roar, missiles whoosh and crack with city slapback; monsters sound wet,
chitinous and huge; a calm robotic cockpit AI calls out events; music rises from tense exploration to a
boss battle. Everything driven by Events + FEEL ids, mixed so payoffs are never buried.

## Read first
`ref/research/audio-music.md` (ALL: twelve rules, layer anatomy, distance classes, 70-row sound list,
synthesis recipes §4, bus/ducking/voice-management §5, music §6 incl. the verified AudioStreamInteractive +
AudioStreamSynchronized API, MiniMax §6.4, autoload skeleton §7), `docs/CONTRACTS.md` §3 (Audio API),
`docs/FEEL.md` (sound column), `docs/SPEC.md` §8 (intensity curve), `game/core/events.gd`.

## You own
`game/audio/**` (the `Audio` autoload body, banks, `SoundEvent` resources, streams, tests, CREDITS_AUDIO.md,
audio_manifest.csv), `tools/sfx/**` (synthesis + processing scripts), `art/audio_src/**` (raw downloads,
git-ignored).

## Build
1. **Sourcing** (repo policy dossier §2.2): download CC0 packs (Kenney sci-fi/impact/interface/digital/
   voiceover/jingles, OGA 50/100/100-2 CC0 SFX, OGA Free Firearm Library, Tallbeard loops, OGA CC0 music)
   with curl into `art/audio_src/<pack>/` (unzip safely: only audio files, flattened names), then process
   with `tools/sfx/` (numpy/scipy/soundfile via `uv run --with`): layering, pitch-down, EQ, normalise to the
   dossier's loudness target, export OGG to `game/audio/sfx/`. Every file in `audio_manifest.csv`.
2. **Synthesis** (dossier §4 recipes): beams, charges, saber hum/swing, servos, whooshes, sub-bass hits,
   UI, alarms, shockwave inhale, overdrive swell, lance roar — rendered to OGG by script, deterministic.
3. **Cockpit AI voice** via the internal ys-api `POST https://ys-api.xaminim.com/api/minimax_tts` (needs
   IOA VPN; find its parameters by probing politely, no secrets in code): a calm female or male robotic
   voice (Chinese lines with English short tags, e.g. 「锁定目标」 "Target locked", 「能量不足」 "Energy low",
   「完美格挡」, 「超载启动」, 「蚀巢已摧毁 1/3」, 「警告：巨型生命体接近」, boss/phase lines, victory) — 40–60 lines,
   processed (robotic + cockpit radio EQ), credited as AI-generated (MiniMax) in CREDITS_AUDIO.md.
4. **Music**: explore / combat / boss / victory + stingers. Prefer CC0/CC-BY tracks from the sourcing
   table (credited). If quality demands, generate instrumental drafts with ys-api `/suno` ONLY after you
   record its usage terms in status (the lead decides before shipping). Implement the dossier §6.3 music
   graph: one AudioStreamInteractive (explore ↔ combat ↔ boss, bar-synced transitions) driven by
   `Audio.music_intensity(0..1)` from encounter state; stingers on stagger/kill/phase/spire destroyed.
5. **Audio autoload** (replace the stub, keep the API): buses per §5.1 (Master, Music, Bed, World,
   Enemies, Impacts, Hero (near-field), Voice, UI) with ducking (§5.2), 8 distance classes (§5.4), voice
   budget (40 world + 12 near + 24 2D, per-event caps/min intervals, priority stealing), `SoundEvent`
   resources (`audio/events/<id>.tres`: AudioStreamRandomizer, bus, class, pitch/volume randomisation,
   near/far variants with far delay d/343 s). Listen to Events + `Feel.event_requested` so every FEEL row
   and movement/combat event has sound without other units calling Audio (they may also call
   `Audio.play(id, pos)` directly). Ambient beds per layer (L0 tunnel hum, L1 street + distant traffic,
   L2/L3 wind, crown storm).

## Done when
- `tools/godot.sh check --only=res://audio/` → 0 errors; `tools/godot.sh test res://audio/tests/test_audio.gd`
  (bus layout, ducking amounts, voice caps + stealing, every FEEL id and every Events signal has a
  SoundEvent, distance class attenuation, music state transitions on intensity changes).
- `game/audio/CREDITS_AUDIO.md` + `audio_manifest.csv` complete (no unknown sources).
- A listening pass: `tools/godot.sh movie` of the feel gallery and of a weapons/melee demo WITH audio
  (movie capture records audio to the AVI) → `captures/audio_*.avi`; describe in status what you heard
  and what you fixed (levels, masking, fatigue).
