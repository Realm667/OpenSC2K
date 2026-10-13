extends "res://tests/support/scene_test_case.gd"

@warning_ignore_start("integer_division")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var art := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.3, 0.6, 0.2, 0.7))
	art.fill_rect(Rect2i(1024, 0, 1024, 1024), Color(0.8, 0.2, 0.1, 0.9))
	art.fill_rect(Rect2i(0, 1024, 1024, 1024), Color(0.2, 0.3, 0.8, 0.4))
	art.fill_rect(Rect2i(1024, 1024, 1024, 1024), Color(0.8, 0.8, 0.2, 1.0))
	var light := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	light.fill(Color(0.7, 0.4, 0.1, 0.3))
	var seasons := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	seasons.fill(Color(0.0, 0.0, 1.0, 1.0))
	var data := {"edge": 2048, "full": true, "indices": PackedInt32Array([0, 1, 2, 3]), "art": [], "emission": [], "seasons": []}
	for index in 4:
		var rect := Rect2i(Vector2i(index % 2, index / 2) * 1024, Vector2i(1024, 1024))
		data.art.append(art.get_region(rect))
		data.emission.append(light.get_region(rect))
		data.seasons.append(seasons.get_region(rect))
	var pages := CityGpuTexturePages.new()
	pages.publish(data)
	for mirrored in [false, true]:
		var expected: Image = await draw_image(art, light, seasons, null, mirrored)
		var actual: Image = await draw_image(art, light, seasons, pages, mirrored)
		assert(expected.get_data() == actual.get_data(), "Texture page boundaries or auxiliary shading differ from the full atlas")
	print("PASS: GPU pages match full atlas exactly across all four page edges, transparency, mirroring and emission")
	quit()

func draw_image(art: Image, light: Image, seasons: Image, pages: CityGpuTexturePages, mirrored: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var instance := MeshInstance2D.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2(256, 0), Vector2(256, 256), Vector2(0, 256)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0.45, 0.45), Vector2(0.55, 0.45), Vector2(0.55, 0.55), Vector2(0.45, 0.55)])
	if mirrored:
		for index in 4:
			arrays[Mesh.ARRAY_TEX_UV][index].x = 1.0 - arrays[Mesh.ARRAY_TEX_UV][index].x
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(2.0 / 255, 0, 0, 1), Color(2.0 / 255, 0, 0, 1), Color(2.0 / 255, 0, 0, 1), Color(2.0 / 255, 0, 0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	instance.mesh = mesh
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CityMapConstants.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_night", 0.6)
	material.set_shader_parameter("environment_has_emission", true)
	material.set_shader_parameter("environment_has_seasons", true)
	if pages == null:
		instance.texture = ImageTexture.create_from_image(art)
		material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(light))
		material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(seasons))
	else:
		pages.apply(material)
	instance.material = material
	viewport.add_child(instance)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image

