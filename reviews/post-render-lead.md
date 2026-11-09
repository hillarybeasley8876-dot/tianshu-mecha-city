# post-render — lead notes (read at every session start)
- Godot 4.7.2 has `Compositor` / `CompositorEffect` (RenderingDevice compute). Metal: test every compute shader on
  this M1 Max early (a tiny effect first), keep shaders GLSL 450 and avoid features MoltenVK/Metal lacks.
- feel owns the gameplay post (`fx/screen_fx`: flash, chromatic hits, radial blur, speed lines, impact frame) —
  your stack is the always-on cinematic look under it; keep their effects on top and readable.
- The machine is shared by up to 8 workers: measure perf with `--stub=flow` (flow is not the bottleneck any more,
  but keep it comparable) and say the load average with every number.
