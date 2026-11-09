class_name HudLocale
extends RefCounted
## Which language the in-game HUD prints in (look review items 3.3 and 8.4). Every label used to carry
## both — "贯光步枪 PIERCE-LIGHT", "装甲 ARMOUR", "0 / 3 HIVES 蚀巢" — which doubles the amount of type
## on screen for no gain while the player is fighting. Menus and the tutorial stay bilingual on purpose
## (brief §10): there the player has time to read.
##
## The source is `Settings.locale` when the settings unit has one, and the OS locale until then.

static var _lang: String = ""


static func language() -> String:
	if _lang == "":
		var v: Variant = Settings.get_value(&"locale")
		var s := "" if v == null else String(v)
		_lang = s if s != "" else OS.get_locale_language()
	return _lang


static func zh() -> bool:
	return language().begins_with("zh")


## The one call every bilingual label goes through.
static func pick(chinese: String, latin: String) -> String:
	return chinese if zh() else latin


## Test hook: force a language without touching the OS or the settings file.
static func set_language(lang: String) -> void:
	_lang = lang
