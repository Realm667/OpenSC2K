class_name CityMapPreviewControl
extends Control

signal center_requested(point: Vector2i)

const MAP_SIZE := 128
const BORDER := 2.0

var ownership_texture: Texture2D
var ownership_signature: Array = []
var map_texture: Texture2D
var viewport_outline := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	custom_minimum_size = Vector2(256, 256)
	gui_input.connect(_on_gui_input)
	# a UI scale change on the main window moves the screen pixel grid
	get_tree().root.size_changed.connect(queue_redraw)


func _draw() -> void:
	var map_edge: int = map_texture.get_width() if map_texture != null else 128
	var target := map_rect()
	draw_rect(target.grow(BORDER), Color("1b222b"), true)
	draw_rect(target.grow(BORDER), Color("8d97a5"), false, 1.0)

	if map_texture != null:
		draw_texture_rect(map_texture, target, false)

	if ownership_texture != null:
		draw_texture_rect(ownership_texture, target, false)
	if viewport_outline.size() < 2:
		return

	var local := PackedVector2Array()

	for point in viewport_outline:
		local.append(target.position + point / float(map_edge) * target.size)

	local.append(local[0])
	draw_polyline(local, Color("202020"), 3.0, false)
	draw_polyline(local, Color("ffffff"), 1.0, false)


func set_map(image: Image) -> void:
	map_texture = null if image == null or image.is_empty() else ImageTexture.create_from_image(image)
	queue_redraw()


func set_viewport_outline(points: PackedVector2Array) -> void:
	viewport_outline = points.duplicate()
	queue_redraw()


func map_rect() -> Rect2:
	# leave room for the border inside the control, which clips its contents
	var edge := maxf(0.0, minf(size.x, size.y) - BORDER * 2.0)
	# give each map pixel the same whole number of screen pixels
	edge = ScreenPixels.whole_cells(edge, map_texture.get_width() if map_texture != null else MAP_SIZE)

	return Rect2(ScreenPixels.snap(self, (size - Vector2(edge, edge)) * 0.5), Vector2(edge, edge))


func _on_gui_input(event: InputEvent) -> void:
	var map_edge: int = map_texture.get_width() if map_texture != null else 128

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var target := map_rect()

	if not target.has_point(mouse_event.position):
		return

	var relative := (mouse_event.position - target.position) / target.size
	var point := Vector2i(
		clampi(floori(relative.x * map_edge), 0, map_edge - 1),
		clampi(floori(relative.y * map_edge), 0, map_edge - 1),
	)
	center_requested.emit(point)
	accept_event()


func set_ownership(state: Dictionary, map_size: int) -> void:
	var owners: Array = state.get("owners", [])
	var actor_ids: Array = state.get("owner_ids", [])
	var colors := {}
	for player: Dictionary in state.get("roster", []):
		colors[player.id] = player.get("color", "ffffff")
	var signature: Array = [hash(owners), hash(state.get("protection", [])), actor_ids, colors]
	if signature == ownership_signature:
		return
	ownership_signature = signature
	ownership_texture = null
	if owners.size() != map_size * map_size or actor_ids.is_empty():
		queue_redraw()
		return
	var image := Image.create(map_size, map_size, false, Image.FORMAT_RGBA8)
	for x in map_size:
		for y in map_size:
			var tile := x * map_size + y
			var owner := int(owners[tile])
			if owner <= 0 or owner > actor_ids.size():
				var reserved := int(state.protection[tile]) if state.get("protection", []).size() == owners.size() else 0
				if reserved == -1:
					image.set_pixel(x, y, Color(0.85, 0.85, 0.85, 0.45))
				elif reserved > 0 and reserved <= actor_ids.size() and (x + y) % 2 == 0:
					image.set_pixel(x, y, Color(Color.from_string(colors.get(actor_ids[reserved - 1], "ffffff"), Color.WHITE), 0.45))
				continue
			var color := Color.from_string(colors.get(actor_ids[owner - 1], "ffffff"), Color.WHITE)
			var edge := x == 0 or y == 0 or x == map_size - 1 or y == map_size - 1
			for next: int in MultiplayerLandRules.neighbours(tile, map_size):
				edge = edge or int(owners[next]) != owner
			image.set_pixel(x, y, Color(color, 0.95 if edge else 0.35))
	ownership_texture = ImageTexture.create_from_image(image)
	queue_redraw()
