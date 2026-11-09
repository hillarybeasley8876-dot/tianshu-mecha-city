class_name RumbleMixer
extends Node
## Controller rumble mixer (feel unit). Rule 10 of the dossier: two motors, and the mix is the
## **max** of the active envelopes, never the sum - otherwise a gatling burst plus a landing saturates
## the pad into mush. Listens to Feel.rumble_requested and drives Input.start_joy_vibration itself
## every SEND_INTERVAL seconds of real time (a shorter pulse than ~60 ms is not felt on ERM motors).

const SEND_INTERVAL := 0.05
const SEND_DURATION := 0.1
const MAX_ENVELOPES := 24

## 0..1 master scale (accessibility slider). Picks up Settings "rumble" as soon as core defines it.
var scale: float = 1.0

var _envelopes: Array[Vector4] = []   ## x = weak, y = strong, z = start, w = end (real seconds)
var _next_send: float = 0.0
var _now: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v: Variant = Settings.get_value(&"rumble")
	if v is float:
		scale = float(v)
	Settings.changed.connect(_on_setting)
	Feel.rumble_requested.connect(add)


## Queue one rumble envelope (weak = high frequency, strong = low frequency, seconds of real time).
func add(weak: float, strong: float, duration: float) -> void:
	if scale <= 0.0 or duration <= 0.0 or (weak <= 0.0 and strong <= 0.0):
		return
	var now := _clock()
	if _envelopes.size() >= MAX_ENVELOPES:
		_envelopes.remove_at(0)
	_envelopes.append(Vector4(clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), now, now + duration))
	_send(now)


## Current mixed motor values (max of the live envelopes, decayed).
func mixed() -> Vector2:
	var out := Vector2.ZERO
	var now := _clock()
	var i := 0
	while i < _envelopes.size():
		var e := _envelopes[i]
		if now >= e.w:
			_envelopes.remove_at(i)
			continue
		var k := 1.0 - (now - e.z) / maxf(e.w - e.z, 0.001)
		out.x = maxf(out.x, e.x * k)
		out.y = maxf(out.y, e.y * k)
		i += 1
	return out * scale


func _process(_delta: float) -> void:
	var now := _clock()
	if now < _next_send:
		return
	_next_send = now + SEND_INTERVAL
	_send(now)


func _send(now: float) -> void:
	var m := mixed()
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, m.x, m.y, SEND_DURATION if m.length_squared() > 0.0 else 0.0)


func _on_setting(key: StringName) -> void:
	if key == &"rumble":
		var v: Variant = Settings.get_value(&"rumble")
		scale = float(v) if v is float else 1.0
		if scale <= 0.0:
			stop()


func stop() -> void:
	_envelopes.clear()
	for pad in Input.get_connected_joypads():
		Input.stop_joy_vibration(pad)


func _clock() -> float:
	return float(Time.get_ticks_usec()) / 1e6
