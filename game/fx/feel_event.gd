@tool
class_name FeelEvent
extends Resource
## One row of docs/FEEL.md as data (fx/events/<id>.tres). FeelDirector.play(id) fires every column.
## All durations are seconds unless a field name says otherwise. Numbers come from FEEL.md; a field
## left at 0 / empty means "this event does not use that channel".
##
## Frame columns in FEEL.md are 60 fps frames ("2 f") and are converted with FRAME.

const FRAME := 1.0 / 60.0

enum Stop {
	NONE,    ## no freeze at all (gunfire, movement: never freeze player-started motion)
	LOCAL,   ## attacker + victim only; the caller runs Feel.local_hit_stop(actors, hitstop_seconds)
	GLOBAL,  ## rate-limited micro-freeze of the whole game through Feel.hit_stop()
}

@export var id: StringName = &""

@export_group("Hit-stop")
@export var hitstop_kind: Stop = Stop.NONE
@export var hitstop_seconds: float = 0.0  ## FeelDirector.hitstop_seconds(id) exposes this to callers

@export_group("Shake")
@export var trauma: float = 0.0            ## added, clamped to 1; shake = trauma^2 (Eiserloh)
@export var kick_deg: float = 0.0          ## directional spring kick (recoil, hit direction)
@export var kick_dir: Vector3 = Vector3.UP ## world direction the camera is shoved towards
@export var kick_seconds: float = 0.2

@export_group("Flash / post")
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.0)  ## alpha 0 = no full-screen flash
@export var flash_frames: int = 0
@export var post: Array[StringName] = []   ## subset of: chromatic, radial_blur, vignette, speed_lines, desaturate
@export var chromatic_px: float = 0.0
@export var radial_blur: float = 0.0       ## UV strength, 0.02..0.06
@export var vignette: float = 0.0          ## 0..1 strength, tinted with vignette_color
@export var vignette_color: Color = Color(0.85, 0.06, 0.05)
@export var speed_lines: float = 0.0       ## 0..1 procedural streak opacity
@export var desaturate: float = 0.0        ## 0..1 (witch time / low HP)
@export var impact_frames: int = 0         ## B/W Kanada impact frame count (finishers, boss stagger)
@export var post_seconds: float = 0.12

@export_group("Camera")
@export var fov_delta: float = 0.0         ## degrees, clamped to +/-15 by the sum in the camera rig
@export var fov_seconds: float = 0.25

@export_group("Time")
@export var slow_scale: float = 1.0        ## < 1 = slow motion
@export var slow_seconds: float = 0.0
@export var slow_witch: bool = false       ## perfect-dodge witch time (player keeps speed)

@export_group("VFX")
@export var vfx: Array[StringName] = []    ## VfxLibrary kinds, spawned in order
@export var vfx_delays: PackedFloat32Array = []  ## seconds before each entry fires (chained blasts)
@export var vfx_scale: float = 1.0
@export var decal: StringName = &""        ## DecalPool kind (&"", scorch, scorch_ring, land_crater)

@export_group("Shockwave ring")
## Used when `shockwave_ring` is in `vfx` (FEEL.md gives a radius and a time per row, e.g. a missile
## hit expands 0 -> 20 m in 180 ms), so ring size never has to be faked with vfx_scale.
@export var ring_radius: float = 8.0
@export var ring_seconds: float = 0.18
@export var ring_color: Color = Color(1.0, 0.54, 0.17, 1.0)

@export_group("Flash light")
@export var light_color: Color = Color(1.0, 0.54, 0.17, 0.0)  ## alpha 0 = no pooled OmniLight3D pop
@export var light_energy: float = 8.0
@export var light_range: float = 12.0      ## metres
@export var light_frames: int = 0

@export_group("Audio")
@export var audio: Array[StringName] = []  ## layer ids for the audio unit (T/B/S/M/Tl/D/UI)

@export_group("Rumble")
@export var rumble_weak: float = 0.0       ## high-frequency motor
@export var rumble_strong: float = 0.0     ## low-frequency motor
@export var rumble_ms: int = 0

@export_group("Afterimages")
## Ghosts of `Game.player.model()` left along the dash / dodge arc (FEEL.md:31-32). They fire
## `ghost_spread` seconds apart so each one catches a different pose instead of stacking into a
## blob — three on one pose is the Overdrive r2 defect.
@export var ghosts: int = 0
@export var ghost_spread: float = 0.05    ## seconds between two ghosts
@export var ghost_life: float = 0.22      ## seconds each ghost lives

@export_group("Limits")
@export var falloff: float = 0.0           ## metres; 0 = no distance falloff
@export var cooldown: float = 0.0          ## per-id rate limit, seconds of real time
## Shares the swarm-kill budgets (FEEL.md:42-43): at most one GLOBAL stop per 2 s and one slow-mo
## per 6 s, and past `budget_falloff` of the falloff radius the row plays its victim's local stop
## only. Rows that leave it false always fire — the boss death is the climax, and the player's own
## damage must never be swallowed by a swarm kill's budget.
@export var budgeted: bool = false
@export var budget_falloff: float = 0.5


## True when the event drives the named screen effect (see Feel.post effect ids).
func uses_post(effect: StringName) -> bool:
	return effect in post


## Flash duration in seconds from the frame column (0 when the event has no flash).
func flash_seconds() -> float:
	return float(flash_frames) * FRAME


func has_slow_mo() -> bool:
	return slow_seconds > 0.0 and slow_scale < 1.0
