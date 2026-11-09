class_name FeelTable
extends RefCounted
## Reads the id column of docs/FEEL.md (the lead-owned source of truth) so the tests and the gallery
## never drift from the table. Cells like "rifle_charge_1 / _2" and "finisher (Core Rend)" expand to
## one id per event.

const DOC := "../docs/FEEL.md"
const HEADER := "| id |"


## Event ids in table order. Empty when the doc cannot be read (the caller reports it).
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var path := ProjectSettings.globalize_path("res://").path_join(DOC)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("FeelTable: cannot read " + path)
		return out
	var in_table := false
	while not f.eof_reached():
		var line := f.get_line()
		if not in_table:
			in_table = line.begins_with(HEADER)
			continue
		if not line.begins_with("|"):
			break
		var cell := line.split("|")[1].strip_edges()
		if cell.is_empty() or cell.begins_with("-"):
			continue
		out.append_array(_expand(cell))
	f.close()
	return out


## One table cell -> its event ids.
static func _expand(cell: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var base := cell
	var paren := base.find("(")
	if paren > 0:
		base = base.substr(0, paren).strip_edges()
	var prev := ""
	for part in base.split("/", false):
		var id := String(part).strip_edges()
		if id.begins_with("_") and prev != "":
			# "rifle_charge_1 / _2" -> the second id reuses the stem before the last underscore.
			var cut := prev.rfind("_")
			id = (prev.substr(0, cut + 1) if cut > 0 else prev) + id.substr(1)
		out.append(StringName(id))
		prev = id
	return out
