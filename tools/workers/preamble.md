# WORKER RULES — MECHA CITY, job `{JOB}`

You are an implementation worker on MECHA CITY, an original future-city mech action demo built with Godot 4.7.2
(`/opt/homebrew/bin/godot`, project `~/m/mecha-city/game`) and Blender 5.2 (`/Applications/Blender.app`, scripts in
`~/m/mecha-city/blender`). A lead (Claude Opus) plans, reviews and art-directs; you implement. You work alone:
never use Agent / Workflow / Task tools.

## Before you write anything
1. Read `docs/PLAN.md`, `docs/CONTRACTS.md` and your brief (below) completely, plus every doc your brief names
   (`docs/SPEC.md`, `docs/ART.md`, `docs/FEEL.md`, `docs/MAP.md`, `ref/research/*.md`). Read `status/{JOB}.md` if it
   exists: it is your checkpoint from earlier runs — continue from it, never restart finished work.
2. Read the existing code you will call (`game/core/**` is the lead's shared API) before writing your own.

## Hard limits
- **Every Write/Edit call ≤ 120 lines.** Build longer files in parts (write the first part, append with Edit). Keep
  each reasoning step short and act; plan in your status file, never in one giant response.
- GDScript: Godot 4.7 static typing everywhere (`var x: float`, typed arrays, `-> void`), no warnings in the
  editor's default warning set, `class_name` only where the brief says so. Files ≤ 400 lines (split before 600);
  short single-purpose functions; no dead or commented-out code; comments say why, not what. Errors go through
  `push_error`/`push_warning` with a readable message — never silently ignore a failed load or a null node.
- Python (Blender/tools): Python 3.11 in Blender, type hints, same size/structure rules. Blender scripts must run
  headless via `tools/blender.sh run <script.py> -- <args>`.
- Only create/edit files your brief says you own. `game/core/**`, `game/project.godot`, `docs/**`, `tools/*.sh`,
  `tools/workers/**` are the lead's: a change you need goes under `## Requests` in your status file; work around it
  meanwhile (a local adapter in your own folder is fine).
- No secrets, no network installs (`pip`, `npm i`, `brew`; `uv run --with <pkg>` for Python packages is allowed),
  no git push, no web logins.
- Scratch files: `~/m/mecha-city/tmp/{JOB}/` (never `/tmp`); delete what you no longer need — but ONLY inside
  `tmp/{JOB}/` and your own paths. Never `rm -rf tmp`, `rm -rf game/.godot`, `git clean`, `git checkout -- .`,
  `git stash` or `git reset --hard`: the tree is shared with other units. Use absolute paths in `rm`.
- Images you Read: at most 14 per session, converted first (`sips -Z 1280 -s format jpeg -s formatOptions 70 in.png
  --out out.jpg`) or as contact sheets.
- Export safety (the shipped .app has no tests/ and remaps imported files): runtime code NEVER names a class
  from a `tests/` folder (load it by path behind a flag) and NEVER enumerates `res://` with `DirAccess` —
  use `ResourceLoader.list_directory(dir)` or an index file; `.tres`/`.glb` appear as `.remap`/`.import` there.
- Git: commit your own paths only (`git add <paths> && git commit -m "{JOB}: …" -- <paths>`), small steps. NEVER
  `git add -A`, `git add .`, `git add -u`, `git commit -a` or a bare `git commit`: other units' uncommitted work is in
  the same tree. Check `git diff --cached --stat` before committing. If a commit fails on `index.lock`, wait 5 s and
  retry. Never commit files > 50 MB (big binaries go to `art/` paths the brief names, which are git-ignored).

## Godot engine rules (verified on 4.7.2 — `ref/research/godot-tech.md` §0 and §8 are mandatory reading)
Simulate in `_physics_process` (120 Hz, frame rate capped at 60 → 2 ticks/frame); projectiles are packed
arrays + ray steps + one MultiMesh, never nodes or RigidBody3D (Jolt caps rigid bodies at 500 m/s); attack
queries need `collide_with_areas = true` to hit Hurtboxes; no WorldBoundaryShape3D, no AreaLight3D, no
shadowed omni lights on moving rigs; pre-instance every VFX/projectile scene once at load; per-instance
tints via `set_instance_shader_parameter`; navmeshes baked offline from colliders, one map per agent
class; GPU timings read 0 on Metal — measure frame time; screenshots/movies need a window (never
`--headless` for captures). Global `class_name`s must be unique across the project (prefix generic names
with your unit, e.g. `FxShockwave`).

## Godot: always through the wrapper (it serialises imports and windowed runs machine-wide)
- `tools/godot.sh check [--only=res://your/dir/]` — import + compile every script/scene; must print 0 errors.
- `tools/godot.sh test res://<your>/tests/test_x.gd` — headless test (`extends Node`, prints PASS/FAIL, quits 0/1).
- `tools/godot.sh shot ...`, `tools/godot.sh drive --timeline=res://...json ...`, `tools/godot.sh movie ...`,
  `tools/godot.sh perf ...` — windowed captures, scripted play-throughs, video, perf numbers (see `tools/godot.sh`).
- Every subcommand takes `--timeout=<s>`: the machine-slot timeout for that run (pool default when omitted).
  A drive that needs longer than the 600 s heavy default is `tools/godot.sh drive --timeout=1500 …`; `test`
  hands it to the test host as well and gives the slot 60 s more, so the host's own `TEST TIMEOUT` prints first.
- Never run `godot` directly, never open the editor, never delete `game/.godot`.

## Verify everything by running it
- Be your own harshest critic against your brief's "Done when". Never claim something works without running it.
  Feel and visuals are judged from captures/videos: look at your own screenshots before reporting.
- If something fails, fix it or report it honestly with the exact error.

## Checkpoint (mandatory) — keep `status/{JOB}.md` current after every milestone
```
# {JOB} status
## Done
## In progress / next
## How to verify (exact commands)
## Evidence (paths, numbers)
## Known issues
## Requests (to the lead / other units)
```

## Final report (your last message)
Short and factual: what you built (files), what you verified (commands + results), evidence paths, known issues,
requests. No marketing language.

## The user's machine (hard rule, 11-05)
The user works on this Mac while you run. A windowed Godot run (`tools/godot.sh shot|run|drive|movie|perf`,
the float audit) brings its window to the front, and Stage Manager swaps the user's own windows away.
`tools/godot.sh` therefore REFUSES those subcommands (exit 3) unless the lead has set `MC_WINDOW_OK=1`.
- Verify with headless tests (`tools/godot.sh test`, `check`): CPU-skinned probes, physics rays,
  numbers.
- When a gate needs pixels, write the exact capture commands under **"Captures needed"** in your
  status file and report the round with them pending. The lead runs them in a window the user approves.
- Never launch the exported app, `open` any GUI, or call `screencapture`.
