# city-art r16a — lead brief (narrow): the settle index measured a falling world. Fix it, re-bake, and prove nothing floats

## Why
The user's complaint is "浮空" (things floating above the ground). hero-v3 r9 fixed the hero; this
round is the city's half.

hero-v3 r9 found a shipped bug in your settle pass (`status/hero-v3.md` §1b, probe
`game/player/model/hero3/tests/probe_surface_mode.gd`):
- `PhysicsServer3D.body_create()` returns a DYNAMIC body in 4.7.2 + Jolt;
- `game/world/art/settle/surface_query.gd:167` and `:175` never set a mode;
- so every support `ArtSurfaces` indexes falls at 9.8 m/s² from the tick it is created. A top face
  that starts at y = 0 is at y = −4.94 one second later.

Both the city settle pass (which drops dressing onto those surfaces) and `tools/float_audit.gd` (which
reports floaters) read that sinking index. The baked `settle_cache.json` may therefore have placed
dressing against surfaces that had already dropped. That is a likely cause of floating or buried props.

## House rules (the user's machine)
You are the ONLY worker running. Measure headless where possible. The float audit has to run windowed,
because MultiMesh transforms are zero on the headless renderer: it opens as a small, unfocused corner
window (`MC_TOOL_WINDOW`). Keep those runs few.

## Do
1. **The fix.** `body_set_mode(BODY_MODE_STATIC)` on both bodies in `surface_query.gd`. Add a unit test
   that fails on the old code: a support stays at y = 0 after 1 s.
2. **Measure the damage.** Run the float audit on the OLD bake against the FIXED static index: how many
   dressing items (by category) float or are buried more than 0.5 m against the real surfaces?
3. **Re-bake** with the fixed index: `SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`
   (corner window). Then re-run the audit: 0 floating > 0.5 m and 0 buried > 0.5 m in the resting
   categories. Name any exception, with its position and the reason.
4. **The content stamp** (acceptance findings `pkg-settle-cache-mtime-stamp` and
   `settle-cache-mtime-false-stale`, in `~/m/mc-lead/accept/findings_all.json`).
   - The bake's fingerprint must hash file CONTENT, not mtimes, so a clean checkout does not read as
     stale and `godot.sh export` does not refuse it.
   - Include `game/world/props/meshes/*.glb` in the stamp (the lead's decision).
   - Prove it with a unit test: touched mtimes leave the stamp unchanged; changed content changes it.
   - Do not do a full fresh-worktree import.
5. **Captures.** Before/after, at street level, of the 3 worst floaters the audit finds, plus the A1
   container yard, where the player starts.

## Gates
- The new static-mode test fails on the old code and passes on the new.
- The float audit, before and after, in a table: 0/0 in the resting categories after the fix.
- `test_settle_cache` passes; the stamp test passes.
- `tools/godot.sh check --only=res://world/` is clean.
- `status/city-art.md` gets an r16a section.
- Commit the re-baked `settle_cache.json` with an explicit path list. Never use git stash.

## Not this round
Golden-hour warmth, the hatch pattern, the HDRI decision, the tod 1.0 budget and the
material_library split: those wait for r16b, one round at a time.
