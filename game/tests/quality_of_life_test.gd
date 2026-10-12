extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_picker()
	_id3_titles()
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
	box.track_tabs.current_tab = 1
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
	box.track_tabs.current_tab = 0
	box.playlist.clear()
	box.play_track(10005)
	await create_timer(0.3).timeout
	box.playback._on_music_track_finished(10005)
	await create_timer(0.3).timeout
	assert(box.playback.current_track_id == 10006, "The library advances after a track finishes without a playlist")
	box.automatic()
	box.track_tabs.current_tab = 1
	box.playlist.assign([10002, 10003])
	box.favorites.assign([10003])
	box.config.set_value("playlists", "Legacy", [10002])
	box._save()
	assert(reread.load(box.storage_path) == OK)
	assert(reread.get_value("playlists", "Legacy") == [10002], "Removing controls must preserve old saved lists")
	assert(reread.load(box.storage_path) == OK and reread.get_value("player", "favorites") == [10003])
	assert(MusicBoxDialog._track_ids([1, 10002, 10002, "10003", 10018, 10019]) == [10002, 10018])
	await _music_sources(box, audio, activity)
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


func _size_bytes(value: int, count: int, sync := false) -> PackedByteArray:
	var result := PackedByteArray()
	for i in count:
		result.append((value >> ((count - i - 1) * (7 if sync else 8))) & (127 if sync else 255))
	return result


func _title_tag(version: int, payload: PackedByteArray) -> PackedByteArray:
	var frame := ("TT2" if version == 2 else "TIT2").to_ascii_buffer()
	frame.append_array(_size_bytes(payload.size(), 3 if version == 2 else 4, version == 4))
	if version >= 3:
		frame.append_array(PackedByteArray([0, 0]))
	frame.append_array(payload)
	var header := PackedByteArray([73, 68, 51, version, 0, 0])
	header.append_array(_size_bytes(frame.size(), 4, true))
	header.append_array(frame)
	return header


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()


func _id3_titles() -> void:
	var folder := "user://id3-%d" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var utf8 := PackedByteArray([3])
	utf8.append_array("Grüße 서울 🎵".to_utf8_buffer())
	var latin := PackedByteArray([0, 67, 97, 102, 233])
	var utf16 := PackedByteArray([1, 255, 254, 71, 0, 114, 0, 252, 0, 223, 0, 101, 0])
	var big := PackedByteArray([2, 0xC1, 0x1C, 0xC6, 0xB8])
	var cases := [
		[_title_tag(4, utf8), "Grüße 서울 🎵"], [_title_tag(3, utf16), "Grüße"],
		[_title_tag(2, latin), "Café"], [_title_tag(4, big), "서울"],
		[_title_tag(4, PackedByteArray([3, 32, 32, 0])), ""],
		[_title_tag(4, PackedByteArray([3, 255, 254])), ""],
		[_title_tag(3, PackedByteArray([1, 255, 254, 0, 216])), ""],
		[PackedByteArray([73, 68, 51, 4, 0, 0, 127, 127, 127, 127]), ""],
		[_title_tag(4, utf8).slice(0, 12), ""], [PackedByteArray([1, 2, 3]), ""]]
	var legacy := PackedByteArray()
	legacy.resize(128)
	legacy[0] = 84
	legacy[1] = 65
	legacy[2] = 71
	legacy[3] = 67
	legacy[4] = 97
	legacy[5] = 102
	legacy[6] = 233
	cases.append([legacy, "Café"])
	for i in cases.size():
		var path := folder.path_join("Fallback-%d.mp3" % i)
		_write_bytes(path, cases[i][0])
		var before := FileAccess.get_sha256(path)
		assert(Mp3Title.read(path) == (cases[i][1] if not cases[i][1].is_empty() else "Fallback-%d" % i))
		assert(FileAccess.get_sha256(path) == before)
	assert(Mp3Title.read(folder.path_join("Missing.mp3")) == "Missing")
	var long_title := PackedByteArray([3])
	long_title.append_array("Long title ".repeat(100).to_utf8_buffer())
	_write_bytes(folder.path_join("Long.mp3"), _title_tag(4, long_title))
	assert(Mp3Title.read(folder.path_join("Long.mp3")).length() == 512)
	print("PASS: bounded read-only ID3 v1/v2.2/v2.3/v2.4 titles, Unicode and corrupt-tag fallbacks")


func _tagged_mp3(path: String, title: String) -> void:
	var audio := FileAccess.get_file_as_bytes("res://tests/fixtures/audio/silence.mp3")
	if audio.slice(0, 3).get_string_from_ascii() == "ID3":
		audio = audio.slice(10 + Mp3Title._number(audio, 6, 4, true))
	var payload := PackedByteArray([3])
	payload.append_array(title.to_utf8_buffer())
	var tagged := _title_tag(4, payload)
	tagged.append_array(audio)
	_write_bytes(path, tagged)


func _choose_source(box: MusicBoxDialog, source: String) -> void:
	for index in box.collection.item_count:
		if box.collection.get_item_metadata(index) == source:
			box.collection.select(index)
			box._refresh_library()
			return
	assert(false, "Missing music source: " + source)


func _music_sources(box: MusicBoxDialog, audio: CityAudioController, activity: Array[bool]) -> void:
	box.open()
	var data := box.app.asset_state.data_pack
	var original := audio.music_pack
	var original_track := audio.current_track_id
	var director := audio.music_director.general_track_index
	var folder := "user://music-source-%d" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	assert(DirAccess.copy_absolute("res://tests/fixtures/audio/silence.mp3", folder.path_join("Buildings.mp3")) == OK)
	var manifest := FileAccess.open(folder.path_join("pack.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"format": "opensc2k-music", "version": 1,
		"name": "Standalone Music", "files": {"10014": "Buildings.mp3"}}))
	manifest.close()
	var replacement := MediaPack.load_folder(folder, "music")
	assert(replacement.error.is_empty())
	box.favorites_only.button_pressed = false
	# An imported music pack alone must not expose originals without the data pack.
	box.app.asset_state.data_pack = DataPack.new()
	box.rescan()
	assert(not box.music_library.sources.has("original"))
	box.play_track(10014)
	assert(not box.active)
	# Standalone files remain available without original imports.
	audio.music_pack = replacement
	box.rescan()
	assert(box.music_library.tracks.size() == 1)
	assert(box.music_library.tracks.has("reticulating:10014"))
	assert(not box.music_library.tracks.has(10014))
	_choose_source(box, "reticulating")
	assert(box.library.item_count == 1)
	# Both sources coexist; equal slot numbers select different files.
	box.app.asset_state.data_pack = data
	box.rescan()
	assert(box.music_library.tracks.has(10014))
	assert(box.music_library.tracks[10014].path != box.music_library.tracks["reticulating:10014"].path)
	for locale in AppLocalization.codes():
		AppLocalization.select(locale)
		await process_frame
		assert(box.track_name("reticulating:10014") == "Reticulating Splines — Buildings")
		assert(box.track_name(10014).ends_with(" — Buildings"))
	assert(box.library.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED)
	AppLocalization.select("en")
	box.track_tabs.current_tab = 1
	box.playlist.assign([10014, "reticulating:10014"])
	box.play_track(10014)
	await create_timer(0.3).timeout
	assert(box.playback.music_pack.import_revision >= 0 and box.playback.track_key() == 10014)
	box.step(1)
	await create_timer(0.3).timeout
	assert(box.playback.track_key() == "reticulating:10014")
	assert(box.playback.music_pack == replacement)
	assert(box.playback.soundtrack_folder.is_empty() and not box.playback.original_media_enabled)
	box.volume.value = 50.0
	assert(box.playback.music_pack == replacement, "Volume must not change the selected source")
	box.volume.value = 100.0
	box._save()
	var saved := MusicBoxDialog.new(box.app)
	assert(saved.playlist == [10014, "reticulating:10014"])
	saved.free()
	assert(audio.current_track_id == original_track and audio.music_director.general_track_index == director)
	assert(activity.is_empty())
	box.automatic()
	# A generic replacement is not mislabeled as either official collection.
	replacement.pack_name = "User replacement"
	box.rescan()
	assert(box.music_library.tracks.has("pack:10014"))
	assert(box.track_name("pack:10014") == "User replacement — Buildings")
	assert(DirAccess.remove_absolute(folder.path_join("Buildings.mp3")) == OK)
	box.rescan()
	assert(not box.music_library.sources.has("pack"))
	box.play_track("reticulating:10014")
	assert(not box.active)
	audio.music_pack = original
	box.rescan()
	_choose_source(box, "all")
	box.playlist.clear()
	print("PASS: imported-data gate, distinct original/replacement files, source titles, languages and persistent source keys")


func _custom_music(box: MusicBoxDialog, audio: CityAudioController, activity: Array[bool]) -> void:
	var folder := "user://custom-music-%d" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute(folder.path_join("Evening/Nested")) == OK)
	assert(DirAccess.make_dir_recursive_absolute(folder.path_join("Other")) == OK)
	var fixture := "res://tests/fixtures/audio/silence.mp3"
	var first := "Evening/Grüße aus der Stadt.MP3"
	var second := "Evening/Nested/Second.mp3"
	for id in [first, second, "Other/Second.mp3", "Root.mp3", "ignored.ogg"]:
		assert(DirAccess.copy_absolute(fixture, folder.path_join(id)) == OK)
	_tagged_mp3(folder.path_join(first), "Abend in Köln — 서울 " + "Long title ".repeat(60))
	_tagged_mp3(folder.path_join(second), "Same title")
	_tagged_mp3(folder.path_join("Other/Second.mp3"), "Same title")
	assert(DirAccess.make_dir_recursive_absolute(folder.path_join("Empty")) == OK)
	box.custom_music = CustomMusicLibrary.new(folder)
	box.rescan()
	assert(box.custom_music.tracks.size() == 4)
	assert("Empty" in box.custom_music.folders)
	assert(box.song_title(second) == box.song_title("Other/Second.mp3"))
	assert(box.custom_music.resolve(second) != box.custom_music.resolve("Other/Second.mp3"))
	_choose_source(box, "folder:Empty")
	assert(box.library.item_count == 0)
	_choose_source(box, "all")
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
	box.track_tabs.current_tab = 1
	box.playlist.assign([10002, first, second])
	box._save()
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
	assert(box.size.x <= root.get_visible_rect().size.x and box.size.y <= root.get_visible_rect().size.y)
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
	box.track_tabs.current_tab = 0
	_choose_source(box, "folder:Evening/Nested")
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
