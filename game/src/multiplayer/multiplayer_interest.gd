class_name MultiplayerInterest
extends RefCounted
## Presentation scheduling only. Every transmitted city is a complete checkpoint.
## Distant changes become due within one second; commands never depend on this hint.
const MAX_AGE_MSEC := 1000
var views: Dictionary = {}
var sent: Dictionary = {}
var forced: Dictionary = {}
var deferred := 0
var checked: Dictionary = {}


func receive(actor: String, value: Variant, edge: int) -> bool:
	if not value is Dictionary or not value.get("bounds") is Array or value.bounds.size() != 4 or not value.get("details") is bool:
		return false
	for number: Variant in value.bounds:
		if not CoopWorld.whole_number(number, 0, edge):
			return false
	var rect := Rect2i(int(value.bounds[0]), int(value.bounds[1]), int(value.bounds[2]), int(value.bounds[3]))
	if not rect.has_area() or rect.end.x > edge or rect.end.y > edge:
		return false
	if views.get(actor) != value:
		views[actor] = value.duplicate(true)
		forced[actor] = true
	return true


func due(world: CoopWorld, actor: String, viewed: String, now: int) -> bool:
	if forced.has(actor) or not sent.has(actor) or not views.has(actor) or views[actor].details:
		return true
	var last: Dictionary = sent[actor]
	var policy: int = world.municipalities[viewed].policy_revision if world is SharedWorld and world.municipalities.has(viewed) else world.policy_revision
	if now - int(last.time) >= MAX_AGE_MSEC or last.view != viewed or int(last.policy) != policy:
		return true
	# An unchanged world/view cannot become relevant on the next render frame.
	# The deadline above still guarantees progress without another mutation.
	var stamp: Array = [world.get_instance_id(), world.revision, viewed, views[actor].bounds, last.revision]
	if checked.get(actor, {}).get("stamp") == stamp:
		return bool(checked[actor].due)
	var versions: PackedInt64Array = world.region_versions.get(viewed, PackedInt64Array()) if world is RegionWorld else world.tile_versions
	if versions.size() != world.city.map_size * world.city.map_size:
		return true
	var bounds: Array = views[actor].bounds
	var edge := world.city.map_size
	for x in range(int(bounds[0]), int(bounds[0]) + int(bounds[2])):
		var row := versions.slice(x * edge + int(bounds[1]), x * edge + int(bounds[1]) + int(bounds[3]))
		if not row.is_empty() and int(Array(row).max()) > int(last.revision):
			checked[actor] = {"stamp": stamp, "due": true}
			return true
	checked[actor] = {"stamp": stamp, "due": false}
	deferred += 1
	return false


func published(actor: String, viewed: String, state: Dictionary, now: int) -> void:
	sent[actor] = {"view": viewed, "revision": int(state.revision), "policy": int(state.get("policy", 0)), "time": now}
	forced.erase(actor)


static func local_view(app: CityApplication) -> Dictionary:
	if app.document_state.city == null:
		return {}
	var edge := app.document_state.city.map_size
	var outline := app.map_view.visible_tile_outline()
	if outline.is_empty():
		return {}
	var first := Vector2(edge, edge)
	var last := Vector2.ZERO
	for point: Vector2 in outline:
		first = first.min(point)
		last = last.max(point)
	# Include elevated terrain and tall sprites whose base lies beyond the flat
	# ground projection, plus a camera prefetch margin.
	var begin := (Vector2i(first.floor()) - Vector2i.ONE * 32).clamp(Vector2i.ZERO, Vector2i.ONE * (edge - 1))
	var end := (Vector2i(last.ceil()) + Vector2i.ONE * 33).clamp(begin + Vector2i.ONE, Vector2i.ONE * edge)
	var details := CityViewMode.is_data(app.view_state.overlay_mode)
	for dialog in app.city_dialogs.modeless_windows + app.city_dialogs.blocking_windows:
		details = details or dialog.visible
	return {"bounds": [begin.x, begin.y, end.x - begin.x, end.y - begin.y], "details": details}
