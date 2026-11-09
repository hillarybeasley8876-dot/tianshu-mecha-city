# monster-assets — lead notes (read at every session start; decisions after the research critic)
**Titan (D1 decided: keep the tail)** — Tripo's titan rig is the 78-joint humanoid (no tail, no jaw, 30 finger
joints). In Blender:
- add a 6-bone tail chain from the pelvis and a jaw bone; collapse the fingers into 3 claw bones per hand;
- weights: Data Transfer from a voxel-remeshed MANIFOLD proxy (Tripo shells are often non-manifold; heat
  weighting fails on them — same for the self-rigged Spitter and Harrier);
- extra clips (keyframed, weighty): `tail_sweep` (1.2 s wind-up + sweep), `climb_over` (3–4 s: hauls itself
  over a deck edge — intro), `phase_roar` (2–3 s), `core_break` (flinch), `death_fall` (3 s, topples backward
  over an edge); tail secondary motion via SpringBoneSimulator3D on top of keys.
- **Skyline walker**: a separate 10k-tri LOD scene `titan_skyline_model.tscn` (walk + roar only) scaled ×1.5
  (90 m) for the distant ring; the fight model stays 60 m.
**Mantis / Juggernaut**: collapse the Tripo finger joints into claws too (the Mantis has scythes, not hands).
**Performance**: report draw calls + skinned vertex counts per model; the trash mobs must stay cheap with 40 on
screen (LOD at 120 m).
- The enemies unit loads `enemies/models/<type>/<type>_model.tscn` (a WRAPPER scene implementing the monster model
  API) — a bare `.glb` is not enough; ship the wrapper for every type so the placeholders switch off.
- (flow r1) `MonsterModel.play_action()` errors `Invalid access … 'slash_1'` on every flow run (a type without
  that clip is asked for it) — never index a clip that does not exist: map unknown ids to the nearest clip of
  that type (or warn once) and add a test over every action id EnemyTypes uses per type. Also expose the hive's
  pod sockets (`pod_0..3` on the glowing bulbs) for the flow unit.
- (audit, 2026-11-02) Robustness findings for your files: reviews/monster-assets-audit.md — fix them in this round after your current items (regression checks for the high ones).
- (skills r3) `--nan-watch` reports a zero-scaled basis from `monster_model.gd` (a model scaled to 0 — dissolve or
  spawn-in?). Never let a visible node reach scale 0: hide it at ≤ 0.01 instead, or clamp to 0.001.
