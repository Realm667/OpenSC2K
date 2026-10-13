class_name MasterSpriteSource
extends RefCounted
## Derive the three existing renderer views from one independently authored
## indexed master. Logical geometry stays in the original coordinate system.
## Full-resolution art is shared by all views; there are no small/medium files.

@warning_ignore_start("integer_division")

const SCALE := 4
const MAX_DECODED_BYTES := 512 * 1024 * 1024
const ROAD_SURFACE_INDEX := 0xa1

var large := Sc2SpriteArchive.new()
var small_medium := Sc2SpriteArchive.new()
var error := ""
var _animation_bytes := 0


func load_records(records: Variant, read_png: Callable, palette: Sc2Palette) -> bool:
	error = ""
	large = Sc2SpriteArchive.new()
	small_medium = Sc2SpriteArchive.new()
	large.draw_building_ground = true
	small_medium.draw_building_ground = true
	_animation_bytes = 0
	if not records is Array or records.is_empty():
		return _fail("Sprite lists must be nonempty arrays")

	var seen: Dictionary[int, bool] = {}
	var decoded_bytes := 0
	for record: Variant in records:
		if not record is Dictionary:
			return _fail("Sprite record must be an object")
		var identifier: Variant = record.get("id")
		if not (identifier is int or identifier is float):
			return _fail("Sprite id must be an integer")
		if not is_finite(float(identifier)) or identifier != int(identifier) or identifier < 1000 or identifier > 1499:
			return _fail("Unsupported graphics pack format or version")
		var id := int(identifier)
		if seen.has(id):
			return _fail("Unsupported graphics pack format or version")
		seen[id] = true
		var size: Variant = record.get("logical_size")
		if not size is Array or size.size() != 2:
			return _fail("Unsupported graphics pack format or version")
		for side: Variant in size:
			if not (side is int or side is float):
				return _fail("Unsupported graphics pack format or version")
			if not is_finite(float(side)) or side != int(side) or side < 1 or side > 4096 / SCALE:
				return _fail("Unsupported graphics pack format or version")
		var logical := Vector2i(int(size[0]), int(size[1]))
		var decoded: IndexedImageResult = read_png.call(record.get("png"))
		if decoded == null or not decoded.ok:
			return _fail("Invalid PNG pixels or palette")
		if decoded.palette.colors != palette.colors:
			return _fail("Sprite palette differs from the pack palette: %s" % record.png)
		if Vector2i(decoded.width, decoded.height) != logical * SCALE:
			return _fail("Unsupported graphics pack format or version")
		decoded_bytes += decoded.width * decoded.height * 8
		if decoded_bytes > MAX_DECODED_BYTES:
			return _fail("Unsupported graphics pack format or version")
		var master := Sc2SpriteArchive.entry_from_indices(id, decoded.width, decoded.height, decoded.pixels)
		var rendered := master.create_image(palette)
		if not rendered.ok:
			return _fail(rendered.error)
		var emission: Image
		if record.has("lightmap"):
			var light: IndexedImageResult = read_png.call(record.lightmap)
			if light == null or not light.ok:
				return _fail("Invalid PNG pixels or palette")
			if Vector2i(light.width, light.height) != logical * SCALE:
				return _fail("Unsupported graphics pack format or version")
			# A mask has its own emission colors. Its nontransparent pixels must
			# belong to the master silhouette; roofs/ground still need art review.
			for pixel in light.pixels.size():
				if light.pixels[pixel] >= 0 and decoded.pixels[pixel] < 0:
					return _fail("Invalid PNG pixels or palette")
			decoded_bytes += light.width * light.height * 8
			if decoded_bytes > MAX_DECODED_BYTES:
				return _fail("Unsupported graphics pack format or version")
			var light_entry := Sc2SpriteArchive.entry_from_indices(id, light.width, light.height, light.pixels)
			var light_rendered := light_entry.create_image(light.palette)
			if not light_rendered.ok:
				return _fail(light_rendered.error)
			emission = light_rendered.image
		var animation := _load_animation(record, decoded, read_png, palette, emission, MAX_DECODED_BYTES - decoded_bytes)
		if not error.is_empty():
			return false
		var traffic_mask: IndexedImageResult
		if record.has("traffic_mask"):
			traffic_mask = read_png.call(record.traffic_mask)
			if traffic_mask == null or not traffic_mask.ok or Vector2i(traffic_mask.width, traffic_mask.height) != logical * SCALE:
				return _fail("Invalid traffic mask geometry")
			var has_road := false
			for pixel in traffic_mask.pixels.size():
				if traffic_mask.pixels[pixel] >= 0:
					has_road = true
					if decoded.pixels[pixel] < 0:
						return _fail("Traffic mask extends outside the artwork")
			if not has_road:
				return _fail("Traffic mask is empty")
			decoded_bytes += traffic_mask.width * traffic_mask.height * 4
		if decoded_bytes + _animation_bytes > MAX_DECODED_BYTES:
			return _fail("Unsupported graphics pack format or version")
		for view in 3:
			var divisor := 4 >> view
			var view_size := Vector2i(maxi(1, logical.x / divisor), maxi(1, (logical.y + divisor - 1) / divisor))
			var view_id := id - 1000 + view * 500
			var indices := _sample_indices(decoded, view_size, divisor)
			if traffic_mask != null:
				var road := _sample_indices(traffic_mask, view_size, divisor)
				for pixel in indices.size():
					# The native traffic compositor reads this semantic index. Keep
					# the full-resolution texture unchanged, including its shading.
					if road[pixel] >= 0 and indices[pixel] >= 0:
						indices[pixel] = ROAD_SURFACE_INDEX
					elif indices[pixel] == ROAD_SURFACE_INDEX:
						indices[pixel] = ROAD_SURFACE_INDEX - 1
			var entry := Sc2SpriteArchive.entry_from_indices(view_id, view_size.x, view_size.y, indices)
			var archive := large if view == 2 else small_medium
			archive.entries.append(entry)
			archive.entries_by_id[view_id] = entry
			var artwork := HdSprite.new()
			artwork.image = rendered.image
			artwork.height = view_size.y
			artwork.emission = emission
			if not animation.is_empty():
				artwork.animation = animation.art
				artwork.frames = animation.frames
				artwork.fps = animation.fps
				artwork.emission_animation = animation.light
			archive.high_resolution[view_id] = artwork
	return true


func _load_animation(record: Dictionary, master: IndexedImageResult, read_png: Callable, palette: Sc2Palette, emission: Image, available_bytes: int) -> Dictionary:
	if not record.has("animation"):
		return {}
	var spec: Variant = record.animation
	if not spec is Dictionary:
		_fail("Unsupported graphics pack format or version")
		return {}
	var paths: Variant = spec.get("frames")
	var rate: Variant = spec.get("fps", 8)
	if not paths is Array or paths.size() < 2 or paths.size() > 32:
		_fail("Unsupported graphics pack format or version")
		return {}
	if not (rate is int or rate is float) or rate != int(rate) or int(rate) not in [5, 8]:
		_fail("Unsupported graphics pack format or version")
		return {}
	var light_paths: Variant = spec.get("lightmaps", [])
	if not light_paths is Array or (not light_paths.is_empty() and light_paths.size() != paths.size()):
		_fail("Unsupported graphics pack format or version")
		return {}
	if not light_paths.is_empty() and emission == null:
		_fail("Invalid PNG pixels or palette")
		return {}
	var frame_size := Vector2i(master.width, master.height)
	# The existing HD GPU atlas adds two padding rows to each frame.
	if (frame_size.y + 2) * paths.size() > 8190:
		_fail("Unsupported graphics pack format or version")
		return {}
	var bytes: int = master.width * master.height * paths.size() * 4
	if emission != null or not light_paths.is_empty():
		bytes *= 2
	_animation_bytes += bytes
	if _animation_bytes > available_bytes:
		_fail("Unsupported graphics pack format or version")
		return {}
	var strip := Image.create(master.width, master.height * paths.size(), false, Image.FORMAT_RGBA8)
	var lights: Image
	if emission != null or not light_paths.is_empty():
		lights = Image.create(master.width, master.height * paths.size(), false, Image.FORMAT_RGBA8)
	for frame in paths.size():
		var decoded: IndexedImageResult = read_png.call(paths[frame])
		if decoded == null or not decoded.ok or Vector2i(decoded.width, decoded.height) != frame_size or decoded.palette.colors != palette.colors:
			_fail("Invalid PNG pixels or palette")
			return {}
		if frame == 0 and decoded.pixels != master.pixels:
			_fail("Invalid PNG pixels or palette")
			return {}
		var entry := Sc2SpriteArchive.entry_from_indices(0, decoded.width, decoded.height, decoded.pixels)
		var rendered := entry.create_image(palette)
		if not rendered.ok:
			_fail(rendered.error)
			return {}
		strip.blit_rect(rendered.image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(0, frame * master.height))
		var light := emission
		if not light_paths.is_empty():
			var light_data: IndexedImageResult = read_png.call(light_paths[frame])
			if light_data == null or not light_data.ok or Vector2i(light_data.width, light_data.height) != frame_size:
				_fail("Invalid PNG pixels or palette")
				return {}
			var light_entry := Sc2SpriteArchive.entry_from_indices(0, master.width, master.height, light_data.pixels)
			var light_image := light_entry.create_image(light_data.palette)
			if not light_image.ok:
				_fail(light_image.error)
				return {}
			light = light_image.image
			if frame == 0 and light.get_data() != emission.get_data():
				_fail("Invalid PNG pixels or palette")
				return {}
		if light != null:
			for y in master.height:
				for x in master.width:
					if light.get_pixel(x, y).a8 > 0 and decoded.pixels[y * master.width + x] < 0:
						_fail("Invalid PNG pixels or palette")
						return {}
			lights.blit_rect(light, Rect2i(Vector2i.ZERO, frame_size), Vector2i(0, frame * master.height))
	return {"art": strip, "light": lights, "frames": paths.size(), "fps": int(rate)}


static func _sample_indices(source: IndexedImageResult, size: Vector2i, divisor: int) -> PackedInt32Array:
	var pixels := PackedInt32Array()
	pixels.resize(size.x * size.y)
	# Keep the bottom baseline, including the extra shared diamond edge. Do not
	# quantize colors: reserved/animated indices must keep their exact meaning.
	for y in size.y:
		var sy := maxi(0, source.height - 1 - (size.y - 1 - y) * divisor * SCALE)
		for x in size.x:
			var sx := mini(source.width - 1, x * divisor * SCALE + divisor * SCALE / 2)
			var index := source.pixels[sy * source.width + sx]
			if index < 0:
				# A point sample can miss an entire cable or wireframe. Retain
				# supported thin details from this pixel's own bottom-aligned cell.
				var step := divisor * SCALE
				index = _covered_index(source, x * step, mini(source.width, (x + 1) * step),
					maxi(0, sy - step + 1), sy + 1)
			pixels[y * size.x + x] = index
	return pixels


static func _covered_index(source: IndexedImageResult, x0: int, x1: int, y0: int, y1: int) -> int:
	var counts: Dictionary[int, int] = {}
	var visible := 0
	var best := -1
	var best_count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var index := source.pixels[y * source.width + x]
			if index < 0:
				continue
			visible += 1
			counts[index] = counts.get(index, 0) + 1
			if counts[index] > best_count:
				best = index
				best_count = counts[index]
	# Suppress isolated source specks, but retain a two-pixel cable in a 16x16
	# overview cell. The selected index is always an existing palette entry.
	return best if visible * 16 >= (x1 - x0) * (y1 - y0) else -1


func _fail(message: String) -> bool:
	error = message
	large = Sc2SpriteArchive.new()
	small_medium = Sc2SpriteArchive.new()
	return false
