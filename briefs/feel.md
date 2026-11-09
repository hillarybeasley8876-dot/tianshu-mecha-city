# Brief: feel — FeelDirector, FEEL table data, screen post-process, VFX library

## Goal
Every hit, kill, dash and landing feels heavy and crisp. You implement the data-driven feel system: each
`docs/FEEL.md` row becomes a `FeelEvent` resource; `Feel.play(&"id", pos, strength)` fires all columns.
You also build the shared VFX library (sparks, blasts, shockwaves, dust, debris, decals, flash lights) and
the full-screen post effects. Quality bar: AC6 / Titanfall 2 impact, never over-juiced (dossier rule 12).

## Read first
`docs/FEEL.md` (all), `ref/research/juice-impact.md` (all; §1 architecture, §4 screen FX, §6 VFX, §12
over-juicing), `docs/CONTRACTS.md` §2–4, `game/core/feel.gd` (you implement its signals' visuals),
`docs/ART.md` when it exists (colour of effects: hero cyan #4FE6FF, enemy acid green #9BFF3A / violet
#B04CFF, explosions warm orange #FF8A2B).

## You own
`game/fx/**`: `feel_director.tscn/.gd` (instanced by main), `feel_event.gd` (Resource class `FeelEvent`),
`events/<id>.tres` (one per FEEL row), `screen_fx/` (CanvasLayer + shader), `vfx/` (particle scenes,
`vfx_library.gd` with a pooled `spawn(kind, pos, normal, scale)` API used by every unit), `decals/`, tests.

## Build
1. **FeelEvent** fields = FEEL columns: hitstop kind (none/local/global) + seconds, trauma, kick
   (deg, dir), flash colour/alpha/frames, post effect list (chromatic px, radial blur, vignette, speed
   lines, desaturate, B/W frame), fov delta + times, slow-mo scale/seconds/witch, vfx kinds + scale,
   decal kind, audio ids (layers), rumble weak/strong/ms, falloff metres, cooldown (rate limit per id).
2. **FeelDirector** listens to `Feel.event_requested`; applies distance falloff from the active camera;
   per-id rate limits; local hit-stop needs the actors — `Feel.play` callers that need local hit-stop
   pass them by calling `Feel.local_hit_stop` themselves; your FeelEvent only stores the seconds and you
   expose `FeelDirector.hitstop_seconds(id)` so callers read the number (no duplication).
3. **Screen FX**: one CanvasLayer (layer 50) with a full-rect ColorRect shader that reads
   SCREEN_TEXTURE (`hint_screen_texture`) for: white/red/colour flash, red damage vignette, chromatic
   aberration (px), radial blur (centre + strength), speed lines (procedural, alpha by speed), desaturate
   (witch time tint cyan edge), 1–2 frame B/W impact frame. Listens to `Feel.flash_requested`,
   `post_requested`, `witch_time_changed`. Respect `Feel.intensity` and Settings.
4. **VFX library** (pooled, no per-shot instantiate): `spark_bullet`, `spark_beam`, `scorch`,
   `missile_blast`, `kill_small`, `kill_large`, `shockwave_ring` (expanding fresnel ring mesh),
   `dust_ring`, `dust_puff`, `debris` (pooled RigidBody3D chunks on `Layers.DEBRIS`, sleep and fade
   after 6 s), `land_crater` decal, `scorch_ring` decal, `steam`, `thruster_burst`, `afterimage` helper
   (copies a MeshInstance pose with a fading unlit shader). GPUParticles3D one-shots with trails where
   it helps; flash OmniLight3D pool (max 8, 3 f). Decals: ring buffer of 96.
5. **Rumble mixing**: max of active envelopes, never the sum (dossier rule 10).

## Done when
- `tools/godot.sh check --only=res://fx/` → 0 errors; every id in FEEL.md has `fx/events/<id>.tres`
  (a test parses FEEL.md's table and checks).
- `tools/godot.sh test res://fx/tests/test_feel.gd`: rate limits, falloff, global hit-stop calls core,
  unknown id warns once, 300 sparks + 40 blasts + 96 decals in one frame keep frame time < 8 ms extra
  (measure with Time.get_ticks_usec around the spawn calls and over 60 frames).
- **Feel gallery**: `fx/tests/feel_gallery.tscn` plays every FEEL id in the sandbox in front of a static
  camera, 1.5 s apart, labelled on screen. Capture it with a timeline that only ends the run
  (`fx/tests/gallery_timeline.json` = `[{"t": 75, "end": true}]`): `tools/godot.sh movie
  --movie=/Users/minimax/m/mecha-city/captures/feel_gallery.avi --scene=res://fx/tests/feel_gallery.tscn
  --timeline=res://fx/tests/gallery_timeline.json` plus 10 stills
  `captures/feel_*.jpg` (blast, shockwave, sparks, decals, flash, chromatic, radial blur, speed lines,
  witch tint, impact frame). Look at them: effects must read clearly on the grey sandbox AND not white
  out the screen.
