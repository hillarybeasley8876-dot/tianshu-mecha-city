extends SceneTree
## Headless writer for the third-party notice file (hud r6 item 3). `tools/godot.sh export` calls it so
## `build/THIRD_PARTY_LICENSES.txt` lands BESIDE the .app, never inside it, and is composed from the
## same `HudLicences` the 开源许可 LICENCES page reads — one source, two outputs.
##
##   godot --headless --path game -s res://ui/licenses/write_third_party.gd -- --out=<file>
##   tools/godot.sh test res://ui/licenses/write_third_party.gd -- --out=<file>
##
## It is a SceneTree script on purpose: it needs no autoload, no scene and no window, so it runs in the
## light pool. Exits 0 on success, 1 on a bad argument or a failed write.

const Composer := preload("res://ui/licenses/composer.gd")
## The autoloads boot with the main loop and `core/input_quad.gd` polls an action on its first frame;
## without the InputMap filled in it logs an engine ERROR into whatever log this runs under (the same
## reason `tools/test_host.gd` registers them).
const InputSetup := preload("res://core/input_setup.gd")


func _initialize() -> void:
	InputSetup.register_actions()
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out == "":
		push_error("write_third_party: --out=<file> is required")
		quit(1)
		return
	var text: String = Composer.new().notice_text()
	if text.length() < 1000:
		push_error("write_third_party: the composed notice is only %d characters" % text.length())
		quit(1)
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("write_third_party: cannot write %s (error %d)" % [out, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("LICENCES %s (%d characters)" % [out, text.length()])
	quit(0)
