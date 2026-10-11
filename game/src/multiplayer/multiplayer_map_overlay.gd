class_name MultiplayerMapOverlay
extends RefCounted
## Cosmetic map-space interpolation and alpha-aware ground boundaries.

const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var cursors: Dictionary = {}
var cached_key: Array = []
var lines: Dictionary = {}
var layer_cache: Dictionary = {}
var highlight: Array = []
var highlight_until := 0
var owned_tiles: Array = []
var reserved_tiles: Array = []
var boundary_edges: Dictionary = {}
var ownership_generation := 0
var occlusion_generation := 0
var segment_cache: Dictionary = {}
var segment_context: Array = []

func invalidate_occlusion(rects: Array[Rect2i]) -> void:
	var changed := false
	for key: Vector3i in segment_cache.keys():
		for rect: Rect2i in rects:
			if segment_cache[key].bounds.intersects(rect):
				segment_cache.erase(key)
				changed = true
				break
	if changed:
		occlusion_generation += 1

func receive_ownership(state: Dictionary) -> void:
	var owned: Array = state.get("owners", [])
	var protection: Array = state.get("protection", [])
	if owned == owned_tiles and protection == reserved_tiles:
		return
	owned_tiles = owned.duplicate()
	reserved_tiles = protection.duplicate()
	ownership_generation += 1
	layer_cache.clear()
	segment_cache.clear()
	boundary_edges.clear()
	var extended := owned.duplicate()
	for tile in mini(extended.size(), protection.size()):
		if int(extended[tile]) == 0 and int(protection[tile]) > 0:
			extended[tile] = protection[tile]
	var size := roundi(sqrt(owned.size()))
	if size == 0:
		return
	for suffix: String in ["", ":reserved"]:
		var ownership: Array = extended if not suffix.is_empty() else owned
		var edges: Array = []
		if suffix.is_empty() or extended != owned:
			for tile in ownership.size():
				var owner := int(ownership[tile])
				if owner <= 0:
					continue
				@warning_ignore("integer_division")
				var point := Vector2i(tile / size, tile % size)
				var visible := 0
				for edge in 4:
					if edge_visible(ownership, size, point, edge):
						visible |= 1 << edge
				if visible:
					edges.append([point, owner, visible])
		boundary_edges[suffix] = edges

static func edge_visible(ownership: Array, size: int, tile: Vector2i, edge: int) -> bool:
	var near: Vector2i = tile + DIRECTIONS[edge]
	return near.x < 0 or near.y < 0 or near.x >= size or near.y >= size or int(ownership[near.x * size + near.y]) != int(ownership[tile.x * size + tile.y])

static func project(city: CityState, position: Vector2) -> Vector2:
	var tile := Vector2i(floori(position.x + 0.5), floori(position.y + 0.5))
	tile = tile.clamp(Vector2i.ZERO, Vector2i.ONE * (city.map_size - 1))
	var polygon := CityIsometricRenderer.terrain_surface_polygon(city, tile.x, tile.y)
	var u := clampf(position.x - tile.x + 0.5, 0.0, 1.0)
	var v := clampf(position.y - tile.y + 0.5, 0.0, 1.0)
	return polygon[0].lerp(polygon[1], u).lerp(polygon[3].lerp(polygon[2], u), v)

static func local_cursor(app: CityApplication) -> Vector2:
	var map := app.map_view
	var hovered := app.get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != map:
		return Vector2(-1, -1)
	var tile := map.hover_tile
	if map.city == null or map.city.index_of(tile.x, tile.y) < 0 or not map.get_global_rect().has_point(map.get_global_mouse_position()):
		return Vector2(-1, -1)
	var scale: float = map.camera._view_scale()
	var point: Vector2 = (map.get_local_mouse_position() - map.camera._draw_offset(scale)) / scale
	var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, tile.x, tile.y)
	# Invert the two ground axes. Sloping corners are approximated locally; the
	# transmitted point remains a sub-tile position, independent of pan and zoom.
	var axes := Transform2D(polygon[1] - polygon[0], polygon[3] - polygon[0], polygon[0])
	var relative := axes.affine_inverse() * point
	return Vector2(tile) + relative.clamp(Vector2.ZERO, Vector2.ONE) - Vector2.ONE * 0.5

func receive(players: Array) -> void:
	var online := {}
	for player: Dictionary in players:
		var value: Variant = player.get("cursor")
		if not player.get("online", false) or not value is Array or value.size() != 2:
			continue
		var position := Vector2(float(value[0]), float(value[1]))
		if not position.is_finite() or position == Vector2(-1, -1):
			continue
		online[player.id] = true
		if not cursors.has(player.id) or Vector2(cursors[player.id].position).distance_to(position) > 12:
			cursors[player.id] = {"position": position, "target": position, "moved": Time.get_ticks_msec()}
		if Vector2(cursors[player.id].target).distance_to(position) > 0.025:
			cursors[player.id].moved = Time.get_ticks_msec()
		cursors[player.id].target = position
		cursors[player.id].received = Time.get_ticks_msec()
	for id: String in cursors.keys():
		if not online.has(id):
			cursors.erase(id)

func step(delta: float) -> void:
	for id: String in cursors.keys():
		if Time.get_ticks_msec() - int(cursors[id].received) > 3000:
			cursors.erase(id)
			continue
		cursors[id].position = Vector2(cursors[id].position).lerp(cursors[id].target, 1.0 - exp(-28.0 * delta))

func boundaries(app: CityApplication, state: Dictionary) -> Dictionary:
	var combined := boundary_layer(app, state, owned_tiles, "")
	if not boundary_edges.get(":reserved", []).is_empty():
		combined.merge(boundary_layer(app, state, owned_tiles, ":reserved"))
	return combined

func boundary_layer(app: CityApplication, state: Dictionary, _ownership: Array, suffix: String) -> Dictionary:
	var city := app.document_state.city
	var map := app.map_view
	var scale: float = map.camera._view_scale()
	var offset: Vector2 = map.camera._draw_offset(scale)
	var area := Rect2(-offset / scale, map.size / scale).grow(3)
	var context := [city.document.get_instance_id(), city.chunk_revision("ALTM"), city.chunk_revision("XTER"),
		app.static_render.city_view_size(), city.compass_rotation(), app.view_state.surface_visibility]
	if context != segment_context:
		segment_context = context.duplicate(true)
		segment_cache.clear()
		occlusion_generation += 1
	# Static rendering invalidates only segments intersecting changed silhouettes.
	var key := [ownership_generation, state.get("owner_ids"), occlusion_generation, area]
	if layer_cache.has(suffix) and layer_cache[suffix].key == key:
		return layer_cache[suffix].lines.duplicate()
	cached_key = key
	lines.clear()
	var ids: Array = state.get("owner_ids", [])
	for entry: Array in boundary_edges.get(suffix, []):
		var point: Vector2i = entry[0]
		var owner: int = entry[1]
		if owner > ids.size():
			continue
		var polygon := CityIsometricRenderer.terrain_surface_polygon(city, point.x, point.y)
		if not area.intersects(Rect2(polygon[0], Vector2.ZERO).expand(polygon[1]).expand(polygon[2]).expand(polygon[3])):
			continue
		for edge in 4:
			if int(entry[2]) & (1 << edge) == 0:
				continue
			var segment_key := Vector3i(point.x, point.y, edge)
			if not segment_cache.has(segment_key):
				var a: Vector2 = polygon[edge]
				var b: Vector2 = polygon[(edge + 1) % 4]
				segment_cache[segment_key] = {"bounds": Rect2i(Rect2(a, Vector2.ZERO).expand(b).grow(2)),
					"segments": visible_segments(app, point, a, b)}
			var segments: PackedVector2Array = segment_cache[segment_key].segments
			var existing: PackedVector2Array = lines.get(str(ids[owner - 1]) + suffix, PackedVector2Array())
			existing.append_array(segments)
			lines[str(ids[owner - 1]) + suffix] = existing
	layer_cache[suffix] = {"key": key, "lines": lines.duplicate()}
	return lines.duplicate()

static func visible_segments(app: CityApplication, tile: Vector2i, a: Vector2, b: Vector2) -> PackedVector2Array:
	var city := app.document_state.city
	var bounds := Rect2i(Rect2(a, Vector2.ZERO).expand(b).grow(2))
	var commands := app.moving_sprites.static_occlusion_candidates(bounds)
	if app.render_caches.region_cache != null:
		commands = app.render_caches.region_cache.occlusion_candidates(bounds, true)
	var view := app.static_render.city_view_size()
	var archive := app.static_render.sprite_archive_for_view(view)
	if archive == null:
		return PackedVector2Array([a, b])
	var divisor := IsometricGeometry.view_configuration(view).divisor
	var masks: Array = []
	var depth := (tile.x + tile.y) * city.map_size + tile.y
	for command in commands:
		if command.depth_order < depth:
			continue
		var occluder_tile := IsometricFloatingOcclusion.depth_tile(command.depth_order, city.map_size)
		# Flat neighbouring ground must not erase an outline shared by two tiles.
		# Raised terrain still masks lower ground; buildings and trees use alpha.
		if command.sprite_id % 500 >= 256 and city.land_altitude(occluder_tile.x, occluder_tile.y) <= city.land_altitude(tile.x, tile.y):
			continue
		var resource := app.moving_sprites.dynamic_sprite_resource(archive, command.sprite_id, command.flip, divisor)
		if resource != null:
			masks.append({"origin": Vector2(command.position) * divisor, "image": resource.image})
	var result := PackedVector2Array()
	var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
	var run := -1
	for index in steps + 1:
		var hidden := index == steps
		var sample := a.lerp(b, (index + 0.5) / float(steps))
		for mask: Dictionary in masks:
			var pixel := Vector2i((sample - Vector2(mask.origin)).floor())
			var image: Image = mask.image
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.1:
				hidden = true
				break
		if not hidden and run < 0:
			run = index
		elif hidden and run >= 0:
			result.append(a.lerp(b, run / float(steps)))
			result.append(a.lerp(b, index / float(steps)))
			run = -1
	return result
