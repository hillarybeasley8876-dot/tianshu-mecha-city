class_name FlowFakeHud
extends CanvasLayer
## Stands in for the HUD in the flow tests (CONTRACTS §6): records the tutorial prompts flow asks it to
## draw and the ones it takes away again, so the prompt contract is checked without a canvas.

var prompted: Array[StringName] = []
var dismissed: Array[StringName] = []


func prompt(id: StringName, _action: StringName = &"", _line: String = "") -> void:
	prompted.append(id)


func dismiss_prompt(id: StringName) -> void:
	dismissed.append(id)
