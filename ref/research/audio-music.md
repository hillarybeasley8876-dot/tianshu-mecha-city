# Audio for 天枢 TIANSHU (Mecha City): mech sound design, legal sourcing, adaptive music, Godot 4.7 mixing. Research dossier v1

Project: mecha-city demo (Godot 4.7.2, Forward+, Metal, M1 Max). Research key: `audio-music`. Date: 2026-11-01.
Audience: the lead designer (Claude Opus), who turns this into the brief for the `audio` unit (owns `game/audio/**`; public API per CONTRACTS §3: `Audio.play(id, at, volume_db, pitch)`, `music_intensity(0..1)`, `stinger(id)`).

Conventions
- `[Xn]` = source; URLs in §9. **(estimate)** = my recommendation or derivation, not a sourced fact. In big tables a header note says which columns are estimates.
- **Verified 4.7.2** = checked on the local `godot 4.7.2.stable.official` binary (ClassDB dump plus headless probes) or in the `4.7.2-stable` source. Scratch evidence: `tmp/research/audio-music/` (`probe/classdb_dump.txt`, `godot_test/*.gd`, `scripts/synth_probe.py`).
- Scale (SPEC §2): hero 16 m, camera 26 m behind, map 1.6 × 1.6 km, layers −40 to +300 m, spire 600 m. 1 f = 16.7 ms.
- Layer codes follow FEEL.md: T transient, B body, S sub, M mechanical, Tl tail, D debris, UI.
- Images in `ref/images/audio-music/`: six spectrograms of the prototype recipes (§4) and three editor screenshots from Godot PR #64488 (clip list, transition table, synchronized stream) [G11].

---

## 0. Twelve rules (read this if nothing else)

1. **Sell mass with machinery, not loudness.** Every hero action gets metal, mechanism and servo layers, Titanfall 2's three Titan pillars [A1]. Borrow heavy industry: AC6 recorded machines and steel in an ironworks [A3]; Pacific Rim based its Jaegers on carriers and destroyers [A4].
2. **Layer, then route layers separately**: T/B/S/M/Tl/D (Kilborn's five plus debris [A9]). Give every sub layer a 90–250 Hz harmonic so laptops hear it (estimate; R1 uses tanh drive).
3. **Build big sounds at runtime from parts.** Battlefield 4 builds explosions from crack, body, environment reflections and debris; near = sharp, far = rolling thunder, city = slapback [A7]. Ship near/mid/far variants and delay the far layer by d/343 s.
4. **One sonic signature per machine/creature class.** Transformers: Optimus = air, Bumblebee = buzz; good = smooth/warm, bad = hissy/sharp [A5]. Ours (estimate): hero = clean turbine + bell-metal; HUSK = wet chitin + insect clicks + pitched animal.
5. **Own mech = near-field C0 on hero sockets; world = 3D**, heard by an `AudioListener3D` at the chest with camera orientation (panning from camera, attenuation from character [A22]; §5.5).
6. **Eight distance classes with a `max_distance` fade, computed with Godot's own formula** (§5.4). Doppler only on flyby sources, never on the listener.
7. **Duck the bed, never the payoff.** Music/Bed/Enemies are sidechained to Impacts and Voice. A key bus needs a higher index than the bus it ducks (verified mix order [G4]). Godot's compressor gives about 2× textbook gain reduction (measured, §5.2).
8. **Budget voices yourself** (estimate): 40 world + 12 near-field + 24 polyphonic 2D, per-event caps and min intervals, lowest priority stolen. Godot's `max_polyphony` just stops the oldest [G6].
9. **Music = one top-level `AudioStreamInteractive` whose clips are `AudioStreamSynchronized` stem sets** ("Elias style" [G11]). Never nest an Interactive [G12]. Stems must be OGG/MP3 with `bpm`/`beat_count`/`bar_beats`, or bar sync falls back to seconds [G2]. Verified 4.7.2 (§6.3).
10. **Sourcing: CC0, then CC-BY.** "Royalty-free, no redistribution" libraries never go raw into the public repo. CC0: Kenney (8 packs), OGA (incl. the 194 MB Free Firearm Library), Freesound CC0, Tallbeard loops. Sonniss/Pixabay/Adobe only inside composites. BBC RemArc is out.
11. **Synthesize what synthesizes well**: UI, alarms, beams, charges, servo, saber, sub, whooshes. Eleven numpy recipes render in 0.6 s (§4). Record or borrow metal, debris and creature bases.
12. **MiniMax**: `speech-2.8-hd` with `voice_modify.sound_effects = "robotic"` or `"lofi_telephone"` for the cockpit AI [C3]. The music API is closed to new users since 2026-08-20 [C1]; open MiniMax-Music3 needs CUDA [C5]; internal YS-API has `/minimax_tts` and `/suno` [C7]. Label AI audio in credits [C5][C6].

---

## 1. How mech games sound heavy

### 1.1 What the references actually do

| Reference | Technique (sourced) | Adopt for TIANSHU (estimate) |
|---|---|---|
| Titanfall 2 [A1][A2] | Titan palette = metal, mechanisms, servos [A1]. Self-recorded metal-on-metal; servo sounds from an Arduino-driven servo, pitched down; contact-mic recordings of forklifts and factory machines for "chassis resonance"; procedural mix weighted by speed, angle, distance and health; occlusion = attenuation + filtering [A2] | M layer on every locomotion and combat event: pitched-down small servo + hydraulic + chassis rattle. Servo pitch follows joint speed |
| Armored Core VI [A3] | Sound director Kota Hoshino: SFX recorded "at an ironworks, using machines and steel"; outside studio INSPION recorded part of the material | First search the "factory/ironworks/contact mic" categories; Freesound CC0 packs *Electromechanical*, *Contact Microphone*, *Sounds of the Machine* [B3] |
| Pacific Rim (Scott Gershin) [A4] | Jaegers based on aircraft carriers and destroyers ("not too sci-fi"); Kaiju voices from elephants, tigers, lions and raccoons, processed; dropped huge cargo containers for impacts; "Silence, if used correctly, is the most powerful sound we have" | Hero footstep body = container or large-metal slam. HUSK voices from animal bases. Before the boss roar: 2 bars of music drop-out and Bed −12 dB |
| Transformers (Erik Aadahl) [A5] | One signature per robot; good = smooth/warm, bad = hissy/sharp. Transformations = multi-beat rhythm with rising/falling pitch. Blackout: slowed UPS buzz through EQ'd delay, scanner servo with pitch acceleration, ice crunches recorded at 192 kHz slowed to ~20 % and cut to a tempo, shotgun cocks for "locking". Devastator steps = dryer-door slams. "Small sounds can be manipulated to sound bigger than big sounds." Predubs: robot mechanics, motors, footsteps, surface textures, weapons, breaths/vocals | §3 categories mirror these predubs. Overdrive ignite / wing deploy = 5-beat servo + lock rhythm on the music grid. Armor break = slowed ice/glass crunch + gun-cock |
| Star Wars lightsaber (Ben Burtt) [A6] | Idle hum of two interlocked projector motors beating against each other, plus the buzz induced when a mic passed behind a TV picture tube, mixed 50/50; movement made by waving a mic past a speaker (Doppler) | Dawn Edge saber hum = recipe R5 (two detuned motors + 120 Hz buzz). Swing = pitch/volume modulation from blade angular speed |
| Battlefield 4 / DICE (Ben Minto) [A7] | Explosions built at runtime from crack, body, environment reflections/echoes and debris; near = sharp transients, distant = rolling thunder; urban = sharp slapback, forest = diffuse; HDR prioritization; "War Tapes" heavily compressed mix mode; phone/handheld recordings to "embrace the dirt" | Explosion builder (§1.3). Slapback from street width. Optional "War Tapes" preset = extra Master compression |
| Battlefield 6 [A13] | Environmental acoustic reactions from a bi-directional raycast setup (from the article's summary) | Cheap version: 6 rays from the listener once per 0.5 s pick zone slapback delays (estimate) |
| Hawken [A8] | Two samples per weapon swapped by distance; tunnels echo; footsteps heavy but "musical" to avoid fatigue | Near/far variants. Footsteps with ±0.7 st random pitch and no harsh 2–4 kHz build-up |
| CoD gunshots (Mark Kilborn) [A9] | Body, transient, sub/LFE, mechanical, tail designed and routed as separate layers | The layer schema for every weapon |
| DOOM 2016 [A10] | Music cut into small sections; code chooses the section that fits the action | Horizontal clips + vertical stems (§6) |
| Gundam-style SFX recreation (Yukitoshi Baba) [A11] | Flight = analog synth with LFO loop + echo; alarm = high-passed synth with the filter looped by an oscillator; MS start-up = synth + a train-coupling clank for attack; cockpit hatch = truck air brake + factory + train coupling; steel walkway steps = recorded steel stairs, pitched | Hero start-up, hatch and cockpit sounds are synth + real-metal hybrids. No copying of any franchise sound |
| Creature voices (Matthew Collings) [A12] | Layer animal recordings chosen for an emotion (Burtt's Chewbacca from bears and others); pitch shift for scale, granular for texture, convolution to blend natural sources; perform through the chain in real time | HUSK vocal chain R11 (§1.4) |

### 1.2 Layer anatomy per family

All bands and durations in this table are (estimate), tuned to the SPEC numbers (16 m hero, run step every 0.55 s, dash 0.30 s, slide 44 m/s, assault 110 m/s, missiles 120→200 m/s, gatling 900 m/s).

| Family | T | B | S | M | Tl / D | Notes |
|---|---|---|---|---|---|---|
| Hero footstep | metal clank 2–5 kHz, 20–40 ms | container/concrete slam 80–250 Hz, 200–350 ms | 45→30 Hz glide, 300 ms, −6 dB under B | servo pre-roll 80 ms *before* contact (R4); hydraulic hiss 2–6 kHz after | gravel/glass 0.4–1.0 s on rubble only; zone slapback | alternate L/R sets; ±0.7 st random pitch; heavy step adds S + D |
| Servo / hydraulic | — | — | — | whine 300–900 Hz gliding with joint speed; pump 120–400 Hz | air release 3–8 kHz, 150 ms at stop | pitch = 0.8 + 0.4 × (ω/ω_max); min interval 120 ms |
| Boost / thrusters | ignition crack 6–10 ms + "chuff" | roar loop: noise 150 Hz–4 kHz | 40 Hz while boosting (FEEL boost_start) | turbine whine 1.2–3.5 kHz rising with speed | spool-down 0.6 s | slide: roar −6 dB. Assault: + sonic boom, roar +3 dB, whine ×1.5 |
| Beam rifle | "tchew" 2.4 kHz→280 Hz in ~140 ms + 4 ms noise (R2) | 200–600 Hz zap, 120 ms | 60 Hz bump, 80 ms | capacitor click 3–5 kHz | sizzle 4–7 kHz decaying 180 ms; slapback 90/160 ms | charge = R3 riser, 1.2 s, with stage clicks |
| Gatling | 1.5–3 kHz, 5–10 ms | 150–400 Hz, 60 ms | 50–70 Hz on every 3rd shot | spin motor 200–600 Hz; belt rattle | city tail 0.8–1.5 s after release; casings | loop + tail, not one-shots per bullet (§5.6) |
| Missiles | launch "fwip" 1–3 kHz, 60 ms × n, 40–60 ms stagger | hatch thump 100–200 Hz | — | hatch servo + latch | flight whoosh loop (R7); impact = explosion builder | ≤ 6 launch voices per salvo |
| Beam saber | swing whoosh shaped by blade speed | hum loop (R5) | — | — | clash: metal ring + crackle 0.3 s | hum +4 st and +4 dB during swings |
| Parry / block | parry "ting" from inharmonic bar partials (R9), 1.4 s | block: muffled clank 300 Hz | 60 Hz thump | shield servo | sparks | parry is a payoff: UI bus, never ducked |
| Explosion | crack 2.5–8 kHz, 10 ms | noise LP sweep 6 kHz→300 Hz, τ 350 ms | 60→32 Hz, 0.9 s | — | slapback 180/420/700 ms; debris 1–3 s; far: LP 800 Hz roll, 3 s | near/mid/far variants (§1.3) |

### 1.3 Space and distance in a 1.6 km vertical city

- **Air absorption** at 20 °C, 50 % RH is about 5 dB/km at 1 kHz and 160 dB/km at 10 kHz. That is why "distant thunder is a rumble, not a crack" [A14]. Far variants are low-passed. Godot's distance high-shelf (§5.4) does part of this automatically [G1].
- **Speed of sound** is 343 m/s; Godot's doppler uses the same constant [G1]. Delays (computed): 100 m = 0.29 s, 343 m = 1.0 s, 1 km = 2.9 s, 1.5 km = 4.4 s.
- **Delay rule (estimate):** delay only the mid/far layer, by `clamp((d − 120 m) / 343, 0, 2.5 s)`. The flash and the near layer stay instant. The "flash … boom" gap sells the Brood Titan's 90 m scale and distant spire fights.
- **Street-canyon slapback (estimate):** first reflection t = 2w/343 s for a façade w m away. That gives 117 ms at 20 m, 233 ms at 40 m and 350 ms at 60 m. Implemented as listener-zone delay taps (§5.3).
- **Explosion builder (estimate)**, choosing variants at spawn time from the distance d to the listener:
  - **Near, d < 150 m:** crack + body + sub + material debris (glass/concrete/metal from the hit collider group) + zone slapback.
  - **Mid, 150–500 m:** body low-passed at 4 kHz + sub −6 dB + tail, delayed.
  - **Far, > 500 m:** R8b rolling layer only, low-passed at 800 Hz, delayed. No crack.
  - **Size:** pitch runs from 1.0 (S) to 0.8 (XL), and duration grows up to ×1.6.

### 1.4 HUSK creature voices (biomechanical)

Base material: Freesound CC0 animal recordings (boar, walrus, big cat, bird screeches) plus our own vocal takes. Chain R11, run offline (estimate):
1. Pitch shift −5 st (Ripper, Mantis), −12 st (Juggernaut) or −19 st (Brood Titan), with formant preservation.
2. Ring modulation at 30–70 Hz for "machine-in-flesh" grit.
3. Granular stretch ×1.5 on sustained roars.
4. Convolution with a metal-plate impulse.
5. Insect-click layer for small types (Farnell practical 27 "Insects" [A17]).

Collings' advice applies: no single process sells a creature; the layering and the performance do [A12].

| Type (SPEC §7) | Signature (estimate) | Gameplay-critical cue (SPEC timing) |
|---|---|---|
| Ripper 裂爪 | chitter: 2–6 kHz click bursts at 18–30 Hz; light skittering steps | rising hiss through the 0.45 s crouch before a leap-bite |
| Mantis 镰影 | blade scrape, mid growl | 2.5 kHz "glint" ping (120 ms) 0.35 s before each parryable hit; growl swell for the 0.6 s red grab |
| Spitter 酸巢 | gurgle/pressure | 1.0 s pressure build before a lob; acid sizzle loop on impact |
| Harrier 鸣翼 | wing beats, flyby doppler | 0.5 s screech before an unblockable dive |
| Juggernaut 裂山 | armor-plate clank, C3-class steps | 0.7 s roar before a charge; ground-slam boom |
| Brood Titan 巢母 | sub footfalls 25–35 Hz audible map-wide; −19 st roar 1.2–2.0 s | roar on each destroyed spire; beam-breath charge 1.5 s |

### 1.5 Cockpit, alarms and the AI voice

FAA alerting guidance [A15], adapted:
- Prioritize alerts into warning, caution and advisory.
- Red = warning, amber = caution.
- An auditory alert should draw attention to a visual; it should not be the only source of information.
- Keep the number of auditory alarms minimal, and never mask a higher-priority alarm.
- Blink rates between 0.8 and 4.0 Hz.

Our tiers (estimate):

| Tier | Triggers | Sound | Voice line |
|---|---|---|---|
| Warning | HP < 25 %, missile lock on us, unblockable telegraph | R6 two-tone 880/660 Hz, 0.5 s each, ×3 | "Warning. Armor critical." / "Missile alert." |
| Caution | EN outage, gatling heat high, barrier down | 1 kHz beep pair every 1.0 s | "Energy depleted." |
| Advisory | overdrive ready, skill ready, objective | soft chime 150 ms | "Overdrive ready." / "Spire destroyed." |

Voice rules (estimate):
- One voice line at a time, from a priority queue.
- The same line is not repeated within 8 s.
- Lines stay at 3 words or fewer.
- Lines duck Music by about 7 dB and the Bed by about 4 dB (§5.2).

Start with about 24 lines in English and Chinese.

---

## 2. Sourcing we can legally use in a free, public demo

### 2.1 Sourcing table

| Pack / source | Licence (what it allows) | Attribution | Raw files in the public repo? | URL | Contents useful to us |
|---|---|---|---|---|---|
| Kenney *Sci-fi Sounds* (70 files) | CC0 [B1] | optional ("Kenney.nl") | yes | https://kenney.nl/assets/sci-fi-sounds · mirror zip: https://opengameart.org/sites/default/files/sci-fi_sounds.zip | engines, explosions, lasers (OGG, normalized) |
| Kenney *Impact Sounds* (130) | CC0 [B1] | optional | yes | https://kenney.nl/assets/impact-sounds | metal/plate/mining impacts, foley hits |
| Kenney *Interface Sounds* (100), *UI Audio* (50) | CC0 [B1] | optional | yes | https://kenney.nl/assets/interface-sounds · https://kenney.nl/assets/ui-audio | menus, clicks, confirms |
| Kenney *Digital Audio* (60) | CC0 [B1] | optional | yes | https://kenney.nl/assets/digital-audio | lasers, phasers, energy |
| Kenney *Voiceover Pack* (90), *Voiceover Pack (Fighter)* (45) | CC0 [B1] | optional | yes | https://kenney.nl/assets/voiceover-pack · https://kenney.nl/assets/voiceover-pack-fighter | placeholder announcer lines and taunts |
| Kenney *Music Jingles* (85) | CC0 [B1] | optional | yes | https://kenney.nl/assets/music-jingles | stingers, UI fanfares |
| OGA *50 CC0 Sci-Fi SFX* (rubberduck) | CC0 [B2] | no | yes | https://opengameart.org/content/50-cc0-sci-fi-sfx | beeps, explosions, loops, lasers, rocket |
| OGA *100 CC0 SFX* #1 and #2 (rubberduck) | CC0 [B2] | no | yes | https://opengameart.org/content/100-cc0-sfx · https://opengameart.org/content/100-cc0-sfx-2 | metal, glass, machine loops, construction site, highway/street loops, thunder, stones |
| OGA *The Free Firearm Sound Library* (194 MB, prepared set) | CC0 [B2] | requested, not required | yes | https://opengameart.org/content/the-free-firearm-sound-library | automatic and bolt actions, mechanics, outdoor tails: gatling transients, reload and "lock" clanks |
| Freesound, filtered to CC0 | per sound: CC0 / CC-BY / CC-BY-NC; filter `license:"Creative Commons 0"` [B3] | CC0: no; CC-BY: yes | CC0: yes | e.g. https://freesound.org/search/?q=servo+motor&f=license%3A%22Creative+Commons+0%22 (64 CC0 hits; packs *Electromechanical*, *Contact Microphone*) | servos, factories, animals, crunches, heartbeats |
| Freesound API | API key (token) enough for search and previews; original-quality downloads need OAuth2. Free only for non-commercial use. 60 req/min and 2,000/day; downloads 30/min and 500/day [B3] | as per sound | — | https://freesound.org/docs/api/overview.html | scripted CC0 search; download originals manually while logged in |
| Sonniss #GameAudioGDC bundles (2015–2026; 2026 = 7.47 GB, 347 WAV) | royalty-free, commercial use, no attribution, unlimited projects. No selling the sounds as-is; no modifying them to claim authorship [B4] | no | **no** (raw files git-ignored; only layered composites) | https://sonniss.com/gameaudiogdc/ · licence https://sonniss.com/gdc-bundle-license/ | pro metal impacts, explosions, debris, ambiences (biggest quality jump) |
| Pixabay sound effects (130,000+) and music | free, no attribution; no standalone distribution (no creative effort applied); some music is registered with Content ID [B5] | no | **no** (composites only) | https://pixabay.com/sound-effects/ · https://pixabay.com/service/license-summary/ | gap filler; avoid its music (trailer Content ID risk) |
| Adobe Audition SFX (12K+) | royalty-free; no distribution "on a standalone basis" [B6] | no | **no** | https://www.adobe.com/products/audition/offers/adobeauditiondlcsfx.html | firearms, impacts, ambiences |
| BBC Sound Effects (RemArc) | personal, educational or research use only; commercial licensing via Pro Sound Effects [B7] | — | **do not use** | https://sound-effects.bbcrewind.co.uk/licensing | — (a public demo is not personal/research use) |
| Tallbeard *Music Loop Bundle* (200+ loops) | CC0 per the itch listing [B8] (verify the licence file in the zip) | no | yes | https://tallbeard.itch.io/music-loop-bundle | seamless game loops, many genres |
| OGA CC0 music collection | CC0 [B2] | no | yes | https://opengameart.org/content/cc0-music-0 | *Fast fight / battle music (looped)*, *Boss Battle Music*, *Battle Theme A*, *Spacecrusher*, *Menace*, *Pressure*, *Covert Operations*, *Factory ambiance* |
| HoliznaCC0 (Free Music Archive) | CC0 [B11] | no | yes | https://freemusicarchive.org/music/holiznacc0/waves-of-nostalgia-2 | cyberpunk / retrowave / synthwave |
| Kevin MacLeod, incompetech | CC BY 4.0 [B9] | **required** | yes (with credit) | e.g. *Cyborg Ninja* (synths): https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1600008&Search=Search | synth action, cinematic |
| Scott Buckley | CC BY 4.0; not to be resold in isolation, not registered with Content ID [B10] | **required** ("[Title] by Scott Buckley – released under CC-BY 4.0. www.scottbuckley.com.au") | yes (with credit) | https://www.scottbuckley.com.au/library/using-this-music/ | epic orchestral and cinematic |
| Own synthesis (numpy, §4) | ours | — | yes | `tools/sfx/` (to create) | UI, alarms, beams, charges, servos, saber, sub, whooshes |
| MiniMax speech (TTS) / MiniMax-Music3 / MiniMax Audio | outputs must be labelled as AI-generated; Music3 commercial products must display "MiniMax-Music3" [C5][C6] | label in credits | yes | §6.4 | AI voice lines; music drafts |

### 2.2 Repository policy (estimate; not legal advice)

The user publishes game repos publicly (memory: games public). So:
1. Commit only CC0, CC-BY (credited), our own renders, and AI outputs (labelled).
2. Raw Sonniss, Pixabay and Adobe files live in git-ignored `art/audio_src/` (`art/**` is already lead-owned and git-ignored, CONTRACTS §1). Only processed, multi-layer composites enter `game/audio/sfx/`.
3. Keep `game/audio/CREDITS_AUDIO.md` and `audio_manifest.csv`:
   - `id, file, source, source_url, licence, author, layers_used, modified(Y/N)`
   - The HUD credits screen reads the CC-BY rows.

---

## 3. Sound list: 70 rows, ≈150 event ids (+6 music stingers), each mapped to source or recipe

Classes C0–C7 are defined in §5.4 (C0 = near-field on hero sockets; "2D" = non-positional). Source codes:
- **Kenney:** KSF sci-fi, KIM impact, KIF interface, KUI UI audio, KDA digital, KVO / KVF voiceover, KJG jingles.
- **OGA:** O50 = 50 CC0 Sci-Fi, O100 / O100b = 100 CC0 SFX #1/#2.
- **Others:** FFL = Free Firearm Library, FS = Freesound CC0 (search term), SON = Sonniss (composites only), MMX = MiniMax speech, R# = synthesis recipe (§4).

Caps and min intervals are (estimate).

| # | id(s) | Trigger (Events / FEEL) | Class → bus | Layers (length) | Source → recipe | Cap / min Δt |
|---|---|---|---|---|---|---|
| 1 | `footstep_hero` | `footstep(pos, false)`, every 0.55 s at run | C0 feet → Player | M pre-roll 80 ms + T 30 ms + B 250 ms + S 300 ms | FS "metal impact heavy", FS "container", R1, R4 | 2 / 90 ms |
| 2 | `footstep_hero_heavy` | `footstep(pos, true)` / `footstep_heavy` | C0 → Player | + D gravel 600 ms + slapback | KIM, O100b stones, R1 | 2 |
| 3 | `servo_move_s/m/l` | aim/turn faster than 40°/s, by size | C0 → Player | M 300–420 ms, pitch ∝ speed | R4, FS "servo motor" | 2 / 120 ms |
| 4 | `hydraulic_release` | after dash/land stop | C0 → Player | air hiss 150–250 ms | FS "pneumatic", KSF | 1 |
| 5 | `jump` | `jumped` / `jump` | C0 → Player | thrust T + servo + whoosh 250 ms | R7, KSF | 1 |
| 6 | `land_light` | `landed(v)` from < 25 m drop / `land_light` | C0 → Player | thud B 200 ms + hydraulics 300 ms | FS, R1 −6 dB | 1 |
| 7 | `land_heavy` | `landed` from > 25 m / `land_heavy` | C0 + C3 copy → Impacts | T + B + S (60→28 Hz, 0.6 s) + D 1.2 s | KIM, O100b, R1, SON | 1 |
| 8 | `hover_loop` | jump held (hover) | C0 loop → Player | roar LP 3 kHz | KSF engine, R7 noise loop | 1 |
| 9 | `flight_loop` | `flight_changed(true)` | C0 loop → Player | roar + turbine whine 1.2–3.5 kHz ∝ speed (50→90 m/s) | KSF, R4 high | 1 |
| 10 | `boost_start` | `boost_started(&"slide")` / `boost_start` | C0 → Player | ignition 10 ms + roar loop + S 40 Hz | KSF, R1 | 1 |
| 11 | `boost_slide_loop` | slide at 44 m/s | C0 loop → Player | roar −6 dB + ground-scrape/spark loop | O100 metal scrape, R7 | 1 |
| 12 | `dash` | `boost_started(&"quick")` / `dash` | C0 → Player | chuff 15 ms + whoosh 300 ms | R7, KSF | 3 (chain ≤ 3) |
| 13 | `assault_boost` | `boost_started(&"assault")` / `assault_boost` | C0 + C4 copy → Player | sonic boom 0.8 s + roar +3 dB + whine ×1.5 | R8a crack, R1, R7 | 1 |
| 14 | `boost_end` | `boost_ended` | C0 → Player | spool-down 0.6 s | R4 falling | 1 |
| 15 | `energy_outage` | `energy_depleted` | 2D → Cockpit | power-down 0.8 s + caution beeps | R3 reversed, R6 | 1 |
| 16 | `camera_toggle` | `camera_mode_changed` | 2D → UI | visor servo 250 ms + seal hiss | R4, FS air | 1 |
| 17 | `rifle_fire` | `weapon_fired(&"rifle")` / `rifle_fire` | C0 muzzle_r → Weapons (+C2 world copy) | R2 + capacitor click + slapback | R2, KSF laser | 3 |
| 18 | `rifle_charge_1/_2`, `rifle_stage2_release` | `rifle_charge_1/_2` | C0 → Weapons | R3 riser 1.2 s, stage clicks; release = R2 at 0.8 pitch + R1 + sizzle 300 ms | R3, R2, R1 | 1 |
| 19 | `rifle_hit` | `hit_landed` (rifle) / `rifle_hit` | C2 → Impacts | tick + zap 120 ms | KSF, KIM | 3 / 40 ms |
| 20 | `rifle_stage2_hit` | `rifle_stage2_hit` | C3 → Impacts | T + B + S, 8 m blast 0.6 s | R8a short | 2 |
| 21 | `gatling_spin_up/_down` | fire held / released | C0 → Weapons | motor 200→600 Hz 0.35 s; down 0.6 s | R4, FFL mechanics | 1 |
| 22 | `gatling_fire_loop`, `gatling_fire_accent` | `weapon_fired(&"gatling")` held / `gatling_fire` (per 3 shots) | C0 loop → Weapons | shots baked at the fire rate + spin; accent = T + S | FFL automatic, R1 short | 1 + 2 |
| 23 | `gatling_tail` | release | C0 + C2 → Weapons | city tail 1.2 s | FFL outdoor tails + zone delay | 1 |
| 24 | `gatling_hit` | `gatling_hit` | C2 → Impacts | tick 30 ms + ricochet on 1 in 4 | KIM, FFL | 4 / 35 ms |
| 25 | `gatling_vent`, `gatling_vent_perfect` | vent press / `gatling_vent_perfect` | C0 → Weapons | steam hiss 400 ms (+ chime 600 ms when perfect) | FS air, R9 high | 1 |
| 26 | `weapon_switch`, `reload` | `weapon_switched` / reload | C0 → Weapons | servo + latch clank 250 ms; mag 600 ms | R4, FFL bolt/reload | 1 |
| 27 | `missile_lock_tick`, `missile_lock_full` | `missiles_locked(n)` | 2D → UI | 1.8 kHz beep 60 ms, interval 180→60 ms with n; full = 3-beep | R6 variant | 1 |
| 28 | `missile_launch` | `missile_launch` × n | C0 missile_l/r → Weapons | "fwip" 60 ms each, 40–60 ms stagger + hatch thump | KSF, R7 | 6 |
| 29 | `missile_flight` | per missile | C7 → Weapons | whoosh loop; flyby one-shot at closest approach | R7 | 6 nearest |
| 30 | `missile_hit` | `missile_hit` | C3 → Impacts | explosion builder S/M | R8a, KIM, O100b, SON | 4 |
| 31 | `lock_on`, `lock_off` | `lock_changed(t / null)` | 2D → UI | two-tone up / down, 80 ms | KIF | 1 |
| 32 | `saber_ignite`, `saber_hum_loop`, `saber_sheathe` | melee drawn / held / stowed | C0 hand_r → Player | swell 0.4 s → R5 loop modulated by blade speed | R5, R3 short | 1 |
| 33 | `saber_swing` | `melee_swing(move, step)` | C0 → Player | whoosh 200–350 ms; +1 st per combo step | R7, R5 mod | 2 |
| 34 | `melee_light` | `melee_light` | C2 → Impacts | T clang + B + M servo | KIM metal, R2 sizzle | 2 |
| 35 | `melee_heavy` | `melee_heavy` | C3 → Impacts | T + B + S + M | KIM, R1, SON | 2 |
| 36 | `lunge_hit` | `lunge_hit` | C2 → Impacts | whoosh → T + B | R7, KIM | 1 |
| 37 | `charge_slash` | `charge_slash` | C3 → Impacts | T + B + S + Tl + crescent-wave whoosh | R3, R7, R8a | 1 |
| 38 | `finisher` | `finisher` (Core Rend, Return Cut) | 2D → Impacts | swell 0.5 s → T + B + S + Tl | R3, R8a, R1 | 1 |
| 39 | `parry_perfect` | `parry_success` / `parry_perfect` | 2D → UI (+ thump → Impacts) | R9 ting 1.4 s + 60 Hz thump | R9, R1 | 1 |
| 40 | `block` | `attack_blocked` / `block` | C0 shield_l → Impacts | muffled clank 300 ms | KIM | 2 |
| 41 | `catch_field_loop`, `catch_release` | guard held ≥ 0.3 s / release | C0 → Weapons | electric hum loop; "whoomp" | R5 variant, R1 | 1 |
| 42 | `perfect_dodge` | `perfect_dodge` | 2D → UI | reversed whoosh 300 ms + heartbeat | R7 reversed | 1 |
| 43 | `rift_out`, `rift_in` | `rift_step` | C0 → Player | reversed whoosh + implosion thump | R7 reversed, R1 | 1 |
| 44 | `anchor_fire`, `anchor_latch`, `anchor_reel_loop` | Skyhook / `anchor_latch` | C0; latch C2 → Player | twang + clank; winch loop | FFL, R4, O100 metal | 1 |
| 45 | `fins_launch`, `fins_hit` | `fins_launch` / fin hits | C0 wing → Weapons; hit C2 → Impacts | chime cascade (6 notes, D minor); small zaps | R9 pitched, R2 short | 1 / 6 |
| 46 | `ward_up_loop`, `ward_hit`, `ward_break` | Corona Ward / `ward_hit` | C0 → Player | glass-ring hum loop; ring; shatter | R9, KIM glass, O100 glass | 3 |
| 47 | `shockcore` | `shockcore` | C3 → Impacts | inhale 0.3 s → crack-boom | R3 reversed, R8a, R1 | 1 |
| 48 | `undertow_loop`, `collapse` | Undertow Well / `collapse` | C3 → Impacts | swirling low loop; reverse cymbal + boom | R7 loop, R1, R8a | 1 |
| 49 | `plunge_dive`, `plunge_land` | `plunge_land` | C0 / C4 → Impacts | whistle 0.6 s → boom + 60 Hz | R3 falling, R8a, R1 | 1 |
| 50 | `overdrive_ignite`, `overdrive_loop` | `overdrive_ignite` / `overdrive_changed(true)` | 2D / C0 → Player | synth swell 1 s + 5-beat servo-lock rhythm (Aadahl) + roar; shimmer loop −12 dB | R3, R4, R5 high | 1 |
| 51 | `lance_charge`, `lance_fire` | `lance_fire` / `ultimate_fired` | 2D + C4 → Weapons | riser 0.8 s → sustained roar + S; release crack | R3, R8a, R1 | 1 |
| 52 | `skill_ready` | `skill_ready(skill)` | 2D → UI | soft chime 150 ms, pitch per skill | KIF, R9 | 1 / 500 ms |
| 53 | `hurt_light`, `hurt_heavy` | `hurt_light` / `hurt_heavy` | 2D → Player (+ Cockpit alarm) | ping + B; heavy = T + B + S + alarm + World LPF dip | KIM, R1, R6 | 2 / 1 |
| 54 | `near_miss` | `near_miss` | C7 → Enemies | doppler flyby 0.4 s | R7 | 2 |
| 55 | `hitmarker`, `hitmarker_weak` | `hit_landed` by player | 2D → UI | R10 click 60 ms; identical every time, never ducked (CoD lesson, juice §8) | R10 | 1 / 30 ms |
| 56 | `kill_confirm`, `kill_small` | `enemy_killed` / `kill_small` | 2D → UI; C2 → Impacts | R10 + 60 Hz thump 120 ms; blast B + D | R10, R1, R8a short, KIM | 3 / 80 ms (merge) |
| 57 | `kill_large`, `jackpot` | `kill_large` / `jackpot` | C4 → Impacts; 2D → Voice | full builder + delayed far layer; "JACKPOT" callout | R8a/b, O100b, MMX or KVF | 2 / 1 |
| 58 | `stagger_enemy`, `boss_stagger` | `enemy_staggered` / `stagger_enemy`, `boss_stagger` | C3 / C5 → Impacts | metal groan 0.8 s (slowed ice/metal crunch); boss + plates ejecting | R11, KIM, SON | 2 / 1 |
| 59 | `combo_rank_up` | `combo_changed(rank up)` | 2D → UI | rising 3-note arpeggio | KJG, R9 | 1 / 400 ms |
| 60 | `ripper_chitter_loop`, `ripper_step`, `ripper_leap_tell`, `ripper_bite`, `ripper_death` | Ripper AI | C1 / C2 → Enemies | clicks, skitter, 0.45 s hiss, snap, wet crunch | R11, FS "crunch", KIM small | 6 nearest |
| 61 | `mantis_glint`, `mantis_swing`, `mantis_grab_tell`, `mantis_death` | Mantis AI | C2 → Enemies | 2.5 kHz ping 120 ms (priority 80); blade whoosh + scrape; 0.6 s growl swell | R9 short, R7, FS scrape, R11 | 2 |
| 62 | `spitter_charge`, `acid_lob`, `acid_impact_loop`, `spitter_death` | Spitter AI | C3 → Enemies | 1.0 s gurgle build; "pthoom"; 2 s sizzle | FS liquid, R11 | 3 |
| 63 | `harrier_screech`, `harrier_flyby`, `harrier_wings` | Harrier AI | C7 → Enemies | 0.5 s screech; doppler flyby; wing beats | FS birds (R11), R7 | 2 |
| 64 | `jugg_roar`, `jugg_step`, `jugg_slam`, `jugg_plate_break` | Juggernaut AI | C4 / C3 → Enemies, Impacts | 0.7 s roar; C3 steps; slam = builder L; plate break = slowed crunch + gun-cock | R11 (−12 st), R8a, SON | 1 |
| 65 | `titan_step_far`, `titan_roar` (`boss_roar`), `titan_breath_beam` | Titan walk and attacks | C5 → Bed / Enemies | sub 25–35 Hz + far rumble delayed by d/343; roar 1.2–2 s audible across 1.5 km; 1.5 s charge + roar | R1, R8b, R11 (−19 st), R3 | 1 |
| 66 | `spire_pulse_loop`, `spire_destroyed` | hive spires / `encounter_cleared` | C4 → Bed; Impacts | 0.8 Hz organic pulse; XL collapse | R1, R11, R8a/b | 3 / 1 |
| 67 | `alarm_warning`, `alarm_caution`, `heartbeat_loop` | tiers in §1.5; HP < 30 % | 2D → Cockpit | R6 ×3; beep pairs; 70→110 BPM | R6, FS heartbeat | 1 each |
| 68 | `ai_*` (24 lines: `ai_overdrive_ready`, `ai_energy_low`, `ai_armor_50`, `ai_armor_critical`, `ai_missile_alert`, `ai_target_staggered`, `ai_spire_down`, `ai_titan_approach`, …) | events per §1.5 | 2D → Voice | 0.6–1.5 s each | MMX speech-2.8-hd "robotic"; placeholder KVO | queue 1 |
| 69 | `ui_move`, `ui_confirm`, `ui_back`, `ui_pause`, `objective_update` | menus, `objective_changed`, `paused_changed` | 2D → UI | 40–120 ms; objective = 2-note chime + radio click | KIF, KUI, R6 | — |
| 70 | `amb_city_bed`, `amb_wind_high`, `siren_emitter`, `maglev_pass`, `neon_buzz`, `distant_battle_bed`, `glass_shatter`, `debris_concrete`, `debris_metal` | zones, props, intensity, destruction | 2D Bed; C4 sirens; C3 maglev; C6 props; C2 debris → Bed / Impacts | zone loops; 600/450 Hz siren at 0.5 s; 3 s pass; 120 Hz buzz; far booms; shatter; 0.5–2 s debris | O100b highway/street loops, FS city, R6, R7, R5 buzz, R8b, O100 glass, O100b stone, SON | 4 sirens, 8 props, 6 debris |

Music stingers (`stinger_stagger`, `stinger_kill_large`, `stinger_boss_phase`, `stinger_spire_cleared`, `stinger_victory`, `stinger_defeat`) are in §6.2.

---

## 4. Procedural / synthesized SFX: recipes, measured output, limits

All eleven recipes are in `tmp/research/audio-music/scripts/synth_probe.py` (numpy only, 48 kHz). They rendered in **0.6 s wall time** in total on the M1 Max (measured). Spectrograms: `ref/images/audio-music/proto_*.png`.

| Recipe | Construction (parameters) | Measured | Used by |
|---|---|---|---|
| R1 sub thump | sine glide 70→30 Hz (τ 60 ms), amplitude τ 120 ms, 1.5 ms HP click, `tanh(1.6x)` adds 90–210 Hz harmonics for small speakers | 0.45 s, −1.0 dBFS peak, −9.8 dBFS RMS | every S layer, kills, landings |
| R2 beam "tchew" | saw falling 2.4 kHz→280 Hz (τ 35 ms) + 4 ms HP noise + 5.2 kHz band-passed sizzle with 43 Hz AM + slapback 90/160 ms | 0.58 s, −20.7 LUFS-I, **true peak +0.6 dBTP at −1.0 dBFS sample peak** | rifle, fins, small energy hits |
| R3 charge riser | FM: carrier 220→880 Hz exponential, mod index 2→5, tremolo 6→28 Hz, stage clicks at 0.6/1.19 s | 1.2 s, −11.6 dBFS RMS | rifle charge, lance, shockcore (reversed) |
| R4 servo whine | `tanh(3·sin)` at 420→560→500 Hz, ±1.5 % random-walk jitter, 90 Hz gear ripple, 1.8 kHz band-pass blend | 0.42 s, −5.5 dBFS RMS | all M layers, spin-ups |
| R5 saber hum loop | additive 87.0 + 89.5 Hz × 8 harmonics (2.5 Hz beat = Burtt's two motors) + 120 Hz buzz to 4 kHz at −14 dB. Integer cycle counts make the 2.0 s loop seamless (seam step = natural sample step) | −12.4 LUFS-I | saber, catch field, neon buzz |
| R6 alarm | two-tone 880/660 Hz alternating every 0.5 s, 2.7 ms glide, `tanh` drive | −4.5 LUFS-I (render at −20 before import) | warning, caution, sirens, lock tones |
| R7 whoosh/flyby | pink noise through a band-pass sweeping 300→2,500→400 Hz under a Gaussian envelope | 1.0 s | dash, swings, missiles, flybys |
| R8a explosion near | crack (HP noise, τ 10 ms) + body (LP 6 kHz→300 Hz, τ 350 ms) + R1 (60→32 Hz) + slapback 180/420/700 ms (−8/−12/−16 dB) | 2.9 s, −22.9 LUFS-I | missile/kill/slam builder |
| R8b explosion far | double LP 800 Hz noise, τ 1 s, random 3–7 Hz "roll" AM | 3.0 s | far variants, Titan, distant battle |
| R9 parry ting | free-bar partials f₀ × {1, 2.76, 5.40, 8.93}, amplitudes {1, .5, .25, .12}, τ {0.9, 0.5, 0.3, 0.2} s, f₀ 1.85 kHz | 1.4 s | parry, ward, fins, chimes |
| R10 UI hit | 2.2 kHz (τ 12 ms) + 4.1 kHz (τ 5 ms) | 60 ms | hitmarker, kill confirm |
| R11 creature chain | (offline DSP chain, §1.4) | — | HUSK voices |

**How far synthesis goes (estimate from the list above):**
- About 35 % of ids can be fully synthetic: UI, alarms, beams, charges, servos, saber, sub, whooshes, energy, chimes.
- About 40 % are hybrid: a synthetic tonal or sub layer over recorded metal, debris or noise.
- About 25 % need recordings: metal clanks, concrete and glass debris, creature bases, water/acid, heartbeats.

Farnell's book shows procedural models for motors, jet engines, footsteps, insects, guns, explosions, rockets, electricity, thunder, wind and "red alert" [A17]. Those are useful references for R4, R7, R8 and R11.

**Process rules (measured or estimate):**
- Normalize to **−1 dBTP true peak, not sample peak.** R2 overshot by 1.6 dB (measured with ffmpeg `ebur128=peak=true`).
- Turn Godot's import *Normalize* off. Godot normalizes to 0 dB peak [G10], which would bring back the overshoot.
- Render mono for 3D sources.
- Tools:
  - numpy (BSD).
  - rFXGen, an sfxr derivative under zlib [A18], for quick UI blips.
  - Spotify pedalboard for reverb, compression and pitch. It is GPL-3.0 [A19], so use it only as an offline tool that never ships with the game (estimate).
  - Demucs (MIT) to split music into stems [A20].
  - ffmpeg `ebur128`, `loudnorm` and `showspectrumpic` are available locally (verified).

---

## 5. Godot 4.7 mixing recipe

### 5.1 Bus layout (build at runtime in `Audio._ready()`; verified to run on 4.7.2)

Index order matters for two reasons:
- **Sends:** a bus may only send to a lower index; an invalid send falls back to Master.
- **Sidechains:** buses are processed from the highest index down to 0, and a compressor reads its sidechain bus's buffer at that moment [G4][G5]. So **a key bus must have a higher index than the bus it ducks**; otherwise it reads a pre-effect, pre-send signal.

| # | Bus | Sends to | Effects in order (parameters) | Contents |
|---|---|---|---|---|
| 0 | Master | — | `AudioEffectHardLimiter` ceiling −1.0 dB, pre_gain 0, release 0.10 s (`AudioEffectLimiter` is deprecated [G7]) | Settings `master_volume_db` |
| 1 | Music | Master | Compressor sc=`Voice` thr −18.5 ratio 4 attack 2000 µs release 500 ms; Compressor sc=`Impacts` thr −13 ratio 2 attack 1000 µs release 350 ms | `music_volume_db` (default −4) |
| 2 | Stinger | Music | — | stingers (inherit music slider and ducking) |
| 3 | UI | Master | — (never ducked) | hitmarkers, menus, lock tones, parry |
| 4 | World | Master | LowPassFilter cutoff 20500 (gameplay-driven); Reverb (zone snapshot, dry 1.0); Delay (zone slapback, dry 1.0) | `sfx_volume_db` |
| 5 | Bed | World | Compressor sc=`Impacts` thr −16 ratio 3 attack 800 µs release 450 ms; Compressor sc=`Voice` thr −18 ratio 2 attack 2000 µs release 400 ms | ambience, sirens, distant battle, Titan far steps |
| 6 | Enemies | World | Compressor sc=`Impacts` thr −13 ratio 2 attack 500 µs release 300 ms | creature vocals, enemy weapons |
| 7 | Player | World | — | own locomotion, servos, boost, saber (C0) |
| 8 | Weapons | World | Compressor thr −8 ratio 2 attack 20 µs release 80 ms (glue) | own weapons, missiles |
| 9 | Impacts | World | Compressor thr −6 ratio 3 attack 20 µs release 120 ms | hits, explosions, kills (**duck key**) |
| 10 | Voice | Master | HighPassFilter 140 Hz; Compressor thr −20 ratio 3 attack 500 µs release 150 ms | AI callouts, radio (**duck key**) |
| 11 | Cockpit | Master | — | alarms, relays, heartbeat |

Sidechain checks: Music (1) reads Voice (10) and Impacts (9); Bed (5) reads 9 and 10; Enemies (6) reads 9. All keys are to the right, as required. Compressor ranges: attack 20–2000 µs (so **at most 2 ms**), release 20–2000 ms, ratio 1–48 [G7]. Proposed new Settings keys (lead owns `core/settings.gd`): `voice_volume_db`, `ui_volume_db`.

### 5.2 Ducking math (verified 4.7.2)

Godot's compressor computes `overdb = 2.08136898 × linear_to_db(peak / threshold)` and `gain_reduction = overdb × (ratio − 1) / ratio` [G5]:

**GR ≈ 2.08 × (key_peak_dB − threshold_dB) × (1 − 1/ratio).**

Measured headless (`godot_test/duck.gd`): key 3 dB over threshold, ratio 3 → Bed peak fell from −23.0 to −27.1 dB.
- Measured: **4.1 dB** reduction.
- Formula prediction: 4.16 dB.
- Textbook compressor: 2.0 dB.

Design targets with that formula (estimate):

| Ducked bus | Key level | Reduction |
|---|---|---|
| Music | Voice at −14 dBFS | ≈ 7 dB |
| Music | Impacts at −10 dBFS | ≈ 3 dB |
| Bed | Impacts at −10 dBFS | ≈ 8 dB |
| Bed | Voice at −14 dBFS | ≈ 4 dB |
| Enemies | Impacts at −10 dBFS | ≈ 3 dB |

Re-tune the thresholds once Impacts' real peak level is known.

### 5.3 Snapshots and listener zones (estimate; tween in script)

| State | Changes | Tween |
|---|---|---|
| Low HP < 30 % / < 15 % | World LPF 8 kHz / 2.5 kHz; `heartbeat_loop` 70→110 BPM (juice §11.3) | 0.4 s |
| `hurt_heavy` | World LPF dips to 1.2 kHz for 400 ms (FEEL row) | in 30 ms / out 400 ms |
| Witch time / slow-mo | World LPF 3.5 kHz; World one-shots `pitch_scale` × 0.85; music untouched (juice §5) | 0.1 s |
| 1st-person cockpit | World LPF 9 kHz, Reverb wet × 0.7, Player +2 dB, Cockpit +3 dB | 0.25 s (SPEC camera blend) |
| Pause | Master −10 dB, World LPF 800 Hz; music keeps playing (`PROCESS_MODE_ALWAYS`) | 0.2 s |
| Pre-boss silence | Music to the "tension" clip, Bed −12 dB for 2 bars, then `titan_roar` | bar-quantized |

Listener zones are Area3D volumes in group `&"audio_zone"`, tested against the listener position:

| Zone | Reverb room / damping / wet / predelay | Delay taps | Bed loops |
|---|---|---|---|
| Rooftops, sky decks (+90…300 m) | 0.35 / 0.7 / 0.05 / 60 ms | 300 ms −18 dB | strong wind; traffic −12 dB |
| Street canyon (0 m) | 0.6 / 0.5 / 0.12 / 40 ms | 117 ms −12 dB, 233 ms −16 dB | traffic hum, sirens, PA |
| Elevated roads, skybridges (+40 m) | 0.5 / 0.6 / 0.08 / 50 ms | 180 ms −14 dB, 320 ms −18 dB | wind, maglev passes |
| Canal trench, tunnels (−40 m) | 0.8 / 0.3 / 0.28 / 25 ms | 60 ms −9 dB | drips, pumps, water |
| Plaza / spire surroundings | 0.55 / 0.5 / 0.08 / 50 ms | 250 ms −16 dB | organic spire pulse |

Crossfade over 1.0 s. Godot's reverb ranges: predelay 20–500 ms, room 0–1, damping 0–1, wet 0–1 (verified dump).

**Why not per-source Area3D reverb (verified):**
- In 4.7, `AudioStreamPlayer3D.area_mask` defaults to **0**: no Area3D audio processing unless set (PR #107679, "Set audiostreamplayer default area_mask to 0" [G13]). This is the cause of the "reverb doesn't work in 4.7" reports [G13].
- An Area3D with a reverb bus silences the player's own bus (issue #96480, open since 4.0 [G13]). The workaround is `audio_bus_override = true` with the dry bus named [A23], but that forces every source in the area onto one bus and breaks our sidechain keys.
- The listener-zone snapshot avoids both problems.

### 5.4 3D distance classes (Godot formula, computed)

Godot 4.7.2 attenuation [G1]:
- Inverse: −20·log10(d/unit_size), capped at `max_db`.
- Inverse-square: twice that slope.
- Logarithmic: −20·ln(d/unit) = **−13.9 dB per doubling**. Too steep for a city; avoid.
- When `max_distance > 0`, an extra × (1 − d/max) fade applies, and the source is culled beyond it.
- A high-shelf at `attenuation_filter_cutoff_hz` has gain `(1 − min(1, multiplier)) × attenuation_filter_db`, so it deepens as the source gets quieter.
- Effective panning = project `3d_panning_strength` (0.5) × `panning_strength` [G1][verified dump].

Values are (estimate); the dB columns are computed with this formula.

| Class | Use | Model | unit_size | max_db | max_distance | filter Hz / dB | panning | 26 m | 100 m | 200 m | 400 m | 800 m | 1600 m |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C0 near-field | own mech on sockets | disabled | — | 0 | 0 | — / 0 | 0.35 | 0 | — | — | — | — | — |
| C1 small | Ripper steps, small debris | inverse | 6 | 0 | 220 | 5000 / −24 | 1.0 | −14 | −30 | −51 | cut | cut | cut |
| C2 mech | hits, Mantis, gunfire copies | inverse | 20 | 3 | 600 | 4000 / −24 | 1.0 | −3 | −16 | −24 | −36 | cut | cut |
| C3 heavy | missile hits, Juggernaut steps, stagger | inverse | 45 | 3 | 1100 | 3000 / −30 | 0.8 | +3 | −8 | −15 | −23 | −36 | cut |
| C4 huge | large explosions, sirens, spires | inverse | 90 | 6 | 2000 | 2500 / −36 | 0.6 | +6 | −1 | −8 | −15 | −23 | −39 |
| C5 titan | Brood Titan, boss staggers | inverse | 200 | 6 | 3000 | 2000 / −36 | 0.5 | +6 | +6 | −1 | −7 | −15 | −25 |
| C6 ambient prop | neon buzz, vents | inverse-sq | 4 | 0 | 60 | 6000 / −12 | 1.0 | −37 (10 m: −18) | cut | cut | cut | cut | cut |
| C7 flyby | Harrier, missiles, near misses | inverse | 15 | 3 | 400 | 5000 / −24 | 1.4 | −5 | −19 | −29 | cut | cut | cut |

C0 is implemented as `attenuation_model = ATTENUATION_DISABLED` on the hero's sockets. Mono sources only.

### 5.5 Listener

- **3rd person:** a single `AudioListener3D` (owned by the camera rig) is made current. Each frame, `global_transform = Transform3D(camera.global_basis, chest.lerp(camera_pos, 0.2))`. When a viewport has a current `AudioListener3D`, Godot uses it instead of the camera for position and orientation [G1].
- **1st person:** the listener sits at the cockpit camera.
- **Rationale:** with the camera 26 m back, a camera-positioned listener would attenuate everything near the hero. Third-person setups commonly take panning from the camera and attenuation from the character [A22].

### 5.6 Voice management (estimate; Godot provides none)

- **Pools:**
  - 40 `AudioStreamPlayer3D` for world sounds, each with `max_polyphony = 1` so we control stealing. Godot's own overflow stops the oldest playback [G6].
  - 12 near-field C0 players on the hero.
  - One `AudioStreamPlayer` holding an `AudioStreamPolyphonic` (polyphony 24; default 32, max 128) for 2D. Its `play_stream(stream, offset, volume_db, pitch, playback_type, bus)` takes a **bus** argument, so one node serves UI, Voice and Cockpit (verified API).
  - Music players.
- **Priority** (0–100): UI 100, Voice 95, own weapons 90, large impacts 85, enemy telegraphs 80 (gameplay-critical), hits 60, footsteps 40, debris 20, props 10. Subtract 1 per 3 dB of predicted attenuation at spawn.
- **Steal rule:** when a pool is full, steal the voice with the lowest `priority − 10 × age_s` if it is lower than the new one; otherwise drop the new one.
- **Caps** as in §3. At most 8 new voices per physics tick (120 Hz).
- **Merging:** kills within 80 ms merge into one layered "multi-kill". Swarms play only the 6 nearest emitters.
- **Gatling:** one loop with shots baked at the fire rate, plus a T/S accent every 3rd shot (FEEL `gatling_fire`), plus a release tail. Never one voice per round.
- **Cost:** Godot docs say WAV is light on the CPU ("hundreds of simultaneous voices in this format are fine"), while OGG needs "significantly more processing power" [G10]. Keep OGG for music, voice lines and long ambiences only.

### 5.7 Doppler policy (computed)

Godot's doppler uses 343 m/s, clamps the pitch factor to 1/8–8×, and reads listener velocity from the `AudioListener3D` or camera [G1]. Computed shifts:
- Hero assault boost at 110 m/s: static emitters would bend **+6.7 / −4.8 semitones**.
- Missiles at 200 m/s: **+15.1 / −8.0 st**.

So:
- `AudioListener3D.doppler_tracking = DISABLED` (and the same on the camera).
- `DOPPLER_TRACKING_PHYSICS_STEP` only on C7 Harrier and near-miss sources, around 60 m/s: +3.3 / −2.8 st.
- Missiles use the R7 flyby one-shot at the predicted closest approach. This is Burtt's moving-mic trick, baked [A6].

### 5.8 Formats and import

| Asset | Format | Settings |
|---|---|---|
| Short one-shots | WAV 48 kHz / 16-bit, mono for 3D | import compression QOA (Godot default); Trim on; Normalize off [G10] |
| Short loops (roar, hum, gatling, props) | WAV with Forward loop points | `loop_begin`/`loop_end` in samples (OGG/MP3 have no loop end [G10]) |
| Music stems, long ambiences | OGG Vorbis 44.1 kHz stereo | `loop = true`; `bpm`, `beat_count`, `bar_beats` in Advanced import [G10] |
| Voice lines | OGG mono 32 kHz (voices are fine down to 22 kHz [G10]) | — |

Godot mixes at 44.1 kHz by default (verified project setting `audio/driver/mix_rate = 44100`). 48 kHz sources are resampled; there is no benefit above 48 kHz unless slowed down [G10].

### 5.9 Loudness target

Sony's ASWG recommends **−23 LUFS ±2 LU integrated** for home console content and −18 LUFS for portable, measured over at least 30 minutes of representative gameplay [A16]. Target −23 LUFS on a 30-minute `tools/godot.sh movie` capture, measured with `ffmpeg -i capture.avi -af ebur128=peak=true -f null -`. Keep true peak ≤ −1 dBTP via the Master limiter. If playtests feel quiet on laptop speakers, raise Master pre-gain toward −18 LUFS (estimate).

### 5.10 Godot 4.7 audio gotchas (verified unless marked)

1. Area3D audio needs `area_mask` on the player (4.7 default 0); a reverb Area3D mutes the player's own bus (#96480) [G13]. See §5.3.
2. Interactive playback has no position (`get_playback_position()` = 0.000 in the probe) and no clip-changed signal: use the metronome clock and poll `get_current_clip_index()` (§6.3).
3. `set_sync_stream_volume()` applies at once with no smoothing (Master −15.4 → −75.3 dB by the next reading): ramp in script. `set_sync_stream()` on a playing stream restarts it [G3].
4. `AudioStreamWAV` has no `bpm`: WAV stems make NEXT_BAR fall back to immediate and `fade_beats` become seconds [G2].
5. Transition lookup order: (from, to) → (from, ANY) → (ANY, to) → (ANY, ANY) [G2].
6. `get_stream_playback()` errors before `play()`; `play()` fails until the node is inside the tree (probe).
7. Players pause with the SceneTree [G6]: music/UI audio nodes need `PROCESS_MODE_ALWAYS`.
8. `Engine.time_scale` does not slow audio; `AudioServer.playback_speed_scale` slows all audio (juice §5 [S41][S45]).
9. The 4.7 release notes have no audio section [G15]: apart from the area_mask default, expect 4.6 behaviour.

---

## 6. Music

### 6.1 Sources (CC0 / CC-BY) for an intense sci-fi combat demo

| Use | First choice | Alternatives |
|---|---|---|
| Explore (0.2) | HoliznaCC0 *Waves Of Nostalgia 2* (cyberpunk/synthwave, CC0) [B11] | OGA CC0 *Covert Operations*, *Menace*, *Factory ambiance* [B2]; Tallbeard CC0 loops [B8] |
| Combat (0.5–0.8) | OGA CC0 *Fast fight / battle music (looped)*, *Battle Theme A*, *Spacecrusher* [B2] | Kevin MacLeod *Cyborg Ninja* (CC BY 4.0) [B9] |
| Boss (1.0) | OGA CC0 *Boss Battle Music* [B2] | Scott Buckley epic orchestral (CC BY 4.0) [B10] |
| Stingers | Kenney *Music Jingles* (85, CC0) [B1] | cut 1–2 bar hits from the combat stems |
| Custom (best fit) | AI-generated instrumentals at a fixed BPM and key (§6.4), then Demucs 4-stem split (drums / bass / other / vocals, MIT) [A20] | — |

None of the free tracks ship as stems. Pick tracks at, or time-stretched to, **one shared tempo and key**. Then either:
- add our own synth stems (pulse, sub, riser) on top, or
- run Demucs on full mixes to get drums, bass and "other" layers.

Demucs separation artifacts are masked inside dense combat mixes (estimate).

### 6.2 Adaptive design (estimate; SPEC §8 intensity targets)

- **Grid:** every clip at **140 BPM, 4/4, D minor** (bar = 1.714 s, beat = 0.429 s). Each loop is a whole number of bars: 16 bars = 27.4 s, `beat_count = 64`. With a shared grid, SAME_POSITION transitions stay musical.
- **Clips (horizontal):**
  - `explore`: pad, pulse, light percussion, drone.
  - `combat`: drums, bass ostinato, lead/brass, choir/riser.
  - `boss`: double-time drums, choir, brass, bass.
  - `boss_p3`.
  - `tension` (near-silent drone, used before the boss).
  - `spire_cleared`: 2 bars, then returns to the held clip.
  - `victory`, `defeat`.
- **Stems (vertical) within a clip:** stem *k* fades in when intensity I > θₖ and out below θₖ − 0.1, with at least 4 bars (6.9 s) between toggles. Fade = 1 bar.
  - `explore`: pulse 0.25, percussion 0.35.
  - `combat`: bass 0.55, lead 0.7, choir 0.85.
  - Intensity comes from flow and the L4D-style director (juice §11.2).

| From → To | from_time | to_time | Fade | Notes |
|---|---|---|---|---|
| ANY → ANY (default) | NEXT_BAR | SAME_POSITION | CROSS, 2 beats | — |
| explore → combat | NEXT_BEAT | SAME_POSITION | CROSS, 1 beat | contact lands in ≤ 0.43 s |
| combat → explore | NEXT_BAR | SAME_POSITION | CROSS, 8 beats | only after 6 s with no threats |
| ANY → boss | NEXT_BAR | START | OUT | `use_filler_clip` = 2-bar `tension` riser |
| ANY → spire_cleared | NEXT_BEAT | START | CROSS, 1 beat | `hold_previous = true`; clip `auto_advance = RETURN_TO_HOLD` |
| spire_cleared → ANY | END | PREVIOUS_POSITION | CROSS, 2 beats | resumes where the held clip left off |
| ANY → defeat | IMMEDIATE | START | OUT, 1 beat | — |

| Stinger | Trigger | Quantize | Rules |
|---|---|---|---|
| `stinger_stagger` | `enemy_staggered` (elite/boss) | next beat | 1 bar brass hit |
| `stinger_kill_large` | `kill_large` | immediate (rides the hit-stop) | Music −4 dB for 0.6 s |
| `stinger_boss_phase` | `boss_phase` | next bar | 2-bar rise, then switch clip |
| `stinger_spire_cleared` | `encounter_cleared` | next beat | the hold/return clip above |
| `stinger_victory` / `stinger_defeat` | `game_won` / `player_died` | — | clip switch |

Global stinger rules: at most one stinger per 2 s, and never two overlapping (estimate).

### 6.3 Godot 4.7.2 API: exact usage (verified by `godot_test/probe.gd` and `run_snippet.gd`)

Probe results:
- `probe.gd`: clips were OGG stems with `bpm 120`, `bar_beats 4`, `beat_count 16`, nested in `AudioStreamSynchronized`. A switch under the ANY→ANY NEXT_BAR rule, requested at t = 0.70 s, took effect at the next bar (metronome read 2.02 s). Setting both layers to −60 dB dropped Master from −15.4 to −75.3 dB by the next reading, 0.5 s later.
- `run_snippet.gd` runs the code below verbatim (BPM 120). The specific explore→combat NEXT_BEAT rule overrode ANY→ANY: requested at 0.91 s, switched on the beat at 1.0 s (metronome 1.025 s). The layer ramp reached gain 0.36 after 0.7 s of a 2.0 s ramp.
- `parameters/switch_to_clip` exists as an enum property on the player.

```gdscript
# audio/music_director.gd (sketch; every call below exists in 4.7.2)
const BPM := 140.0
var player := AudioStreamPlayer.new()     # bus &"Music", process_mode ALWAYS
var metro := AudioStreamPlayer.new()      # silent 1-bar OGG at 140 BPM, loop, volume_db -80: the beat clock
var stream := AudioStreamInteractive.new()
var syncs := {}                           # clip name -> AudioStreamSynchronized
var gain := {}                            # "clip:k" -> current linear gain

func build(clips: Dictionary) -> void:     # {"explore": [AudioStreamOggVorbis, ...], ...}
	stream.clip_count = clips.size()
	var i := 0
	for clip_name in clips:
		var s := AudioStreamSynchronized.new()
		s.stream_count = clips[clip_name].size()
		for k in s.stream_count:
			s.set_sync_stream(k, clips[clip_name][k])           # OGG: bpm=140, bar_beats=4, beat_count=64, loop=true
			s.set_sync_stream_volume(k, 0.0 if k == 0 else -60.0)
		stream.set_clip_name(i, StringName(clip_name))
		stream.set_clip_stream(i, s)
		syncs[clip_name] = s
		i += 1
	stream.add_transition(AudioStreamInteractive.CLIP_ANY, AudioStreamInteractive.CLIP_ANY,
		AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR, AudioStreamInteractive.TRANSITION_TO_TIME_SAME_POSITION,
		AudioStreamInteractive.FADE_CROSS, 2.0, false, -1, false)
	# explore(0) -> combat(1): fast response (specific pair overrides ANY->ANY)
	stream.add_transition(0, 1, AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT,
		AudioStreamInteractive.TRANSITION_TO_TIME_SAME_POSITION, AudioStreamInteractive.FADE_CROSS, 1.0, false, -1, false)
	player.stream = stream

func switch_to(clip: StringName) -> void:  # call only after player.play()
	(player.get_stream_playback() as AudioStreamPlaybackInteractive).switch_to_clip_by_name(clip)
	# equivalent: player.set(&"parameters/switch_to_clip", clip)

func set_layer(clip: String, k: int, on: bool, delta: float) -> void:   # call every frame
	var key := "%s:%d" % [clip, k]
	var g: float = move_toward(gain.get(key, 0.0), 1.0 if on else 0.0, delta / (4.0 * 60.0 / BPM))
	gain[key] = g
	syncs[clip].set_sync_stream_volume(k, linear_to_db(maxf(g, 0.001)))  # ramp in linear gain: no dB zipper

func seconds_to_next_beat() -> float:      # hardware-clock method from the Godot docs [G9]
	var pos := metro.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var beat := 60.0 / BPM
	return beat - fmod(pos, beat)
```

- **Stinger:** `get_tree().create_timer(seconds_to_next_beat(), true, false, true).timeout.connect(stinger_player.play)`. The last argument (`ignore_time_scale`) keeps stingers on the beat during hit-stop.
- **Metronome resync:** restart `metro.play()` whenever the clip index changes through a START transition.
- **Playlist:** `AudioStreamPlaylist` (shuffle, loop, `fade_time` 0–1 s, up to 64 streams; verified) can be an `explore` clip for variety (Wwise style [G11]).
- **Clip limits:** Interactive holds up to 63 clips and Synchronized up to 32 streams (verified hints).

### 6.4 MiniMax models: status and use (2026-11-01)

| Capability | Model / endpoint | Facts | How we use it |
|---|---|---|---|
| Text-to-speech | `POST https://api.minimax.io/v1/t2a_v2`, models `speech-2.8-hd` / `speech-2.8-turbo` (legacy 2.6, 02, 01) [C2][C3] | text < 10,000 chars; pause markers `<#0.3#>` (0.01–99.99 s); 2.8-only interjection tags such as `(breath)`, `(gasps)`, `(groans)`; `voice_setting`: speed 0.5–2, vol (0, 10], pitch −12…12 st, emotion `happy/sad/angry/fearful/disgusted/surprised/calm` (`whisper` not on 2.8); `voice_modify`: pitch/intensity/timbre ±100, `sound_effects` ∈ {`spacious_echo`, `auditorium_echo`, `lofi_telephone`, `robotic`}; `audio_setting`: 8–44.1 kHz, mp3/pcm/flac/wav/opus, mono or stereo; 40 languages; 60 RPM [C3][C4] | Cockpit AI: `speech-2.8-hd`, emotion `calm` (`fearful` for critical alarms), `sound_effects: "robotic"`, wav 44.1 kHz mono. HQ radio: `lofi_telephone`. Voice Design (20 RPM [C4]) gives a unique voice; system voices include e.g. `English_Lucky_Robot` [C3] |
| Music generation | `POST /v1/music_generation`, `music-3.0` / `music-2.6` / `music-cover` (120 RPM; free tiers 3 RPM) [C1] | Instrumental: `is_instrumental: true` + prompt 1–2,000 chars; lyrics 1–3,500 chars; output hex or URL (URLs expire in 24 h). **Since 2026-08-20 the paid APIs are unavailable to new users and the free APIs are discontinued** [C1][C2] | Usable only by existing paying accounts or via MiniMax Audio (web). Not for stems: it outputs a full mix, so split with Demucs |
| Open weights | MiniMax-Music3 on Hugging Face [C5] | 8B global + 0.6B local LLM + 2.4B flow matching; 32 kHz 16-bit stereo; songs up to 5 min (hard cap 9,000 frames at 25 fps = 6 min); prompt ≤ 5,000 tokens; **inference requires CUDA** (fits under 24 GB; ~22 GB with CPU offload; 8 GB with group offload); tempo/key "may not always match". Licence: display "MiniMax-Music3" in commercial products, authorization above $20 M revenue, and AUP §11 requires disclosing machine-generated content | Cannot run on the M1 Max. Needs a CUDA box. Prompt with "Global Metadata / Vocal Details / Arrangement" sections, e.g. "Instrumental. Genre: industrial hybrid orchestral. BPM: 140. Key: D minor. Taiko + trap drums, distorted analog bass 16ths, brass stabs every 2nd bar, choir pads, anvil hits. Loopable, no intro, no outro." |
| MiniMax Audio (web app) | https://www.minimax.io/audio [C6] | output may carry embedded identifiers/watermarks; the user must label AI output | Draft music if the API is unavailable; credit "AI-generated (MiniMax)" |
| Internal YS-API (MiniMax intranet) | `/minimax_tts`, `/suno`, `/kling_video_to_audio` [C7] | reachable 2026-11-01 (`get_configs` → `success: true`); `/minimax_tts` answers `text不能为空` (text required); other parameters unverified | Fastest route for voice lines. **Check the licence/terms of `/suno` outputs with the platform owners** before shipping music from it |

---

## 7. Audio autoload skeleton (fits CONTRACTS §3; estimate)

```gdscript
extends Node   # autoload "Audio" (audio/audio.gd), process_mode ALWAYS
## Data: res://audio/events/<id>.tres (class SoundEvent: streams: AudioStreamRandomizer, bus, klass (C0..C7),
## priority, max_instances, min_interval_ms, far_variant: AudioStream, far_delay: bool, near_socket: StringName).

func play(id: StringName, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	var ev: SoundEvent = _events.get(id)
	if ev == null:
		_warn_once(id)                       # never silently swallow; one warning per id
		return
	if not _rate_ok(ev):                     # caps and min interval (§3)
		return
	if at == Vector3.INF:
		_poly_2d.play_stream(ev.streams, 0.0, volume_db, pitch, AudioServer.PLAYBACK_TYPE_DEFAULT, ev.bus)
		return
	var d := _listener_pos().distance_to(at)
	var p := _acquire_3d(ev.priority - _predicted_loss_db(ev.klass, d) / 3.0)   # loss in dB (positive); steal or null
	if p == null:
		return
	_apply_class(p, ev.klass)                # unit_size/max_db/max_distance/filter/panning/doppler (§5.4)
	p.global_position = at
	p.bus = ev.bus
	p.stream = ev.streams if d < 500.0 or ev.far_variant == null else ev.far_variant
	p.volume_db = volume_db
	p.pitch_scale = pitch
	var delay := clampf((d - 120.0) / 343.0, 0.0, 2.5) if ev.far_delay else 0.0
	if delay > 0.0:
		get_tree().create_timer(delay, true, false, true).timeout.connect(p.play)
	else:
		p.play()

func music_intensity(level: float) -> void:   # forwards to MusicDirector: clip choice plus stem thresholds (§6.2)
	_music.set_intensity(clampf(level, 0.0, 1.0))

func stinger(id: StringName) -> void:        # beat-quantized, max 1 per 2 s (§6.2)
	_music.stinger(id)
```

The `_ready()` steps:
1. Build the buses (§5.1).
2. Create the pools (§5.6).
3. Connect the Events signals to ids (§3).
4. Apply Settings volumes on `Settings.changed`.
5. Create and make current the `AudioListener3D` (§5.5).

---

## 8. Risks

1. **Licence breach by redistribution**: raw Sonniss/Pixabay/Adobe files in the public repo [B4][B5][B6]. Mitigation: git-ignored `art/audio_src/`, manifest audit, CC0/CC-BY-only commits.
2. **MiniMax music access**: paid API closed to new users, free API discontinued [C1]; Music3 needs CUDA [C5]; `/suno` licensing unknown [C7]. Mitigation: CC0/CC-BY music first, AI music as an upgrade.
3. **AI labelling** required by the Music3 AUP §11 and MiniMax Audio terms [C5][C6]: add an "AI-generated audio" credits line.
4. **Interactive-music engine limits** (no position, no signal, no nesting, instant volumes) [G2][G3][G12]. Mitigation: the §6.3 pattern.
5. **Area3D audio in 4.7** (area_mask default 0, reverb-bus bug) [G13]. Mitigation: listener-zone snapshots.
6. **Over-ducking**: Godot's compressor gives ~2× textbook gain reduction (§5.2). Use the formula and measure.
7. **Doppler artifacts** (+6.7 to +15 st at 110–200 m/s) if listener tracking is on. Keep it disabled.
8. **Voice storms** from 16-Ripper packs, the 900 m/s gatling and 12-missile salvos. Mitigation: §5.6 caps, merging, loops.
9. **Inter-sample peaks**: sample-peak-normalized renders overshot by 1.6 dB (measured). Normalize to −1 dBTP; Master limiter at −1 dB.
10. **Readability vs. weight**: sub-heavy layers can mask telegraphs. Enemy telegraphs get priority 80 and their own bands (Mantis glint 2.5 kHz, Harrier screech).
11. **Snippet-only sources** (fetch blocked): Sonniss, Pixabay and Adobe licences, the Titanfall 2 articles, BF6, Tallbeard. Re-read those pages in a browser before shipping.

---

## 9. Sources

Sound design
- A1 Respawn, "Inside Development – Echo of Titans // Titanfall 2" (Rick Hernandez): https://www.respawn.com/news/inside-development-echo-of-titans-titanfall-2 (now 404; quoted from the search index; video: https://www.youtube.com/watch?v=a0Bd-cja4gc)
- A2 A Sound Effect, "Creating Titanfall 2's Terrific Sci-Fi Sound": https://www.asoundeffect.com/titanfall-2-sound/ (403 to our fetcher; facts as recorded in `feel-mech-games.md` [TF16])
- A3 Kota Hoshino (FromSoftware) on X, 2023-09-02: https://x.com/kota_hoshino/status/1697836830945919079
- A4 Edinburgh Napier, "Beasts, Bots & Booms: Scott Gershin on the Sonic World of Pacific Rim": http://blogs.napier.ac.uk/sounddesign/2025/04/28/beasts-bots-booms-scott-gershin-on-the-sonic-world-of-pacific-rim/
- A5 Designing Sound, Erik Aadahl on Transformers: https://designingsound.org/2010/03/25/erik-aadahl-special-the-sound-design-of-transformers-exclusive-interview/
- A6 FilmSound.org, Ben Burtt interview (lightsabers): http://www.filmsound.org/starwars/burtt-interview.htm
- A7 Edinburgh Napier, Ben Minto guest lecture (Battlefield 4 runtime explosions, HDR, War Tapes): http://blogs.napier.ac.uk/sounddesign/2025/07/21/ben-mintos-guest-lecture-the-complexity-and-craft-of-runtime-sound-design-in-video-games/
- A8 Game Developer, Hawken art and design (Khang Le): https://www.gamedeveloper.com/business/inside-the-striking-art-and-design-of-i-hawken-i- (via `feel-mech-games.md` [HW1])
- A9 Pro Sound Effects, Mark Kilborn gunshot layers: https://blog.prosoundeffects.com/how-to-sound-design-first-person-shooter-gunshot-sound-effects-with-mark-kilborn
- A10 Everything Is Noise, "Sound Test: DOOM (2016)": https://everythingisnoise.net/features/sound-test-doom-2016/
- A11 Soaring Sound Factory (Yukitoshi Baba), ガンダムの効果音を作る: https://soaring-sound-factory.com/gandam/
- A12 Edinburgh Napier, Matthew Collings on creature sound design (2026-09-07): http://blogs.napier.ac.uk/sounddesign/2026/09/07/creature-sound-design/
- A13 A Sound Effect, "Behind Battlefield 6's Gritty Game Audio": https://www.asoundeffect.com/battlefield-6-game-audio/ (search summary only)
- A14 Doug James, Atmospheric Absorption demo (ISO 9613-1): https://dougjam.github.io/demos/atmospheric-absorption/
- A15 FAA, Human Factors guidance, Alerting: https://hfcc.dot.gov/publications/docs/GeneralGuidance/zz_FAA_GeneralGuidanceDoc_Chapter_04_Section_01.html
- A16 Designing Sound, Garry Taylor (Sony ASWG) on loudness: https://designingsound.org/2012/07/30/video-games-and-loudness-standards-interview-with-sonys-garry-taylor/
- A17 Andy Farnell, *Designing Sound*, code examples index: https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/index.html
- A18 rFXGen (zlib): https://github.com/raysan5/rfxgen
- A19 Spotify pedalboard (GPL-3.0): https://github.com/spotify/pedalboard
- A20 Demucs (MIT): https://github.com/facebookresearch/demucs
- A21 Audiokinetic, Integrating Listeners: https://www.audiokinetic.com/library/edge/?source=SDK&id=soundengine_listeners.html
- A22 Epic forums, 3rd-person listener (panning from camera, attenuation from character): https://forums.unrealengine.com/t/change-audio-listener-in-c/408596
- A23 r/godot PSA, reverb Area3D needs `audio_bus_override`: https://www.reddit.com/r/godot/comments/1wxju2k/psa_in_godot_4_a_sound_inside_an_area3d_with_a/ (search summary)

Sourcing
- B1 Kenney audio: https://kenney.nl/assets/category:Audio (pack pages list file counts and "Creative Commons CC0")
- B2 OpenGameArt: https://opengameart.org/content/50-cc0-sci-fi-sfx · https://opengameart.org/content/100-cc0-sfx · https://opengameart.org/content/100-cc0-sfx-2 · https://opengameart.org/content/the-free-firearm-sound-library · https://opengameart.org/content/cc0-music-0
- B3 Freesound API: https://freesound.org/docs/api/overview.html · https://freesound.org/docs/api/authentication.html · https://freesound.org/docs/api/terms_of_use.html
- B4 Sonniss: https://sonniss.com/gameaudiogdc/ · https://sonniss.com/gdc-bundle-license/ · https://gdc.sonniss.com/ (403 to our fetcher; terms from search results)
- B5 Pixabay: https://pixabay.com/service/license-summary/ · https://pixabay.com/service/faq/ (snippets)
- B6 Adobe Audition SFX: https://www.adobe.com/products/audition/offers/adobeauditiondlcsfx.html (snippet)
- B7 BBC Sound Effects licensing: https://sound-effects.bbcrewind.co.uk/licensing · RemArc summary: https://sonicstate.com/news/2018/04/18/the-bbc-are-offering-16000-free-sound-effects/ · https://news.ycombinator.com/item?id=16864050
- B8 Tallbeard Music Loop Bundle: https://tallbeard.itch.io/music-loop-bundle (listing snippet)
- B9 incompetech (Kevin MacLeod): https://incompetech.com/music/royalty-free/music.html
- B10 Scott Buckley, Using This Music: https://www.scottbuckley.com.au/library/using-this-music/
- B11 HoliznaCC0: https://freemusicarchive.org/music/holiznacc0/

MiniMax
- C1 Music Generation API: https://platform.minimax.io/docs/api-reference/music-generation
- C2 Models: https://platform.minimax.io/docs/guides/models-intro
- C3 Synchronous TTS (t2a_v2): https://platform.minimax.io/docs/api-reference/speech-t2a-http
- C4 Rate limits: https://platform.minimax.io/docs/guides/rate-limits
- C5 MiniMax-Music3: https://huggingface.co/MiniMaxAI/MiniMax-Music3 · licence: https://huggingface.co/MiniMaxAI/MiniMax-Music3/raw/main/LICENSE
- C6 MiniMax Audio Music Creation Terms: https://www.minimax.io/audio/doc/terms-of-service-music.html
- C7 YS-API intranet (`ys-api` skill catalogue; connectivity checked 2026-11-01): https://ys-api.xaminim.com/api

Godot (4.7.2-stable)
- G1 audio_stream_player_3d.cpp: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/audio_stream_player_3d.cpp
- G2 audio_stream_interactive.cpp: https://github.com/godotengine/godot/blob/4.7.2-stable/modules/interactive_music/audio_stream_interactive.cpp
- G3 audio_stream_synchronized.cpp: https://github.com/godotengine/godot/blob/4.7.2-stable/modules/interactive_music/audio_stream_synchronized.cpp
- G4 audio_server.cpp (`_mix_step`): https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.cpp
- G5 audio_effect_compressor.cpp: https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/effects/audio_effect_compressor.cpp
- G6 audio_stream_player_internal.cpp: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/audio/audio_stream_player_internal.cpp
- G7 Class docs: https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/AudioEffectHardLimiter.xml · AudioEffectLimiter.xml (deprecated) · AudioEffectCompressor.xml
- G8 Audio buses: https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html
- G9 Sync the gameplay with audio and music: https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
- G10 Importing audio samples: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html
- G11 PR #64488 "Add interactive music support" (reduz): https://github.com/godotengine/godot/pull/64488
- G12 Godot forum, switching a nested AudioStreamInteractive: https://forum.godotengine.org/t/how-to-switch-clip-of-an-audiostreaminteractive-inside-another-audiostream/85757
- G13 Issues and PRs: https://github.com/godotengine/godot/issues/96480 · https://github.com/godotengine/godot/issues/120509 · https://github.com/godotengine/godot/issues/120546 · https://github.com/godotengine/godot/pull/107679
- G14 Local verification (this dossier): `tmp/research/audio-music/probe/classdb_dump.txt`, `godot_test/{probe,buses,duck,params,run_snippet,music_director_snippet}.gd`, `scripts/synth_probe.py`
- G15 Godot 4.7 release notes: https://godotengine.org/releases/4.7/

Internal cross-references: `docs/SPEC.md` §2–§8, `docs/FEEL.md`, `ref/research/juice-impact.md` (§5, §8, §9, §11; [S27][S31][S41][S45]), `ref/research/feel-mech-games.md` ([TF16], [HW1]).
