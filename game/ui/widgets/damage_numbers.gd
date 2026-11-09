extends HudWidget
## Damage numbers (brief §6, juice-impact §8): floating values at the point of impact. They live 0.7 s,
## rise 80 px and merge into one rolling number per target inside 150 ms so a gatling burst does not
## bury the screen. White normal, amber crit / weak point, blue for damage the shield ate.
## The whole widget obeys the `damage_numbers` preference (SPEC §9).

const LIFE := 0.7                ## s
const RISE := -96.0              ## px travelled over the lifetime
const SIDE := 92.0               ## px right of the impact: clear of the enemy plate above it
const MERGE_WINDOW := 0.15       ## s, juice §8
const POP_TIME := 0.12           ## s the crit pop takes
const CRIT_POP := 1.35
const MAX_NUMBERS := 24

var prefs: HudPrefs = null
var numbers: Array[Dictionary] = []


func _ready() -> void:
	super()
	Events.hit_landed.connect(_on_hit)
	Events.attack_blocked.connect(_on_blocked)


func _on_hit(hit: HitInfo, receiver: Node) -> void:
	if hit == null or receiver == Game.player or hit.finisher:
		return
	var p := Game.player
	if p == null or hit.source == null or not (hit.source == p or p.is_ancestor_of(hit.source)):
		return
	var amount := hit.final_amount if hit.final_amount > 0.0 else hit.amount
	var kind := &"crit" if (hit.weak_point or hit.crit) else &"normal"
	spawn(amount, hit.position, kind, receiver.get_instance_id())


func _on_blocked(hit: HitInfo) -> void:
	if hit == null or Game.player == null:
		return
	spawn(hit.amount, Game.player.global_position + Vector3.UP * 6.0, &"shield", 0)


## Adds a number, merging into a live one for the same target inside the merge window (juice §8).
func spawn(amount: float, world_pos: Vector3, kind: StringName, target_id: int) -> void:
	if prefs != null and not prefs.get_bool(&"damage_numbers"):
		return
	if amount <= 0.0 or data == null or data.camera == null:
		return
	for n in numbers:
		if int(n["target"]) == target_id and float(n["age"]) < MERGE_WINDOW:
			n["value"] = float(n["value"]) + amount
			n["age"] = 0.0
			n["kind"] = kind if kind != &"normal" else n["kind"]
			return
	var p := data.project(world_pos)
	if not bool(p["visible"]):
		return
	if numbers.size() >= MAX_NUMBERS:
		numbers.pop_front()
	numbers.append({"at": p["pos"] + Vector2(SIDE + randf_range(-10.0, 10.0), randf_range(-10.0, 6.0)),
			"value": amount, "kind": kind, "age": 0.0, "target": target_id})


func update_hud(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for n in numbers:
		n["age"] = float(n["age"]) + delta
		if float(n["age"]) < LIFE:
			kept.append(n)
	numbers = kept
	visible = not numbers.is_empty()


func color_for(kind: StringName) -> Color:
	match kind:
		&"crit": return HudPalette.AMBER
		&"shield": return HudPalette.CYAN
		_: return HudPalette.WHITE


func _draw() -> void:
	for n in numbers:
		var t := float(n["age"]) / LIFE
		var kind := StringName(n["kind"])
		var pop := 1.0
		if kind == &"crit" and float(n["age"]) < POP_TIME:
			pop = lerpf(CRIT_POP, 1.0, float(n["age"]) / POP_TIME)
		var col := color_for(kind)
		# Hold full strength for most of the rise and fade in the last third: a number that is already
		# half transparent when it appears reads as decoration, not as a hit (juice-impact §8).
		col.a = 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
		var s := "%d" % int(round(float(n["value"])))
		var size := int(round(float(HudPalette.SIZE_NUM) * pop))
		var at := (n["at"] as Vector2) + Vector2(0.0, RISE * t)
		HudPalette.draw_text(self, font(), at - Vector2(text_w(s, size) * 0.5, 0.0), s, size, col,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
