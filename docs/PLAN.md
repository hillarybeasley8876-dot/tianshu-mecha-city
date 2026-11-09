# MECHA CITY — PLAN (lead-owned)

Goal: a playable, beautiful demo of one vertical city district (SPEC §8 flow) in Godot 4.7, built by
MiniMax-M78 workers from briefs; the lead (Claude Opus) plans, reviews, art-directs and integrates.

## Units and waves
| Unit | Wave | Depends on | Brief |
|---|---|---|---|
| mech-move | 1 | core | briefs/mech-move.md |
| camera-aim | 1 | core, mech-move API (contract) | briefs/camera-aim.md |
| feel | 1 | core | briefs/feel.md |
| enemies | 1 | core | briefs/enemies.md |
| weapons | 1 | core, PlayerMech/AimSystem API (contract) | briefs/weapons.md |
| city-layout | 1 | MAP.md, level-design dossier | briefs/city-layout.md |
| city-build | 2 | city-layout PASS + lead plan review | briefs/city-build.md |
| melee-defense | 2 | mech-move, camera-aim | briefs/melee-defense.md |
| skills | 2 | mech-move, camera-aim, enemies | briefs/skills.md |
| hud | 2 | all gameplay hud_state() | briefs/hud.md |
| hero-asset | 2 | lead's Tripo hero parts | briefs/hero-asset.md |
| city-art | 2 | city-blockout tiles, ART.md | briefs/city-art.md |
| audio | 2 | Events, FEEL ids | briefs/audio.md |
| monster-assets | 3 | lead's Tripo monster models | briefs/monster-assets.md |
| flow | 3 | enemies, city, hud | briefs/flow.md |
| boss | 3 | enemies, monster-assets (titan) | briefs/boss.md |

Lead tasks in parallel: Tripo asset generation (hero parts, monsters, landmarks, props), concept art,
integration builds, look-dev reviews, perf passes, final acceptance and the packaged build.

## Review loop (every unit, every round)
1. Worker reports done → lead runs the brief's "Done when" commands itself (never trusts the report).
2. Visual/feel units: lead watches captures/movies and compares against ART.md/FEEL.md targets.
3. Review written to `reviews/<unit>-rN.md` (MUST-FIX numbered, SHOULD, evidence), sent with
   `tools/workers/m78.py feedback <unit> --file reviews/<unit>-rN.md`.
4. A unit passes when every MUST-FIX is closed with evidence. After 4 failed rounds the lead (or an Opus
   fixer) takes over that unit.

## Shared rules for all briefs
- Numbers come from SPEC / FEEL / dossiers; when a number is missing, choose, document it in your status
  file under "Tuning choices", and make it a named constant or resource field.
- Everything must run in the core sandbox (`--sandbox`) before the city exists.
- Placeholders are fine when the brief says so, but they must use the final APIs.
