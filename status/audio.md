# audio status

## Done

**Sourcing (`art/audio_src/`, git-ignored by `art/audio_src/.gitignore`)** — every pack's and
track's licence, author and page are recorded on disk in an `oga_sources.json` sidecar written by
`tools/sfx/oga_fetch.py`, and `tools/sfx/run.sh credits_check.py` joins those records to the
shipped files, the manifest and `CREDITS_AUDIO.md`. Nothing is credited from memory.

**The one credit table is `game/audio/CREDITS_AUDIO.md`.** It names every pack and track that
ships, its author, its licence and the sound ids that layer it, and the check fails if any of
those disagree with what is on disk. Current summary (r6):

```
files=300 rows=300 sources=17 unmatched file→credit=0 credit→file=0 no_record=0 bad_author=0 unused_pack=0 used_for=0
```

Everything is CC0 1.0 — **no CC-BY and no non-commercial material ships**, so the credits screen has
no mandatory attribution rows.

Three of the records were written when the pack was fetched (`oga_bossmetal`, `oga_kenney2`,
`oga_music`); the other seven shipped packs (`oga_creature`, `oga_firearm`, `oga_moresounds`,
`oga_scifi50`, `oga_sfx100`, `oga_sfx100v2`, `oga_swishes`) were recorded on **2026-11-05** by the
fixed fetcher, without re-downloading anything. Kenney — Sci-Fi Sounds is not on OGA: its record is
the archive's own `kenney_scifi/License.txt` (CC0). Kenney — Digital Audio's is
`oga_kenney2/oga_sources.json`, joined by URL.

**Rule 11 split is now real.** Recorded: T (metal clank), B (container slam), D (stone/glass/metal
fragments), gunfire, mechanism (latch/switch), creature bases, thunder, air swish, bell, zap,
force-field, ambience beds. Synthesised: S (sub), M (servo/hydraulic), beams, charges, saber hum,
whooshes, alarms, UI, stingers.

**Toolchain (`tools/sfx/`)**
- `unpack.py` — safe archive extraction: audio + licence members only, `._` AppleDouble skipped,
  names flattened, magic bytes verified, nothing executed
- `oga_fetch.py` — fetch an OGA node's files and record what the node itself states (licence,
  author field, submitter, Attribution Instructions, date) in a JSON sidecar; retries, and
  refuses a licence this project may not ship
- `credits_check.py` / `credits_records.py` — the credit gate: join every shipped audio file to its
  manifest row, its CREDITS_AUDIO.md row and the licence record on disk, in both directions
- `sources.py` — the only reader of `art/audio_src/`; cached decode, deterministic pick, pitch
  shift, loop crossfade, peak normalise, per-render pack log
- `recorded.py` — the recorded layer kit (clank, slam, mechanism, debris, gunshot,
  explosion_recording, creature_base, thunder, swish, bell, zap, forcefield, ambience_loop)
- `analyse_music.py` — tempo (spectral-flux autocorrelation) + key (Krumhansl chroma) for the
  candidate tracks
- `music_tracks.py` — trim to whole bars, equal-power loop crossfade, loudness-match, write
  `game/audio/music/<clip>_mix.ogg` + `clips.json`
- `measure_movie.py` — loudness / true peak / band balance / per-window activity of a capture
- `build.py` — records which packs each rendered id actually used, so the manifest is honest per layer
- `dsp.write_ogg` now writes in 10 s blocks: a single `sf.write` of >30 s float32 stereo segfaults
  inside libsndfile's Vorbis encoder on this machine (bisected)
- The bank is deterministic: every WAV re-renders byte-identical. The five OGG beds re-render with
  identical *audio* (verified by decoding both revisions: max abs diff 0.0) but different container
  bytes — libsndfile writes a fresh OGG serial number each time. Expect those five files in a diff
  after any rebuild.

**Music** — six sourced CC0 tracks replace the synthesised score. They are not one key/tempo family,
so the graph crossfades full mixes on each clip's own bars instead of layering stems:

| Clip | Track | Author | BPM | Key | Bars |
|---|---|---|---|---|---|
| explore | Covert Operations | artisticdude | 95.7 | C maj | 39 |
| tension | Technological Menace | Umplix | 110.0 | C maj | 32 |
| combat | Epic Combat | Chester01 | 129.2 | D min | 40 |
| boss | Boss Battle #2 [Symphonic Metal] | nene | 145.6 | E maj | 24 |
| spire_cleared | Heroic Pressure (Loop) | StarNinjas | 120.2 | D maj | 12 |
| victory | Forgotten Victory | yd | 139.7 | F maj | 32 |

`AudioMusicDirector` reads `clips.json` for per-clip bpm/bar_beats/beat_count, and restarts the
silent metronome at the new clip's tempo on every switch, so stinger quantisation follows the music
that is actually playing. Stingers and the metronome stay synthesised.

**Assets** — 139 SFX ids / 240 files (310 s), 6 music clips + 7 cues, 47 voice lines. 300 manifest
rows, every one with source/licence/author/layers. QA: 0 files over −0.9 dBTP, 0 loop-point seams.

**CSV import fixed** — `audio_manifest.csv.import` is now `importer="keep"`; the six generated
`*.translation` files are deleted and do not come back.

## Listening pass

`captures/audio_reel.avi` — 88 s, movie mode, stereo 48 kHz audio track, 0 errors.
Timeline `game/audio/tests/timeline_reel.json` on `main.tscn --sandbox --skip-menu`, cycling:
walk → dash → assault → jump/land ×2 → rifle auto + singles + reload → gatling burst ×2 (spin, loop,
accent, spin-down, tail, vent) → rifle → missile salvo ×2 → saber string + charged slash →
guard/parry → shockcore burst → fins → well → rift step → anchor → overdrive + lock → sustained
combat (weapons, guard, melee, missiles, skills) → final push.

Measured with `tools/sfx/run.sh measure_movie.py`:

| | before (r1 captures) | reel now |
|---|---|---|
| LUFS-I | −21.2 (gatling) / −20.1 (melee) | **−21.6** (target −23) |
| true peak | −6.3 / −5.9 dBFS | **−5.9 dBTP** |
| LRA | 3.4 / 6.7 LU | **9.3 LU** |
| spectral tilt | 20–80 Hz led by 3 dB, 250 Hz–1 kHz 13 dB down (scooped) | **250 Hz–1 kHz leads, tilt 12.9 dB** |
| dead windows | — | **0 / 44** |

What the numbers said and what I changed, each re-measured:

1. **The gatling accent was a thump, not a crack.** Its 1–4 kHz band sat 27.4 dB under its
   20–80 Hz band. Cause: the recorded report was high-passed at 700 Hz and the synth sub sat at
   0.22. Now the report keeps its own band (only 120 Hz removed, so the sub has room) and the sub
   is at 0.12. → tilt 38.9 → **24.5 dB**, the gap 27.4 → **14.5 dB**.
2. **The recorded metal is dark.** `oga_sfx100/metal_*` measures 35.6 dB of band tilt with 4–16 kHz
   15 dB under the mid. Added `dsp.high_shelf` (+8 dB at 3.5 kHz in `recorded.clank`, +4 dB at
   2.2 kHz in `recorded.slam`) and raised the synthesised tick in `l_transient` 0.35 → 0.55.
   → footstep tilt 13.0 → 12.3 dB with 4–16 kHz up 1.8 dB; melee_light 22.7 → 20.6 dB.
3. **The gatling loop had no air.** Added a +6 dB shelf at 3 kHz to the per-round recorded base.
   → 4–16 kHz −45.0 → **−42.3 dB**.
4. **Creature vocals had no bite.** The creature packs are close-miked and dark; `titan_roar`
   measured 32.9 dB of tilt with 4–16 kHz 26 dB down. Added a +7 dB shelf at 2.5 kHz in
   `creature_voice`. → tilt 32.9 → **26.9 dB**, 4–16 kHz **+6.1 dB**.

Per-section band shape of the reel (dB, 20-80 / 80-250 / 250-1k / 1-4k / 4-16k), first capture →
second capture (with fixes 1–4 in the bank):

| section | first | second | tilt 1st → 2nd |
|---|---|---|---|
| walk 1–7 s | −33.8 / −40.3 / −35.9 / −43.9 / −46.6 | −33.8 / −40.1 / −36.1 / −43.9 / −45.9 | 12.9 → **12.1** |
| gatling 18–28 s | −36.1 / −35.5 / −29.1 / −41.7 / −52.4 | −41.1 / −35.5 / −28.8 / −41.4 / −51.7 | 23.3 → **22.8** |
| missiles 29–32 s | −33.7 / −38.3 / −40.1 / −44.3 / −47.8 | −35.8 / −37.8 / −39.7 / −44.4 / −48.1 | 14.1 → **12.3** |
| melee 32–37 s | −32.8 / −35.2 / −40.7 / −44.8 / −52.7 | −33.1 / −35.2 / −40.7 / −45.0 / −52.7 | 19.8 → **19.6** |
| skills 39–49 s | −42.9 / −39.3 / −39.6 / −43.1 / −51.0 | −43.0 / −39.6 / −40.2 / −43.8 / −51.4 | 11.7 → 11.8 |
| combat 60–72 s | −43.1 / −38.2 / −42.1 / −41.8 / −47.5 | −41.3 / −38.5 / −42.6 / −42.0 / −47.6 | 9.2 → 9.2 |

Second capture overall: **−21.6 LUFS-I, −5.9 dBTP, LRA 9.6 LU, tilt 12.7 dB, 0/44 dead windows.**

5. **The remaining reel tilt is the music, not the bank.** After fixes 1–4 the *rendered* gatling loop
   measures 80–250 Hz −32.9 / 250 Hz–1 kHz −40.5 / 1–4 kHz −37.0 / 4–16 kHz −42.3 — its 1–4 kHz band
   is 3.5 dB *above* its 250 Hz–1 kHz band. But in the reel the gatling window still reads 250 Hz–1 kHz
   12.6 dB over 1–4 kHz. Measuring the clips explains it: `explore_mix`, `combat_mix` and `boss_mix`
   all sit at **15.0–15.1 dB of band tilt** with 1–4 kHz 5–11 dB under the low end. These CC0 tracks
   are mixed dark. The bank is no longer the dark part of the mix; I left the tracks alone rather
   than EQ sourced music to match synthesis — if the lead wants more bite on the score that is a
   per-track shelf, not a bank change.

## Robustness round (reviews/audio-audit.md, 2026-11-02) — all 5 findings fixed

Every interval, age and quantisation in the unit now runs on **game time**, never the wall clock.
`game/audio/clock.gd` (`AudioClock.now()` → `Feel.real_now()`) is the one clock; a wall clock reads
~70 ms per frame under `tools/godot.sh movie` and ~5 ms per frame in a fast headless test, so every
interval measured on it shrank or stretched with the capture speed.

| # | Finding | Fix | Regression check (fails on the old code) |
|---|---|---|---|
| 1 | gatling loop released on a 250 ms wall-clock gap in `_process` | `_gatling_idle_s += Feel.player_delta(delta)` in `_physics_process` — the clock the gatling itself fires on (PROCESS_MODE_ALWAYS, so a pause still releases) | `the loop survives a hit-stop: release counts player_delta, not wall time` |
| 2 | pool `min_interval` + steal ages on `Time.get_ticks_msec()` | `AudioClock.since()` in `budget_ok`, `_steal_slot`, `_steal_2d`; `started_ms` → `started_at` (seconds) | `a 600 ms interval still blocks after 0.62 s of WALL time` |
| 3 | cockpit queue busy window + 8 s repeat guard on the wall clock | `AudioClock` for both, **and** the busy window now also waits for the pool to report the line stopped (new `line_sounding` callable → `pool.active_count`) | `the 1.2 s line is still speaking after 0.62 s of WALL time`, `a line the pool still reports as sounding holds the speaker` |
| 4 | music director's 2 s stinger gap on the wall clock (stingers bypass the pool, so it is their only limit) | `AudioClock.since(_last_stinger_at)` | `the 2 s gap still holds after 2.5 s of WALL time` |
| 5 | the beat clock restarted when a switch was *requested*, but the interactive stream only enters the destination at the next bar/beat | `switch_to()` now only queues; `_sync_to_stream()` polls `get_current_clip_index()` and hands the metronome over then — carrying the phase for SAME/PREVIOUS_POSITION, restarting at 0 for TO_TIME_START (`ENTERS_AT_HEAD`). A switch timeout (2 bars + 2 s) covers a mixer that never reports a change | `the beat clock stays on the playing clip's tempo (95.7 BPM) until the stream switches` |

`grep -rn "Time.get_ticks" game/audio/` → nothing.

The regression suite is `game/audio/tests/test_audio_clocks.gd` (runnable on its own, and run by
`test_audio.gd`, which adds its failures to its own). It reproduces the capture condition honestly:
`tools/godot.sh test` runs `--fixed-fps 120`, so `_slow_frames(n, ms)` burns `ms` of wall time per
frame while the game clock advances one fixed step — the same divergence a movie capture has. Each
check was proved to fail by patching the source file back to the wall-clock version and re-running
(evidence below).

### Also fixed from reviews/audio-lead.md (open notes)
- **`Events.boss_intro` is now bound** — the "every Events signal is wired" test was **red** on it
  (39 declared, 38 bound). `on_boss_intro` → `stinger_boss_phase` + `alarm_warning` +
  `ai_titan_approach` + `music_intensity(1.0)`.
- **`WEAPON_SOUNDS`**: the key `beam_rifle_stage2` never matched anything; `rifle.gd`'s stage ids
  are `rifle_stage1` / `rifle_stage2`. Now `rifle_stage1 → rifle_hit`,
  `rifle_stage2 → rifle_stage2_hit`.
- **`telegraph_unblockable` had no row at all** — `enemy_base.gd` calls it at every unblockable
  wind-up, so every fight logged an unknown-id warning. New synthesis recipe
  (`recipes.unblockable_tell`: a metallic screech rising a twelfth, high-passed and driven, over a
  96→41 Hz pulse) on the never-ducked **UI** bus, priority 92, cap 2, 220 ms interval. Measured
  band tilt 5.5 dB (the cue is bright on purpose). 138 ids / 238 files, 298 manifest rows.

### r4 capture (`captures/audio_reel_r4.avi`, 88 s, recorded at **68 % of real-time speed**,
24.5 ms of wall time per frame — the condition the audit describes)

| | r1 reel | r4 reel |
|---|---|---|
| LUFS-I | −21.6 | **−21.7** |
| true peak | −5.9 dBTP | **−5.8 dBTP** |
| LRA | 9.6 LU | **10.0 LU** |
| spectral tilt | 12.7 dB | **12.8 dB** |
| dead windows | 0/44 | **0/44** |
| DRIVE | errors=0 warnings=1 | **errors=0 warnings=0** |

The mix is unchanged to within 0.1 LU and 0.1 dB — as it should be: these fixes change *when* a
sound fires, not what is in the bank. Two honest caveats:

- **This capture cannot show finding 1.** At 68 % of real-time speed a gatling round lands every
  4 frames = 98 ms of wall time, under the old 250 ms threshold, so the old code would not have
  released the loop here either. The 0.25 s RMS windows over the gatling section (18–28 s) are
  therefore the same in both reels (min −29.4 dB, spread 11.2 dB). The audit's trigger needs a
  capture below ~20 % of real-time speed; the regression check reproduces it deterministically
  instead (a hit-stop plus 25 ms frames).
- `telegraph_unblockable` is not guaranteed to appear in this reel — the timeline can only press
  inputs, and whether an enemy runs an unblockable wind-up depends on the sandbox wave table. The
  drive log has **0 unknown-id warnings**, which is the part that used to be broken (every
  unblockable wind-up logged one).

## r5 — the five sound ids the enemies asked for did not exist (reviews/audio-r5.md)

**The root cause was one word, and it was bigger than the five rows.**
`event_router.enemy_type()` looked for `type_id` / `archetype` / `type`. `EnemyBase` declares
`@export var enemy_type`. So *every* enemy in the game classified as `""`, and with it:

- `telegraph_sound()` returned `""` → **no archetype telegraph tell ever played**, for any enemy,
  in any fight. That is the single most gameplay-critical cue in the dossier (§1.4).
- `is_boss()` / `is_large()` were always false → `on_enemy_staggered` played `stagger_enemy` for a
  Brood Titan instead of `boss_stagger`, and `on_enemy_killed` always chose `kill_small`. (`kill_large`
  still reached the mix, but only through `EnemyBase`'s own `Feel.play(body_height >= 12)` test, so it
  lost the router's priority-90 weighting and its far-delay layer.)
- `death_sound()` (new) would have had nothing to key off.

Proved before and after with a throwaway probe against a node carrying `enemy_type`:

```
PROBE keys -> ''          PROBE keys -> 'juggernaut'
PROBE tell -> ''          PROBE tell -> 'jugg_roar'
PROBE is_large -> false   PROBE is_large -> true
```

### Row by row

| id | decision | why |
|---|---|---|
| `enemy_telegraph` | **deleted the call** (enemy_base.gd) | the router voices the same moment through `Events.enemy_telegraph` → `ripper_leap_tell` / `mantis_glint` / `spitter_charge` / `harrier_screech` / `jugg_roar` / `titan_roar`. Before the `enemy_type` fix that tell was silent, which is why the direct call looked necessary. `telegraph_unblockable` stays: it is the enemies unit's own call on the never-ducked UI bus. |
| `enemy_stagger` | **deleted the call** | `Events.enemy_staggered` → `stagger_enemy` (+ `boss_stagger` for a boss, now that classification works) plus the `stinger_stagger` and the `ai_target_staggered` cockpit line. |
| `enemy_death` | **deleted the call, gave the moment a real sound** | `Events.enemy_killed` already played `kill_small` / `kill_large` + `kill_confirm`, but a HUSK died with a metal thud and no voice — `ripper_death`, `mantis_death` and `spitter_death` were sitting in the bank played by nothing. `on_enemy_killed` now adds `death_sound(enemy_type)`. |
| `juggernaut_plate_break` | **alias → `jugg_plate_break`** | no Events signal exists for a plate; the bank row was already built and wired to nothing. |
| `juggernaut_slam` | **alias → `jugg_slam`** | same. The *hit* router already mapped the `juggernaut_slam` weapon to `jugg_slam`; only the positional spawn call at `enemy_shockwave.gd:39` was dead. |

**Two things I did not leave alone:**

- **A sixth dead id the new scan found:** `flow/hive_spire.gd:210` calls `Audio.play(&"core_rupture")`
  — every burst Hive Spire pod was silent. Aliased to `finisher`, the same event the hit router
  already maps the `core_rupture` weapon to.
- **The same moment played twice.** `EnemyBase._die` emits `Events.enemy_killed` *and* calls
  `Feel.play(&"kill_large")`; `_on_staggered` does the same with `stagger_enemy`. Both reach the
  router, so one impact stacked two copies of itself in the same frame (`kill_large` cap 2, no
  interval). `kill_large` and `stagger_enemy` now carry a 60 ms `interval_ms`.

**New bank row:** `harrier_death` (the only archetype without a death cry) — a falling screech over a
wet collapse and a body impact, from `creature_voice` + `metal_impact`. 240 files / 139 ids,
300 manifest rows. QA: peak −7.0 dBTP, RMS −27, centroid 4.5–5.0 kHz, which sits right beside
`mantis_death` (−7.0 / −27 / 3.6 kHz) and is brighter on purpose for a flyer.

### The test that stops this coming back

`game/audio/tests/test_audio_call_sites.gd` — walks every `.gd` under `res://` (skipping `tests/`
and the import cache), collects every literal id handed to `Audio.play` / `play_loop` / `voice` /
`stinger`, and fails on any the bank cannot answer. Inside `res://audio/` the `Audio.` prefix is
optional so the router's own `play(&"…")` calls are covered too. **114 call sites, 0 unresolved.**

- It found the sixth id on its first run.
- Proved it catches a regression: breaking the `juggernaut_slam` alias produced
  `UNRESOLVED res://enemies/enemy_shockwave.gd:39 play(&"juggernaut_slam") -> Audio.resolve() returned null`.
- `game/audio/tests/test_audio_enemies.gd` covers the routing itself: every archetype reaches a
  tell and a death cry, the boss/large split reads `enemy_type` (**fails with 2 FAILs on the old key
  list**), and the directly-called ids must *start a voice*, not merely resolve —
  `juggernaut_plate_break` has no Events signal behind it, so nothing else would notice it going
  silent.

### `--audio-trace`

A drive log only says what *warned*. `Audio --audio-trace` now prints a per-id tally of every id
that resolved and asked the pool for a voice, at shutdown. These are **requests**, counted before
the pool's cap/interval budget — `heartbeat_loop=113` is the 0.25 s HP poll re-requesting one loop,
not 113 heartbeats.

30 s fight, `--enemies=juggernaut:1,mantis:2,ripper:5,spitter:1,harrier:1`, `errors=0 warnings=0`:

```
ripper_leap_tell=15  mantis_glint=11  spitter_charge=5  harrier_screech=8  jugg_roar=5
jugg_slam=3  ripper_death=3  telegraph_unblockable=8  stagger_enemy=14
kill_small=9  kill_confirm=9  hitmarker=37  melee_light=54  missile_hit=24
```

Every archetype's tell and death cry fires. Without the `enemy_type` fix that whole first group
reads zero.

### Listening pass — `captures/audio_fight_r5.avi` (30.7 s, stereo 48 kHz)

| | r4 reel (88 s, mixed) | r5 fight (30 s, 10 enemies) |
|---|---|---|
| LUFS-I | −21.7 | **−16.7** |
| true peak | −5.8 dBTP | **−5.8 dBTP** |
| LRA | 10.0 LU | **2.5 LU** |
| spectral tilt | 12.8 dB | **15.1 dB** |
| dead windows | 0/44 | **0/15** |

What I heard in the numbers, and what I did about it:

1. **The tells and death cries are back and they cut through.** The bright cue band is where they
   live: `telegraph_unblockable` measures 5.5 dB of tilt and the creature layer now carries
   `ripper_death` under every small kill. Nothing is buried — 0 unknown ids, 0 dead windows.
2. **The fight reads 5 dB hotter than the reel and has almost no dynamic range left (LRA 2.5 LU).**
   Every 2 s window sits at −18 to −22 dBFS, which is the *peak* window level of the 88 s reel, for
   30 s straight. That is the fatigue risk in this mix.
   I tested the obvious suspect first: `hurt_light` 90→200 ms and cap 2→1, `hurt_heavy` 150→300 ms.
   Re-recorded and re-measured: **−16.7 → −17.5 LUFS, LRA 2.5 → 2.7 LU.** Under a dB. The per-event
   budget was already limiting that layer, so the change bought nothing and would have decoupled the
   audio from FEEL's 150 ms vignette — **reverted**, both captures measured, the experiment capture
   deleted. The density is the *content*: ~46 ids firing near-continuously, most of them class C0
   (no distance attenuation) because the player is in the middle of the brawl.
   The real lever is the master calibration (`MASTER_TRIM_DB = −5.0` is set against the −23 target on
   the reel, not against a peak-density minute) or a density-driven duck of the near-field buses. I
   did not move the global trim off a stress scenario — that is a lead call, and it is **Request 6**.

## r6 — the credits name exactly what ships, file by file (reviews/audio-r6.md)

Provenance only: **no audio file changed this round.** `git status --short game/audio` after the
rebuild shows `CREDITS_AUDIO.md`, `audio_manifest.csv` and `music/clips.json` and nothing else — no
`.wav`, and the five OGG beds were restored from HEAD after their usual container-serial
re-encode (decoded against HEAD: max abs diff 0.0 on all five).

### The gate: `tools/sfx/run.sh credits_check.py`

Written and **committed first**, then run on the unfixed tree → `tmp/audio/r6_credits_head.txt`,
exit 1, 27 problems. It flagged exactly the three items the brief predicted:

```
file→credit: source “OpenGameArt CC0 music collection” has no CREDITS_AUDIO.md row (5 files)
credit→file: CREDITS row “OGA — Monster Sound Effects 2” is named by no shipped file
credit→file: status/audio.md pack row “OGA — Monster Sound Effects 2” is named by no shipped file
no_record:  “OGA — 100 CC0 SFX” (122 shipped files) has no licence record for …/100-cc0-sfx
no_record:  “OGA — 100 CC0 SFX #2” (118) …   no_record: “OGA — 202 More Sound Effects” (7) …
no_record:  “OGA — 50 CC0 Sci-Fi SFX” (17) … no_record: “OGA — 80 CC0 Creature SFX” (38) …
no_record:  “OGA — Swishes Sound Pack” (10) … no_record: “OGA — The Free Firearm Sound Library” (25) …
unused_pack: sources.PACKS “oga_monster2” (OGA — Monster Sound Effects 2) is layered by no shipped file
… plus the six CREDITS music rows and the six status music rows nothing named
files=300 rows=300 sources=13 unmatched file→credit=2 credit→file=15 no_record=7 bad_author=0 unused_pack=1
```

After the fixes → `tmp/audio/r6_credits.txt`, exit 0:

```
files=300 rows=300 sources=17 unmatched file→credit=0 credit→file=0 no_record=0 bad_author=0 unused_pack=0 used_for=0
```

The check lists every shipped file (file → manifest source(s) → CREDITS row(s) → licence), then
every credited pack and track with the files and ids that layer it, its record's path and that
record's licence and author. "Shipped" is read from `game/export_presets.cfg`'s `exclude_filter`:
300 files.

### Item by item

| # | HEAD re-check | Cause | Fix |
|---|---|---|---|
| 1 | `grep -c 'Monster Sound Effects 2' game/audio/audio_manifest.csv` → 0; `"huge"` only at `recorded.py:117`; `bank_common.py:204-205` never produces it. **Not fixed on HEAD.** | `recorded.creature_base` mapped role `huge` to `oga_monster2`, but the role map in `creature_voice` is `{chitter, growl, roar, screech, gurgle, wet}` — `huge` is unreachable, so the row and the `PACKS` entry were dead code. | The `Pack` and the table row are gone; `bank_enemies`' docstring now says the bank layers OGA — 80 CC0 Creature SFX for every archetype. Not layered in instead: that changes the boss's voice and judging it needs an ear. The `art/audio_src/oga_monster2/` download itself is left on disk — this round was told to touch no download. |
| 2 | "bart" in `CREDITS_AUDIO.md`, `sources.py` and 25 manifest rows. **Not fixed on HEAD.** | `oga_fetch.AUTHOR_RE` took the first `/users/<name>` link after the author field. The firearm page's author is plain text (`<span class='username'>Ben Jaszczak, et al.</span>`), so the first link is the "Submitted by bart" one. | The fetcher reads the author field's own text, records `submitted_by` separately and records the node's Attribution Instructions. Verified live: `author='Ben Jaszczak, et al.'`, `submitted_by='bart'`, `attribution='These sounds were created and recorded by Ben Jaszczak, Brian Nelson, Kevin Heras, and Matthew Nanney'`; on 100 CC0 SFX it still returns `rubberduck`. Credit is now the four recordists, in `sources.py` → 25 manifest rows → CREDITS. |
| 3 | `for d in art/audio_src/oga_*; do ls "$d" \| grep -c oga_sources.json; done` → only `oga_bossmetal`, `oga_kenney2`, `oga_music`. **Not fixed on HEAD.** | The sidecar was only written for the packs fetched through the tool; the rest were unpacked by hand from earlier downloads. | All seven recorded on **2026-11-05** with the fixed fetcher and **no `--get`** (no re-download); `oga_music`, `oga_bossmetal` and `oga_kenney2` re-recorded so every record carries its date. All say CC0. The status sentence now says which three were written at fetch time and which seven on 11-05. |
| 4 | `grep -n 'cc0-music-0' …` → 5 manifest rows + `build.py:32`. **Not fixed on HEAD.** | `MUSIC_PACKS` was keyed by *folder*, so five clips from one folder shared one source string pointing at a user's collection page, where no licence was read. | `music_tracks.track_credit(folder, file)` reads title / page / licence / author from the fetch records; `build.py` uses it, so all six rows name their track and its own node in one format. Titles are now the OGA node's own: "Boss Battle #2 [Symphonic Metal]", "Heroic Pressure (Loop)". |
| 5 | a dry `manifest_rows()` gave 0 of 240 SFX rows naming a pack. **Not fixed on HEAD.** | `row.packs` is only filled inside `render()`, and `--manifest-only` / `--only=<id>` render nothing or one id while still rewriting every row. | `manifest_rows()` calls `discover_packs()`, which renders any unrendered row (no file written) before reading its credits. |

**Item 5 gate.** Full build → `tmp/audio/r6_manifest_full.csv`; then `--manifest-only` and
`--only=rifle_fire`, each `cmp`-equal to the copy:

```
CMP OK (manifest-only == full)
CMP OK (only == full)
```

The old code, same two runs (`git checkout HEAD -- tools/sfx/build.py tools/sfx/registry.py`, then
restored):

```
OLD --manifest-only:   0 of 240 SFX rows name a pack
OLD --only=rifle_fire: 3 of 240 SFX rows name a pack
```

**The firearm record** — `art/audio_src/oga_firearm/oga_sources.json`:

```json
{"slug": "the-free-firearm-sound-library", "author": "Ben Jaszczak, et al.", "submitted_by": "bart",
 "attribution": "These sounds were created and recorded by Ben Jaszczak, Brian Nelson, Kevin Heras, and Matthew Nanney",
 "licences": ["CC0"], "page": "https://opengameart.org/content/the-free-firearm-sound-library",
 "recorded": "2026-11-05"}
```

### What else the round fixed in the same tools

- `oga_fetch.get()` retries 3× with backoff — one OGA page timed out during this round. Proved by
  a stub that fails twice then succeeds: 3 attempts, page fetched.
- A licence outside `CC0` / `CC-BY ` is now **refused** (exit 2, nothing recorded or downloaded)
  instead of printing "skipping" and carrying on. The trailing space matters: `CC-BY-SA 3.0` also
  starts with `CC-BY`. Tested: `CC0` and `CC-BY 4.0` → exit 0 and recorded; `CC-BY-SA 3.0` and
  `GPL 3.0` → exit 2, no sidecar.
- `credits_check.author_named` separates a record's **creators** (author field + Attribution
  Instructions) from its **submitter**, so crediting an uploader is now a failure. Patching
  `sources.py` back to `"bart"` gives
  `bad_author: “OGA — The Free Firearm Sound Library” credited to “bart”, which
  art/audio_src/oga_firearm/oga_sources.json does not name` (exit 1). On HEAD that patch exited 0.
- `check_used_for` holds the prose to the data: a CREDITS "Used for" cell must state the real id
  count and may only name ids that layer the pack. `CREDITS_AUDIO.md:25` used to claim 202 More
  Sound Effects served "weapon switch"; the check now lists it as 3 ids — `block`, `missile_launch`,
  `reload` — and the cell says so.
- Without `art/audio_src/` the check says `no art/audio_src/ — licence records unchecked`, exits 1
  with `no_record=15` and **no traceback** (proved by pointing `SRC_ROOT` at a path outside the
  repo).

### Negative tests (each patches one thing, runs, restores)

| patch | result |
|---|---|
| `sources.py` firearm author → `"bart"` | exit 1, `bad_author` |
| CREDITS "Used for" → `9 ids … \`weapon_switch\`` | exit 1, `used_for=2` (count and id) |
| delete the `saber_swing_2` manifest rows | exit 1, `file→credit` for both files + `used_for` for the swishes row |
| `SRC_ROOT` → a path outside the repo | exit 1, `no_record=15`, no crash |

### Unchanged, as required

`tools/godot.sh check --only=res://audio/` → `CHECK 23 files, 0 failed, 0 engine errors, 0 warnings`
`tools/godot.sh test res://audio/tests/test_audio.gd` → `TEST audio: PASS (0 failures)`

Every file touched is under 400 lines except `status/audio.md` (431, a document).

## r7 — the five new FEEL rows get sounds, and the beat-clock flake is root-caused (reviews/audio-r7.md)

Two unrelated-looking items, one shared lesson: **a sound that is wired nowhere fails silently.** The
five rows below shipped with a FEEL entry and a `.tres` but no bank row and no `FEEL_IDS` entry, so
the only symptom was one `WARNING: Audio: unknown or empty sound id '…'` line buried in another
unit's drive log. The flake was the same disease in the music director: the beat clock followed
whatever clip the interactive graph walked through instead of the clip the score asked for.

### The five rows

| FEEL row | sound | decision |
|---|---|---|
| `last_stand` | **new bank row** `last_stand` (2.1 s) | FEEL.md's sound column is "alarm + low sub". The row is a MASTER CAUTION pair a fifth **below** `alarm_warning` (440/330 Hz, 2 repeats) so the moment is its own alert and not a second copy of the damage alarm the row already layers through `cockpit_alarm`; under it a 55 → 22 Hz sub drop, both steam vents from the row's VFX column, the thruster burst, and a pitched-down armour groan. `FEEL_EXTRAS` adds `ai_armor_critical` — the cockpit line belongs on *this* frame, not on the next 0.25 s HP poll. Bus `Player`, C0, prio 96, 5 s interval (the row's own 60 s cooldown is the real limiter). |
| `boss_kill` | **new bank row** `boss_kill` (4.2 s) | **Layers with `kill_large`, does not replace it** — and that is the answer to the brief's question. `kill_large` already reaches this moment three ways (the row's own `fx/events/boss_kill.tres` audio column, `brood_titan.gd:285`'s direct `Audio.play`, and the router's `on_enemy_killed`), and its `cap 2 / 60 ms interval` collapses those to one impact; a fourth explosion crack in `boss_kill` would only stack. What the death lacked was everything **after** the impact, so that is what the row is: the titan's own roar stretched and falling, a 48 → 20 Hz sub under the 0.2× slow-mo, three body impacts walking up the collapse at 0.30 / 0.85 / 1.70 s, two debris layers, the city's slapback and the structure letting go. Bus `Impacts`, C4, prio 99, `far_delay` like the other big rows. |
| `gatling_vent_good` | `OVERRIDES` → `gatling_vent` | r16-lead-decisions. The good vent is the same steam release without the ring, so it reuses the plain hiss; the perfect vent keeps its own row (hiss + chime). |
| `gatling_overheat` | already in the bank | only the `FEEL_IDS` entry was missing. |
| `gatling_jam` | already in the bank | only the `FEEL_IDS` entry was missing. |
| `near_miss` | already in the bank and in `FEEL_IDS` | it *did* reach a sound — `enemies_near_miss` traced `near_miss=6` requests with 0 unknown ids. No change needed; recorded here because the brief asked. |

Plus FEEL.md's own sound column for both kill rows, which was never implemented: **"world −6 dB"**.
`AudioMixer.duck_world()` drops the World bus (the parent of Bed / Enemies / Player / Weapons /
Impacts, so Voice, UI, Cockpit and Music are untouched) for 0.5 s on `kill_large` and 1.2 s on
`boss_kill` — the length of its slow-mo — and returns in 400 ms. A duck already running keeps its baseline and is restarted; a finished one re-reads the bus, so
the user's sfx volume stays the floor. `test_audio.gd::_world_duck()` asserts all three
properties: the bus moves by exactly −6.0 dB, Voice / UI / Cockpit / Music do not move, and
World is back on its baseline afterwards.

### The regression test that stops this coming back

`test_audio.gd::_event_coverage()` now reads **docs/FEEL.md itself** through `FeelTable.ids()` (the
same parser the feel gallery and `test_feel_rows` use) and fails on any row that does not reach a
`SoundEvent`:

```
PASS all 49 FEEL ids resolve to a SoundEvent ([])
PASS all 49 docs/FEEL.md rows reach a sound (0 silent: [])
```

`FEEL_IDS` is a hand-kept copy, so a row the feel unit adds lands with no entry and no bank row and
nothing notices. This reads the lead's source of truth, so a new row cannot ship silent again. It was
written *after* the five rows were wired, so it is proved against the real table, not a fixture.

### The beat-clock flake — root cause

`FAIL the beat clock reaches the requested clip (110.0 BPM)` (`test_audio_clocks.gd:171`), 1 of 4
full table passes, 0 of 4 solo runs. **110.0 BPM is `clip_bpm(&"tension")`** — a clip
`_clip_for_intensity()` can never return, so it could only come from the stream-report path in
`_sync_to_stream()`.

**Two clocks, and only one of them can differ.** `probe_clock_drift.gd` settles tooling r1b's
hypothesis first: `AudioClock` (`Feel.real_now()`) and the physics-frame count that
`_settle_music()` counts are the **same clock**, to within 0.000 s, through stalls of 0 / 8 / 30 /
120 / 300 / 900 ms:

```
PROBE tps=120 max_physics_steps=8 max_fps=60
PROBE stall=   0ms  physics_frames= 240 (2.000 s)  real_now=2.000 s  wall=0.010 s  drift=-0.000 s
PROBE stall= 900ms  physics_frames= 240 (2.000 s)  real_now=2.000 s  wall=0.914 s  drift=-0.000 s
```

So the timeout and the wait cannot drift apart. The clock that *can* differ is the **wall clock** —
and that is the one the audio mixer runs on. An idle headless loop here runs ~24,000 frames/s
(`--fixed-fps 120` fixes the frame delta, it does not throttle), so `_settle_music()`'s 8 s of game
time is ~40 ms of wall time: the mixer never reaches the explore clip's 2.508 s bar, the stream never
reports a clip change, the `AudioClock` timeout always wins, and the suite is green. Under load the
same 8 s of game time takes **seconds** of wall time, the mixer reaches the bar — and then:

1. the stream enters `boss`, because `music_intensity(1.0)` queued it;
2. `_add_transitions()` had `any → boss` carrying **`auto_advance = true, next_clip = tension`**, so
   the graph immediately walks on to `tension`;
3. `_sync_to_stream()` polls `get_current_clip_index()`, sees 3, and — with `_timeout_target` still
   empty, because the 5.3 s `AudioClock` timeout has not fired yet — calls `_adopt_clip(&"tension")`;
4. `playing_clip = tension`, `_metro_bpm = 110.0` → **the reported failure, exactly**.

Reproduced deterministically with `probe_boss_switch.gd` (4 ms of wall time bought per frame, 960
frames = 5.5 s of wall time inside the same 8 s of game time — the ratio a loaded machine has):

```
OLD (HEAD)  PROBE wall=5.69s game=8.01s stream_idx=3(tension) adopt=tension want=boss bpm=110.0
NEW         PROBE wall=5.49s game=8.01s stream_idx=2(boss)    adopt=boss    want=boss bpm=145.6
```

### The two fixes

**1. The beat clock follows the SCORE, not the graph.** `music_director.gd` now latches
`_want_clip` — the clip `switch_to()` was last asked for — and `_sync_to_stream()` adopts **only**
that, whether the handover comes from the stream reporting it or from the `AudioClock` timeout.
Anything else the graph walks through (a filler riser, an auto-advance hop) is not the score and can
never move the metronome. `_pending_clip` / `_timeout_target` are gone; `_switch_pending` +
`_pending_since` replace them.

**2. The graph no longer walks off the boss clip.** `any → boss` carried
`auto_advance = true, auto_advance_next_clip = tension`, i.e. the score left the boss theme the
instant it entered it. The dossier's table (§6.2 line 491) wants a **2-bar `tension` riser as the
filler** under that switch; Godot's `add_transition()` has no filler parameter, and the sourced
`tension` track is a full 65 s bed, so using it as the filler would play a minute of it before the
boss. The transition now enters `boss` at its head over a 1-beat fade of the source and lets the clip
loop (every clip OGG is `loop = true`).

### A second order-dependence the same probe found

`probe_music_clock.gd` (the first version, which replayed `test_audio.gd`'s own order) showed this:

```
PROBE music_intensity(0.2)  adopt=explore want=combat  bpm=95.7 heat=0.599 target=0.20 pend=combat
```

`Audio.music_intensity(0.2)` left the score on **combat**, because `_decay_combat_heat()` re-asserts
`music.set_intensity(maxf(_intensity_target, _combat_heat))` every frame and combat heat decays at
only 0.08/s — a single `add_heat(1.0)` from a boss intro held the score at boss for 12 s *over* a
later explicit request. That is a CONTRACTS §3 violation (the flow unit drives the score from the
encounter state) and a real order-dependence: `test_audio.gd::_music()`'s
`_check(music.clip == &"explore", "intensity 0.2 -> explore")` only passed because heat happened to
have decayed below 0.45 by then. `music_intensity()` now clamps the residual heat to the level just
asked for, so an explicit request is authoritative; `add_heat()` still lifts the score between flow
updates, which is what it is for.

### Gate results

| gate | result |
|---|---|
| `tools/godot.sh check --only=res://audio/` | `CHECK 26 files, 0 failed, 0 engine errors, 0 warnings` |
| `test_audio` | `TEST audio: PASS (0 failures)`, `TEST ERRORS 0` |
| `test_audio_clocks` ×20 back-to-back | **20/20 `PASS (0 failures)`**, and all 20 report `145.6 BPM on boss … stream on clip 2` — i.e. the mixer really did walk the graph in every run and the beat clock stayed put |
| `test_audio_call_sites` | `TEST audio call sites: PASS (0 failures)` |
| `test_audio_enemies` | `TEST audio enemies: PASS (0 failures)` |
| `test_feel_rows -- --audio-trace` | `TEST 13 checks, 0 failed`, and the `WARNING: Audio: unknown or empty sound id 'gatling_vent_good'` line that used to be line 5 of its log is **gone** |
| `tools/sfx/run.sh credits_check.py` | `files=302 rows=302 sources=17 unmatched file→credit=0 credit→file=0 no_record=0 bad_author=0 unused_pack=0 used_for=0` |
| `tools/sfx/run.sh measure.py` | `242 files, 316.1 s`, `over -0.9 dBTP: 0`, `loop seams>0.05: 0` (the 7 pre-existing click flags are unchanged) |
| **`tools/suites.sh --jobs=1` — the whole 92-row table, in order** | **`SUITES 92 rows, 90 green, 2 known, 0 red`** (exit 0). The two known are other units' allow-lists (`art_design_copy` map-r8-unbuilt, `art_occlusion` test-occlusion-stale-premise); all five audio rows and `weapons_feel_rows` are `ok` |
| `tools/suites.sh --only=weapons_feel_rows,hud,audio,audio_clocks,audio_call_sites,audio_enemies` (the audio block in full-run order) | `SUITES 6 rows, 6 green, 0 known, 0 red` |
| `tools/suites.sh --list` | `coverage: every tracked test has a row` — the two `probe_*.gd` files are correctly not counted |
| `grep -c "unknown or empty sound id" tmp/suites/*.log` | **0 in every suite log of the full pass** |

New checks this round, all green: `the kill duck drops World by -6 dB (0.0 -> -6.0)`, `the duck
leaves Voice / UI / Cockpit / Music alone ([])`, `World is back on its baseline after the duck`,
`all 49 docs/FEEL.md rows reach a sound (0 silent: [])`, `the beat clock stays on the requested clip
while the mixer walks the graph`. `test_audio` is now 115 checks.

### Listening pass — `tmp/audio/reel_r7_new.wav` (31.1 s, stereo 44.1 kHz, rendered to a file)

`tools/godot.sh movie` needs a window, and the house rules keep windows off the user's machine, so
the reel is built straight from the shipped PCM by `tools/sfx/reel.py`: each slot is one moment
(a single id, or the ids that really do sound together), separated by 0.6 s and preceded by a short
marker tone. Nothing is re-synthesised — it is the exact bank, laid out in order.

| slot | length | peak | RMS |
|---|---|---|---|
| `last_stand` | 2.10 s | −2.01 dBFS | −20.63 dBFS |
| `last_stand + alarm_warning + ai_armor_critical` (−6 dB) — the moment as the game plays it | 3.20 s | −4.49 | −18.77 |
| `boss_kill` | 4.20 s | −3.05 | −21.39 |
| `boss_kill + kill_large_01 + kill_confirm + boss_roar + stinger_kill_large` (−3 dB) — the full boss death | 4.20 s | −1.26 | −21.19 |
| `gatling_vent` (now also `gatling_vent_good`) | 0.45 s | −6.01 | −23.60 |
| `gatling_vent_perfect` | 0.90 s | −4.27 | −16.17 |
| `gatling_overheat` | 1.80 s | −4.01 | −24.96 |
| `gatling_jam` | 1.40 s | −4.01 | −20.30 |
| `near_miss_01` | 0.40 s | −6.01 | −23.26 |

Whole reel: **−16.3 LUFS-I, LRA 12.2 LU, true peak −0.9 dBFS** (it is normalised to −1 dBFS by the
tool, so the reel's own peak says nothing about the game — the per-slot peaks above do).

**What the numbers say, and what I changed after reading them.**

1. **Band balance is in family, both new sounds.** `boss_kill` measures 11.8 dB of tilt with its
   20–80 Hz band leading (the sub drop is the point) and 4–16 kHz only 11.8 dB under it;
   `last_stand` measures 13.8 dB with 250 Hz–1 kHz leading and 4–16 kHz at −39.6. For comparison
   `kill_large_01` is 1.9 dB and the r1 pass's failure cases were 27–39 dB. Neither new sound is the
   dark part of the mix.
2. **`boss_kill` peaked at −1.0 dBTP and I pulled it to −3.0.** It *always* layers with `kill_large`
   (−1.5), and the worst-case five-id stack summed to **+1.74 dBFS raw** — the Master hard limiter
   would have been doing the mixing. At −3.0 the row is still 5.5 dB louder in RMS than `kill_large`,
   which is what a climax should be, and the stack now peaks at **−3.3 dBFS at the Master input**
   after `MASTER_TRIM_DB = −5`, clear of the −1 dB limiter. (That figure is pessimistic: the reel sums
   the five ids on one bus, while in play `kill_confirm` is on UI and `stinger_kill_large` on
   Stinger→Music, so they never share a bus.)
3. **Both files had silent tails and I trimmed them.** `boss_kill` was 5.2 s with its last 1.3 s
   digital silence and `last_stand` 2.6 s with 0.7 s: a C4 world voice held for nothing. Now 4.2 s
   and 2.1 s, each ending within 0.15 s of its last layer.
4. **The envelopes say the design is actually there** (`tools/sfx/run.sh envelope.py`, 0.1 s windows).
   `boss_kill`: −14.6 dB opening (cry + sub), a clear **−11.3 dB spike at 0.30 s** (first body
   impact), **−15.4 at 0.90 s** (second), a long debris decay, **−17.8 at 1.70 s** (third), **−26.8
   at 2.30 s** (the settling debris) and the tail running out to −95 by 3.9 s — five distinct events,
   not one block. `last_stand`: −12.8 dB at the hit, the first alarm pair decaying to −30 by 0.7 s,
   the **second pair swelling back to −19.2 at 1.0 s**, then out by 1.7 s.

**Captures needed** (the lead runs these in a window the user approves — nothing below has been run):

```
tools/godot.sh movie --movie=$PWD/captures/audio_r7_boss.avi \
    --timeline=res://audio/tests/timeline_reel.json --scene=res://main.tscn --sandbox --skip-menu
tools/godot.sh drive --timeline=res://audio/tests/timeline_fight_r5.json --scene=res://main.tscn \
    --sandbox --skip-menu --enemies=juggernaut:1,mantis:2,ripper:5,spitter:1,harrier:1 \
    --audio-trace --nan-watch
```

### The skate trail scrape — deliberately NOT added

The brief made it optional "only if it fits the mix budget". It does not, and the moment it names is
already covered:

1. **The loop budget is already saturated.** `AudioVoicePool.LOOP_VOICES = 6`, and at steady state
   the game wants more than that: `amb_tunnel_hum`, `amb_street`, `amb_wind_high`,
   `distant_battle_bed` and `heartbeat_loop` are five of the six, leaving **one** slot for whichever of
   `boost_slide_loop` / `flight_loop` / `overdrive_loop` / `saber_hum_loop` / `ward_up_loop` /
   `undertow_loop` / `gatling_fire_loop` / `hover_loop` / `missile_flight` / `spire_pulse_loop` /
   `neon_buzz` is live. `test_audio` already prints
   `WARNING: AudioVoicePool: no loop voice free for 'spire_pulse_loop'`. A seventh permanent loop
   would evict a bed.
2. **The 42 m/s ground skate already scrapes.** That state is the `slide` boost, and
   `boost_slide_loop` is rendered by `C.thruster_loop(seed, 2.0, 0.9, scrape=0.9)` — the ground-grit
   layer is *inside* the thruster loop, by design.
3. **The remaining gap has no hook.** A ground `dash_f` slide and a floor-skimming `assault` boost
   would need audio to duck-type the player (`move_state` / `is_grounded` / `velocity`) every physics
   tick, duplicating `FxSkateTrail.wants()` — logic the feel unit owns, in a file audio does not.

→ **Request 9** below, if the lead wants the dash/assault scrape.


## In progress / next

- A human listening pass is the one thing this environment cannot do. The captures are analysed,
  not heard. Timbre judgements — does the saber read as metal, is the HUSK wet enough, do the six
  music tracks sit together across a crossfade — need an ear.
- If the score needs more bite: the six tracks all measure ~15 dB of band tilt. A per-clip shelf in
  `music_tracks.py` would fix it; I did not add one unasked, because EQ-ing sourced music to match
  synthesis is the wrong default.
- **r7's `boss_kill` and `last_stand` have never been heard inside a mix.** The reel is the bank on
  its own; the two commands are under "Captures needed" in the r7 section. In particular the
  five-id boss-death stack sums to +1.7 dBFS raw (−3.3 after `MASTER_TRIM_DB`), which is under the
  Master limiter but is the loudest moment in the game by a distance — worth an ear.

## How to verify (exact commands)
```
tools/sfx/run.sh credits_check.py                          # the credit gate: exit 0, all zeros
tools/sfx/run.sh build.py                                  # 242-file bank + manifest (~7 s)
tools/sfx/run.sh music_tracks.py                           # 6 adaptive clips + clips.json
tools/sfx/run.sh music.py                                  # stingers + silent beat clock
tools/sfx/run.sh voice.py                                  # cockpit AI lines (ys-api; cached raw)
tools/sfx/run.sh analyse_music.py                          # tempo/key of the sourced tracks
tools/sfx/run.sh measure.py --csv tmp/audio/bank_qa_r5.csv # per-file peak/RMS/seam QA
tools/sfx/run.sh reel.py tmp/audio/reel.wav <id> [<id>…]    # lay ids out into one listenable file
tools/sfx/run.sh bands.py <id> [<id>…]                      # 20-80/80-250/250-1k/1-4k/4-16k + tilt
tools/sfx/run.sh envelope.py <id>[,<id>…] [window_s]        # RMS envelope, the shape over time
tools/sfx/run.sh measure_movie.py $PWD/captures/audio_reel_r4.avi --window=2.0

tools/godot.sh check --only=res://audio/                   # CHECK 25 files, 0 failed, 0 errors, 0 warnings
tools/godot.sh test res://audio/tests/test_audio.gd        # TEST audio: PASS (0 failures)
tools/godot.sh test res://audio/tests/test_audio_clocks.gd # TEST audio clocks: PASS (0 failures)
tools/godot.sh test res://audio/tests/test_audio_call_sites.gd  # 114 call sites, 0 unresolved
tools/godot.sh test res://audio/tests/test_audio_enemies.gd     # TEST audio enemies: PASS (0 failures)
tools/godot.sh test res://enemies/tests/test_ai.gd         # AI TEST 12 checks, 0 failures
tools/suites.sh --only=audio,audio_clocks,audio_call_sites,audio_enemies,weapons_feel_rows
                                                          # SUITES 5 rows, 5 green, 0 known, 0 red

# --audio-trace: every id that resolved and asked the pool for a voice, printed at shutdown. The
# three commands below are how the r7 rows were proved to reach a sound in a REAL suite.
tools/godot.sh test res://player/mech/tests/test_damage.gd -- --audio-trace --timeout=600
                                                          # AUDIOTRACE ... last_stand=3 ...
tools/godot.sh test res://fx/tests/test_boss_kill.gd -- --audio-trace
                                                          # AUDIOTRACE ... boss_kill=1 kill_large=2 ...
tools/godot.sh test res://enemies/tests/test_near_miss.gd -- --audio-trace --timeout=300
                                                          # AUDIOTRACE ... near_miss=6

# 30 s fight with every archetype on: 0 errors, 0 warnings, 0 unknown sound ids
tools/godot.sh drive --timeline=res://audio/tests/timeline_fight_r5.json --scene=res://main.tscn \
    --sandbox --skip-menu --enemies=juggernaut:1,mantis:2,ripper:5,spitter:1,harrier:1 \
    --audio-trace --nan-watch
tools/godot.sh movie --movie=$PWD/captures/audio_fight_r5.avi \
    --timeline=res://audio/tests/timeline_fight_r5.json --scene=res://main.tscn --sandbox \
    --skip-menu --enemies=juggernaut:1,mantis:2,ripper:5,spitter:1,harrier:1
tools/godot.sh drive --timeline=res://audio/tests/timeline_reel.json --scene=res://main.tscn \
    --sandbox --skip-menu --nan-watch                       # DRIVE done t=88.0 errors=0 warnings=0, no NANWATCH
tools/godot.sh movie --movie=$PWD/captures/audio_reel_r4.avi \
    --timeline=res://audio/tests/timeline_reel.json --scene=res://main.tscn --sandbox --skip-menu
```

## Evidence
- `tmp/audio/r6_credits.txt` — the credit gate after the fixes: exit 0, every counter 0
- `tmp/audio/r6_credits_head.txt` — the same gate on the unfixed tree: exit 1, 27 problems
- `tmp/audio/r6_manifest_full.csv` — the manifest a full build writes, `cmp`-ed against the one
  `--manifest-only` and `--only=rifle_fire` write (item 5)
- `game/audio/audio_manifest.csv` — 300 rows (240 SFX + 13 music + 47 voice); 160 of the 240 SFX
  files list one or more recorded packs alongside the synthesis, the other 80 are pure synthesis
  (UI, alarms, beams, charges, servos, subs, whooshes — exactly rule 11's list)
- `game/audio/CREDITS_AUDIO.md` — every pack, author, licence and OGA URL, plus the required
  AI-audio label for the voice lines
- `game/audio/music/clips.json` — per-clip bpm / bar count / source track / author
- `tmp/audio/bank_qa_r5.csv` — per-file peak/RMS/true-peak/loop-seam/centroid report
- `captures/audio_reel.avi`, `captures/audio_reel_r4.avi` — 88 s listening reels with audio
  (git-ignored); r4 is the post-audit-fix capture
- `captures/audio_fight_r5.avi` — 30.7 s, stereo 48 kHz, 10 enemies, the r5 listening pass
- `tools/godot.sh test res://audio/tests/test_audio.gd` — PASS, 0 failures (110 checks, including
  the clock, call-site and enemy-routing sub-suites)
- `tools/godot.sh test res://audio/tests/test_audio_clocks.gd` — PASS, 0 failures (17 checks)
- `tools/godot.sh test res://audio/tests/test_audio_call_sites.gd` — PASS, 114 call sites scanned
- `tools/godot.sh test res://audio/tests/test_audio_enemies.gd` — PASS, 0 failures (6 checks)
- `tmp/audio/reg/` — the five source files as fixed; each regression was proved by patching one back
  to its wall-clock form and re-running the clock suite (all five produced FAIL lines)
- `tmp/audio/reel_r7_new.wav` — the r7 listening reel, 31.1 s stereo 44.1 kHz, rendered from the
  shipped bank by `tools/sfx/reel.py` (no window). −16.3 LUFS-I, LRA 12.2 LU
- `tmp/audio/r7_clocks_20.txt` — 20 back-to-back `test_audio_clocks` runs: 20 × `PASS (0 failures)`,
  20 × `145.6 BPM on boss … stream on clip 2`
- `tmp/audio/r7_measure.csv` — the bank QA report for this round (242 files, 0 over −0.9 dBTP)
- `game/audio/tests/probe_clock_drift.gd`, `probe_boss_switch.gd` — the two probes that root-caused
  the beat-clock flake. They are `probe_*.gd`, not `test_*.gd`, so `tools/suites.sh`'s coverage check
  ignores them. `probe_clock_drift.gd` proves AudioClock and the frame count are one clock;
  `probe_boss_switch.gd` is the deterministic reproduction (old director → `tension` / 110.0 BPM,
  new → `boss` / 145.6)
- `tools/sfx/reel.py`, `tools/sfx/bands.py`, `tools/sfx/envelope.py` — three new bank-QA tools, all
  runnable as `tools/sfx/run.sh <name>.py …`: lay a set of ids out into one listenable file, print the
  r1 listening-pass band balance of a file, and print its RMS envelope

## Tuning choices (numbers the docs did not fix)
- Recorded layers are peak-normalised after shaping (`sources.norm`), so a composite's layer gains
  mean the same thing whether the layer is a recording or a synthesis.
- `recorded.clank` pitches down 7 st per doubling of `size`, `slam` 9 st — the 16 m hero needs the
  source objects to read an octave lower than they were recorded.
- Creature bases are pitched per role through `recipes.creature` (−2 to −19 st), so one recorded
  roar serves Ripper, Brood and Titan at three scales.
- Music clips are loudness-matched to −20 LUFS-I / −1.5 dBTP; the Music bus trim puts them under
  the −23 LUFS mix target.
- Loop crossfades are 2 bars of equal power, so a clip's own reverb tail wraps into its head.
- `MASTER_TRIM_DB = −5.0` still calibrates the mix; the reel reads −21.6 LUFS-I against the −23
  target, which is within tolerance for a reel that is mostly near-field hero sound. A 30 s
  10-enemy brawl reads −16.7 with LRA 2.5 LU (see r5); the trim is calibrated on the reel, not on
  peak density.
- `kill_large` and `stagger_enemy` carry a 60 ms `interval_ms` purely to collapse the double-fire
  from `EnemyBase` (Events signal *and* `Feel.play`), not as a rate limit on gameplay.
- `harrier_death` sits at priority 58 on the Enemies bus, below the 80 the telegraphs carry: a death
  cry is feedback, a tell is information.

## Known issues
- **The captures were analysed, not heard.** No listening is possible in this environment. Every
  number above is an objective measurement; none of it proves the saber *sounds* like metal.
- **A peak-density fight has no dynamic headroom left** (LRA 2.5 LU at −16.7 LUFS-I over 30 s with
  10 enemies). Measured, root-caused to content density rather than any one row, and left alone —
  see r5 §3 and Request 6.
- `juggernaut_plate_break` is proved by `test_audio.gd`'s `_enemy_ids_sound()` rather than by a
  capture: the drive timeline can only press inputs, and in 60 s of scripted fighting the mech never
  landed 900 damage on a plate hurtbox. The slam from the same call-site shape does appear
  (`jugg_slam=3`).
- `captures/audio_reel.avi` logs `FlowDropIn: no landing after 30 s, continuing` — a flow-unit
  warning, not audio; `drive` reports 0 errors.
- The 7 files `measure.py` flags as "clicks" carry a designed transient (recipe R1's 1.5 ms tick);
  the metric is informational, not fatal.
- The reel cannot show a Brood Titan / Juggernaut roar-and-slam on demand: the timeline can only
  press inputs and call `player.debug_teleport`, so which HUSK types appear depends on the sandbox
  wave table. `titan_roar`, `jugg_slam` and `ripper_step` all exist in the bank and are wired
  to enemy events; they are not guaranteed to be in this particular 88 s. The r5 fight timeline
  (`--enemies=…`) does pin the roster.
- The six music tracks are from six different authors and three keys (C, D, E/F). Crossfades are
  bar-synced and 1–2 s, but adjacent clips will not share a key. That was the trade the brief
  allowed for real music; if it reads as jarring in play, the fix is to pick a second combat track
  in C from the same collection.
- Voice lines are one AI voice (`female-shaonv`, calm, robotic); no per-emotion variants yet.
- **(r7) The boss-death stack is the loudest moment in the game and has not been heard in a mix.**
  See "Captures needed" in the r7 section. The numbers are inside the limiter; the judgement is not.
- **(r7) `boss_kill` fires under 0.2× slow-mo for 1.2 s and Godot does not pitch-shift audio with
  `Engine.time_scale`.** The 4.2 s row therefore plays at normal speed while the picture crawls. That
  is true of every long sound in the game (`kill_large`, `collapse`, `spire_destroyed`); it is noted
  here because the boss death is the most extreme case.
- **(r7) The two probes are still on disk** (`game/audio/tests/probe_*.gd`). They are excluded from
  the suite table by name, but they are diagnostic scaffolding, not tests. Delete them once the lead
  has read the r7 section, or keep `probe_boss_switch.gd` as the reproduction recipe.

## Requests (to the lead / other units)
1. **A human listening pass on `captures/audio_reel_r4.avi` and `captures/audio_fight_r5.avi`.**
   Everything above is measured, not heard. In particular: (a) do the six music tracks sit together
   across the explore→combat crossfade, (b) is the gatling's bite right now or still soft, (c) is
   the HUSK wet/chitinous enough or just animal, (d) do the archetype telegraph tells read as
   *distinct* from each other now that all six actually fire.
2. ~~Settings keys `voice_volume_db` / `ui_volume_db`~~ — **closed**, they exist in
   `core/settings.gd` DEFAULTS now.
3. **Settings menu**: voice and UI volume sliders are missing (hud unit).
4. ~~**Credits screen** should read `game/audio/audio_manifest.csv` and show the AI-audio label from
   `game/audio/CREDITS_AUDIO.md`~~ — **closed in r6**: hud's page already reads the manifest
   (`game/ui/menus/credits_data.gd:98-121`). What is still open is the string list in Request 8.
5. **Anyone adding a `Feel.play(&"new_id")` or `Audio.play(&"new_id")`**: either add a row in
   `game/audio/tables/` or send the id. `Audio` warns once per unknown id, and
   `audio/tests/test_audio_call_sites.gd` now fails the suite on any literal id the bank cannot
   answer — but it only sees *literals*, so an id passed through a variable still needs a human.
6. **Master calibration at peak density** (lead call): `MASTER_TRIM_DB = −5.0` is set so the 88 s
   reel reads −21.7 LUFS-I. A 30 s ten-enemy brawl reads −16.7 with LRA 2.5 LU — loud, and flat
   enough that no payoff stands out. Options: (a) accept it, since a real fight is rarely 10 enemies
   at once for 30 s; (b) drop the trim ~3 dB and re-calibrate the reel upward elsewhere; (c) duck the
   near-field Player/Cockpit buses on combat density (`Audio.add_combat_heat` already tracks it).
   I measured (b) and (c)'s cheap proxy and did not ship either unasked.
7. **`enemy_type` is the contract** — if the enemies unit ever renames `@export var enemy_type` on
   `EnemyBase`, the whole per-archetype sound layer goes silent again. The router keeps
   `type_id`/`archetype`/`type` as fallbacks and `test_audio.gd::_enemy_routing()` fails loudly.
8. **hud r6 — the exact final credit strings to copy into `credits_data.gd`.** These are what
   `audio_manifest.csv` now carries; hud's `PACKS` (`:12-23`) and `OTHER` (`:37-42`) key on them and
   warn on each one it does not know (`:72-76`).

   **`PACKS` — one row dropped, one author changed, one spelling changed:**

   | manifest `source` | manifest `author` |
   |---|---|
   | `OGA — The Free Firearm Sound Library` | `Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (submitted to OGA by bart)` |
   | `OGA — 202 More Sound Effects` | `OwlishMedia` (was `owlishmedia`) |
   | `OGA — Monster Sound Effects 2` | **remove this row** — no shipped file layers it |

   The other six pack rows are unchanged.

   **`OTHER` — the six music keys are renamed from the collection to the track.** Each clip row's
   `source` is now the track title and its `source_url` the track's own OGA node:

   | clip | manifest `source` (= `source_url` target) | manifest `author` |
   |---|---|---|
   | `explore_mix` | `Covert Operations` → `https://opengameart.org/content/covert-operations` | `artisticdude` |
   | `tension_mix` | `Technological Menace` → `https://opengameart.org/content/technological-menace` | `Umplix` |
   | `combat_mix` | `Epic Combat` → `https://opengameart.org/content/epic-combat` | `Chester01` |
   | `boss_mix` | `Boss Battle #2 [Symphonic Metal]` → `https://opengameart.org/content/boss-battle-2-symphonic-metal` | `nene` |
   | `spire_cleared_mix` | `Heroic Pressure (Loop)` → `https://opengameart.org/content/heroic-pressure-loop` | `StarNinjas` |
   | `victory_mix` | `Forgotten Victory` → `https://opengameart.org/content/forgotten-victory` | `yd` |

   The string `OpenGameArt CC0 music collection` and the URL `…/content/cc0-music-0` no longer
   appear anywhere and should be dropped. `tools/sfx/run.sh credits_check.py` fails if the page and
   the manifest ever disagree again, so copying these once is enough.
9. ~~**Logged, not this round** — `last_stand`, `boss_kill` and the three gatling vent rows had no
   sound~~ — **closed in r7**: all five are wired (`last_stand` and `boss_kill` are new bank rows,
   `gatling_vent_good` overrides onto `gatling_vent`, `gatling_overheat` / `gatling_jam` already had
   rows), and `test_audio.gd` now reads docs/FEEL.md itself so the next row cannot land silent. What
   is still logged from that item is skills r4's `timeline_reel.json` t=46 `rift_step` blink.

10. **(lead / feel) The skate scrape, if you want it.** Audio will not add a 7th loop voice on its own
   (see the r7 section: `LOOP_VOICES = 6` is already saturated and the 42 m/s `slide` skate already
   carries a ground-grit layer inside `boost_slide_loop`). To get the *dash* and floor-skimming
   *assault* scrapes, two things are needed and neither is audio's:
   - a hook. Cheapest is for `FxSkateTrail` (feel's file, `fx/vfx/skate_trail.gd`) to emit when
     `wants()` flips — it already computes exactly the predicate — as an `Events` signal or a
     `Feel.play(&"skate_scrape_start" / &"skate_scrape_stop")` pair. Audio then wires it like any
     other row.
   - budget: `AudioVoicePool.LOOP_VOICES` 6 → 7, or the scrape has to share the boost slot.
   The bank row itself is 20 minutes of work once those exist.
11. **(tooling) `audio` / `audio_clocks` flake — closed, please drop Request 18.** Root cause,
    a deterministic reproduction and the fix are in the r7 section above; the regression check is
    `test_audio_clocks.gd::_metronome_ignores_graph_hops()`, which prints `FAIL … 110.0 BPM on
    tension` against the old director and `PASS … 145.6 BPM on boss` against the new one. 20
    back-to-back runs are green.
