class_name SkillInputSuite
extends RefCounted
## The REAL input path (r4 items 1, 3, 5 and 6). Every other suite calls `try_*()` directly on a
## stand-in, which is why a quick Rift Step tap could be eaten for a whole round without a single red
## check: this suite drives the registered actions (`Input.action_press`, `InputEventKey` through
## `Input.parse_input_event`, and pad buttons through the `PadInput` autoload) and measures the
## physics-frame latency between the press and `Events.skill_used`.

const RIFT := &"rift_step"
const HOME := Vector3(0.0, 8.0, 0.0)


static func run(h: SkillTestHarness) -> void:
	h.watch_skill_used()
	await _rift_press_edges(h)
	await _rift_key_and_pad(h)
	await _rift_with_lock_on_held(h)
	await _press_buffer(h)
	await _lance_press_edge(h)
	await _lance_ignition_hold(h)
	await _dead_mech_inputs(h)
	await _contract_sockets(h)


# --- helpers ---------------------------------------------------------------------------------------

## Fresh state, mech home, every cooldown clear and the blink settled to idle.
static func _prep(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = HOME
	h.player.velocity = Vector3.ZERO
	h.player.global_basis = Basis.IDENTITY
	h.aim.locked = null
	h.aim.soft = null
	h.aim.point = Vector3(0.0, 8.0, -300.0)
	for a: StringName in [RIFT, &"anchor", &"burst", &"well", &"overdrive", &"lock_on"]:
		Input.action_release(a)
	await h.step(0.05)
	for _i in 240:
		if not h.system.rift.is_busy():
			break
		await h.tree.physics_frame


## Holds `action` for `hold_ticks` physics ticks and returns the latency, in physics ticks, of the
## first `skill_used(id)` after the press (-1 when it never fired).
static func _press(h: SkillTestHarness, action: StringName, id: StringName,
		hold_ticks: int) -> int:
	var n0 := h.used_count(id)
	await h.tree.physics_frame
	var f0 := Engine.get_physics_frames()
	Input.action_press(action)
	for i in hold_ticks:
		await h.tree.physics_frame
	Input.action_release(action)
	await h.step(0.35)
	return h.used_latency(id, n0, f0)


## Same, but the press arrives as an OS-level key event (the path a human's keyboard takes).
static func _press_key(h: SkillTestHarness, key: Key, id: StringName, frames: int) -> int:
	var n0 := h.used_count(id)
	await h.tree.process_frame
	var f0 := Engine.get_physics_frames()
	_key(key, true)
	for _i in frames:
		await h.tree.process_frame
	_key(key, false)
	await h.step(0.35)
	return h.used_latency(id, n0, f0)


## Pad buttons go through the `PadInput` autoload, which is the only place a gamepad becomes an
## action: RB then B is `rift_step`, L3 then R3 is `overdrive`.
static func _press_pad(h: SkillTestHarness, shift: bool, button: JoyButton, id: StringName,
		frames: int) -> int:
	var n0 := h.used_count(id)
	await h.tree.process_frame
	if shift:
		_joy(JOY_BUTTON_RIGHT_SHOULDER, true)
		await h.tree.process_frame
	var f0 := Engine.get_physics_frames()
	_joy(button, true)
	for _i in frames:
		await h.tree.process_frame
	_joy(button, false)
	await h.tree.process_frame
	if shift:
		_joy(JOY_BUTTON_RIGHT_SHOULDER, false)
	await h.step(0.35)
	return h.used_latency(id, n0, f0)


## Holds `action` and reports the latency, in physics ticks, of the first tick `cond()` is true
## (-1 when it never became true). For skills whose start is not announced by `Events.skill_used`.
static func _press_until(h: SkillTestHarness, action: StringName, hold_ticks: int,
		cond: Callable) -> int:
	await h.tree.physics_frame
	var f0 := Engine.get_physics_frames()
	Input.action_press(action)
	var at := await _poll(h, cond, hold_ticks)
	Input.action_release(action)
	await h.step(0.1)
	return at - f0 if at >= 0 else -1


## Same, through an OS-level key event.
static func _key_until(h: SkillTestHarness, key: Key, frames: int, cond: Callable) -> int:
	await h.tree.process_frame
	var f0 := Engine.get_physics_frames()
	_key(key, true)
	var at := -1
	for i in maxi(frames * 2, 12):
		await h.tree.physics_frame
		if at < 0 and bool(cond.call()):
			at = Engine.get_physics_frames()
		if i == frames - 1:
			_key(key, false)
	_key(key, false)
	await h.step(0.1)
	return at - f0 if at >= 0 else -1


## Same, through pad buttons (`PadInput` turns them into actions).
static func _pad_until(h: SkillTestHarness, buttons: Array[JoyButton], cond: Callable) -> int:
	await h.tree.process_frame
	for b in buttons:
		_joy(b, true)
		await h.tree.process_frame
	var f0 := Engine.get_physics_frames()
	var at := await _poll(h, cond, 4)
	for b in buttons:
		_joy(b, false)
	await h.step(0.1)
	return at - f0 if at >= 0 else -1


## Watches `cond` for up to 24 physics ticks and returns the frame it first held, or -1.
static func _poll(h: SkillTestHarness, cond: Callable, hold_ticks: int) -> int:
	var at := -1
	for i in 24:
		await h.tree.physics_frame
		if at < 0 and bool(cond.call()):
			at = Engine.get_physics_frames()
		if i >= hold_ticks:
			break
	return at


static func _key(key: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


static func _joy(button: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A blink that fired must also have MOVED the mech: `skill_used` alone would pass on a no-op.
static func _moved(h: SkillTestHarness, before: Vector3) -> float:
	return Vector2(h.player.global_position.x - before.x,
			h.player.global_position.z - before.z).length()


# --- item 1: Rift Step fires on the press edge ------------------------------------------------------

## The old `_rift()` waited the 4-frame L3+R3 chord window after the press and cancelled if the key
## came up first, so every hold of 4 frames or less was eaten with no cost, no FEEL row and no blink —
## and every blink that did fire started 9 ticks (75 ms) late, against SPEC §1's 2 frames.
static func _rift_press_edges(h: SkillTestHarness) -> void:
	for ticks: int in [1, 2, 3, 4]:
		await _prep(h)
		var before := h.player.global_position
		var lat := await _press(h, RIFT, RIFT, ticks)
		var moved := _moved(h, before)
		h.check("input.rift_fires_on_a_%d_tick_hold" % ticks, lat >= 0,
				"a %d-tick hold was eaten" % ticks)
		h.check("input.rift_latency_%d_tick_hold" % ticks, lat >= 0 and lat <= 2,
				"fired %d ticks after the press" % lat)
		h.check("input.rift_moves_the_mech_%d_tick_hold" % ticks, moved > 10.0,
				"the mech moved %.1f m" % moved)


## The keyboard and the pad reach the same press edge through different code (`InputEventKey` on the
## InputMap, `PadInput` for the pad), so both are driven for a single frame.
static func _rift_key_and_pad(h: SkillTestHarness) -> void:
	await _prep(h)
	var before := h.player.global_position
	var lat := await _press_key(h, KEY_C, RIFT, 1)
	h.check("input.rift_fires_on_a_one_frame_key_tap", lat >= 0, "KEY_C down/up a frame apart did nothing")
	h.check("input.rift_key_latency", lat >= 0 and lat <= 2, "fired %d ticks after the key" % lat)
	h.check("input.rift_key_moves_the_mech", _moved(h, before) > 10.0,
			"the mech moved %.1f m" % _moved(h, before))

	await _prep(h)
	before = h.player.global_position
	lat = await _press_pad(h, true, JOY_BUTTON_B, RIFT, 1)
	h.check("input.rift_fires_on_a_one_frame_pad_tap", lat >= 0, "pad RB+B for a frame did nothing")
	h.check("input.rift_pad_latency", lat >= 0 and lat <= 2, "fired %d ticks after pad B" % lat)
	h.check("input.rift_pad_moves_the_mech", _moved(h, before) > 10.0,
			"the mech moved %.1f m" % _moved(h, before))


## The old code also cancelled the blink while `lock_on` was held, which made Rift Step dead exactly
## when the player was aiming at something — the reason the chord existed at all.
static func _rift_with_lock_on_held(h: SkillTestHarness) -> void:
	await _prep(h)
	var foe := h.add_target(Vector3(0.0, 0.0, -60.0))
	h.aim.locked = foe
	Input.action_press(&"lock_on")
	await h.step(0.1)
	var before := h.player.global_position
	var lat := await _press(h, RIFT, RIFT, 3)
	Input.action_release(&"lock_on")
	h.check("input.rift_fires_with_lock_on_held", lat >= 0, "the press was cancelled by lock_on")
	h.check("input.rift_lock_on_latency", lat >= 0 and lat <= 2, "fired %d ticks after the press" % lat)
	h.check("input.rift_lock_on_moves_the_mech", _moved(h, before) > 5.0,
			"the mech moved %.1f m" % _moved(h, before))


## SPEC §3: one 6 f buffer on the real clock for every press-edge skill. A press 4 f before the mech
## may act fires as soon as it may; a press 8 f before has left the window and never fires.
static func _press_buffer(h: SkillTestHarness) -> void:
	for frames: float in [4.0, 8.0]:
		await _prep(h)
		h.player.cancellable = false
		var n0 := h.used_count(RIFT)
		Input.action_press(RIFT)
		await h.step(frames / 60.0)
		Input.action_release(RIFT)
		var opened := Engine.get_physics_frames()
		h.player.cancellable = true
		await h.step(0.4)
		var lat := h.used_latency(RIFT, n0, opened)
		if frames < 6.0:
			h.check("input.buffered_press_fires_when_the_mech_may_act", lat >= 0 and lat <= 2,
					"a press %0.0f f early fired %d ticks after the gate opened" % [frames, lat])
		else:
			h.check("input.press_outside_the_buffer_is_dropped", lat < 0,
					"a press %0.0f f early still fired %d ticks after the gate opened" % [frames, lat])
	h.player.cancellable = true


# --- item 3: the Lance fires on a press during the Overdrive -----------------------------------------

## Fills the meter and ignites, leaving the Overdrive running with the Lance available.
static func _overdrive_running(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = HOME
	h.player.velocity = Vector3.ZERO
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 8.0, -300.0)
	Input.action_release(&"overdrive")
	h.player.overdrive = h.system.tuning.od_required
	h.system.try_overdrive()
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 6.0)


## SPEC §3 gives the Lance "V hold 0.25 s / V". The old router put the 0.25 s hold on BOTH, so a tap
## during the Overdrive did nothing at all.
static func _lance_press_edge(h: SkillTestHarness) -> void:
	var lat := -1
	for ticks: int in [1, 3]:
		await _overdrive_running(h)
		lat = await _press_until(h, &"overdrive", ticks,
				func() -> bool: return h.system.zenith.is_charging())
		h.check("input.lance_fires_on_a_%d_tick_press" % ticks, lat >= 0,
				"V for %d ticks during the Overdrive never charged" % ticks)
		h.check("input.lance_latency_%d_tick_press" % ticks, lat >= 0 and lat <= 2,
				"charging started %d ticks after the press" % lat)

	await _overdrive_running(h)
	lat = await _key_until(h, KEY_V, 1, func() -> bool: return h.system.zenith.is_charging())
	h.check("input.lance_fires_on_a_one_frame_key_tap", lat >= 0,
			"KEY_V a frame apart during the Overdrive never charged")
	h.check("input.lance_key_latency", lat >= 0 and lat <= 2,
			"charging started %d ticks after the key" % lat)

	await _overdrive_running(h)
	lat = await _pad_until(h, [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK],
			func() -> bool: return h.system.zenith.is_charging())
	h.check("input.lance_fires_on_pad_l3_r3", lat >= 0,
			"pad L3+R3 during the Overdrive never charged")
	h.check("input.lance_pad_latency", lat >= 0 and lat <= 2,
			"charging started %d ticks after the chord" % lat)


## Audit #8 still holds with the press edge: ONE long hold ignites and must never also fire the Lance.
static func _lance_ignition_hold(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = HOME
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 8.0, -300.0)
	Input.action_release(&"overdrive")
	h.player.overdrive = h.system.tuning.od_required
	Input.action_press(&"overdrive")
	await h.step(1.0)
	h.check("input.long_hold_ignites", h.system.is_overdrive_active(),
			"a 1 s hold from a full meter did not ignite")
	h.check("input.long_hold_never_fires_the_lance", not h.system.zenith.lance.is_running(),
			"the same hold also fired the Lance")
	Input.action_release(&"overdrive")
	await h.step(0.1)


# --- item 6: a dead mech's skill inputs do nothing ----------------------------------------------------

## mech-move owns the single death predicate (`PlayerMech.is_alive()`); this is the skills half. While
## it is false, no input may change skill state, EN, a cooldown or emit an event — and the 6 f press
## buffer must DROP a press made while dead rather than carry it into the first live tick.
static func _dead_mech_inputs(h: SkillTestHarness) -> void:
	await _prep(h)
	h.player.hp = 0.0
	h.check("input.dead_predicate", not h.player.is_alive(), "the rig is still alive at 0 hp")
	var used_before := h.used_count(RIFT) + h.used_count(&"anchor") + h.used_count(&"fins") \
			+ h.used_count(&"ward") + h.used_count(&"burst") + h.used_count(&"well") \
			+ h.used_count(&"plunge") + h.used_count(&"overdrive")
	var en_before := h.player.energy
	var cds_before := h.system.hud_state()
	# every skill input, each held long enough for its own gesture (0.25 s holds, the 0.35 s ward)
	for a: StringName in [RIFT, &"anchor", &"fins", &"burst", &"well", &"melee", &"overdrive"]:
		Input.action_press(a)
		await h.step(0.45)
		Input.action_release(a)
		await h.step(0.05)
	var used_after := h.used_count(RIFT) + h.used_count(&"anchor") + h.used_count(&"fins") \
			+ h.used_count(&"ward") + h.used_count(&"burst") + h.used_count(&"well") \
			+ h.used_count(&"plunge") + h.used_count(&"overdrive")
	h.check("input.dead_mech_emits_no_skill_used", used_after == used_before,
			"%d activations while dead" % (used_after - used_before))
	h.near("input.dead_mech_spends_no_energy", h.player.energy, en_before, 0.01)
	var cds_after := h.system.hud_state()
	var cooled := false
	for id: String in ["rift_step", "anchor", "fins", "ward", "burst", "well", "plunge"]:
		if float(cds_after.get(id + "_cd", 0.0)) > float(cds_before.get(id + "_cd", 0.0)):
			cooled = true
	h.check("input.dead_mech_starts_no_cooldown", not cooled,
			"a cooldown started while the mech was dead")
	h.check("input.dead_mech_raises_no_ward", not h.system.fins.ward.is_active(),
			"a corpse raised the Corona Ward")
	h.check("input.dead_mech_fires_no_lance", not h.system.zenith.lance.is_running(),
			"a corpse fired the Zenith Lance")
	h.check("input.dead_mech_ignites_no_overdrive", not h.system.is_overdrive_active(),
			"a corpse ignited the Overdrive")

	# a press made while dead is dropped, not carried into the first live tick
	h.system.reset()
	h.player.hp = 0.0
	Input.action_press(RIFT)
	await h.step(0.05)
	Input.action_release(RIFT)
	var n0 := h.used_count(RIFT)
	h.player.hp = h.player.hp_max
	await h.step(0.4)
	h.check("input.dead_press_is_not_buffered_into_life", h.used_count(RIFT) == n0,
			"a press made while dead fired on the first live tick")

	# and the corpse lets go of what it was holding
	h.player.hp = h.player.hp_max
	h.system.reset()
	h.system.try_ward()
	h.system.anchor.begin()
	await h.step(0.05)
	h.player.hp = 0.0
	await h.step(0.1)
	h.check("input.death_releases_the_anchor", not h.system.anchor.is_attached(),
			"the corpse kept its grapple line")
	h.check("input.death_drops_the_ward", not h.system.fins.ward.is_active(),
			"the corpse kept its barrier up")
	h.player.hp = h.player.hp_max
	await h.step(0.05)


# --- item 5: the skills only ask for CONTRACTS §5 sockets ---------------------------------------------

## The Skyhook used to ask for `muzzle_l`, which is in neither CONTRACTS §5 nor `Hero3Sockets.TABLE`:
## every grapple tick logged `Hero3Rig: no socket named muzzle_l` and `ctx.socket()` fell back to the
## chest, so the cable left the torso. The stand-in hid it by inventing any node asked for.
static func _contract_sockets(h: SkillTestHarness) -> void:
	var model := h.player.rig_model
	h.check("input.stand_in_publishes_the_contract_sockets",
			not SkillRigModel.SOCKETS.has(&"muzzle_l") and SkillRigModel.SOCKETS.has(&"hand_l")
			and SkillRigModel.SOCKETS.has(&"shield_l") and SkillRigModel.SOCKETS.has(&"muzzle_r"),
			"the stand-in's socket table is not the CONTRACTS §5 one")
	h.check("input.cable_leaves_a_contract_socket",
			SkyhookAnchor.CABLE_SOCKET in SkillRigModel.SOCKETS,
			"the cable asks for %s" % SkyhookAnchor.CABLE_SOCKET)

	# exercise every skill that reads a socket, and assert nothing asked for a name it should not
	h.reset()
	h.clear_enemies()
	h.player.global_position = HOME
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 8.0, -300.0)
	await h.step(0.05)
	h.system.try_rift_step()
	h.system.try_anchor()
	h.system.try_fins()
	h.system.try_burst()
	h.system.try_well()
	h.player.overdrive = h.system.tuning.od_required
	h.system.try_overdrive()
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 6.0)
	h.system.zenith.begin_lance()
	await h.wait_until(func() -> bool: return not h.system.zenith.lance.is_running(), 16.0)
	h.check("input.no_socket_outside_the_contract", model.bad_sockets.is_empty(),
			"asked for %s" % ", ".join(model.bad_sockets))

	# and the stand-in really is strict, so that check above can fail
	var before := model.bad_sockets.size()
	h.check("input.stand_in_rejects_a_foreign_socket", model.socket(&"muzzle_l") == null,
			"the stand-in invented a node for a socket the contract does not publish")
	h.check("input.stand_in_records_the_foreign_socket", model.bad_sockets.size() == before + 1,
			"%d names recorded, was %d" % [model.bad_sockets.size(), before])
