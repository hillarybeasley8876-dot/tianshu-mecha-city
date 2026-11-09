class_name BroodTitan
extends EnemyBase
## 巢母 BROOD TITAN — the 60 m climax (boss unit). SPEC §7/§7.1: 150,000 HP, stability 9,000 with a
## 3.4 s stagger and 6 s immunity, three 8,000 HP weak cores whose breaks each remove an attack, and
## three phases at 65 % / 30 % with a 2.6 s roar between them.
##
## Everything numeric lives in `BossTuning`; every attack's resolution lives in `BossCombat`. This
## file is the actor: stats, body, cores, the damage pipeline, phases and the death sequence.

## Emitted when a core breaks, so the director can run the stagger cinematic and the HUD can flash it.
signal core_broken(core: BossCore)
## Emitted on every phase change (1 → 3) before the boss goes invulnerable for the roar.
signal phase_changed(phase: int)
## Emitted the instant the killing blow lands; the director owns the 4 s victory beat after it.
signal death_started()

var phase: int = 1
var cores: Array[BossCore] = []

var _table: Array[EnemyAttack] = []
var _removed: Array[StringName] = []
var _spawner: EnemySpawner = null
var _transition_left: float = 0.0
var _collapsing: bool = false
var _collapse: BossCollapse = null
var _collapse_elapsed: float = 0.0
var _demanded: StringName = &""
## m the titan may drop below the deck under it, and rise above it, before `_clamp_height` puts it
## back on a ring point. The gate is |y − deck| < 20 m for 30 s after a RETRY.
const HEIGHT_DROP := 20.0
const HEIGHT_RISE := 40.0


func _ready() -> void:
	enemy_type = BossTuning.TYPE
	circle_speed = 0.2
	wreck_lifetime = 1.0e9   ## the death sequence owns the body; EnemyBase must not dissolve it
	super._ready()


# --- stats and body -----------------------------------------------------------------------------

## EnemyBase reads its numbers from `EnemyTypes`, which is enemies-owned and has no titan row, so the
## titan applies its own before the body is built (EnemyBase calls this hook from `_ready`).
func _apply_stats() -> void:
	hp_max = BossTuning.HP_MAX
	hp = hp_max
	body_height = BossTuning.HEIGHT
	mass_kg = BossTuning.MASS
	move_speed = BossTuning.MOVE_SPEED
	turn_rate = BossTuning.TURN_RATE
	engage_range = BossTuning.ENGAGE
	# A 60 m colossus has a 50 m head and a 1.5 km voice: EnemyBase's defaults (320 m, 75°) come from
	# EnemyTypes, which has no titan row. It also never loses the player — the whole crown is its arena.
	perception.configure(self, BossTuning.SIGHT, 180.0)
	status.configure({
		"stability": BossTuning.STABILITY, "decay": BossTuning.STABILITY_DECAY,
		"decay_delay": BossTuning.DECAY_DELAY, "stagger": BossTuning.STAGGER_TIME,
		"immunity": BossTuning.STAGGER_IMMUNITY,
	})


## Body capsule, three hurtboxes (body / head / armoured legs), the body lock point and the cores.
## The shapes live in `BossBody` for the same reason the enemies unit has `EnemyBodyBuilder`.
func _build_body() -> void:
	_apply_stats()
	# Its own adds must never be its floor: `move_and_slide` reads a body it is standing on as a moving
	# platform, and a summoned add that Jolt then moves to its ring point hands the titan that motion
	# (r5 brief item 3). It still collides with them — only the FLOOR test is narrowed.
	platform_floor_layers = Layers.WORLD | Layers.PROPS
	for core: BossCore in BossBody.build(self):
		core.shattered.connect(_on_core_broken)
		cores.append(core)


func on_spawned() -> void:
	add_to_group(&"boss")
	_table = BossCombat.build_table(phase, _removed)
	_attach_spawner()
	# The titan announces itself the moment it is in the world (SPEC §8: the music is at 1.0 here).
	Audio.music_intensity(1.0)


## The AddSpawner is a SIBLING of the titan, never its child. `EnemySpawner.spawn()` calls
## `add_child()` on a new add before it sets that add's transform, so an add parented to the titan is
## created at the titan's own feet: for one tick it IS the titan's floor, and the next step hands the
## titan the adds' ring-point motion as platform velocity. The acceptance per-tick trace measured that
## as a 68-134 m fling in a single 1/120 s tick, at the first summon of every fight (r5 brief item 3).
func _attach_spawner() -> void:
	if _spawner != null and is_instance_valid(_spawner):
		return
	var parent := get_parent()
	if parent == null:
		push_error("BroodTitan: no parent to put the AddSpawner under — the summon is disabled")
		return
	_spawner = EnemySpawner.new()
	_spawner.name = "AddSpawner"
	_spawner.auto_spawn = false
	_spawner.leash = false
	parent.add_child(_spawner)


func _make_brain() -> EnemyBrain:
	return BossBrain.new()


func spawner() -> EnemySpawner:
	return _spawner


# --- damage -------------------------------------------------------------------------------------

## `EnemyTypes.ARMOUR` has no titan row, so the per-part multiplier is applied here before the
## shared pipeline runs. Cores arrive already stripped of their weak-point flag (see BossCore), so
## the core parts are ×1.0 against the main pool exactly as SPEC §7.1 requires.
func take_hit(hit: HitInfo) -> void:
	# The phase roar is a cutscene, not a damage window: a player who keeps firing through it must not
	# be able to skip the next threshold, and the boss must not be punished for its own cinematic.
	if not alive or _collapsing or _transition_left > 0.0:
		return
	var mult := BossTuning.armour_for(hit.hurtbox_part)
	if not is_equal_approx(mult, 1.0):
		hit.amount *= mult
		hit.stagger *= mult
	super.take_hit(hit)
	BossPlate.push(self)
	_check_phase()


## A core that empties staggers the titan and takes its attack away for the rest of the fight.
func _on_core_broken(core: BossCore) -> void:
	if core.removes != &"" and core.removes not in _removed:
		_removed.append(core.removes)
		_table = BossCombat.build_table(phase, _removed)
	# Breaking a core always staggers, even inside the immunity window: it is the payoff for the
	# whole phase, and a stagger the player cannot use would be a lie.
	status.add_impact(BossTuning.STABILITY * 2.0)
	play_action(&"core_break")
	Feel.play(&"boss_stagger", global_position, 1.0)
	core_broken.emit(core)


## skills-catalog §4.6: a Core Rend on a Colossus is 12 % of max HP and is never lethal.
func execute_hit(by: Node3D, _damage: float = 0.0) -> void:
	if not is_executable(by):
		return
	var hit := HitInfo.make(hp_max * BossTuning.EXECUTE_FRACTION, HitInfo.MELEE, by, &"core_rend")
	hit.finisher = true
	hit.position = centre()
	hit.stagger = 0.0
	take_hit(hit)
	Feel.play(&"finisher", global_position, 1.0)


# --- phases -------------------------------------------------------------------------------------

func _check_phase() -> void:
	if not alive:
		return
	var want := BossTuning.phase_for(hp / maxf(hp_max, 1.0))
	if want <= phase:
		return
	phase = want
	_table = BossCombat.build_table(phase, _removed)
	_transition_left = BossTuning.PHASE_CINEMATIC
	set_ai_enabled(false)
	invulnerable_transition()
	play_action(&"phase_roar")
	Feel.play(&"boss_roar", global_position, 1.0)
	Audio.music_intensity(1.0)
	if phase >= 3:
		_storm_on()
	phase_changed.emit(phase)
	Events.boss_phase.emit(phase)


## Nothing the player does during the roar may be punished, so the titan stops resolving hits.
func invulnerable_transition() -> void:
	_transition_left = maxf(_transition_left, BossTuning.PHASE_CINEMATIC)


## The roar the flow unit asks for when a spire falls (FlowProgress calls `roar()` on `&"boss"`),
## and the intro beat. Non-interactive: it does not interrupt an attack in progress.
func roar() -> void:
	if alive and _transition_left <= 0.0:
		play_action(&"roar")
	Feel.play(&"boss_roar", global_position, 1.0)


func _storm_on() -> void:
	# CONTRACTS §7 environment hook: the violet storm around the crown. No environment = no-op.
	get_tree().call_group(&"time_of_day", &"set_storm", BossTuning.STORM_AMOUNT,
			BossTuning.STORM_SECONDS)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_keep_the_scent()
	_stay_on_the_deck()
	if _transition_left > 0.0:
		_transition_left -= delta
		if _transition_left <= 0.0:
			set_ai_enabled(true)
	if _collapsing:
		_tick_collapse(delta)


## Perception's line-of-sight test runs from a monster's ankles, which for a 60 m body means the
## crown's own steps can hide the player from it. A colossus on a 300 m disc always knows where its
## one opponent is, so it re-acquires rather than standing blind.
func _keep_the_scent() -> void:
	if not alive or perception.target != null:
		return
	var player := Game.player
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		perception.acquire(player, false)


## A 60 m body steered straight at its target walks off its own arena and falls down the Spire — the
## city test caught it 300 m out and 120 m below the deck. The Crown is the fight, so the titan is
## held inside it: its feet never cross the rim and its height never leaves the deck, whatever the
## deck under it does. The radius alone was not enough: a fling that drove the beast under the deck
## left it on the S3 collar for good, where the player cannot see it and the arena catapults them
## back up (r5 brief item 3).
func _stay_on_the_deck() -> void:
	if not alive or _collapsing:
		return
	var arena := get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if arena == null:
		return
	_clamp_height(arena)
	_clamp_radius(arena)


## The intro walks the titan up over the rim from below, so the height clamp only runs once the beast
## is fighting (`_ai_enabled` is off for the whole climb).
func _clamp_height(arena: BossArena) -> void:
	if not _ai_enabled:
		return
	var deck := arena.floor_y_at(global_position)
	if global_position.y >= deck - HEIGHT_DROP and global_position.y <= deck + HEIGHT_RISE:
		return
	global_position = arena.ring_point(0.25, 0.72, 0.0)
	velocity = Vector3.ZERO


func _clamp_radius(arena: BossArena) -> void:
	var out := global_position - arena.global_position
	out.y = 0.0
	var limit := BossTuning.DECK_RADIUS - BossTuning.RADIUS
	if out.length() <= limit:
		return
	global_position -= out.normalized() * (out.length() - limit)
	velocity.x = 0.0
	velocity.z = 0.0


# --- death --------------------------------------------------------------------------------------

## The killing blow: slow-mo, JACKPOT, a chain of blasts up the body, then the corpse goes over the
## deck edge trailing dust and smoke (brief §5). The director listens to `death_started` and owns the
## 4 s victory beat.
func _die(hit: HitInfo) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	_collapsing = true
	_collapse_elapsed = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for child in get_children():
		if child is Hurtbox:
			(child as Hurtbox).collision_layer = 0
	remove_from_group(&"enemy")
	if _brain != null:
		_brain.stop()
	end_telegraph()
	set_ai_enabled(false)
	_collapse = BossCollapse.begin(self, model)
	Feel.play(&"boss_kill", global_position, 1.0)
	if hit.weapon in [&"rifle_stage2", &"zenith_lance"]:
		Feel.play(&"jackpot", global_position, 1.0)
	Audio.play(&"kill_large", global_position)
	play_action(&"death_fall")
	Events.enemy_killed.emit(self, hit)
	death_started.emit()
	died.emit(self)


## The body turns to face the rim and the chain of blasts starts walking up it; `BossCollapse` owns
## everything after this line.
func _tick_collapse(delta: float) -> void:
	if _collapse == null:
		return
	# EnemyBase stops ticking visuals the moment an actor dies, so the killing blow's white hit flash
	# and the red telegraph tint stay on the corpse for the whole victory beat: the titan read as a
	# white silhouette instead of a falling body. The collapse owns them from here.
	visuals.tick_flash(delta)
	visuals.tick_telegraph(delta)
	_collapse.tick(delta)
	if _collapse.finished:
		_collapse_elapsed += delta
		if _collapse_elapsed > BossCollapse.smoke_seconds():
			_collapse.release()


## The borrowed edge smoke outlives the topple; the director frees the body after the victory beat,
## so it is given back from here as well as from `_exit_tree`.
func _exit_tree() -> void:
	if _collapse != null:
		_collapse.release()


## Where the death beat is: `progress` 0→1 over the topple, `blasts` of the chain fired so far. The
## whole beat runs on the slowed clock, so callers must not assume real seconds.
func collapse_state() -> Dictionary:
	if _collapse == null:
		return {"progress": 0.0, "blasts": 0}
	return {"progress": _collapse.progress(), "blasts": _collapse.blasts}

## EnemyBase's wreck timer must never run: the collapse above owns the body until the director frees
## it (it stays as scenery through the victory beat).
func _tick_wreck(_delta: float) -> void:
	pass


# --- attacks ------------------------------------------------------------------------------------

func attacks() -> Array[EnemyAttack]:
	return _table


func choose_attack() -> EnemyAttack:
	var demanded := _take_demanded()
	if demanded != null:
		return demanded
	return BossCombat.pick(_table, global_position.distance_to(target_centre()))


## Forces the next attack the brain starts. Used by the capture driver and the tests to put one
## specific telegraph on screen; nothing in normal play calls it.
func demand(id: StringName) -> void:
	_demanded = id


func _take_demanded() -> EnemyAttack:
	if _demanded == &"":
		return null
	var want := _demanded
	_demanded = &""
	for a: EnemyAttack in _table:
		if a.id == want:
			return a
	push_warning("BroodTitan: attack '%s' is not in the phase %d table" % [want, phase])
	return null


func attack_windup(attack: EnemyAttack, dt: float) -> void:
	BossCombat.windup(self, attack, dt)


func attack_started(attack: EnemyAttack) -> void:
	BossCombat.started(self, attack)


func attack_active(attack: EnemyAttack, dt: float, _hit_done: bool) -> void:
	BossCombat.active(self, attack, dt)


func attack_recover(attack: EnemyAttack, dt: float) -> void:
	BossCombat.recover(self, attack, dt)


func spawn_attack(attack: EnemyAttack) -> bool:
	return BossCombat.spawn(self, attack)


func melee_sweep(attack: EnemyAttack) -> bool:
	return BossCombat.sweep(self, attack)


## CONTRACTS §5 "Large-target framing": the camera rig reads this off a hard-locked target and, at
## ≥ 30 m, lengthens its arm and raises its pitch so the hero and the titan's head share the frame.
func framing_height() -> float:
	return BossTuning.FRAMING_HEIGHT


## The colossus never queues behind the swarm's three melee tokens.
func token_kind() -> StringName:
	return &"boss"


# --- checkpoints and HUD --------------------------------------------------------------------------

## SPEC §7.1: dying puts the player back on the Crown at full HP with the boss restored to the start
## of the phase it was in, so a checkpoint is never a soft-lock.
func restore_for_checkpoint(to_phase: int) -> void:
	phase = clampi(to_phase, 1, BossTuning.PHASE_COUNT)
	# The phase thresholds are fractions of the pool, so a scripted run's `--boss-hp-scale` survives a
	# restore: `hp_max` used to be reset to the tuning constant here, which put 150,000 HP back on a
	# titan a 300 s drive had 3,000 (r5 brief item 3).
	hp_max = maxf(hp_max, 1.0)
	hp = BossTuning.phase_start_hp(phase) * hp_max / BossTuning.HP_MAX
	_transition_left = 0.0
	_collapsing = false
	_collapse_elapsed = 0.0
	if _collapse != null:
		_collapse.release()
		_collapse = null
	status.reset()
	visuals.reset()
	_removed.clear()
	# The previous attempt's adds go with the checkpoint: they survived every death, blocked the next
	# summon ("summon skipped, 15 adds are already up") and were still hitting the player the moment
	# the fight resumed (r5 brief item 4).
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.clear()
	for core: BossCore in cores:
		core.restore()
	_table = BossCombat.build_table(phase, _removed)
	alive = true
	collision_layer = Layers.ENEMY
	collision_mask = Layers.MASK_CHARACTER
	for child in get_children():
		if child is Hurtbox:
			(child as Hurtbox).collision_layer = Layers.ENEMY_HURTBOX
	if not is_in_group(&"enemy"):
		add_to_group(&"enemy")
	if model != null:
		model.rotation_degrees = Vector3.ZERO
		model.position = Vector3.ZERO
		model.visible = true
	# Back on a deck ring point: the restore used to leave the beast wherever the death found it, and
	# after a fling that could be under the deck, where the player cannot see it or finish the fight.
	var arena := get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if arena != null:
		global_position = arena.ring_point(0.25, 0.72, 0.0)
		velocity = Vector3.ZERO
	if _brain != null:
		_brain.restart()
	set_ai_enabled(true)
	BossPlate.reset()
	BossPlate.push(self)


## CONTRACTS §6: name, hp, hp_max, phase and one entry per core — `BossPlate` builds it and pushes
## it, because the HUD polls the boss only when the lead's request 2 lands.
func hud_state() -> Dictionary:
	return BossPlate.plate(self)
