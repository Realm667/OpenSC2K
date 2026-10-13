extends SceneTree
## Start from real canonical RS bundles with no preferences or original data.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_root := AppPaths.root()
	var previous_portable := AppPaths.is_portable()
	var previous_error := AppPaths.error()
	var overrides := {}
	for key in ["OPENSC2K_GRAPHICS_PACK", "OPENSC2K_DATA_PACK", "OPENSC2K_ASSET_SOURCE"]:
		overrides[key] = OS.get_environment(key)
		OS.set_environment(key, "")
	var executable_folder := ProjectSettings.globalize_path("user://fresh-rs-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var data := executable_folder.path_join("data")
	assert(DirAccess.make_dir_recursive_absolute(data) == OK)
	for pair in [["standalone-graphics/graphics", "graphic"], ["standalone-audio/sound", "sounds"], ["standalone-audio/music", "music"]]:
		var source := ProjectSettings.globalize_path("res://../packs/" + pair[0])
		var copied := OriginalGameInstaller._copy_tree(source, data.path_join(pair[1] + "/reticulating-splines"))
		assert(copied.ok, copied.error)
	AppPaths.use_executable_folder(executable_folder, true)
	assert(AppPaths.is_portable() and AppPaths.root() == data)
	assert(not FileAccess.file_exists(AppSettingsStore.default_path()))
	assert(OriginalImportPrompt.first_start(AppSettingsStore.default_path(), data))
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	# Avoid unrelated main-menu simulation; do not use configure(), which writes
	# a preferences file and injects original-asset fixture paths before startup.
	main.set_script(preload("res://tests/support/app_fixture.gd").NoMenuApp)
	root.add_child(main)
	await process_frame
	await process_frame
	assert(main.asset_state.assets_ready)
	assert(not main.asset_state.data_pack.is_loaded())
	assert(main.preferences.data_pack_folder.is_empty())
	assert(main.asset_state.asset_source.import_revision == ImportedPackRevision.NOT_IMPORTED)
	assert(main.audio_controller.sound_pack.import_revision == ImportedPackRevision.NOT_IMPORTED)
	assert(main.audio_controller.music_pack.import_revision == ImportedPackRevision.NOT_IMPORTED)
	assert(main.assets.stale_pack_kinds().is_empty())
	assert(not main.pack_update_dialog.visible, "Fresh RS startup must not open Update imported packs")
	# Exported interactive startup calls this same entry after initialization.
	main.assets.show_reference_import_dialog()
	assert(main.assets.original_import_prompt.visible and not main.pack_update_dialog.visible)
	main.assets.original_import_prompt.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	assert(not main.assets.original_import_prompt.visible)
	assert(not main.reference_import_dialog.visible and not main.pack_update_dialog.visible)
	assert(main.preferences.data_pack_folder.is_empty() and main.asset_state.assets_ready)
	assert(not OriginalImportPrompt.first_start(main.preferences.settings_path, data))
	# An explicit source that has gone missing must still offer repair.
	main.preferences.data_pack_folder = data.path_join("pack/sc2000/missing/data/pack.json")
	assert(main.assets.stale_pack_kinds() == PackedStringArray(["data"]))
	main.assets.prompt_for_stale_packs()
	assert(main.pack_update_dialog.visible)
	main.pack_update_dialog.get_cancel_button().pressed.emit()
	await process_frame
	main.preferences.data_pack_folder = ""
	OS.set_environment("OPENSC2K_DATA_PACK", data.path_join("missing-override"))
	assert(main.assets.stale_pack_kinds() == PackedStringArray(["data"]))
	OS.set_environment("OPENSC2K_DATA_PACK", "")
	# A damaged legacy automatic import also remains a repair case.
	assert(DirAccess.make_dir_recursive_absolute(DataPack.default_folder()) == OK)
	var manifest := FileAccess.open(DataPack.default_folder().path_join("pack.json"), FileAccess.WRITE)
	manifest.store_string("{}")
	manifest.close()
	assert(main.assets.stale_pack_kinds() == PackedStringArray(["data"]))
	main.queue_free()
	await process_frame
	await process_frame
	for key in overrides:
		OS.set_environment(key, overrides[key])
	AppPaths._root = previous_root
	AppPaths._portable = previous_portable
	AppPaths._error = previous_error
	print("PASS: fresh portable RS startup has one import question; No leaves no update dialog; explicit/override/legacy missing imports still warn")
	quit()
