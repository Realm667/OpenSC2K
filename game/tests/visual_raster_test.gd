extends SceneTree
## Independent scalar references retain the former pixel and crowding rules.
@warning_ignore_start("integer_division")

func _initialize() -> void:
	for scale_value in [1, 2, 4]:
		for diagonal in [false, true]:
			for slope in [0.0, 3.0, -7.0]:
				_check_pixels(scale_value, diagonal, slope)
	_check_crowding()
	_check_clipped_masks()
	_check_world_cache()
	_check_figure_buffers()
	_check_alpha_mask()
	print("PASS: bulk light raster/encoding matches scalar pixels; crowding decisions unchanged")
	quit()


func _check_pixels(scale_value: int, diagonal: bool, slope: float) -> void:
	var bounds := Rect2i(-24, -20, 48, 40)
	bounds = Rect2i(bounds.position * scale_value, bounds.size * scale_value)
	var inverse := Transform2D(Vector2(16, 8 + slope), Vector2(-8, 4), Vector2(-4, -3)).affine_inverse()
	var tile := Vector2(64, 63)
	var start := Vector2(0, -0.5) if diagonal else Vector2.ZERO
	var along := Vector2(0.5, 0.5) if diagonal else Vector2(0, 0.5)
	var side := Vector2(-0.3535534, 0.3535534) if diagonal else Vector2(0.5, 0)
	var expected := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBAF)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var uv := inverse * (Vector2(x + 0.5, y + 0.5) / scale_value)
			var local := start + along * uv.x + side * (uv.y - 0.5)
			if uv.y >= 0.0 and uv.y <= 1.0 and ((absf(local.x) <= 0.5 and absf(local.y) <= 0.5) if diagonal else (uv.x >= 0.0 and uv.x <= 1.0)):
				var world := tile + local
				expected.set_pixel(x - bounds.position.x, y - bounds.position.y, Color(world.x, world.y, 0, 1))
	var actual := NativeVisualRaster.road_patch(bounds, inverse, scale_value, tile, start, along, side, diagonal)
	assert(actual.get_data() == expected.get_data(), "Native road plane differs from scalar projection")
	var encoded := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	var reference := encoded.duplicate() as Image
	var destination := Vector2i(-3, 2)
	NativeVisualRaster.encode_receiver(encoded, actual, destination, tile)
	for y in reference.get_height():
		for x in reference.get_width():
			var point := Vector2i(x, y) - destination
			if not Rect2i(Vector2i.ZERO, expected.get_size()).has_point(point):
				continue
			var sample := expected.get_pixelv(point)
			if sample.a <= 0:
				continue
			var local := Vector2(sample.r, sample.g) - tile + Vector2(4, 4)
			var u := clampi(roundi(local.x * 512.0), 0, 4095)
			var v := clampi(roundi(local.y * 512.0), 0, 4095)
			reference.set_pixel(x, y, Color8(u >> 4, ((u & 15) << 4) | (v >> 8), v & 255, 255))
	assert(encoded.get_data() == reference.get_data(), "Receiver clipping or 12-bit coordinates changed")
	var batch := NativeVisualRaster.headlight_receiver(bounds.size, -destination, [{"image": actual, "origin": Vector2i.ZERO}], tile)
	assert(batch.get_data() == reference.get_data(), "Batched receiver differs from scalar encoding")
	var lamps: Array = [{"position": tile + Vector2(0.1, -0.2), "color": Color("ffda84"), "radius": 0.8, "intensity": 0.4},
		{"position": tile + Vector2(-0.1, 0.3), "color": Color("92baf1"), "radius": 0.5, "intensity": 0.75}]
	var lit := NativeVisualRaster.night_receiver(bounds.size, bounds.position, [{"image": actual, "origin": bounds.position}, {"image": actual, "origin": bounds.position}], lamps)
	reference.fill(Color(0, 0, 0, 0))
	for y in expected.get_height():
		for x in expected.get_width():
			var sample := expected.get_pixel(x, y)
			if sample.a <= 0.0:
				continue
			var color := Color(0, 0, 0, 1)
			for light in lamps:
				var distance := Vector2(sample.r, sample.g).distance_to(light.position)
				var falloff := pow(maxf(0.0, 1.0 - distance / float(light.radius)), 1.6)
				color += Color(light.color) * falloff * float(light.intensity)
				color.a = 1.0
			reference.set_pixel(x, y, color.clamp())
	if lit.get_data() != reference.get_data():
		for index in lit.get_data().size():
			if lit.get_data()[index] != reference.get_data()[index]:
				print("RASTER DIFFERENCE ", scale_value, " ", diagonal, " ", slope, " byte ", index, " native ", lit.get_data()[index], " reference ", reference.get_data()[index])
				break
		assert(false, "Street light color, falloff or overlapping patch ownership changed")


func _check_clipped_masks() -> void:
	var source := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	source.fill_rect(Rect2i(7, 9, 65, 60), Color(0.2, 0.5, 0.7, 0.4))
	var candidates: Array = [{"origin": Vector2i(-30, -40), "image": source}, {"origin": Vector2i(35, 15), "image": source}]
	var clip := Rect2i(-4, 6, 61, 37)
	var merged := CityLifeCanvas.merged_occluders(candidates, clip)
	var scaled := CityLifeCanvas.scaled_occluders(merged, 4, clip)
	for y in range(clip.position.y, clip.end.y):
		for x in range(clip.position.x, clip.end.x):
			var point := Vector2i(x, y)
			assert(CityLifeCanvas.hidden_at(point, merged) == CityLifeCanvas.hidden_at(point, candidates))
			assert(CityLifeCanvas.hidden_at(point * 4 + Vector2i(3, 2), scaled) == CityLifeCanvas.hidden_at(point, candidates))
	assert(CityLifeCanvas.merged_occluders(candidates, Rect2i(1000, 1000, 8, 8)).is_empty())
	assert(merged[0].image.get_width() <= clip.size.x and merged[0].image.get_height() <= clip.size.y)


func _check_crowding() -> void:
	var app := CityApplication.new()
	var controller := app.city_life
	var random := RandomNumberGenerator.new()
	random.seed = 712984
	for id in 100:
		var figure := CityLifeController.Figure.new()
		figure.id = id
		figure.walking = id % 4 == 0
		figure.vehicle_kind = id % 3
		figure.position = Vector2(random.randf_range(-32, 32), random.randf_range(-32, 32))
		figure.enter = random.randi_range(0, 3)
		figure.exit = random.randi_range(0, 3)
		figure.progress = random.randf()
		figure.diagonal = id % 2 == 0
		figure.age = 50 if id % 7 == 0 else 0
		controller.figures.append(figure)
	controller._rebuild_buckets()
	for figure in controller.figures:
		for spawning in [false, true]:
			for offset in [Vector2.ZERO, Vector2(1, -2), Vector2(-8, 5)]:
				assert(controller._crowded(figure, figure.position + offset, spawning) == _reference_crowded(controller, figure, figure.position + offset, spawning))
	app.free()


func _reference_crowded(controller: CityLifeController, figure: CityLifeController.Figure, position: Vector2, spawning: bool) -> bool:
	var center := CityLifeController._bucket(position)
	var direction := figure.heading()
	var world := CityLifePaths.forward(direction)
	var forward := Vector2((world.x - world.y) * 16, (world.x + world.y) * 8)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for other: CityLifeController.Figure in controller._buckets.get(center + Vector2i(x, y), []):
				if other == figure or other.walking != figure.walking or other.age >= other.lifetime:
					continue
				var separation := other.position - position
				if not spawning:
					var other_direction := other.heading()
					if CityLifePaths.opposite(direction) == other_direction:
						continue
					if direction == other_direction and separation.dot(forward) <= 0.0:
						continue
					if direction != other_direction and figure.id < other.id:
						continue
				var spacing := 3.0 if spawning or figure.walking else 5.0
				if not figure.walking:
					spacing += figure.extra_spacing() + other.extra_spacing()
				if separation.length_squared() < spacing * spacing:
					return true
	return false


func _check_world_cache() -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	var lights := CityLifeLights.new()
	var figure := CityLifeController.Figure.new()
	figure.tile = Vector2i(64, 64)
	city.set_building_id(64, 64, BuildingTileIds.ROAD_CROSSROADS)
	for height in [0, 3, 7]:
		city.set_land_altitude(64, 64, height)
		lights.sync_geometry(city)
		for enter in 4:
			for exit in 4:
				figure.enter = enter
				figure.exit = exit
				for progress in [0.0, 0.3, 0.8, 1.0]:
					figure.progress = progress
					figure.position = CityLifePaths.point(city, figure.tile, enter, exit, progress, false)
					assert(lights.cached_vehicle_world(city, figure) == CityLifeLights.vehicle_world(city, figure), "Cached vehicle plane must follow road edits without changing world coordinates")


func _check_figure_buffers() -> void:
	for scale_value in [1, 2, 4]:
		var entries: Array = []
		var rectangles := {}
		var origins := PackedVector2Array()
		var layers := PackedInt32Array()
		var expected: Array[PackedFloat32Array] = []
		var buffer := PackedFloat32Array()
		var data := PackedFloat32Array()
		var origin := Vector2i(-30, 84)
		for index in 70:
			var slot := index % 64
			if slot == 0:
				buffer = PackedFloat32Array()
				buffer.resize(64 * 8)
				data = PackedFloat32Array()
				data.resize(64 * 12)
			var sprite := Image.create(2, 2, false, Image.FORMAT_RGBA8)
			var rect := Rect2i(index * 3, 9, 9 * scale_value, 6 * scale_value)
			rectangles[sprite.get_instance_id()] = rect
			var figure := CityLifeController.Figure.new()
			figure.position = Vector2(index - 25.375, 8.625 + index)
			figure.previous_position = figure.position - Vector2(0.25, 0.125)
			figure.has_previous_position = index % 2 == 0
			var point := Vector2i(figure.position.round())
			var opacity := index / 70.0
			entries.append({"sprite": sprite, "origin": point, "opacity": opacity, "figure": figure})
			origins.append(Vector2(index * 32, -index))
			layers.append(index % 7)
			var visual: Vector2 = figure.position
			var destination := visual - Vector2(origin)
			var at := slot * 8
			buffer[at] = rect.size.x / scale_value
			buffer[at + 3] = destination.x
			buffer[at + 5] = rect.size.y / scale_value
			buffer[at + 7] = destination.y
			at = slot * 4
			for channel in 4:
				data[at + channel] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y][channel]
			var previous := figure.previous_position if figure.has_previous_position else figure.position
			for channel in 4:
				data[64 * 4 + at + channel] = [visual.x, visual.y, previous.x - figure.position.x, previous.y - figure.position.y][channel]
				data[64 * 8 + at + channel] = [origins[index].x, origins[index].y, layers[index], opacity][channel]
			if slot == 63 or index == 69:
				expected.append(buffer)
				expected.append(data)
		var actual := NativeVisualRaster.figure_buffers(entries, rectangles, origins, layers, origin, scale_value, 64)
		assert(actual == expected, "Native instance streams must preserve exact transforms, interpolation, masks and opacity across group boundaries")
		for entry in entries:
			assert(entry.figure.has_previous_position and entry.figure.previous_position == entry.figure.position)


func _check_alpha_mask() -> void:
	var image := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for index in 256:
		image.set_pixel(index, 0, Color8(255 - index, 42, 170, index))
	var mask := NativeVisualRaster.alpha_mask(image)
	assert(mask.get_format() == Image.FORMAT_R8 and mask.get_data().size() == 256)
	for index in 256:
		assert(mask.get_data()[index] == index, "Single-channel GPU masks must preserve every alpha level")
