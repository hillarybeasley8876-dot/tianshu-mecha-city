# Audio credits — MECHA CITY / 天枢 TIANSHU

Every file under `game/audio/` is listed in `game/audio/audio_manifest.csv` with its id, source,
licence, author and the layers it is built from. Nothing here has an unknown source.

The manifest names **every** pack a file layers, not just its main source: a sound that mixes our
synthesis with a CC0 recording lists both, because that is what is actually in the file.

## Sound effects — recorded CC0 layers over our own synthesis

The bank follows rule 11 of `ref/research/audio-music.md`: **record or borrow metal, debris,
explosions and creature bases; synthesise what synthesises well.** So the transient, body, debris,
gunfire, mechanism and creature layers are real recordings, and the sub, servo, beam, charge, saber,
whoosh, alarm and UI layers are numpy/scipy renders of the dossier's §4 recipes.

| Pack | Author | Licence | Used for |
|---|---|---|---|
| [Kenney — Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | Kenney | CC0 1.0 | 42 ids — metal and plate impacts, explosion body, force-field hums: `footstep_hero`, `melee_light`, `melee_heavy`, `land_heavy`, `servo_move_l`, `rifle_fire`, `block`, `jugg_plate_break`, `ward_up_loop`, `boss_kill` |
| [Kenney — Digital Audio](https://opengameart.org/content/63-digital-sound-effects-lasers-phasers-space-etc) | Kenney | CC0 1.0 | 2 ids — energy discharge under the synthesised beams: `rifle_hit`, `fins_hit` |
| [OGA — 50 CC0 Sci-Fi SFX](https://opengameart.org/content/50-cc0-sci-fi-sfx) | rubberduck | CC0 1.0 | 9 ids — explosion and rocket bodies: `kill_large`, `kill_small`, `missile_hit`, `lance_fire`, `finisher`, `plunge_land`, `jugg_slam`, `spire_destroyed`, `rifle_stage2_hit` |
| [OGA — 100 CC0 SFX](https://opengameart.org/content/100-cc0-sfx) | rubberduck | CC0 1.0 | 57 ids — metal clank, container slam, glass, stone, debris, bell, switches: `footstep_hero`, `melee_light`, `reload`, `weapon_switch`, `debris_metal`, `glass_shatter`, `collapse`, `hydraulic_release`, `parry_perfect`, `last_stand`, `boss_kill` |
| [OGA — 100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0 1.0 | 57 ids — metal hits, stones, thunder and the machine / traffic / room beds: `amb_tunnel_hum`, `amb_street`, `amb_wind_high`, `amb_storm_crown`, `debris_concrete`, `land_light`, `hurt_light`, `ward_break`, `boss_kill` |
| [OGA — 80 CC0 Creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 1.0 | 22 ids — every HUSK vocal base (roar, screech, chitter, grunt, breath): `ripper_leap_tell`, `ripper_death`, `mantis_grab_tell`, `spitter_charge`, `harrier_screech`, `jugg_roar`, `titan_roar`, `boss_roar`, `titan_breath_beam`, `spire_pulse_loop`, `boss_kill`, `last_stand` |
| [OGA — 202 More Sound Effects](https://opengameart.org/content/202-more-sound-effects) | OwlishMedia | CC0 1.0 | 3 ids — latch / lock mechanisms: `block`, `missile_launch`, `reload` |
| [OGA — Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack) | artisticdude | CC0 1.0 | 4 ids — air swish under the saber and the missile launch: `saber_swing`, `saber_swing_2`, `saber_swing_3`, `missile_launch` |
| [OGA — The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (submitted to OGA by bart) | CC0 1.0 | 15 ids — gunfire transients and tails, explosion crack: `gatling_fire_loop`, `gatling_fire_accent`, `gatling_tail`, `rifle_fire`, `rifle_stage2_hit`, `shockcore`, `missile_hit`, `kill_large`, `lance_fire` |

Every one of these is **CC0 1.0**, and every one has a licence record on disk under
`art/audio_src/<pack>/` (an `oga_sources.json` sidecar written by `tools/sfx/oga_fetch.py`, or the
archive's own `License.txt`). `tools/sfx/run.sh credits_check.py` joins those records to the
shipped files, this table and `audio_manifest.csv`, and fails if any of the four disagree. No
CC-BY or non-commercial material ships in this build, so the credits screen has no mandatory
attribution rows — the names above are given as a courtesy and because they earned it.

Downloads live in `art/audio_src/<pack>/` and are git-ignored; only the layered composites under
`game/audio/sfx/` are committed. Extraction is done by `tools/sfx/unpack.py`, which reads audio and
licence members only, flattens names, verifies each file's magic bytes and never executes anything
from an archive.

## Music — sourced CC0 tracks

The adaptive score is real music, not synthesis. Six CC0 tracks were chosen, measured for tempo and
key (`tools/sfx/run.sh analyse_music.py`), trimmed to a whole number of their own bars, equal-power
crossfaded so each loops seamlessly, and loudness-matched to −20 LUFS-I / −1.5 dBTP
(`tools/sfx/run.sh music_tracks.py`). The clip graph (`game/audio/music_director.gd`) crossfades
between full mixes on each clip's own bars — the tracks are not one key/tempo family, so vertical
stem layering is not used.

| Clip | Track | Author | Licence |
|---|---|---|---|
| `explore` | [Covert Operations](https://opengameart.org/content/covert-operations) | artisticdude | CC0 1.0 |
| `tension` | [Technological Menace](https://opengameart.org/content/technological-menace) | Umplix | CC0 1.0 |
| `combat` | [Epic Combat](https://opengameart.org/content/epic-combat) | Chester01 | CC0 1.0 |
| `boss` | [Boss Battle #2 [Symphonic Metal]](https://opengameart.org/content/boss-battle-2-symphonic-metal) | nene | CC0 1.0 |
| `spire_cleared` | [Heroic Pressure (Loop)](https://opengameart.org/content/heroic-pressure-loop) | StarNinjas | CC0 1.0 |
| `victory` | [Forgotten Victory](https://opengameart.org/content/forgotten-victory) | yd | CC0 1.0 |

Each row is the track's own OpenGameArt node — the same title, page, author and licence the
manifest carries for that clip, read from the fetch record rather than retyped. All six are CC0 1.0
(public domain dedication); attribution is given here as a courtesy, not as a licence requirement.
The short **stingers** and the silent beat-clock metronome remain our own synthesis
(`tools/sfx/run.sh music.py`).

## Cockpit AI voice — AI-generated (minimax)

The 47 cockpit AI callouts in `audio/voice/*.ogg` are **AI-generated speech**, produced with
minimax's text-to-speech service (model `speech-2.8-hd`, voice `female-shaonv`, emotion `calm`,
`voice_modify.sound_effects = "robotic"`) through the internal `ys-api` platform, then processed
into a cockpit-radio character by `tools/sfx/run.sh voice.py` (190 Hz–5.2 kHz band limit, 55 Hz ring
modulation, tanh drive, squelch hiss, true-peak normalised).

Per minimax's terms, AI-generated audio must be labelled as such. The credits screen and this file
carry that label. If the build ships the voice lines, the credits screen must show:

> Cockpit AI voice: AI-generated speech (minimax), processed in-house.

Raw MP3 downloads live in `art/audio_src/voice/` and are git-ignored; only the processed OGGs are
committed.

## Attribution required by this build

None. Every third-party sound and every music track ships under CC0 1.0; the rest is our own
synthesis or AI-generated and labelled as such.

## Rebuilding

```
tools/sfx/unpack.py <archive> art/audio_src/<pack>     # extract a downloaded pack safely
tools/sfx/oga_fetch.py <slug> --dest art/audio_src/... # fetch + record an OGA node's licence
tools/sfx/run.sh build.py                              # the SFX bank + manifest
tools/sfx/run.sh music_tracks.py                       # the six adaptive music clips
tools/sfx/run.sh music.py                              # stingers + silent beat clock
tools/sfx/run.sh voice.py                              # cockpit AI lines (needs ys-api)
tools/sfx/run.sh measure.py --csv tmp/audio/bank_qa.csv
```
