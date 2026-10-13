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
