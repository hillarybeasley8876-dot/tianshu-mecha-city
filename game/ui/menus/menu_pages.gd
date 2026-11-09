class_name HudMenuPages
extends RefCounted
## The row lists every menu page is built from (brief §9). Kept out of `HudMenuRoot` so the root stays
## the thing it should be — which page is up, the navigation, and the wiring to `Settings` and the
## flow — and so the tables (SPEC §3 controls, SPEC §9 settings) can be read and tested on their own.

## Settings rows, in the order SPEC §9 lists them: key, label, kind, range.
const SETTING_ROWS: Array[Array] = [
	["quality", "画质 QUALITY", HudMenuScreen.Kind.CHOICE, [&"low", &"medium", &"high"]],
	["mouse_sensitivity", "鼠标灵敏度 MOUSE SENS", HudMenuScreen.Kind.SLIDER, 0.2, 3.0, 0.05, ""],
	["stick_sensitivity", "摇杆灵敏度 STICK SENS", HudMenuScreen.Kind.SLIDER, 0.2, 3.0, 0.05, ""],
	["invert_y", "反转 Y 轴 INVERT Y", HudMenuScreen.Kind.TOGGLE],
	["fov_third", "第三人称视场 FOV 3RD", HudMenuScreen.Kind.SLIDER, 45.0, 80.0, 1.0, "deg"],
	["fov_first", "第一人称视场 FOV 1ST", HudMenuScreen.Kind.SLIDER, 45.0, 90.0, 1.0, "deg"],
	["screen_shake", "画面震动 SCREEN SHAKE", HudMenuScreen.Kind.SLIDER, 0.0, 1.0, 0.05, "%"],
	["aim_assist", "瞄准辅助 AIM ASSIST", HudMenuScreen.Kind.SLIDER, 0.0, 1.0, 0.05, "%"],
	["master_volume_db", "主音量 MASTER", HudMenuScreen.Kind.SLIDER, -40.0, 6.0, 1.0, "db"],
	["music_volume_db", "音乐 MUSIC", HudMenuScreen.Kind.SLIDER, -40.0, 6.0, 1.0, "db"],
	["sfx_volume_db", "音效 SFX", HudMenuScreen.Kind.SLIDER, -40.0, 6.0, 1.0, "db"],
	["damage_numbers", "伤害数字 DAMAGE NUMBERS", HudMenuScreen.Kind.TOGGLE],
	["hud_scale", "HUD 缩放 HUD SCALE", HudMenuScreen.Kind.SLIDER, 0.8, 1.4, 0.05, "%"],
	["photosensitive", "光敏安全 PHOTOSENSITIVE", HudMenuScreen.Kind.TOGGLE],
	["hold_to_toggle", "长按改为切换 HOLD → TOGGLE", HudMenuScreen.Kind.TOGGLE],
]

## SPEC §3 control table, drawn as the controls page: verb, keyboard + mouse, pad.
const CONTROL_ROWS: Array[Array] = [
	["移动 / 视角 Move / look", "WASD / MOUSE", "LS / RS"],
	["开火 Fire (hold = charge)", "LMB", "RT"],
	["瞄准 / 变焦 Aim / zoom", "RMB", "LT"],
	["跳跃 / 悬停 Jump / hover", "SPACE", "A"],
	["飞行切换 Flight (空中双击 / double-tap in air)", "SPACE ×2", "A ×2"],
	["下降 Descend (flight)", "CTRL", "B (飞行时)"],
	["冲刺 / 滑行 Dash / boost", "SHIFT", "B"],
	["强攻推进 Assault boost", "LEFT ALT", "L3"],
	["光刃 Melee", "F", "X"],
	["格挡 / 反击 Guard / parry", "Q", "LB"],
	["雹暴齐射 Missiles", "1 / MOUSE4", "RB + RT"],
	["天钩锚 Anchor", "E", "Y"],
	["裂隙步 Rift Step", "C", "RB + B"],
	["日冕翼片 Corona Fins", "Z", "RB + Y"],
	["震核爆 Shockcore Burst", "X", "RB + X"],
	["暗流引井 Undertow Well", "G", "RB + A"],
	["切换 / 换弹 Swap / reload", "WHEEL/R", "D↑ 轻按/长按"],
	["天顶超驱 Overdrive (hold 0.25 s)", "V 长按", "L3 + R3"],
	["天顶长矛 Zenith Lance (OD running)", "V", "L3 + R3"],
	["锁定 / 切换 Lock-on", "TAB/MMB", "R3 / D←→"],
	["视角切换 Camera", "B", "VIEW / D↓"],
	["暂停 Pause", "ESC", "MENU"],
	["全屏 Fullscreen", "F11", "—"],
	["RB 是手柄的组合层 (RB is the pad shift layer)", "", ""],
]


static func title() -> Array[Dictionary]:
	return [
		_action("start", "开始行动  START"),
		_action("settings", "设置  SETTINGS"),
		_action("controls", "操作  CONTROLS"),
		_action("credits", "制作名单  CREDITS"),
		_action("quit", "退出  QUIT"),
	]


static func pause() -> Array[Dictionary]:
	return [
		_action("resume", "继续  RESUME"),
		_action("retry", "从检查点重试  RETRY FROM CHECKPOINT"),
		_action("settings", "设置  SETTINGS"),
		_action("controls", "操作  CONTROLS"),
		_action("credits", "制作名单  CREDITS"),
		_action("quit", "退出行动  ABORT"),
	]


static func settings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for spec in SETTING_ROWS:
		var key := StringName(spec[0])
		var r: Dictionary = {"id": String(spec[0]), "label": String(spec[1]), "kind": int(spec[2]),
				"value": Settings.get_value(key)}
		if int(spec[2]) == HudMenuScreen.Kind.SLIDER:
			r["min"] = float(spec[3])
			r["max"] = float(spec[4])
			r["step"] = float(spec[5])
			r["unit"] = String(spec[6])
		elif int(spec[2]) == HudMenuScreen.Kind.CHOICE:
			r["options"] = spec[3]
		rows.append(r)
	rows.append(_action("back", "返回  BACK"))
	return rows


## Both schemes side by side (SPEC §3), drawn as a two-column table of INFO rows.
static func controls() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for r in CONTROL_ROWS:
		rows.append({"id": String(r[0]), "label": String(r[0]), "kind": HudMenuScreen.Kind.INFO,
				"value": "" if String(r[1]) == "" else "%s   /   %s" % [String(r[1]), String(r[2])]})
	rows.append(_action("back", "返回  BACK"))
	return rows


static func game_over() -> Array[Dictionary]:
	return [
		_action("retry", "从检查点重试  RETRY FROM CHECKPOINT"),
		_action("controls", "操作  CONTROLS"),
		_action("quit", "退出  QUIT"),
	]


static func victory(stats: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: String in ["time", "max_combo", "kills", "parries", "perfect_dodges", "executions"]:
		rows.append({"id": key, "label": stat_label(key), "kind": HudMenuScreen.Kind.INFO,
				"value": stat_text(stats, key)})
	rows.append(_action("finish", "结束  FINISH"))
	return rows


## Credits (ACCEPTANCE §5): every audio pack and music track the build ships, the AI-content labels
## the licences require, the engine and font licences, and the way in to their full texts. The rows
## come from `HudCredits`, which reads the audio and texture manifests, so nothing is credited wrongly.
static func credits() -> Array[Dictionary]:
	var rows := HudCredits.new().rows()
	rows.append(_action("licences", "开源许可  LICENCES"))
	rows.append(_action("back", "返回  BACK"))
	return rows


static func stat_label(key: String) -> String:
	match key:
		"time": return "用时  TIME"
		"max_combo": return "最高连击  MAX COMBO"
		"kills": return "击杀  KILLS"
		"parries": return "格挡反击  PARRIES"
		"perfect_dodges": return "完美闪避  PERFECT DODGES"
		"executions": return "处决  EXECUTIONS"
		_: return key


static func stat_text(stats: Dictionary, key: String) -> String:
	var v: Variant = stats.get(key, 0)
	if key == "time":
		var t := int(float(v))
		return "%d:%02d" % [t / 60, t % 60]
	return str(int(v))


static func _action(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label, "kind": HudMenuScreen.Kind.ACTION}
