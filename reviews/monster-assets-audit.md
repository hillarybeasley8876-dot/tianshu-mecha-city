# monster-assets — numeric-robustness audit (lead, 2026-11-02) — 2 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [medium] game/enemies/models/monster_model.gd:293 (other)
**What**: _apply_state switches to the locomotion loop whenever the current clip differs, and the brain calls set_locomotion every tick (attack_windup/attack_recover -> &"idle"; _staggered -> &"stagger", which maps to idle). So any one-shot clip started by play_action is cross-faded away one physics tick later.

**Trigger**: Normal play with the shipped real models (all 5 <type>_model.tscn exist). _begin_attack plays leap/bite/slash/fire/charge, then the next tick's attack_windup -> set_locomotion(&"idle") blends to idle in 0.18 s. Monsters wind up and strike in their idle loop, the juggernaut charges at 60 m/s playing idle, and stagger clips are replaced the same way.

**Fix**: As proposed: hold one-shots for their clip length in MonsterModel, and keep updating only the speed scale meanwhile. Also start the juggernaut roar with play_action(&"roar") instead of set_locomotion(&"roar").

**Skeptic's check**: _apply_state calls animation.play(loop) whenever current_animation differs (monster_model.gd:283-293). attack_windup and attack_recover call set_locomotion(&"idle") every tick (enemy_base.gd:425, 441), so the leap/bite/slash/fire/charge clip from _begin_attack is cross-faded to idle one tick later. _staggered's &"stagger" and the juggernaut's &"roar" (juggernaut.gd:59) also resolve to idle, because no locomotion table has those keys. All five <type>_model.tscn exist, so this is normal play.

## 2. [low] game/enemies/models/monster_model.gd:322 (other)
**What**: play_action follows an alias without checking that the aliased clip exists, so `_clips[clip_id]` raises a script error when &"attack_1" is aliased to &"slash_1" on types that have no slash clips.

**Trigger**: Every ripper bite (BITE anim &"attack_1") and juggernaut swipe (SWIPE anim &"attack_1"): neither rig JSON has slash_1, so each attack logs an invalid-key error and the call aborts, leaving EnemyBase.play_action with no return value.

**Fix**: As proposed: check _clips.has() after aliasing and return MISSING_ACTION with a warning. Point the ripper bite at &"attack" (alias bite) and the juggernaut swipe at &"swipe".

**Skeptic's check**: Ripper BITE and juggernaut SWIPE use anim &"attack_1" (ripper.gd:16, juggernaut.gd:23), which aliases to slash_1, and neither rig JSON has that clip (ripper: bite/leap/...; juggernaut: swipe/ground_slam/...). A Godot 4.7.2 probe confirmed that the String lookup matches the StringName alias key, and that `_clips["slash_1"]` raises 'Invalid access to property or key' and aborts the call, which then returns 0.0.
