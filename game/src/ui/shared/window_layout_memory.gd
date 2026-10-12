class_name WindowLayoutMemory
extends Node
## Local window geometry. Popups and modal decisions are never reopened.

signal save_failed(message: String)

var storage_path := ""
var config := ConfigFile.new()
var windows: Dictionary[String, Window] = {}
var _shown: Dictionary[String, bool] = {}
var _dirty := false
var _elapsed := 0.0


func _ready() -> void:
	config.load(storage_path)
	_scan(get_parent())
	get_tree().node_added.connect(_node_added)


func _scan(node: Node) -> void:
	_node_added(node)
	for child in node.get_children():
		_scan(child)


func _node_added(node: Node) -> void:
	if node is Window and not node is Popup:
		_register.call_deferred(node.get_instance_id())


func _register(instance_id: int) -> void:
	var node := instance_from_id(instance_id) as Node
	if not is_instance_valid(node) or not node.is_inside_tree() or not get_parent().is_ancestor_of(node):
		return
	var window := node as Window
	var key := window.scene_file_path
	if key.is_empty():
		key = str(window.get_script().resource_path) if window.get_script() != null else window.get_class()
		key += ":" + window.title
	if key.is_empty():
		return
	windows[key] = window
	_shown[key] = window.visible
	window.visibility_changed.connect(_visibility_changed.bind(key))


func _visibility_changed(key: String) -> void:
	var window: Window = windows.get(key)
	if not is_instance_valid(window):
		return
	if window.visible:
		# popup_centered finishes after visibility_changed; restore afterwards.
		_shown[key] = false
		_restore.call_deferred(key)
	else:
		if _shown.get(key, false):
			config.set_value("windows", key, Rect2i(window.position, window.size))
			_dirty = true
		_shown[key] = false
		flush.call_deferred()


func _restore(key: String) -> void:
	var window: Window = windows.get(key)
	if not is_instance_valid(window) or not window.visible:
		return
	var saved: Variant = config.get_value("windows", key, Rect2i())
	if saved is Rect2i and saved.size.x > 0 and saved.size.y > 0:
		if not window.unresizable:
			window.size = saved.size
		window.position = saved.position
	_clamp(window)
	_shown[key] = true


static func fit_position(position: Vector2i, size: Vector2i, bounds: Rect2i, title_height := 30) -> Vector2i:
	return Vector2i(clampi(position.x, bounds.position.x, maxi(bounds.position.x, bounds.end.x - size.x)),
		clampi(position.y, bounds.position.y + title_height, maxi(bounds.position.y + title_height, bounds.end.y - size.y)))


func _clamp(window: Window) -> void:
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(get_tree().root.get_visible_rect().size)) if window.is_embedded() \
		else DisplayServer.screen_get_usable_rect(window.current_screen)
	if not window.unresizable:
		window.size = window.size.min(Vector2i(bounds.size.x, maxi(1, bounds.size.y - 30)))
	window.position = fit_position(window.position, window.size, bounds)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	for key in windows:
		var window: Window = windows[key]
		if not is_instance_valid(window) or not window.visible or not _shown.get(key, false):
			continue
		_clamp(window)
		var rect := Rect2i(window.position, window.size)
		if config.get_value("windows", key, Rect2i()) != rect:
			config.set_value("windows", key, rect)
			_dirty = true
	# Write on close, workspace save or application exit, not on every drag.


func capture() -> Dictionary:
	var result := {}
	for key in windows:
		var window: Window = windows[key]
		if is_instance_valid(window) and window.visible and _shown.get(key, false):
			result[key] = Rect2i(window.position, window.size)
	return result


func apply_geometry(layout: Dictionary) -> void:
	for key: Variant in layout:
		if key is String and layout[key] is Rect2i:
			config.set_value("windows", key, layout[key])
			_restore(str(key))
	_dirty = true


func flush() -> void:
	if not _dirty or storage_path.is_empty():
		return
	var error := config.save(storage_path)
	if error != OK:
		save_failed.emit(tr("Cannot save window layouts: %s") % error_string(error))
	else:
		_dirty = false


func save_workspace(name: String, geometry: Dictionary, visible_ids: Array[int]) -> bool:
	config.set_value("workspaces", name, {"geometry": geometry, "visible": visible_ids})
	_dirty = true
	flush()
	return not _dirty


func reset_positions() -> void:
	if config.has_section("windows"):
		config.erase_section("windows")
	for window: Window in windows.values():
		if is_instance_valid(window) and window.visible:
			window.position = Vector2i(get_tree().root.get_visible_rect().size - Vector2(window.size)) / 2
			_clamp(window)
	_dirty = true
	flush()


func _exit_tree() -> void:
	var current := capture()
	for key: String in current:
		config.set_value("windows", key, current[key])
		_dirty = true
	flush()
