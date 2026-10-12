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
	var window_menu := app.city_menu_bar.windows_menu.get_popup()
	for scenario_available in [false, true, false]:
		app.city_menu_bar.set_scenario_available(scenario_available)
		assert(window_menu.get_item_index(0x8400) < 0)
		assert(window_menu.get_item_index(ApplicationQualityOfLife.MENU_MUSIC_BOX) >= 0)
	window_menu.id_pressed.emit(ApplicationQualityOfLife.MENU_MUSIC_BOX)
	assert(qol.music_box.visible, "The real Windows menu must open the music box after loading a city")
	qol.music_box.hide()
	app.reports.on_windows_menu(4)
	await process_frame
	await process_frame
	app.city_dialogs.graph_window.position = Vector2i(80, 90)
	qol.memory._process(1.0)
	app.city_dialogs.graph_window.hide()
	app.reports.on_windows_menu(4)
	await process_frame
	await process_frame
	assert(app.city_dialogs.graph_window.position == Vector2i(80, 90))
	app.city_dialogs.graph_window.hide()
	var reread := ConfigFile.new()
	assert(reread.load(qol.memory.storage_path) == OK)
	assert(not reread.has_section("workspaces"))
	var bounds := Rect2i(0, 0, 800, 600)
	assert(WindowLayoutMemory.fit_position(Vector2i(2000, -300), Vector2i(300, 200), bounds) == Vector2i(500, 30))
	assert(WindowLayoutMemory.fit_position(Vector2i(400, 200), Vector2i(1000, 900), bounds) == Vector2i(0, 30))
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
	await _custom_music(box, audio, activity)
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
	print("PASS: tool pipette, unchanged city, local window recovery and simulation-independent music playlists")
	quit()


func _custom_music(box: MusicBoxDialog, audio: CityAudioController, activity: Array[bool]) -> void:
	var folder := "user://custom-music-%d" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute(folder.path_join("Evening/Nested")) == OK)
	assert(DirAccess.make_dir_recursive_absolute(folder.path_join("Other")) == OK)
	var fixture := "res://tests/fixtures/audio/silence.mp3"
	var first := "Evening/Grüße aus der Stadt.MP3"
	var second := "Evening/Nested/Second.mp3"
	for id in [first, second, "Other/Second.mp3", "Root.mp3", "ignored.ogg"]:
		assert(DirAccess.copy_absolute(fixture, folder.path_join(id)) == OK)
	box.custom_music = CustomMusicLibrary.new(folder)
	box.rescan()
	assert(box.custom_music.tracks.size() == 4)
	assert(box.library.item_count == 23)
	assert(box.custom_music.resolve("../outside.mp3").is_empty())
	assert(box.custom_music.resolve("C:/outside.mp3").is_empty())
	assert(box.custom_music.resolve("Evening\\bad.mp3").is_empty())
	assert(MusicBoxDialog._track_ids([10002, first, first, second, "../bad.mp3", "wrong.ogg"]) == [10002, first, second])
	# A folder is a playable collection, with stable relative paths in metadata.
	for index in box.collection.item_count:
		if box.collection.get_item_metadata(index) == "folder:Evening":
			box.collection.select(index)
	box._refresh_library()
	assert(box.library.item_count == 1 and box.library.get_item_metadata(0) == first)
	box.library.select(0)
	box._favorite_selected()
	assert(first in box.favorites)
	box.playlist.assign([10002, first, second])
	box.playlist_name.text = "Mixed MP3"
	box._save_playlist()
	box.playlist.clear()
	box.playlist_names.select(box.playlist_names.item_count - 1)
	box._load_playlist()
	assert(box.playlist == [10002, first, second])
	var saved := MusicBoxDialog.new(box.app)
	assert(saved.playlist == box.playlist and first in saved.favorites)
	saved.free()
	var original_track := audio.current_track_id
	var original_director := audio.music_director.general_track_index
	box.play_track(first)
	await create_timer(0.45).timeout
	assert(box.active and box.playback.track_key() == first)
	assert(box.playback.recording_player.stream is AudioStreamMP3)
	assert(box.playback.recording_player.stream.get_length() > 1.0)
	box._toggle_pause()
	assert(box.playback.music_paused and box.playback.recording_player.stream_paused)
	box._toggle_pause()
	box.playback.application_has_focus = false
	box.playback.set_background_audio(false)
	assert(box.playback.recording_player.stream_paused)
	box.playback.application_has_focus = true
	box.playback.set_background_audio(true)
	box.volume.value = 40.0
	assert(is_equal_approx(box.playback.recording_player.volume_linear, audio.music_volume * 0.4))
	box.volume.value = 100.0
	box.rescan()
	assert(box.playback.track_key() == first, "Rescan must not restart the playing song")
	box.playback.recording_player.finished.emit()
	await create_timer(0.35).timeout
	assert(box.playback.track_key() == second)
	box.step(1)
	await create_timer(0.3).timeout
	assert(box.playback.track_key() == 10002, "Mixed playlists wrap to original tracks")
	assert(DirAccess.remove_absolute(folder.path_join(first)) == OK)
	box.step(1)
	await create_timer(0.3).timeout
	assert(box.playback.track_key() == second, "Removed files are skipped without losing saved entries")
	box.play_track(first)
	await create_timer(0.3).timeout
	assert(not box.active and not box.status.text.is_empty())
	# Cancel during decoding: a late result must never restart custom playback.
	assert(box.playback.play_custom(second, box.custom_music.resolve(second)))
	box.playback._process(0.0)
	box.automatic()
	await create_timer(0.3).timeout
	assert(box.playback.custom_track.is_empty() and box.playback.recording_player.stream == null)
	assert(audio.current_track_id == original_track and audio.music_director.general_track_index == original_director)
	assert(activity.is_empty(), "Custom MP3 playback must not signal the simulation")
	box.rescan()
	assert(box.custom_music.tracks.size() == 3 and first in box.playlist)
	box.playlist.clear()
	box.collection.select(2)
	box._refresh_library()
	box.play_track(second)
	await create_timer(0.3).timeout
	for id in box.custom_music.tracks:
		assert(DirAccess.remove_absolute(folder.path_join(id)) == OK)
	box.rescan()
	assert(box.library.item_count == 0)
	box.playback.recording_player.finished.emit()
	await create_timer(0.3).timeout
	assert(not box.active and is_equal_approx(audio.music_output_gain, 1.0))
	print("PASS: MP3 folders, decoding, mixed playlists, persistence, pause, next, deletion and cancellation")


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
