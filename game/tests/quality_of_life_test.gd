extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_picker()
	var settings_path := "user://qol-%d.cfg" % OS.get_process_id()
	var settings := ConfigFile.new()
	for kind in ["music", "sound"]:
		settings.set_value("audio", kind + "_pack_folder", ProjectSettings.globalize_path("res://../ext/" + kind))
	settings.set_value("audio", "background_audio", true)
	settings.set_value("graphics", "source", "folder")
	settings.set_value("graphics", "folder", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_DATA_PACK", ProjectSettings.globalize_path("res://../ext/data"))
	assert(settings.save(settings_path) == OK)
	var app := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	app.preferences.settings_path = settings_path
	app.asset_state.reference_root = ProjectSettings.globalize_path("res://../references/SIMCITY2000")
	root.add_child(app)
	await process_frame
	await process_frame
	var qol: ApplicationQualityOfLife
	for child in app.get_children():
		if child is ApplicationQualityOfLife:
			qol = child
	assert(qol != null)
	app.city_files._load_city_unchecked(GeneratedCityFixture.path(128))
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.interface.hide_main_menu()
	qol.layouts.popup_centered(Vector2i(500, 300))
	await process_frame
	await process_frame
	qol.layouts.position = Vector2i(70, 85)
	qol.memory._process(1.0)
	qol.layouts.hide()
	qol.layouts.popup_centered()
	await process_frame
	assert(qol.layouts.position == Vector2i(70, 85), "Window did not retain its position")
	qol.layouts.hide()
	var bounds := Rect2i(0, 0, 800, 600)
	assert(WindowLayoutMemory.fit_position(Vector2i(2000, -300), Vector2i(300, 200), bounds) == Vector2i(500, 30))
	assert(WindowLayoutMemory.fit_position(Vector2i(400, 200), Vector2i(1000, 900), bounds) == Vector2i(0, 30))
	qol.workspace_choice.select(0)
	qol._save_layout()
	var reread := ConfigFile.new()
	assert(reread.load(qol.memory.storage_path) == OK and reread.has_section_key("workspaces", "Building"))
	app.reports.on_windows_menu(4)
	await process_frame
	await process_frame
	app.city_dialogs.graph_window.position = Vector2i(80, 90)
	qol._save_layout()
	app.city_dialogs.graph_window.hide()
	qol._restore_layout()
	await process_frame
	await process_frame
	assert(app.city_dialogs.graph_window.visible and app.city_dialogs.graph_window.position == Vector2i(80, 90))
	app.city_dialogs.graph_window.hide()
	var audio := app.audio_controller
	var old_track := audio.current_track_id
	var old_director := audio.music_director.general_track_index
	var activity: Array[bool] = []
	audio.music_activity_changed.connect(func(value: bool) -> void: activity.append(value))
	var box := qol.music_box
	box.playlist.assign([10002, 10003])
	box.play_track(10002)
	await create_timer(0.5).timeout
	assert(box.active and box.playback.current_track_id == 10002)
	assert(audio.current_track_id == old_track and audio.music_director.general_track_index == old_director)
	assert(activity.is_empty(), "User music must not change simulation music activity")
	assert(is_zero_approx(audio.music_output_gain))
	box.playback._on_music_track_finished(10002)
	await create_timer(0.5).timeout
	assert(box.playback.current_track_id == 10003)
	var media_key := InputEventKey.new()
	media_key.keycode = KEY_MEDIAPLAY
	media_key.pressed = true
	assert(app.controls.handle_music_key(media_key))
	assert(box.playback.music_paused and not audio.music_paused)
	box.automatic()
	await create_timer(0.3).timeout
	assert(is_equal_approx(audio.music_output_gain, 1.0) and activity.is_empty())
	var original_volume := audio.music_volume
	box.volume.value = 40.0
	assert(is_equal_approx(audio.music_output_gain, 0.4) and audio.music_volume == original_volume)
	box.volume.value = 100.0
	box.playlist.clear()
	box.play_track(10005)
	await create_timer(0.3).timeout
	box.playback._on_music_track_finished(10005)
	await create_timer(0.3).timeout
	assert(box.playback.current_track_id == 10006, "The library advances after a track finishes without a playlist")
	box.automatic()
	box.playlist.assign([10002, 10003])
	box.favorites.assign([10003])
	box.playlist_name.text = "Evening"
	box._save_playlist()
	box.playlist.clear()
	box._load_playlist()
	assert(box.playlist == [10002, 10003])
	assert(reread.load(box.storage_path) == OK and reread.get_value("player", "favorites") == [10003])
	assert(MusicBoxDialog._track_ids([1, 10002, 10002, "10003", 10018, 10019]) == [10002, 10018])
	for locale in ["de", "es", "fr", "it", "ko", "pt_BR"]:
		TranslationServer.add_translation(load("res://assets/localization/" + locale + ".po") as Translation)
		TranslationServer.set_locale(locale)
		box.open()
		await process_frame
		await process_frame
		assert(box.size.x <= root.get_visible_rect().size.x, "Music controls do not fit: " + locale)
		assert(box.size.y <= root.get_visible_rect().size.y, "Music controls are too tall: " + locale)
	box.hide()
	TranslationServer.add_translation(load("res://assets/localization/de.po") as Translation)
	TranslationServer.set_locale("de")
	assert(TranslationServer.translate("Pick building tool") == "Bauwerkzeug aufnehmen")
	assert(TranslationServer.translate("Music box") == "Musikbox")
	app.queue_free()
	await process_frame
	print("PASS: tool pipette, unchanged city, local window recovery, workspaces and simulation-independent music playlists")
	quit()


func _picker() -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(16))
	var p := Vector2i(4, 5)
	var cases := [[0x1d, 0, Vector2i(6, 0)], [0x43, 0, Vector2i(6, 0)],
		[0x2c, 0, Vector2i(7, 0)], [0x5c, 0, Vector2i(3, 0)], [0x5d, 0, Vector2i(6, 3)],
		[0x6a, 0, Vector2i(6, 1)], [0x3f, 0, Vector2i(6, 2)], [0x6c, 0, Vector2i(7, 4)],
		[0x70, 2, Vector2i(9, 1)], [0x88, 5, Vector2i(11, 0)], [0, 9, Vector2i(8, 0)],
		[0, 8, Vector2i(8, 1)], [0, 7, Vector2i(-1, -1)], [0, 0, Vector2i(-1, -1)]]
	for entry in cases:
		city.set_building_id(p.x, p.y, entry[0])
		city.set_zone_id(p.x, p.y, entry[1])
		var before := city.document.serialize().data
		assert(ApplicationToolPicker.tool_at(city, p) == entry[2], "Wrong tool for %s" % str(entry))
		assert(city.document.serialize().data == before)
	for entry in [[0x01, Vector2i(7, 1)], [0x10, Vector2i(4, 0)], [0x1f, Vector2i(4, 0)], [0x23, Vector2i(7, 3)]]:
		city.set_underground_id(p.x, p.y, entry[0])
		assert(ApplicationToolPicker.tool_at(city, p, true) == entry[1])
	assert(ApplicationToolPicker.tool_at(city, Vector2i(-1, 0)) == Vector2i(-1, -1))
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	assert(ControlBindings.defaults().action_for(mouse, [ControlActions.KIND_CLICK]) == "map_pick_tool")
	var old := ConfigFile.new()
	old.set_value("controls", "binding/map_center_on_tile", PackedStringArray(["mouse:Middle"]))
	old.set_value("controls", "bindings_version", 2)
	assert(AppSettingsStore.load_bindings(old).action_for(mouse, [ControlActions.KIND_CLICK]) == "map_pick_tool")
