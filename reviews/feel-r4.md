# feel — review r4 (lead, audit round) — PASS

18/18 findings fixed with regression proof (each fix reverted → its checks fail), the export-safe event listing
(44 rows load via `ResourceLoader.list_directory`), a new 32-check clocks suite, 52/0 feel suite, a
`--nan-watch` fight clean (p50 16.8 ms). Both requests done by the lead: CONTRACTS §2 now lists the shader
globals (fx_opacity / fx_pixel_scale are declared in project.godot; VfxLibrary only sets them) and the
export-safety rule. Polish queue: smoke/dust/steam sizing via `node.scale` under `local_coords = false`.
