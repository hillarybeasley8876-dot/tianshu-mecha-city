# trailer r1 — lead brief: a 60–90 s in-engine highlight trailer of 天枢 TIANSHU

## Why
The user asked when there will be "炫酷的实机": real in-game footage of the game being cool. Every
capture so far is a test harness: a side camera, a frozen street camera, a dolly. This job makes the
first piece the user would actually show someone. It must be the REAL game: the real mech, enemies,
weapons, FX, post stack and sound, recorded from the engine. Nothing is mocked or composited from
renders.

## What to deliver
- `captures/trailer/TIANSHU_trailer_v1.mp4`
  - 60–90 s at 1920×1080, 60 fps, H.264 (CRF 16 or better, yuv420p), AAC 320 k.
  - Loudness −14 LUFS integrated, true peak ≤ −1 dBTP.
  - 16:9 exactly: crop or scale, never stretch. **Check the movie's real frame size first**: on this
    Retina Mac the game window has come out 3024 × 1898 (16:10) in earlier captures.
- `tools/trailer/` and `game/trailer/`, so the whole thing re-renders from one command. The lead
  will re-cut it as the game improves:
  - `tools/trailer/render_all.sh` renders every shot;
  - `tools/trailer/cut.py` builds the edit with ffmpeg from a shot list (`game/trailer/shots.json`:
    source, in/out, speed, transition, title);
  - `tools/trailer/sheet.py` makes contact sheets.
- `status/trailer.md`: what each shot is, how to re-render it, and what you could not get.

## How the footage is made (use what exists)
- **Recording.** `tools/godot.sh movie --movie=<abs .avi> --timeline=res://… [--scene=…] [game flags]`
  runs `tools/autoplay.gd` under Godot's Movie Maker at a locked 60 fps.
  - Pass `--render-scale=1` for full quality; speed does not matter offline.
  - Autoplay timeline commands are in the header of `game/tools/autoplay.gd`: press / release / tap
    actions, look, look_rate, player method calls.
  - Input action names are in `game/core/input_setup.gd`: boost, melee, guard, overdrive,
    camera_toggle, lock_on, fire, weapon_next…
  - Game flags: `--god`, `--no-enemies`, `--enemies=type:count`, `--spawn=x,y,z,yaw`, `--skip-menu`,
    `--quality=high`.
- **Existing scripted material to build on:**
  - `game/player/model/hero3/tests/timeline_combat.json`: melee combo, aimed fire, guard / parry,
    dash / slide.
  - `timeline_drop.json`: a 20 m drop and the heavy landing.
  - `game/enemies/boss/tests/boss_showcase.tscn` + `boss_showcase_timeline.json`: the Brood Titan's
    REAL brain, every attack, the phases and the death, in about 2.5 min.
  - `game/flow/tests/e2e_movie.json` / `e2e_district_movie.json`: flow's E2E bot fighting through the
    city with the real weapons.
  - `world/art/tests/probe_kit_layers.gd --probe-dolly=<cam>:<secs>`: city-art's camera dolly.
  - Street cameras: `tools/citykit/cams_street.json`. Vistas: `data/vistas.json`.
- **Cinematic cameras** (orbit, crane, dolly, a close-up on the mech) for the non-gameplay shots go in
  `game/trailer/` as your own small camera rig, driven by your shot list.
- **A moment the game cannot script** (a guaranteed perfect dodge or parry, a full overdrive meter):
  - first look for an existing hook;
  - else add a minimal `debug_` method to the owning unit's file. Those units are idle: melee-defense,
    mech-move, skills, weapons, enemies. Run that unit's tests after the change.
  - Never change gameplay numbers.

## Shot list (the spine; reorder or swap with evidence that it plays better)
| # | shot | source | len |
|---|---|---|---|
| 1 | cold open: black, a servo whine, the Tianshu's eye and cockpit light up in a slow close-up | trailer cam on hero3 | 3–4 s |
| 2 | the city at dusk: a slow crane past the T1 towers (lit windows, the new skyline) toward the Spire beam | trailer cam, HUD off | 5–6 s |
| 3 | drop-in: a 40 m fall off a skybridge onto the A5 deck; the heavy landing, shockwave, dust, camera dip | autoplay, game camera | 3–4 s |
| 4 | combat montage vs a pack (`--god`): assault boost into melee l1→l3 + charge slash; a perfect dodge into witch time; rifle stage-2 piercing a line; gatling spin-up; missile salvo; guard + perfect parry on a juggernaut slam; overdrive + the lance ultimate | autoplay timelines + flow's E2E bot | 25–35 s in 2–4 s cuts |
| 5 | first person: 2–3 s of gatling fire from the cockpit (the user asked for switchable 1st / 3rd person) | camera_toggle | 2–3 s |
| 6 | flight: boost up a tower face and across the roofs (the roof plant is visible now), an air combo on a harrier | autoplay | 4–6 s |
| 7 | hive spire: pods bursting, the spire falling | flow E2E / spire | 3–5 s |
| 8 | the boss: the Brood Titan's reveal and roar, the breath beam dodged, a core shattered, the stagger, the finisher | boss_showcase | 12–18 s |
| 9 | end card: 天枢 TIANSHU over the city, `未来城市 · 机甲动作`, `Godot 4.7 实机录制 In-engine footage` | trailer cam + ffmpeg drawtext (`/System/Library/Fonts/Hiragino Sans GB.ttc`) | 4 s |

## The look and the edit
- **Cut on the music.** Use `game/audio/music/combat_mix.ogg` for the montage and `boss_mix.ogg` for
  the boss, with a stinger from `game/audio/music/stingers/` on the end card. The game's own SFX
  stay in, ducked about 6 dB under the music except on the big hits.
- **Slow motion only where it sells a hit:** the dodge, the parry, the core shatter. Retime in the
  edit; speed ramps are fine.
- **HUD.** Keep the combat HUD in the gameplay shots (it proves this is the game), off in the
  cinematic shots. **Hide the tutorial key prompts** (the "W 移动 MOVE" / "MOUSE 环视 LOOK" boxes):
  they read as a prototype. If the HUD has no switch for them, add a launch flag in `ui/` (hud is
  idle) and run the hud tests.
- **No visible defects.** Discard any take that has:
  - a camera inside geometry;
  - a frozen frame or a black frame;
  - an engine error (autoplay exits 1 on errors);
  - debug text;
  - an enemy T-posing.

  Route the bug to its owner in `## Requests`.
- **Variety of framing:** the game camera, a low hero angle, a wide shot, a close-up. No more than two
  cuts in a row from the same kind of camera.

## Checkpoints (the lead reviews each one; keep going while it does)
1. **About 60 min in:** the pipeline end to end, one shot rendered and cut into a 10–15 s
   `captures/trailer/test_v0.mp4`, plus its contact sheet (one frame every 0.5 s). Note it in
   `status/trailer.md`.
2. **Raw shots:** every shot's contact sheet in `captures/trailer/sheets/`.
3. **v1:** the cut, plus a sheet of one frame per shot.

## Rules
- **The city is frozen for this job.** Do not rebuild tiles, re-bake the settle cache or touch
  `world/kit/`, `world/city/` or `world/art/` (city-art is finishing its r13 perf round in the
  same tree).
- Movie runs share the machine-wide heavy slots (`tools/slots.py`); keep each take short.
- New files under `game/trailer/` and `tools/trailer/` only, each under about 400 lines.
- Commit per step with an explicit path list.
- Do not commit the .avi / .mp4 files; they live in `captures/` (ignored).
