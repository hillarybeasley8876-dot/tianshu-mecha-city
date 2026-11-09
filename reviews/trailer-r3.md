# trailer r3 — lead brief: a gameplay showcase reel. 打怪 / 技能展示 / 机制展示 (fighting monsters, skills, mechanics)

## Why
The user asked: **"打怪 技能展示 机制展示都要录制"** — fighting monsters, a skill showcase and a mechanics
showcase must all be recorded. The 60 s trailer (v2, rendering now in `~/m/trailer-r2b` by the lead —
do not touch that worktree) shows these only as 2.5 s flashes. This round makes a separate, longer
**showcase reel** where every verb is shown long enough to understand it.

## The user's machine — this round only
The user said "现在录，我离开电脑": the screen is ours while they are away. For this round ONLY, run
windowed commands as `MC_WINDOW_OK=1 tools/godot.sh shot|drive|movie ...`. Rules:
- One Godot window at a time from you. The lead's trailer render may still be running for a few
  minutes; it uses its own worktree.
- You are the only M78 worker. Author in the live tree (`game/trailer/**`, `tools/trailer/**` are yours);
  nobody else is editing it.
- Never `open` the exported app, never `screencapture`.

## Deliverable
`captures/trailer/TIANSHU_showcase.mp4` — 1920×1080, 60 fps, H.264, the same loudness targets as the
trailer, **4–7 minutes**, three chapters. Each segment is **6–12 s**, performs its verb clearly 2–3
times, and carries a lower-third title label (PIL, as `tools/trailer/titles.py` does): the Chinese and
English in-game name (take them from `game/ui/hud_locale.gd` and the HUD) plus the key, e.g.
`技能 · <中文名> <ENGLISH NAME>  [Z]`. A 1.5 s chapter card opens each chapter. The HUD stays on (it shows
the meters and prompts). Build it with the same pipeline: a `game/trailer/showcase.json` spec,
timelines under `game/trailer/showcase/`, rendered with `tools/trailer/render_all.py --spec …` and cut
with `cut.py` (add a `--spec`/output option if it lacks one).

### Chapter 1 — 打怪 (one segment per enemy)
- Ripper swarm: melee combo and gatling into a pack.
- Mantis: block, then a perfect parry of its telegraphed strike.
- Spitter: dodge its lob, then a charged rifle shot.
- Harrier: lock-on and a Hailstorm salvo at fliers.
- Juggernaut: stagger it, then an execution.
- A hive spire: shoot its pods, open the core, and the collapse (flow's `hive_collapse.gd`) in the
  un-stubbed flow, if it films cleanly; otherwise film the pods and core and say why.
- The Brood Titan: 20–30 s across its phases (`game/trailer/boss_shot.tscn` is your wrapper).

### Chapter 2 — 技能展示 (every skill in SPEC §3)
Skyhook anchor (E), Rift Step (C), Corona Fins send (Z tap) and the ward barrier (Z hold), Shockcore
Burst (X), Undertow Well (G), Zenith Overdrive (V hold) then the Lance (V), Hailstorm missiles (hold to
paint, release). Use enemies as targets so each skill visibly does something to them.

### Chapter 3 — 机制展示 (movement, defence, weapons, camera)
- Dash in several directions; the boost skate; the slide.
- Assault boost and the ram kick.
- Jump, hover, a boost-jump onto a +40 m deck; a heavy landing.
- Flight: double-tap, climb, cruise, bank, flight boost, descend, land (mech-move r6 flags;
  hero-v3 r8/r9 gave it the lean and the nozzles).
- A perfect dodge → witch time.
- Guard: block, perfect parry, the catch field (hold ≥ 0.3 s).
- Melee: the L1–L3 combo, a charged slash, a lunge, an air combo or plunge, an execution.
- Weapons: rifle charge shot, the gatling spin-up and a perfect vent, a weapon swap.
- Lock-on and target switch.
- First person: toggle, fire, look around the cockpit, toggle back.

## How to film
Use your camera kit (orbit / crane / chase / low / locked-off wide) and stages (A6 Sky Garden main,
H0 pier alternate; A1 container yard for the opening fights is fine). Light: pick the `--tod` per
segment so the hero is never a silhouette (city-art r15's sky). `--god` and `--trailer-pack` as in r2.
If a verb does not work or reads badly on screen, do not fake it: film what it does, label it, and
list it under Known issues with the frame — the lead routes it.

## Gates
- Every take `DRIVE done … errors=0`; `framing_report.py` 0 failed over the cut windows (relax the
  enemy-visible rule for chapter 3 movement segments, and say which).
- The reel's ffprobe, loudness, 0 black and 0 frozen frames.
- `captures/trailer/sheets/TIANSHU_showcase_segments.jpg`: one frame per segment with its label, and a
  2 s sheet. The lead reviews these first.
- `status/trailer.md` gets an r3 section: the segment list with in/out times, what each shows, and
  what reads badly.
- Commit with explicit path lists. Never use git stash.
