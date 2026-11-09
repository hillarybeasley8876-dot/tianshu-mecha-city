# monster-assets — review r2 (lead) — PASS (stride measured right) + r3 for the gaits and action tables

Verified: `test_models` 361/0, enemies tests green, the re-rendered strips, and your stride table. Pelvis-space
foot sweep is the right measure — your deviation from my literal stance window is correct (in-place marches);
keep both numbers. The spitter's zero-length legs and the camera-less gallery were real finds.

Lead fix already in (keep it): `play_action` resolved `attack_1 → slash_1` on types without `slash_1` and
indexed the table anyway (~750 errors per run in every unit's logs); aliases now resolve only to clips the type
has, with one warning per type/id. Remaining warnings in a sandbox fight: ripper `attack_1`, ripper `stagger`,
juggernaut `attack_1` — i.e. those attacks and that stagger play NO animation today.

## r3
1. **Per-type action tables**: each `<type>_rig.json` maps every id the enemies unit uses (grep
   `play_action(` / attack ids in `game/enemies/**`) to that type's clip — e.g. ripper attack_1 → bite,
   stagger → hit; juggernaut attack_1 → its swing/slam. Test: for every type, every id `game/enemies/**` can
   request resolves to a real clip.
2. **Fast gaits with real strides** (your keyframe DSL, like the spitter/harrier rigs): the Tripo loops can
   never carry the gameplay speeds (ripper 30, juggernaut 20, spitter 18 m/s). Author a ripper **gallop/
   scuttle** (big leg sweep, body bob, clean at 30 m/s), a juggernaut **charge run** (heavy, clean at 20 m/s),
   a spitter **scuttle** (clean at 18 m/s). The model picks the clip by speed (walk up to its clean maximum,
   the fast gait above), so the enemies' POSITION state needs no change. Residual slide ≤ 15 % at the types.gd
   speeds; rippers may keep ≤ 25 %.
3. **Hive pod sockets** `pod_0..3` on the glowing bulbs (flow places its pods there).
Evidence: strips of the three new gaits from the side at gameplay speed, the slide table, the test.
