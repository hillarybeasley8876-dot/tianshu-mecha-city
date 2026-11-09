# skills — review r2 (lead) — PASS (polish round requested)

Verified: `check` 53 files 0 errors; `test_skills` 176/0 (clocks suite included); the 13 stills reviewed at
gameplay framing. Every skill now has its own signature and none borrows `kill_large`: the Shockcore shell with
radial arcs, the Plunge sheath and light column, the Rift streak + hologram decoy, the Ward hex sphere, the
Undertow lens, the anchor cable with reel lines, and the Lance — the layered white-gold-red sweep is the best
image in the build so far. The two rendering bugs (row-scaled `Basis.scaled()`, invisible beam faces) were
real finds. `--no-cinematic` is no longer needed: `--sandbox` is free play (flow idle) since CONTRACTS §2
changed tonight.

## Polish round (r3) — small, all visual
1. **Overdrive afterimages only while moving** (planar speed ≥ 12 m/s): standing still, a ghost every 3 f stacks
   five gold copies on the hero and turns it into a flat orange blob (`skills_overdrive.jpg`). At rest the
   overdrive reads through the hero's gold glow strips, the vents and your gold rim.
2. **Corona Fins read at 100 m**: core 1.2 m / glow 4 m, a bright station marker on each fin, a 4 f pre-flash ring
   at each muzzle, and hit sparks on the target.
3. **Plunge impact**: cap the column's peak emission so it blooms instead of whiting out at 25 m.
4. **Undertow presence**: a violet ground ripple pulsing inward every 0.5 s under the lens.
Re-capture those four + the showcase movie; keep the suite green.
