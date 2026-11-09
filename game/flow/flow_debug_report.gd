class_name FlowDebugReport
extends RefCounted
## The E2E run's evidence: the phase marks, every capture's camera verdict, the debug fallbacks the
## bot needed and the weapon tally. Split out of `flow_debug.gd` (r5: that file is the script
## interpreter and was heading for the 600-line limit); `FlowDebug` keeps interpreting commands and
## hands every beat to this.

## The pacing table (r3 brief 3): wall time per marked phase, from the marks' own wall stamps.
var _marks: Array[Dictionary] = []
## Every capture's camera verdict (r4 brief item 4), from `FlowDebugView._save`.
var _cams: Array[Dictionary] = []
## Spires the bot could not shoot, and scripted clears that stood in for a fight.
var _fallbacks: Array[StringName] = []
## Scripted clears that stood in for a real fight (`clear_arena`), by arena id.
var _scripted: Array[StringName] = []
var _won: bool = false
var _reported: bool = false


func mark(phase: String, t: float, state: StringName) -> void:
	_marks.append({"name": phase, "t": t, "wall": Time.get_ticks_msec(), "state": state})
	print("E2EMARK %s t=%.1f wall=%d state=%s" % [phase, t, Time.get_ticks_msec(), state])


func note_won() -> void:
	_won = true


func won() -> bool:
	return _won


## A capture's camera verdict, from `FlowDebugView._save`. A capture is taken at the end of the frame
## and may still be settling when `report` runs, so a verdict that lands after the report prints its
## own line rather than going missing.
func note_camera(shot_name: String, verdict: String, at: Vector3, open: float, who: String,
		md5: String = "", subject: String = "") -> void:
	_cams.append({"name": shot_name, "verdict": verdict, "at": at, "open": open, "who": who,
			"md5": md5, "subject": subject})
	if _reported:
		print("E2ECAMREPORT %-18s %s at %.0f,%.0f,%.0f open=%.2f in %s (after the report)"
				% [shot_name, verdict, at.x, at.y, at.z, open, who])


func note_fallback(id: StringName) -> void:
	if id not in _fallbacks:
		_fallbacks.append(id)


func note_scripted_clear(id: StringName) -> void:
	if id not in _scripted:
		_scripted.append(id)


func fallbacks() -> Array[StringName]:
	return _fallbacks.duplicate()


func report(spires_down: int, t: float) -> void:
	_reported = true
	_phases(t)
	var buried := 0
	for row: Dictionary in _cams:
		if String(row["verdict"]) != "ok":
			buried += 1
			var at: Vector3 = row["at"]
			print("E2ECAMREPORT %-18s %s at %.0f,%.0f,%.0f open=%.2f in %s"
					% [row["name"], row["verdict"], at.x, at.y, at.z, float(row["open"]),
					row["who"]])
	print("E2ECAMREPORT captures=%d clean=%d buried=%d won=%s"
			% [_cams.size(), _cams.size() - buried, buried, str(_won)])
	_beats()
	# `bot_kills` counts the spires the weapons destroyed: a spire the script finished for the bot, and
	# a spire whose fall the script's `kill_spire` caused, are both fallbacks (r5 brief item 7).
	print("E2EWEAPONS spires=%d bot_kills=%d debug_fallbacks=%d %s scripted_clears=%d %s"
			% [spires_down, spires_down - _fallbacks.size(), _fallbacks.size(), str(_fallbacks),
			_scripted.size(), str(_scripted)])


## r5 brief item 8: two things the old report could not say. Frames that are BYTE-IDENTICAL are two
## beats that fired together (the script used to move on while the capture was still waiting for the
## rig), and a frame whose SUBJECT is not in it filmed the wrong moment — `a_dropin` was taken after
## the landing, `n_crown_boss` was the inside of the catapult beam.
func _beats() -> void:
	var seen := {}
	var dupes := 0
	var empty := 0
	for row: Dictionary in _cams:
		var md5 := String(row.get("md5", ""))
		var name := String(row["name"])
		if md5 != "":
			if seen.has(md5):
				dupes += 1
				print("E2ECAMREPORT DUPLICATE %s == %s (the same frame, two beats)"
						% [name, seen[md5]])
			else:
				seen[md5] = name
		var subject := String(row.get("subject", ""))
		if subject == "NONE" or subject == "no-camera":
			empty += 1
			print("E2ECAMREPORT NO-SUBJECT %s (neither the hero nor a target is in frame)" % name)
	print("E2ECAMREPORT distinct=%d duplicates=%d no_subject=%d" % [seen.size(), dupes, empty])


func _phases(t: float) -> void:
	var total := 0.0
	for i in _marks.size():
		var row := _marks[i] as Dictionary
		var end := float((_marks[i + 1] as Dictionary)["t"]) if i + 1 < _marks.size() else t
		var secs := end - float(row["t"])
		total += secs
		print("E2EPHASE %-14s %6.1f s  (ends %s)" % [row["name"], secs, row["state"]])
	print("E2EPHASE %-14s %6.1f s  marks=%d" % ["TOTAL", total, _marks.size()])
