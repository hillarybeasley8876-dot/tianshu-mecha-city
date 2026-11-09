class_name ArtRepo
extends RefCounted
## Where the repository is, derived — never written down (city-art r12 §3).
##
## Runtime code used to name an absolute home path to reach `data/map/city_layout.json` and
## `data/vistas.json`. That works on the machine the game was built on and nowhere else: in an exported
## build those paths are still readable on the developer's disk and absent everywhere else, so the roof
## dressing and the cargo blocks silently vanished on any other Mac. Nothing under `game/` may contain a
## absolute home path any more — `tools/godot.sh check` fails on one (see `test_no_abs_paths.gd`).
##
## Two answers, in order:
##   1. Runtime code reads a `res://` copy. `world/city/design_layout.json` is written by the same
##      Blender step that writes `world/city/layout.json`, so it cannot go stale without the layout
##      going stale too.
##   2. Tools, tests and probes that genuinely need the repo (a capture output directory, the design
##      layout the copy was made from) derive it from the project directory, which is wherever the
##      checkout happens to be. `--repo=<path>` overrides it for a checkout at an unusual depth.

## `res://` is `<repo>/game`, so the repo is its parent. `globalize_path` is the only honest way to ask
## where the project actually lives; `OS.get_executable_path()` is the .app in a shipped build.
static func root() -> String:
	var flag := Game.flag("repo")
	if not flag.is_empty():
		return flag
	var project := ProjectSettings.globalize_path("res://")
	return project.path_join("..").simplify_path()


## A path under the repo's `data/` tree. Dev-only: an exported build has no `data/`, which is exactly
## why every RUNTIME reader has a `res://` copy to fall back to.
static func data(rel: String) -> String:
	return root().path_join("data").path_join(rel)


## A path under the repo, for tools and probes (capture output, scratch).
static func at(rel: String) -> String:
	return root().path_join(rel)


## The design layout: the `res://` copy first, the repo original only when it is missing (a checkout
## where the Blender step has not run yet). Returns "" when neither exists.
static func design_layout() -> String:
	const COPY := "res://world/city/design_layout.json"
	if FileAccess.file_exists(COPY):
		return COPY
	var original := data("map/city_layout.json")
	return original if FileAccess.file_exists(original) else ""
