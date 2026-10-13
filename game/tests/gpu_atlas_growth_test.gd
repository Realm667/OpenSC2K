extends SceneTree

@warning_ignore_start("integer_division")


func _initialize() -> void:
	var city := CityState.from_document(Sc2File.load_path("res://tests/fixtures/cities/generated-128.SC2"))
	var sprites := FixtureGraphics.pack().large_sprites
	var center := (CityIsometricRenderer.output_size_for_view(2, city.map_size) / 2) / 256
	# Native slot growth is a Rust unit test. This batch checks normalized UVs.
	var context := CityGpuBuildContext.new()
	context.atlas_edge = 64
	var request := CityGpuRegionBatch.Request.new()
	request.city = city
	request.prepared = true
	request.visibility = {}
	request.palette = Sc2Palette.index_encoding()
	request.sprites = sprites
	request.keys = [center, center + Vector2i.ONE, center + Vector2i(2, 0)]
	request.edge = 256
	request.view = 2
	request.mode = CityViewMode.Mode.CITY
	request.pipes = true
	request.subways = true
	request.generation = 1
	var batch := CityGpuRegionBatch.build(request, context, -1)
	assert(batch.ok and context.atlas_edge > 64)
	for region: CityGpuRegionResult in batch.regions:
		assert(region.atlas_edge == context.atlas_edge)
		var uvs: PackedVector2Array = region.gpu_arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector2Array = region.gpu_arrays[Mesh.ARRAY_VERTEX]

		for index in region.draw_count():
			var at := index * CityGpuRegionResult.RECORD_SIZE
			var position := Vector2i(region.draw_records[at], region.draw_records[at + 1])
			var image := region.draw_images[region.draw_records[at + 4]]
			var uv := (uvs[index * 4] + uvs[index * 4 + 2]) * 0.5
			assert(uv.x >= 0 and uv.y >= 0 and uv.x <= 1 and uv.y <= 1)
			var point := (vertices[index * 4] + vertices[index * 4 + 2]) * 0.5 + Vector2(region.bounds.position)
			assert(
				batch.atlas_image.get_pixelv(Vector2i(uv * context.atlas_edge)) == image.get_pixelv(Vector2i(point) - position),
				"Batch UV sampled the wrong pixel after atlas growth",
			)
	print("PASS: atlas growth preserves normalized UVs across a region batch")
	_check_pages(city, sprites, center)
	quit()


func _check_pages(city: CityState, sprites: Sc2SpriteArchive, center: Vector2i) -> void:
	var plain := CityGpuBuildContext.new()
	var palette := Sc2Palette.index_encoding()
	var paged := CityGpuBuildContext.new()
	paged.paged = true
	var image: Image
	for key in [center, center + Vector2i.ONE, center]:
		var bounds := Rect2i(key * 256, Vector2i(256, 256))
		var expected := plain.render(city, palette, sprites, bounds, 2, CityViewMode.Mode.CITY, true, true, 0, -1, true, true)
		var actual := paged.render(city, palette, sprites, bounds, 2, CityViewMode.Mode.CITY, true, true, 0, -1, true, true)
		assert(expected.ok and actual.ok)
		var update := actual.page_update
		if not update.is_empty():
			if update.full:
				image = Image.create(update.edge, update.edge, false, Image.FORMAT_RGBA8)
			var span := ceili(float(update.edge) / 1024)
			for index in update.indices.size():
				var layer: int = update.indices[index]
				image.blit_rect(update.art[index], Rect2i(0, 0, 1024, 1024), Vector2i(layer % span, layer / span) * 1024)
		assert(image.get_data() == plain.atlas.get_data(), "Paged atlas changed decoded pixels")
	var unchanged := paged.render(city, palette, sprites, Rect2i(center * 256, Vector2i(256, 256)), 2, CityViewMode.Mode.CITY, true, true, 0, -1, true, true)
	assert(unchanged.page_update.is_empty(), "Unchanged region reuploaded atlas pages")
	print("PASS: paged atlas matches full atlas and suppresses unchanged uploads")
