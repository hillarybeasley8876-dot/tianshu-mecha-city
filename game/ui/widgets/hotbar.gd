extends HudWidget
## Skill hotbar (brief §4, skills-catalog §4.9, look review item 12): the left hand's four verbs sit in
## a 2×2 hex cluster just above the armour bar, the right hand's four above the weapon panel. The
## bottom CENTRE is left to the world — the twin 330 px arcs used to wall off the street the monsters
## walk down, and one Ripper's plate ended up trapped inside the overdrive ring.

const HEX := 18.0                 ## px circumradius — 36 px across the flats (item 12.2)
const COL_GAP := 44.0             ## px between the two columns of a cluster
const ROW_GAP := 42.0             ## px between the two rows
const CORNER := Vector2(64.0, 214.0)  ## px from the left edge / bottom edge to a cluster's top-left
const MISSILE_CD_MAX := 14.0       ## s, combat/weapons/tuning/missile_tuning.gd (not in hud_state)

## id, label, action, mode — the layout the brief specifies, left hand first.
const LAYOUT: Array[Array] = [
	["guard", "镜返盾 GUARD", &"guard", HudHotSlot.Mode.GUARD],
	["rift_step", "裂隙步 RIFT", &"rift_step", HudHotSlot.Mode.COOLDOWN],
	["well", "暗流引井 WELL", &"well", HudHotSlot.Mode.COOLDOWN],
	["fins", "日冕翼片 FINS", &"fins", HudHotSlot.Mode.COOLDOWN],
	["missiles", "雹暴齐射 MSL", &"missiles", HudHotSlot.Mode.MISSILES],
	["anchor", "天钩锚 ANCHOR", &"anchor", HudHotSlot.Mode.COOLDOWN],
	["burst", "震核爆 BURST", &"burst", HudHotSlot.Mode.COOLDOWN],
	["melee", "曦刃 SABER", &"melee", HudHotSlot.Mode.MELEE],
]

var slots: Array[HudHotSlot] = []
var glyphs: HudGlyphs = null

var _was_ready: Dictionary = {}


func _ready() -> void:
	super()
	glyphs = HudGlyphs.new()
	for row in LAYOUT:
		var s := HudHotSlot.new()
		s.id = StringName(row[0])
		s.label = String(row[1])
		s.action = row[2]
		s.mode = int(row[3])
		add_child(s)
		slots.append(s)
		_was_ready[s.id] = true
	resized.connect(_place)
	_place.call_deferred()


## Two 2×2 clusters of slot CENTRES: the left hand bottom-left above the armour bar, the right hand
## bottom-right above the weapon panel.
func _place() -> void:
	var s := screen_size()
	for i in slots.size():
		var right := i >= 4
		var k := i % 4
		var col := float(k % 2)
		var row := float(k / 2)
		var x := CORNER.x + col * COL_GAP
		if right:
			x = s.x - CORNER.x - COL_GAP + col * COL_GAP
		var at := Vector2(x, s.y - CORNER.y + row * ROW_GAP)
		slots[i].position = at - slots[i].size * 0.5


## The blocks of screen the clusters claim, so enemy plates keep off them (look review item 10.4).
func chrome_rect() -> Rect2:
	var s := screen_size()
	var w := COL_GAP + HEX * 2.0 + 10.0
	var h := ROW_GAP + HEX * 2.0 + 10.0
	var top := s.y - CORNER.y - HEX - 5.0
	return Rect2(Vector2(CORNER.x - HEX - 5.0, top), Vector2(w, h)) \
			.merge(Rect2(Vector2(s.x - CORNER.x - COL_GAP - HEX - 5.0, top), Vector2(w, h)))


func slot(id: StringName) -> HudHotSlot:
	for s in slots:
		if s.id == id:
			return s
	return null


func update_hud(delta: float) -> void:
	visible = data.alive() and data.has("en")
	if not visible:
		return
	glyphs.poll()
	for s in slots:
		s.tick(delta)
		s.glyph = glyphs.glyph(s.action)
		s.outage = data.flag("outage")
		_bind(s)
		var now_ready: bool = s.ready_now
		if now_ready and not bool(_was_ready[s.id]):
			s.signal_ready()
		_was_ready[s.id] = now_ready
		s.queue_redraw()


## Reads one slot's numbers out of the merged snapshot. Every branch tolerates its component being
## absent: the slot simply greys out instead of the HUD throwing.
func _bind(s: HudHotSlot) -> void:
	s.active = false
	s.charge = 0.0
	s.lock_count = 0
	match s.mode:
		HudHotSlot.Mode.GUARD:
			var broken := data.flag("guard_break")
			s.ready_now = data.has("guarding") and not broken
			s.wipe = 1.0 if broken else 0.0
			s.active = data.flag("guarding")
			s.charges = 1
			s.charges_max = 1
		HudHotSlot.Mode.MISSILES:
			var cd := data.num("missile_cd")
			s.wipe = clampf(cd / MISSILE_CD_MAX, 0.0, 1.0)
			s.ready_now = cd <= 0.0
			s.lock_count = int(data.num("missile_locks"))
			s.charges = 1
			s.charges_max = 1
			s.active = data.flag("missile_painting")
		HudHotSlot.Mode.MELEE:
			s.charge = clampf(data.num("charging"), 0.0, 1.0)
			s.ready_now = true
			s.wipe = 0.0
			s.charges = 1
			s.charges_max = 1
			s.active = data.flag("execution_available") or int(data.num("combo_step")) > 0
		_:
			_bind_cooldown(s)


func _bind_cooldown(s: HudHotSlot) -> void:
	var key := String(s.id)
	if not data.has("%s_cd" % key):
		s.ready_now = false
		s.wipe = 1.0
		s.charges = 1
		s.charges_max = 1
		return
	s.charges = int(data.num("%s_charges" % key, 1.0))
	s.charges_max = maxi(s.charges, int(data.num("%s_charges_max" % key, float(s.charges))))
	s.ready_now = data.flag("%s_ready" % key)
	var cd_max := maxf(data.num("%s_cd_max" % key, 1.0), 0.001)
	s.wipe = 0.0 if s.ready_now else clampf(data.num("%s_cd" % key) / cd_max, 0.0, 1.0)
	s.active = _is_running(s)


## "Running" is spelled differently by each skill's hud_state(); collected here so the layout stays
## readable and a new skill only needs one line.
func _is_running(s: HudHotSlot) -> bool:
	match s.id:
		&"fins": return data.flag("fins_out") or data.num("ward_left") > 0.0
		&"well": return data.num("well_left") > 0.0
		&"anchor": return data.flag("anchor_attached")
		_: return false
