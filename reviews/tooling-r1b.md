# tooling r1b — lead brief: one green regression table before the next export

## Why
Your r1 round was stopped mid-work on 11-05, when the user ordered all parallel work stopped. Items 1–8
are committed. Your `status/tooling.md` has 63 uncommitted lines in the tree, and they are yours. Since
then, ten rounds have landed and their new tests are not in `tools/suites.txt`. `tools/suites.sh --list`
reports 16 UNLISTED tests (see below). The lead wants ONE command that proves the whole game before each
export.

## House rules (the user's machine)
- You are the ONLY worker.
- Everything here is headless (`tools/godot.sh test` / `check`). Never run `shot|run|drive|movie|perf`;
  they refuse without the lead's `MC_WINDOW_OK` anyway.
- Never use git stash. Commit with explicit paths.

## Do
1. **Your uncommitted status.** Commit the `status/tooling.md` work, or reconcile it with r1's state.
2. **The suite rows.** Add a row for every UNLISTED test, with the flags its owner documents in
   `status/<unit>.md` "How to verify" or Requests:
   - `test_guard_capture`, `test_input_quad`, `test_pad_atom`, `test_readme_controls`;
   - `test_near_miss`, `test_spawn_safety`;
   - `test_collapse_camera`, `test_die_once`;
   - `test_boss_kill`, `test_skate`, `test_swarm`;
   - `test_death`, `test_hero3_flight`, `test_hero3_thruster`;
   - `test_capture_clock`;
   - `test_title_tutorial` (it needs `--timeout=900`).

   Then re-scan, so that `--list` shows 0 UNLISTED.
3. **Run the whole table, sequentially** (`--jobs=1`, so the machine stays usable), and fix
   harness-only problems: wrong flags, timeouts.
   - A red that is a real defect in another unit's code: do NOT fix it. List it in Requests by owner,
     with the failing line.
   - A known one: allow-list it with a tag, the way the host already works.
   - Expect the flake at `enemies_ai` (1 of 5 runs failed under load). If it fails, re-run it once
     and record both results.
4. **One-line wrapper for the lead.** Make `tools/suites.sh` (no arguments) end with a single verdict
   line: `SUITES <n> rows, <g> green, <k> known, <r> red`, and exit 0 only when r = 0.

## Gates
- `tools/suites.sh --list`: 0 UNLISTED.
- `tools/suites.sh`: the verdict line, with every red attributed in your status.
- `status/tooling.md` gets an r1b section with the table.
