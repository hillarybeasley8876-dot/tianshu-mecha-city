class_name SkillVfx
extends Node3D
## Pool for every effect the skills unit draws itself (CONTRACTS §1: `fx/**` belongs to the feel unit,
## so each ability's signature geometry lives under `combat/skills/fx/`). Built once with the
## SkillSystem and never allocates at fire time; the oldest live piece is recycled when a pool runs
## dry, which is the same rule the shared VfxLibrary uses.
##
## The node is `top_level`, so pieces left standing in the world (a Shockcore shell, a rift decoy)
## do not ride along with the mech that spawned them.

const SIZES: Dictionary = {
	# shell/ring are shared by the Shockcore shell, the well ripples and every fin muzzle + hit pop,
	# so they carry the largest pools: six fins firing at 0.22 s keep ~12 shells alive at once.
	# `trail` is a second beam pool for the fin ribbons only: six fins drop a 0.24 s ribbon every
	# 0.045 s (~30 live), which used to flood the shared beam pool and steal the Skyhook cable and the
	# Lance layers out from under their owners (audit #6).
	&"shell": 14, &"ring": 14, &"beam": 28, &"trail": 40, &"column": 3, &"arcs": 3,
	&"inflow": 6, &"sheath": 2, &"decoy": 2, &"brackets": 2, &"haze": 3,
}

var vignette: SkillGoldVignette = null

var _pools: Dictionary = {}     ## kind -> Array[SkillFxPiece]
var _cursor: Dictionary = {}    ## kind -> int


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for kind: StringName in SIZES:
		var pool: Array[SkillFxPiece] = []
		for i in int(SIZES[kind]):
			var piece := _build(kind)
			piece.name = "%s%d" % [kind, i]
			add_child(piece)
			pool.append(piece)
		_pools[kind] = pool
		_cursor[kind] = 0
	vignette = SkillGoldVignette.new()
	vignette.name = "GoldVignette"
	add_child(vignette)


func _build(kind: StringName) -> SkillFxPiece:
	match kind:
		&"shell": return SkillFxShell.new()
		&"ring": return SkillFxRing.new()
		&"beam": return SkillFxBeam.new()
		&"trail": return SkillFxBeam.new()
		&"column": return SkillFxColumn.new()
		&"arcs": return SkillFxArcs.new()
		&"inflow": return SkillFxInflow.new()
		&"sheath": return SkillFxSheath.new()
		&"decoy": return SkillFxDecoy.new()
		&"haze": return SkillFxHaze.new()
		_: return SkillFxBrackets.new()


## First free piece of `kind`. When the pool is dry the BUSIEST-SOONEST piece is recycled — the one
## with the least life left — so a burst of short one-shots can never hijack a piece that an owner is
## holding open (the Skyhook cable and the three Lance layers are opened with a 3,600 s life and are
## therefore always stolen last; audit #6).
func take(kind: StringName) -> SkillFxPiece:
	var pool: Array = _pools.get(kind, [])
	if pool.is_empty():
		return null
	var start: int = int(_cursor.get(kind, 0))
	for i in pool.size():
		var slot := (start + i) % pool.size()
		if (pool[slot] as SkillFxPiece).free_to_use():
			_cursor[kind] = (slot + 1) % pool.size()
			return pool[slot]
	var soonest := pool[0] as SkillFxPiece
	var best: float = soonest.life_left()
	for piece: SkillFxPiece in pool:
		if piece.life_left() < best:
			best = piece.life_left()
			soonest = piece
	_cursor[kind] = (pool.find(soonest) + 1) % pool.size()
	soonest.stop()
	return soonest


## Typed accessors — one per signature effect, so a skill reads as `vfx.shell().fire(...)`.
func shell() -> SkillFxShell:
	return take(&"shell") as SkillFxShell


func ring() -> SkillFxRing:
	return take(&"ring") as SkillFxRing


func beam() -> SkillFxBeam:
	return take(&"beam") as SkillFxBeam


## Ribbon pool: the Corona Fins' flight trails, kept away from the shared beam pool (audit #6).
func trail() -> SkillFxBeam:
	return take(&"trail") as SkillFxBeam


func column() -> SkillFxColumn:
	return take(&"column") as SkillFxColumn


func arcs() -> SkillFxArcs:
	return take(&"arcs") as SkillFxArcs


func inflow() -> SkillFxInflow:
	return take(&"inflow") as SkillFxInflow


func sheath() -> SkillFxSheath:
	return take(&"sheath") as SkillFxSheath


func decoy() -> SkillFxDecoy:
	return take(&"decoy") as SkillFxDecoy


func brackets() -> SkillFxBrackets:
	return take(&"brackets") as SkillFxBrackets


func haze() -> SkillFxHaze:
	return take(&"haze") as SkillFxHaze


func stop_all() -> void:
	for kind: StringName in _pools:
		for piece: SkillFxPiece in _pools[kind]:
			piece.stop()
	if vignette != null:
		vignette.close()


## Diagnostics for the tests and the capture driver.
func live_count() -> int:
	var n := 0
	for kind: StringName in _pools:
		for piece: SkillFxPiece in _pools[kind]:
			if not piece.free_to_use():
				n += 1
	return n
