# city-kit r8 — lead brief: the cover keeps its concept's colours, then all twelve

## r7 verdict
**Accepted as engineering:**
- the dense UV layout;
- the low-pass in 3D (your finding that a per-island mean is one sample of the baked shading is
  correct and important);
- gradients inside a face;
- gutter dilation;
- the honest deviations.

**Not yet accepted as a look.** In the game the tanks and the transformer are dark tan objects, and
the concepts are white and light grey. The lead's probe on your `k07_15m` / `k02_15m` cameras
(`captures/lead_r8probe_*`) shows two things:
- **the geometry reads clean.** With a flat untextured material (the `flatmat` rung), k07 is a crisp box
  with radiator fins and k02 three smooth cylinders.
- **the albedo is what makes them dark and brown.** `k07_k07_albedo.jpg` has a stored mean of
  (0.37, 0.32, 0.26); `k02` (0.41, 0.35, 0.28). Both are tan.

## 1. The units: you read the lead's number as sRGB, but it was linear
You wrote that "the lead's 'painted white steel at 0.45–0.55' is the p97 and 0.50 is 0.21
scene-linear". The brief said **linear albedo**, and white paint at linear 0.21 is mid-grey under a
dusk sun. Use these, in stored sRGB:

| surface | stored sRGB |
|---|---|
| white or light grey paint (k02 tanks, k07 tank and fins, k03 crates, k06 container, k12 silo) | **0.72–0.80**, i.e. linear 0.48–0.60 |
| steel frames and dark parts | 0.25–0.40 |
| concrete | 0.50–0.60 |
| wood (k08 drums) | 0.40–0.55 |

r6's pale sheets were the EMISSION, not albedo, so a white tank is safe. Keep the cover band's
emission off.

## 2. The hue: transfer the concept's palette, do not keep the atlas's
The Tripo atlas is warm-biased everywhere, so "hue untouched" keeps every model tan. For each model:
1. **Transfer the colour.** Take its concept image (`art/concept/citykit/<id>-1-1.png`), mask out the
   light grey background, and do a Reinhard colour transfer in Lab, matching the mean and std of L, a
   and b, onto your LOW-PASSED albedo. Then apply the levels from §1.
2. **Protect the accent colours.** Saturated accents in the concept must survive: the red
   insulators, the blue logo bands, the hazard yellow.
3. **Check it.** The model's dominant hue in the game must match the concept's at a glance.

## 3. Paint the hazard bands and the panel lines back, procedurally
Your 0.45 m chroma diffusion washed out the 0.5 m hazard band, so `hazard_pct` is 0.
- Wherever the concept has a hazard band, draw it in the bake as an object-space pattern: the k07
  plinth, the k12 silo base, the k05 barrier.
  - 45° stripes, 0.6 m period, yellow (stored 0.85, 0.70, 0.10) on black.
  - A clean edge, and no diffusion over it.
- Logos are a stretch goal: a dark or coloured band where the concept has one is enough. Text is not
  needed.

## 4. Then all twelve
Run the method on all twelve k-models. k01 (the mech wreck), k09 (the billboard) and k11 (rubble)
keep their concept palettes too.

**Gates:**
- **Concept fidelity.** One sheet, twelve rows: concept | in-game at 15 m | in-game at 40 m, at the
  dusk time the street cameras use. Every white object reads white or light grey, and every hazard
  band shows.
- **Wedges.** `tools/citykit/wedge.py` on A5deck and A1yard: at most 1.5×.
- **Unchanged.** `rebase_glb.py --check` PASS; kit draws at the A1 spawn stay at 98 or under; report
  the VRAM delta.
- **The settle bake.** city-art r12 is also running and re-bakes LAST. Re-bake when you finish and say
  so in `status/city-kit.md`, then run `test_settle_cache` and `float_audit` STRUCTURE = 0.
- **For the user.** A5deck, A1yard, A3st and A6garden as a before/after sheet, at the shipping default
  scale.

Commit per step with an explicit path list. Report in `status/city-kit.md` (an r8 section).
