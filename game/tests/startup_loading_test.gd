extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_DATA_PACK", ProjectSettings.globalize_path("res://../ext/data"))
	var settings := ConfigFile.new()
	settings.set_value("general", "check_for_updates", false)
	assert(settings.save(AppPaths.path("settings.cfg")) == OK)
	var boot := (load("res://src/ui/startup/startup_loading.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	assert(boot.overlay.visible)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	for viewport_size in [Vector2i(640, 480), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var view := root.get_visible_rect()
		var logo_rect: Rect2 = boot.logo.get_global_rect()
		assert(logo_rect.size.x <= view.size.x * 0.3 + 1.0, "Startup logo must not exceed 30% of the viewport width")
		assert(logo_rect.get_center().distance_to(view.get_center()) < 1.0, "Startup logo stays centered when resizing")
		assert(is_equal_approx(logo_rect.size.aspect(), boot.logo.texture.get_size().aspect()), "Startup logo keeps its aspect ratio")
		assert(boot.overlay.bar.is_visible_in_tree() and boot.overlay.bar.size.y > 0.0)
		assert(boot.overlay.bar.size.x > logo_rect.size.x * 0.5, "The loading bar must not collapse to the text's minimum width")
		assert(absf(boot.overlay.bar.get_global_rect().get_center().x - logo_rect.get_center().x) < 1.0,
			"The loading bar stays centered below the logo")
		assert(view.encloses(boot.overlay.bar.get_global_rect()), "The existing loading bar must remain inside the viewport")
	var started := Time.get_ticks_msec()
	while is_instance_valid(boot):
		assert(Time.get_ticks_msec() - started < 60000, "Startup failed to hand off to the application")
		await process_frame
	var main := current_scene as CityApplication
	assert(main != null and main.startup_progress == null)
	assert(main.asset_state.runtime_initialized and main.asset_state.assets_ready)
	assert(main.main_menu.visible)
	main.queue_free()
	await process_frame
	print("PASS: startup progress, background asset loading and application handoff")
	quit()
