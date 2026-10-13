extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _write(path: String, contents: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)


func _run() -> void:
	var base := "user://pack-library-%d" % Time.get_ticks_usec()
	var sound_manifest := {"format": "opensc2k-sound", "version": 1, "name": "Readable sound", "files": {"500": "sound.wav"}}
	_write(base.path_join("sounds/good/pack.json"), JSON.stringify(sound_manifest))
	_write(base.path_join("sounds/good/sound.wav"), "fixture")
	_write(base.path_join("sounds/broken/pack.json"), "invalid")
	_write(base.path_join("sounds/missing-file/pack.json"), JSON.stringify(sound_manifest))
	_write(base.path_join("sounds/wrong/pack.json"), JSON.stringify({"format": "opensc2k-music", "version": 1, "name": "Wrong category"}))
	_write(base.path_join("packs/legacy/sound/pack.json"), JSON.stringify(sound_manifest))
	_write(base.path_join("packs/legacy/sound/sound.wav"), "fixture")
	_write(base.path_join("pack/sc2000/windows/sound/pack.json"), JSON.stringify(sound_manifest))
	_write(base.path_join("pack/sc2000/windows/sound/sound.wav"), "fixture")
	_write(base.path_join("godot_wry/sound/pack.json"), JSON.stringify(sound_manifest))
	var chosen := base.path_join("external/sound/pack.json")
	_write(chosen, JSON.stringify(sound_manifest))
	_write(chosen.get_base_dir().path_join("sound.wav"), "fixture")
	var rows := PackLibrary.scan("sound", chosen, base)
	assert(rows.size() == 7, "Structured, legacy, original and selected external packages are separate sources")
	var unavailable := 0
	for row in rows:
		assert(not "godot_wry" in row.path)
		if not str(row.error).is_empty():
			unavailable += 1
	assert(unavailable == 3)
	assert(PackLibrary.scan("godot_wry", "", base).is_empty())
	assert(PackLibrary.scan("sound", base.path_join("sounds/good"), base).size() == 6, "Selected folder and manifest must deduplicate")
	assert(not str(PackLibrary.inspect("sound", base.path_join("gone")).error).is_empty())
	_write(base.path_join("brightmaps/test/catalog.json"), '{"sprites":{}}')
	assert(PackLibrary.scan("brightmaps", "", base).size() == 1)
	assert(PackLibrary.inspect("brightmaps", base.path_join("brightmaps/test")).error == "")
	_write(base.path_join("cities/collection/My city.sc2"), "untouched city")
	assert(PackLibrary.scan("cities", "", base).size() == 2)
	_write(base.path_join("music/reticulating-splines/pack.json"), '{"format":"opensc2k-music"}')
	_write(base.path_join("music/reticulating-splines/song.mp3"), "fixture")
	_write(base.path_join("music/personal/pack.json"), '{"notes":"personal metadata"}')
	_write(base.path_join("music/personal/song.mp3"), "fixture")
	var custom := CustomMusicLibrary.new(base.path_join("music"))
	custom.refresh()
	assert(custom.tracks == ["personal/song.mp3"], "Package tracks must not duplicate the Music Box's pack source; custom metadata must not hide personal songs")
	assert(not custom.resolve("reticulating-splines/song.mp3").is_empty(), "Previously saved custom IDs remain resolvable")
	_write(base.path_join("mods/example/info.json"), '{"id":"example","name":"Example","version":"1.0.0","main":"main.js"}')
	_write(base.path_join("mods/example/main.js"), "// no execution during discovery")
	assert(ModCatalog.scan(base.path_join("mods/example"), "1.0.0").size() == 1)
	var empty_root := base.path_join("new-profile")
	DirAccess.make_dir_recursive_absolute(empty_root)
	var settings_path := empty_root.path_join("settings.cfg")
	assert(OriginalImportPrompt.first_start(settings_path, empty_root))
	assert(OriginalImportPrompt.remember(settings_path) == OK)
	assert(not OriginalImportPrompt.first_start(settings_path, empty_root))
	assert(not OriginalImportPrompt.first_start(base.path_join("missing.cfg"), base), "An existing import is not a new installation")
	var options := AppSettingsStore.SaveOptions.new()
	options.cities_folder = base.path_join("cities/collection")
	options.mods_folder = base.path_join("mods/example")
	assert(AppSettingsStore.save_values(0.5, 0.5, false, settings_path, options) == OK)
	var saved := AppSettingsStore.load_values(settings_path)
	assert(saved.cities_folder == options.cities_folder and saved.mods_folder == options.mods_folder)
	var config := ConfigFile.new()
	assert(config.load(settings_path) == OK and config.get_value("data", "import_prompt_seen", false))
	var dialog := (load("res://src/ui/settings/app_settings_dialog.tscn") as PackedScene).instantiate() as AppSettingsDialog
	root.add_child(dialog)
	await process_frame
	assert(dialog.pack_selectors.size() == 8)
	dialog.sound_pack_edit.text = chosen
	dialog.rescan_packages()
	var selector: PackSourceSelector = dialog.pack_selectors.sound
	assert(str(selector.get_item_metadata(selector.selected)) == PackLibrary.normalized(chosen, "sound"))
	selector.rescan(base)
	var duplicate_labels := {}
	for index in range(1, selector.item_count):
		var label := selector.get_item_text(index)
		assert(not duplicate_labels.has(label), "Repeated package names need distinct source paths")
		duplicate_labels[label] = true
	var notices := [0]
	dialog.settings_changed.connect(func() -> void: notices[0] += 1)
	dialog.rescan_packages()
	assert(notices[0] == 0 and dialog.sound_pack_edit.text == chosen, "Rescan must not activate or change a saved source")
	selector.item_selected.emit(0)
	assert(dialog.sound_pack_edit.text.is_empty() and notices[0] == 1)
	var prompt := OriginalImportPrompt.new()
	root.add_child(prompt)
	var modes := []
	prompt.import_chosen.connect(func(activate: bool) -> void: modes.append(activate))
	prompt.canceled.emit()
	assert(modes.is_empty())
	prompt.custom_action.emit(&"import")
	prompt.confirmed.emit()
	assert(modes == [false, true])
	dialog.sound_pack_edit.text = chosen
	for locale in AppLocalization.codes():
		AppLocalization.select(locale)
		if locale != "en":
			assert(TranslationServer.translate("Would you like to import SimCity 2000 data?") != "Would you like to import SimCity 2000 data?")
		dialog.rescan_packages()
		assert(selector.item_count >= 2)
	assert(FileAccess.get_file_as_string(base.path_join("cities/collection/My city.sc2")) == "untouched city")
	prompt.free()
	dialog.free()
	print("PASS: pack discovery, invalid sources, category independence, preferences, import choices and seven UI languages")
	quit()
