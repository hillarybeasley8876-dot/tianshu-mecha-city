extends RefCounted
## Finds the node that first goes non-finite or degenerate (drive/movie `--nan-watch`, core-owned).
## Engine warnings such as "Vector3 cannot be normalized" or "det == 0" carry no script backtrace when the
## bad transform is consumed inside the renderer or physics, so the only way to the culprit is to scan
## the tree: every Node3D whose global transform is non-finite or has a zero-determinant basis is
## printed once as "NANWATCH t=.. <reason> <path> <class> <script>", in tree order.

const MAX_REPORTS := 40
const DET_EPS := 1e-12

var _seen: Dictionary = {}
var _reports: int = 0


func scan(root: Node, t: float) -> void:
	if _reports >= MAX_REPORTS:
		return
	_visit(root, t)


func _visit(node: Node, t: float) -> void:
	if node is Node3D and node.is_inside_tree():
		var reason := _problem((node as Node3D).global_transform)
		if reason != "" and not _seen.has(node.get_instance_id()):
			_seen[node.get_instance_id()] = true
			_report(node, reason, t)
	for child in node.get_children():
		if _reports >= MAX_REPORTS:
			return
		_visit(child, t)


func _problem(xf: Transform3D) -> String:
	if not xf.origin.is_finite():
		return "origin=%s" % xf.origin
	if not xf.basis.is_finite():
		return "basis-nonfinite"
	if absf(xf.basis.determinant()) < DET_EPS:
		return "basis-det0 scale=%s" % xf.basis.get_scale()
	return ""


func _report(node: Node, reason: String, t: float) -> void:
	_reports += 1
	var script := node.get_script() as Script
	print("NANWATCH t=%.3f %s %s %s %s" % [t, reason, node.get_path(), node.get_class(),
			script.resource_path if script != null else "-"])
