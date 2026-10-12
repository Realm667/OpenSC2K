extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fog := CityVisualFog.new(null)
	fog.prepare()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := ColorRect.new()
	layer.size = Vector2(256, 256)
	var material := ShaderMaterial.new()
	material.shader = CityVisualFog.SHADER
	material.set_shader_parameter("fog_field", fog.field)
	material.set_shader_parameter("fog_canvas_to_grid", CityVisualClouds.shader_basis(Transform2D(
		Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-8, -8))))
	material.set_shader_parameter("fog_density", 0.65)
	layer.material = material
	viewport.add_child(layer)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	var minimum := 1.0
	var maximum := 0.0
	for y in range(24, 240, 4):
		for x in range(24, 240, 4):
			var alpha := original.get_pixel(x, y).a
			minimum = minf(minimum, alpha)
			maximum = maxf(maximum, alpha)
	assert(maximum - minimum > 0.15 and maximum < 0.7, "Fog must have distinct translucent sheets and gaps")
	assert(original.get_pixel(0, 0).a == 0.0, "Fog escaped the map edge")
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Fog moved without advancing its clock")
	material.set_shader_parameter("fog_drift", Vector2.ONE * CityVisualFog.WRAP)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Fog drift wrap introduced a seam")
	var pan := Vector2(12, 8)
	layer.position = pan
	viewport.canvas_transform = Transform2D(0.0, -pan)
	material.set_shader_parameter("fog_canvas_to_grid", CityVisualClouds.shader_basis(Transform2D(
		Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-8, -8) - pan * 0.5)))
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Fog slipped relative to the city during a camera pan")
	material.set_shader_parameter("fog_drift", Vector2(6, 3))
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() != original.get_data(), "Fog sheets did not drift")
	material.set_shader_parameter("fog_density", 0.0)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().is_invisible(), "Zero strength left visible fog")
	viewport.queue_free()
	await process_frame
	print("PASS: visible translucent fog wisps, map bounds, pause, seamless drift and zero strength")
	await _check_reduced_surface(fog.field, false)
	await _check_reduced_surface(fog.field, true)
	quit()


func _check_reduced_surface(noise: Texture2D, hdr: bool) -> void:
	var reduced := SubViewport.new()
	reduced.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reduced.size = Vector2i(128,128)
	reduced.use_hdr_2d = hdr
	reduced.transparent_bg = true
	reduced.world_2d = World2D.new()
	root.add_child(reduced)
	var output := SubViewport.new()
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	output.size = Vector2i(256,256)
	output.use_hdr_2d = hdr
	output.transparent_bg = true
	output.world_2d = World2D.new()
	root.add_child(output)
	var small := ColorRect.new()
	small.size = Vector2(reduced.size)
	var original := ColorRect.new()
	original.size = Vector2(output.size)
	for pair in [[small,0.25],[original,0.125]]:
		var shader := ShaderMaterial.new()
		shader.shader = CityVisualFog.SHADER
		shader.set_shader_parameter("fog_field",noise)
		shader.set_shader_parameter("fog_canvas_to_grid",CityVisualClouds.shader_basis(Transform2D(Vector2(pair[1],0),Vector2(0,pair[1]),Vector2(-8,-8))))
		shader.set_shader_parameter("fog_density",0.65)
		pair[0].material = shader
	reduced.add_child(small)
	output.add_child(original)
	var composite := ColorRect.new()
	composite.size = original.size
	var material := ShaderMaterial.new()
	material.shader = load("res://src/view/environment/fog_composite.gdshader")
	material.set_shader_parameter("fog_surface",reduced.get_texture())
	composite.material = material
	composite.hide()
	output.add_child(composite)
	await RenderingServer.frame_post_draw
	var expected := output.get_texture().get_image()
	assert(not expected.is_invisible(),"Fog reference did not render")
	original.hide()
	composite.show()
	await RenderingServer.frame_post_draw
	var actual := output.get_texture().get_image()
	var error := 0.0
	var largest := 0.0
	for y in 256:
		for x in 256:
			var a := actual.get_pixel(x,y)
			var b := expected.get_pixel(x,y)
			var difference := maxf(absf(a.r-b.r),absf(a.a-b.a))
			error += difference
			largest = maxf(largest,difference)
	assert(error / 65536.0 < 0.012 and largest < 0.09,"Reduced fog differs: mean %s max %s" % [error/65536.0,largest])
	reduced.queue_free()
	output.queue_free()
	await process_frame
	print("PASS: reduced fog color/alpha and world alignment (mean %s max %s)" % [error/65536.0,largest])
