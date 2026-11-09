# enemies r11 — lead brief: a monster is born where it is sent, a near miss is felt, the balance gate measures SPEC

## Why
The r15 acceptance pass found three gaps in your unit:
- `EnemySpawner.spawn()` adds a new monster at the spawner's own origin and only then moves it. A hero standing on the
  sandbox origin was thrown at ~16 km/s. In the city that point is inside building D4_b003, but the boss's add spawner
  is the titan's child: every summon builds its new adds at the titan's feet, and a verifier's per-tick trace shows the
  titan flung 68–134 m in one tick (`boss-titan-leaves-crown-after-phase3-restore`, a blocker).
- `near_miss` is the only one of 44 FEEL rows with no gameplay caller. Enemy fire that misses is silent.
- `test_ai.gd` passes while printing a time-to-death outside SPEC §7.1's band, on a sample that is 9 % at full attack
  tokens, because its gate accepts 18–50 s.

The findings were made on a frozen copy at b5d26d4. Your files are byte-identical at HEAD (c75628c: `git diff b5d26d4
HEAD -- game/enemies ':!game/enemies/boss' ':!game/enemies/models'` is empty; flow r5 is editing `boss/` and
monster-assets r5 `models/`), but `game/player/mech/**` has moved (mech-move r6). Re-check each item on HEAD
before you change anything; if one no longer reproduces, say so in your status file with the log.

## 1. A new monster exists at the spawner's origin before it is placed — minor as filed; the boss blocker's trigger
**The defect.** `spawner.gd:92-94` calls `add_child(enemy)`, then sets `global_transform`. `EnemyBase._ready()` runs
inside that `add_child` (`enemy_base.gd:57-87`: collision on at :59, body and model :79-80, nav agent :82, brain :86),
all at the spawner's origin: (0,0,0) for main's, the titan's feet for the `AddSpawner` (`brood_titan.gd:71-75`). A
pooled ripper is placed before `recycle()` re-enables its collision (`enemy_base.gd:410-413`): keep that. The titan
trace shows the mechanism: the new body is the stander's floor for one tick, then jumps to its spawn point, and the
stander inherits the jump as platform velocity. The hero's `platform_floor_layers` is the engine default (all layers;
`player_mech.gd:102-108` sets none). Confirm the chain on the hero with a per-tick trace across the spawn tick.
- **Repro (live tree):** port the acceptance probe `~/m/mc-accept/game/tmp_accept/spec-coverage/fling_probe.gd`
  (read-only reference: 10 trials on the real `main.tscn`) to `game/enemies/tests/spawn_probe.{gd,tscn}` with an end
  timeline, and run the `spawn_probe` drive in Gates. At b5d26d4 a ripper under the hero gave 15979 m/s and 7846 m
  (and 16866 / 8285). Mantis, spitter and juggernaut gave 0 m/s but moved 7–10 m, a teleport that the probe's `flung`
  count (> 200 m/s only) misses. Every off-origin trial gave 0 / 0.
- **Done means:** a new monster never enters the tree, or turns its collision on, anywhere but its spawn point, whatever
  the spawner's own transform (at the origin, translated, rotated, moving with its parent). `spawn(type, at)` (CONTRACTS
  §6) does not change, and every caller's monsters land where they land today.
- **Test it on the real path** (`tools/godot.sh test`; extend `test_main_spawn.gd` or add a `test_*.gd`):
  - the real PlayerMech (`main.tscn --sandbox`) stands on the spawner's origin. Spawn ripper ×2, mantis, spitter,
    harrier and juggernaut 40–60 m away, one at a time; for 60 ticks after each the hero moves ≤ 0.1 m, under 1 m/s;
  - an `EnemySpawner` under a translated, rotated parent, with a `CharacterBody3D` in `move_and_slide` on its origin:
    the stander stays put, and each new monster is at its spawn point when it enters the tree (`SceneTree.node_added`);
  - FAIL on the old `spawner.gd`, PASS on the new. Paste both. To get the old file, copy yours aside and
    `git show HEAD:game/enemies/spawner.gd > game/enemies/spawner.gd`, then restore it. Never use
    `git stash`: the stash stack is shared with every other worker in this tree.
- **Gate:** the test; the probe with every trial under 1 m/s and 0.1 m; the boss and flow suites in Gates unchanged.

## 2. Nothing in the game calls `near_miss` — minor
**The defect.** The row (`docs/FEEL.md:41`; `fx/events/near_miss.tres`: trauma 0.04, 0.4° kick, `near_miss_flyby` at
the event position, rumble 0.25/0/60, cooldown 0.25 s) fires only in the feel gallery. Both enemy shots, the acid lob
(arc, 12 m blast) and the harrier strafe (flat, 220 m/s), leave `strike.gd:90-92` via `EnemyProjectilePool.spawn` as
an `EnemyProjectile`: one detection point covers both. A shot ends on a hurtbox (`enemy_projectile.gd:110-117`), on
anything else (`_detonate`, :118, :122-125; the barrier is in `MASK_ENEMY_ATTACK`), on expiry (:83), or caught and
`reflect`ed (:129). Rule: juice §11.3 (`ref/research/juice-impact.md:447-451`), a non-hit pass at its closest point.
- **Repro (live tree):** `grep -rn --include='*.gd' --exclude-dir=.godot --exclude-dir=tests near_miss game` lists
  three audio files and no `Feel.play(&"near_miss"`.
- **Done means:**
  - one `Feel.play(&"near_miss", p, s)` per live enemy shot that passes within `NEAR_MISS_RADIUS` of the player's
    hurtbox without damaging the player; `p` is the closest point of the shot's path (the flyby plays there);
  - none for a hurtbox contact (whatever the hurtbox does with it: i-frames, perfect dodge, `--god`), a blast that
    damages the player, a shot ending on the barrier or in the catch field, a reflected shot, a pass outside the radius;
  - a flat shot fires within 0.1 s of its closest approach, not when it expires; your rule for lobs goes in Tuning
    choices. A relaunched pooled shot starts clean;
  - the 4/s limit stays the row's cooldown (`feel_director.gd:68-70`), no second limiter; no extra physics query per
    shot per tick. `NEAR_MISS_RADIUS` is a named const: 6 m from the hurtbox, unless the lead says otherwise.
- **Test** through `EnemyProjectilePool.spawn` (extend `test_projectile.gd` or add one), counting
  `Feel.event_requested` (`core/feel.gd:31`: your calls, before the director's cooldown). A flat pass at 0.5 R → 1, at
  1.5 R → 0; a direct hit → 0; a lob whose blast damages the dummy → 0; a reflected shot → 0; a shot reused after a
  near miss counts afresh; two passes 0.1 s apart → 2. FAIL on the old code (0 calls), PASS on the new.
- **Gate:** the test; the grep finds your call site; `fight_probe` prints a `FIGHT … near_miss <attack> <d> m` line
  per call and a summary count beside the director's `event_played` count; the movie in Gates.

## 3. test_ai passes on a time-to-death outside SPEC's band — minor
**The defect.** SPEC §7.1 (`docs/SPEC.md:124`): a player who never defends under full attack tokens (3 melee + 2
ranged) dies in 25–35 s. At b5d26d4 the run printed `only 1.7 s at full attack tokens — falling back to the whole
window`, `427 DPS … 9 % saturated`, `dies in 23.4 s`, then `ok … 18-50 s`: the fallback (`test_ai.gd:215-219`) and
the wide gate (:27-28) pass a sample that is not SPEC's case. A pointer on the 9 %: the re-grant delay is per kind,
not per slot. `release` shuts the whole kind for 0.8 s (`attack_token_pool.gd:39`), and `request` refuses then while
anyone still holds one (:25), so "3 + 2 held at once" may be a peak by construction (your Known issues: 4–8 %).
- **Repro (live tree):** one `test_ai` run from Gates, through `grep -E 'BALANCE|test_ai:|dies'`.
- **Do:**
  1. Log, per kind, the share of the window at the limit, below it with the delay holding the rest shut, free with a
     monster asking, and free with nobody asking. That shows whether the pool or the pack is short.
  2. Measure SPEC's case as "the pool is at capacity": every slot of both kinds is held, or shut by the delay, while
     another monster of that kind is asking. Put the definition in the test header. If the ranged pair lacks askers,
     hold the spitters and harriers in their bands in the test; do not change the pool's cadence this round.
  3. Tune attack damage (the `EnemyAttack` rows in each archetype script) until death lands in 25–35 s. 23.4 s is too
     much damage: the Known-issues lever "attack damage (+15 %) or a faster approach" (status line 318) points the wrong way.
  4. Tighten the check to 25–35 s, and make saturation under 80 % a FAIL instead of a warning and a fallback.
- **Gate:** five consecutive runs, each ≥ 80 % at capacity and 25–35 s, all five BALANCE blocks in your status. The
  tightened check FAILS on the old damage rows (or say why not) and PASSES on the new; the TTK and PERF lines unchanged.

## 4. Status file
- Re-baseline the Gates at HEAD before your change. Add an r11 section (causes, fixes, the three FAIL/PASS pairs, the
  probe table, the five BALANCE blocks); rewrite Known issues lines 312–322 with the new definition and numbers; add the
  new tests and the probe to How to verify; re-check Requests 1, 13, 15 and 17 and drop what no longer reproduces.

## Gates (the lead re-runs all of these on the live tree)
```
tools/godot.sh check --only=res://enemies/                                                   # 0 errors, 0 warnings
tools/godot.sh test res://enemies/tests/test_audit.gd -- --timeout=300
tools/godot.sh test res://enemies/tests/test_fight.gd -- --timeout=400
tools/godot.sh test res://enemies/tests/test_status.gd
tools/godot.sh test res://enemies/tests/test_projectile.gd -- --timeout=300
tools/godot.sh test res://enemies/tests/test_spawner.gd -- --enemies=ripper:4,mantis:1 --timeout=300
tools/godot.sh test res://enemies/tests/test_spawner.gd -- --no-enemies --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6 --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:4 --stub=enemies --timeout=300
for i in 1 2 3 4 5; do tools/godot.sh test res://enemies/tests/test_ai.gd -- --timeout=400 2>&1 | grep -E 'BALANCE incoming|dies in|^PASS|^FAIL'; done
# + your new test_*.gd files. Consumers of spawn() and EnemyProjectile (read-only to you):
tools/godot.sh test res://enemies/boss/tests/test_boss.gd
tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60
tools/godot.sh test res://combat/defense/tests/test_defense.gd
tools/godot.sh test res://combat/skills/tests/test_skills.gd
# the real path
tools/godot.sh drive --scene=res://enemies/tests/spawn_probe.tscn --timeline=res://enemies/tests/spawn_probe.json --sandbox --god --quality=low
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json --out=enemies_r11 \
  --shots=14,24,34 --sandbox --stub=hud --nan-watch --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/enemies_r11_near_miss.avi --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --sandbox --stub=hud --enemies=harrier:2,spitter:2
grep -rn --include='*.gd' --exclude-dir=tests near_miss game/enemies                       # >= 1 line: your call site
```
- Every suite 0 failed, with check counts ≥ the HEAD baseline; `DRIVE done … errors=0` on both drives.
- The fight summary reports ≥ 1 near miss, every distance ≤ R. Put the near-miss timestamps beside the movie path so
  the lead can scrub to them, hear the flyby and see the nudge; `captures/enemies_r11_t14/24/34_0.jpg` show the fight.
- No file over 600 lines, no dead code, and never "fixed" without the re-run beside it.

## Coordination
- **Ownership:** `game/enemies/**` except `models/` (monster-assets) and `boss/` (boss), plus `status/enemies.md`.
- **flow** r5 (item 3) fixes the titan side of the boss blocker under an exception on `game/enemies/boss/**` (the boss
  unit is idle), and its fix must hold without yours; yours is `spawn()`. Put your commit hash in your status so the
  lead can run flow's titan tracker on both. Do not edit `game/enemies/boss/**` or `game/flow/**`.
- **mech-move:** after item 1, a monster that moves under the hero still carries it (default floor layers). Put your
  trace in Requests; do not edit `game/player/mech/**`.
- **feel** r5 has an exception on `enemy_base.gd` (`_die` :281, the dead branch :288-291, `_tick_wreck`): stay off
  those lines. The file is 566 lines; if either change takes it past 600, the split is yours, in its own commit, first.
  The `near_miss` row always kicks camera-right (`near_miss.tres` kick_dir (1,0,0), `feel_director.gd:150-152`), not
  "toward the side", and "edge blur if suppressed" has no meter: both are feel's. Pass the true closest point as `at`,
  put the rest in Requests, and do not edit `game/fx/**`.
- **Consumers:** melee-defense and skills use `EnemyProjectile` (catch field, Mirror Guard, `suite_aoe.gd`): keep its
  metadata contract and `reflect`. `spawn()` callers: `flow_spawner.gd:54`, trailer, melee rig, `boss_combat.gd:172`.
  In Requests, tell flow what item 3 does to SPEC §7.1's "median run finishes a hive at 30–60 % HP" (adds share rows).
- **Same acceptance pass, in parallel:** flow r5, feel r5, mech-move r7, skills r4 and hud r6, plus
  city-art r16, hero-v3 and monster-assets r5 (uncommitted and staged files under `game/enemies/models/**`: not yours to
  commit). Heavy slots queue.
- **Commit** with an explicit path list (`git commit -m … -- <paths>`), never `-a`. Requests go in `status/enemies.md`.

## Lead decisions (read first)
`reviews/r16-lead-decisions.md` holds the lead's dispatch decisions. Read its "Shared" section, and every section that names this unit, including those under "Round 2". Where a decision and this brief differ, the decision wins.

## Dispatch note from the lead (11-06 18:55): one worker at a time, headless only
You are the ONLY worker. `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's
`MC_WINDOW_OK` (see the end of `tools/workers/preamble.md`).
- Verify with headless tests: spawn safety, the near-miss detection with its Feel and Events calls, and
  the test_ai band.
- List the exact commands for the near-miss movie and the fight stills under **"Captures needed"** in
  your status.
- Since this brief was written, monster-assets r5 has landed (its models commit is 590a6a1) and feel r5
  has landed the near_miss path. mech-move r7b changed the death gate, and its suites pass.
- Read `reviews/r16-lead-decisions.md` (enemies r11, Round 2) and `reviews/r16-conflicts.md`
  (D1–D6).
