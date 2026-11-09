# melee-defense r6 — lead brief: hud_state() must answer before the first physics tick

## Why
The r15 acceptance pass found 2 SCRIPT ERRORs from `MeleeSystem` in every headless `tools/godot.sh test`
run that boots `res://main.tscn`. A verifier reproduced them and narrowed the scope. They fire once, on
frame 1, and only when main enters the tree partway through a frame, which is what the test host does. The
shipping boot and the windowed tools (`run`, `drive`, `shot`) add main before frame 1, and the verifier's
runs that way logged 0. So the player never sees it, and it does not fail ACCEPTANCE §1 today.

It still has to go. The pair is in every test-host log that boots the real game, where it hides the next
real frame-1 error. Once the test host fails on script errors (finding `test-host-ignores-script-errors`),
the suites that boot main go red on this pair alone. CONTRACTS §5 says the HUD polls every component's
`hud_state()` each frame, so a component that is in the tree must answer.

The finding was made on a frozen copy at b5d26d4, and the tree has moved on. Re-check it against HEAD
before you change anything. If it no longer reproduces, say so in your status file and include the log.
The files on the bug path (`game/combat/melee/**`, `ui/hud.gd`, `ui/hud_data.gd`, `tools/test_host.gd`,
and both gate tests) are byte-identical to b5d26d4 today, so expect it to reproduce.

## 1. Two SCRIPT ERRORs on frame 1 of every test-host boot of main.tscn — minor
**The defect.** `hud_state()` (`game/combat/melee/melee_system.gd:407`) calls `charge_ratio()` (l.185–186)
and `lunge_ready()` (l.232–233). Both dereference `charge` and `lunge` with no guard. Those two are only
built in `_refresh()` (l.75–80, together with `strike`), and `_refresh()` only runs from
`_physics_process()` (l.97). The HUD polls from `_process` (`ui/hud.gd:127` → `ui/hud_data.gd:75`).
`game/tools/test_host.gd:39` adds the test node with `call_deferred`, `enemies/tests/test_main_spawn.gd:26`
defers main once more, and `test_flow_perf.gd` adds it from a deferred `_run`. So main enters in the
deferred-call flush after that frame's physics step, and the HUD's first poll beats MeleeSystem's first
tick. The result is `Invalid call. Nonexistent function 'ratio' in base 'Nil'` at :186, then `'ready' in
base 'Nil'` at :233. From frame 2 on, the values are right. The file already handles this state elsewhere:
`last_hit_usec()` and `last_hit_kind()` (l.380–386) and `reset()` (l.429, l.436) check for null, and
`execution_available()` is already safe, because `_execution_target()` returns null while `_aim` is null
(l.218). `DefenseSystem` builds its parts in `_ready()` (`defense_system.gd:40–46`), so its `hud_state()`
needs no change.
- **Repro (live tree):**
  ```
  tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6 \
    --timeout=300 2>&1 | tee tmp/melee-defense/r6_repro.log | grep -A4 'SCRIPT ERROR'
  ```
  At b5d26d4 this printed exactly the 2 errors, with the chain `hud_state` ← `HudData.poll` ←
  `Hud._process`. Then it printed `MAIN SPAWN TEST 6 checks, 0 failures` and `PASS`, and exited 0. The
  host does not fail on script errors yet, so read the log, not the exit code.
- **Fix it in `melee_system.gd`**, not in `game/ui/**` and not in the test host. The rule is that every
  public `MeleeSystem` method (`hud_state`, `charge_ratio`, `lunge_ready`, `execution_available`,
  `cancel_open`, `last_hit_usec`, `last_hit_kind`, `reset`) is safe from the moment the node is in the
  tree. Before the first physics tick, it returns what an idle mech returns after that tick: `charging`
  0.0, `lunge_ready` false, `execution_available` false.
  - Guard, or build the pieces earlier: your call. Use one rule for the whole file, leave no dead guards
    behind, and write the reason in your status file.
  - If you build earlier, note that `_refresh()` also attaches the saber and sets up the executor
    (l.68–72), and it is lazy on purpose (l.61–62). The integration drive in Gates must then show that the
    blade is still in the hand.
- **Done means:** the four main.tscn boots in Gates log 0 `SCRIPT ERROR` lines (for a line from another
  unit's file, see Coordination) and still pass, and the item 2 test passes.
- **Gate:** the boot block and the integration drive in Gates.

## 2. No test calls hud_state() before the first physics tick — minor (the regression test)
**The defect.** The melee suite's first check runs after `h.fresh()` and `await h.step(0.1)`
(`suite_combo.gd:54–55`), and every later suite runs after that. So no test ever reads `hud_state()` in the
state the HUD sees on a mid-frame boot. The one call that does run before the first tick is `reset()`,
from `fresh()` (`melee_harness.gd:84`), and `reset()` is guarded.
- **Build it** in `game/combat/melee/tests/`, on the real `melee_system.tscn` under the harness player
  (`MeleeTestHarness.build()`, `melee_harness.gd:25–52`). Call `hud_state()` in the same frame the system
  enters the tree. Either make it the first block in `test_melee.gd`, before any suite steps physics, or
  ship it as its own `test_*.gd`.
- **It proves its own precondition:** `Engine.get_physics_frames()` is the same at the `add_child` and at
  the call.
- **It asserts:**
  - 0 errors are logged during the call. The host's exit code ignores them, so count them yourself with
    the host's `res://tools/error_counter.gd` (add it with `OS.add_logger`, remove it afterwards);
  - all 12 keys listed at `melee_system.gd:11–12` are present;
  - `charging` is a float 0.0, and `lunge_ready` and `execution_available` are bool false;
  - one physics tick later, the same keys come back with the same types.
- **It must FAIL on the old code and PASS on the new.**
  1. Put back the pre-fix `melee_system.gd` only. Copy your fixed file aside
     (`cp game/combat/melee/melee_system.gd tmp/melee-defense/fixed.gd`), then
     `git show HEAD:game/combat/melee/melee_system.gd > game/combat/melee/melee_system.gd`. Never use
     `git stash`: the stash stack is shared with every other worker in this tree.
  2. Run the test and paste its FAIL lines into your status file. They must be FAIL lines, not a crash or
     a timeout.
  3. Restore the fix (`cp tmp/melee-defense/fixed.gd game/combat/melee/melee_system.gd`), re-run, and paste
     the PASS.
- **Gate:** the melee suite line in Gates, plus that FAIL/PASS pair.

## 3. Status file — housekeeping
- **Re-baseline first.** Your r5 numbers (252 and 90 checks, `INT done shots=9 failed=0`) predate three
  later commits into your folder by other hands: 5526977 (hero-v3, `melee_table.gd`), 4d486e2 (the probes
  load hero3) and e63e072 (city-art: `integration_rig.gd`, `melee_range.gd`, `melee_strip.gd`). Run the
  Gates once at HEAD before your change, and record what you get.
- **Known issue 4 and Request 3 are stale.** They are the `aim_system.gd:68` flood after a freed target.
  The lead fixed it in 24f0021 (11-02, `AimSystem._is_valid` untyped), and your own r5 integration drive
  logged `errors=0`. Confirm it on this round's drive, then drop both.
- **Re-check Request 4** (a dying monster scaled to 0) the same way. Your r5 `--nan-watch` run reported
  nothing, so keep it only if you have fresh evidence.
- **Add an r6 section:** the cause in two lines, the fix, the FAIL/PASS pair, and the `SCRIPT ERROR` count
  of every gate log. Add the new test and the four boots to How to verify.

## Gates (the lead re-runs all of these on the live tree)
```
tools/godot.sh check --only=res://combat/melee/,res://combat/defense/    # 0 errors
tools/godot.sh test res://combat/melee/tests/test_melee.gd                 # 0 failed; checks = HEAD baseline + yours
tools/godot.sh test res://combat/defense/tests/test_defense.gd             # 0 failed
# + your own test_*.gd, if the item 2 test is its own file

# the four test-host boots of res://main.tscn (flags as documented in status/enemies.md and status/flow.md)
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6 --timeout=300 2>&1 | tee tmp/melee-defense/r6_ms_ripper6.log
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies --timeout=300 2>&1 | tee tmp/melee-defense/r6_ms_none.log
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:4 --stub=enemies --timeout=300 2>&1 | tee tmp/melee-defense/r6_ms_stub.log
tools/godot.sh test res://flow/tests/test_flow_perf.gd -- --skip-menu --no-enemies --spawn=-514.5,112,105.1,-66.4 --timeout=300 2>&1 | tee tmp/melee-defense/r6_flow_perf.log
grep -c 'SCRIPT ERROR' tmp/melee-defense/r6_ms_*.log tmp/melee-defense/r6_flow_perf.log   # 0 in every file

# the shipping boot stays clean, and the real game's melee is unchanged
tools/godot.sh run res://main.tscn 20                                     # SMOKE ... errors=0
tools/godot.sh drive --scene=res://combat/melee/tests/integration.tscn --sandbox \
  --enemies=mantis:2,ripper:6 --timeline=res://combat/melee/tests/timeline_integration.json \
  --nan-watch --out=melee_r6_int                                           # INT done ... failed=0, DRIVE done ... errors=0
```
- **The boots still pass:** `MAIN SPAWN TEST` gives 6, 2 and 2 checks with 0 failures, each followed by
  `PASS`, and flow_perf gives `TEST n checks, 0 failed`.
- **The item 2 FAIL-on-old and PASS-on-new lines** are in your status file.
- **No new captures:** nothing visual changes. If you built the pieces earlier, look at
  `captures/melee_r6_int_*.jpg` and confirm in one line that the blade is still in the hand.
- **The rules:** no file over 600 lines (`melee_system.gd` is 445 today), and no "fixed" without the re-run
  beside it.

## Coordination
- **Ownership:** you own `game/combat/melee/**`, `game/combat/defense/**` and `status/melee-defense.md`. No
  exceptions this round: `game/ui/**` is hud's, `game/tools/**` (the test host, `error_counter.gd`) is the
  lead's, and the enemies and flow tests you run as gates are read-only to you.
- **Foreign errors:** a SCRIPT ERROR from outside your folders in a gate log does not block you. Put its
  first lines in Requests and leave the file alone.
- **Order:** this lands before the test host is made to fail on script errors
  (`test-host-ignores-script-errors`). After that change, the four boots go red on this pair alone.
- **Others working the tree at the same time:**
  - city-art r16 (`game/world/art/**`);
  - hero-v3, whose uncommitted files (`game/player/model/hero3/**`, `status/hero-v3.md`) are in the
    working tree now;
  - hud r6, when it is dispatched. It polls your `hud_state()`, and no guard for this goes into the HUD.

  Heavy slots (`run`, `drive`) queue behind their renders.
- **Commit** with an explicit path list (`git commit -m … -- <paths>`), never `-a` or `add -A`.
- **Requests channel:** the Requests section of `status/melee-defense.md`.
