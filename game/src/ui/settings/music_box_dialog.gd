class_name MusicBoxDialog
extends QolDialog
## A local playlist player. The original music controller retains its timing
## and reports to the simulation while its audible output is faded out.

var app: CityApplication
var playback: MusicBoxPlayback
var config := ConfigFile.new()
var storage_path := ""
var library: ItemList
var queue_list: ItemList
var favorites_only: CheckBox
var favorites: Array[int] = []
var playlist: Array[int] = []
var playlist_index := -1
var playlist_names: OptionButton
var playlist_name: LineEdit
var now_playing: Label
var status: Label
var play_button: Button
var volume: HSlider
var active := false
var _fade: Tween
var _switch_serial := 0
var _refresh_elapsed := 0.0
var _effects_dirty := false
var _effects_save_delay := 0.0


func _init(application: CityApplication) -> void:
	super()
	app = application
	title = "Music box"
	min_size = Vector2i(590, 470)
	storage_path = app.preferences.settings_path + ".music-box.cfg"
	config.load(storage_path)
	favorites = _track_ids(config.get_value("player", "favorites", []))
	playlist = _track_ids(config.get_value("player", "queue", []))
	now_playing = label("", "SectionHeading")
	label("Choose a track or create a playlist. Automatic music keeps the original game selection.", "HelpLabel")
	favorites_only = CheckBox.new()
	favorites_only.text = "Favorites only"
	favorites_only.toggled.connect(func(_enabled: bool) -> void: _refresh_library())
	column.add_child(favorites_only)
	var lists := row()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library = ItemList.new()
	library.custom_minimum_size = Vector2(245, 160)
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.item_activated.connect(func(index: int) -> void: play_track(int(library.get_item_metadata(index))))
	lists.add_child(library)
	queue_list = ItemList.new()
	queue_list.custom_minimum_size = Vector2(245, 160)
	queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_list.item_activated.connect(func(index: int) -> void:
		playlist_index = index
		play_track(playlist[index]))
	lists.add_child(queue_list)
	var edit := row()
	button(edit, "Add to playlist", _add_selected)
	button(edit, "Favorite", _favorite_selected)
	button(edit, "Remove", _remove_selected)
	button(edit, "Move up", _move_up)
	var transport := row()
	button(transport, "Previous", func() -> void: step(-1))
	play_button = button(transport, "Play / Pause", _toggle_pause)
	button(transport, "Next", func() -> void: step(1))
	button(transport, "Automatic music", automatic)
	label("Music volume")
	volume = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 1.0
	volume.value = clampf(float(config.get_value("player", "gain", 1.0)), 0.0, 1.0) * 100.0
	volume.value_changed.connect(_volume_changed)
	column.add_child(volume)
	label("Sound effects volume")
	var effects := HSlider.new()
	effects.max_value = 100.0
	effects.value = app.preferences.effects_volume * 100.0
	effects.value_changed.connect(func(value: float) -> void:
		app.preferences.effects_volume = value / 100.0
		app.audio_controller.set_volumes(app.preferences.music_volume, app.preferences.effects_volume)
		_effects_dirty = true
		_effects_save_delay = 0.5)
	column.add_child(effects)
	var names := row()
	playlist_names = OptionButton.new()
	playlist_names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(playlist_names)
	button(names, "Load playlist", _load_playlist)
	playlist_name = LineEdit.new()
	playlist_name.placeholder_text = "Playlist name"
	playlist_name.max_length = 48
	playlist_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(playlist_name)
	button(names, "Save playlist", _save_playlist)
	status = label("", "HelpLabel")
	_refresh_names()
	close_requested.connect(_save)


func _ready() -> void:
	playback = MusicBoxPlayback.new()
	add_child(playback)
	playback.setup(app.audio_controller.reference_root, app.preferences.music_volume, 0.0, app.audio_controller.original_media_enabled)
	app.audio_controller.set_music_output_gain(volume.value / 100.0)
	playback.song_finished.connect(func(id: int) -> void: step(1, id))
	playback.music_activity_changed.connect(func(playing: bool) -> void:
		if not playing and playback.current_track_id >= 0:
			_recover_failed_playback.call_deferred())
	_refresh_library()
	_refresh_queue()


static func _track_ids(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array or value is PackedInt32Array:
		for id: Variant in value:
			if id is int and id >= MusicDirector.FIRST_TRACK_ID and id < MusicDirector.FIRST_TRACK_ID + MusicDirector.TRACK_COUNT and id not in result:
				result.append(id)
	return result


func track_name(id: int) -> String:
	var source := str(app.audio_controller.music_pack.files.get(id, ""))
	if source.is_empty():
		var recordings := RecordedSoundtrack.find_tracks(app.audio_controller.soundtrack_folder, id)
		if not recordings.is_empty():
			source = recordings[0]
	var text := source.get_file().get_basename().trim_prefix("%d - " % id)
	return tr("Track %d") % id if text.is_empty() or text == str(id) else text


func _refresh_library() -> void:
	library.clear()
	for id in range(MusicDirector.FIRST_TRACK_ID, MusicDirector.FIRST_TRACK_ID + MusicDirector.TRACK_COUNT):
		if favorites_only.button_pressed and id not in favorites:
			continue
		var index := library.add_item(("★ " if id in favorites else "") + track_name(id))
		library.set_item_metadata(index, id)


func _refresh_queue() -> void:
	queue_list.clear()
	for id in playlist:
		queue_list.add_item(track_name(id))
	if playlist_index >= 0 and playlist_index < playlist.size():
		queue_list.select(playlist_index)


func open() -> void:
	_refresh_library()
	_refresh_queue()
	popup_centered(Vector2i(720, 540))


func _add_selected() -> void:
	for index in library.get_selected_items():
		var id := int(library.get_item_metadata(index))
		if id not in playlist:
			playlist.append(id)
	_refresh_queue()
	_save()


func _favorite_selected() -> void:
	for index in library.get_selected_items():
		var id := int(library.get_item_metadata(index))
		if id in favorites:
			favorites.erase(id)
		else:
			favorites.append(id)
	_refresh_library()
	_save()


func _remove_selected() -> void:
	var selected := queue_list.get_selected_items()
	if selected.is_empty():
		return
	playlist.remove_at(selected[0])
	playlist_index = playlist.find(playback.current_track_id)
	_refresh_queue()
	_save()


func _move_up() -> void:
	var selected := queue_list.get_selected_items()
	if selected.is_empty() or selected[0] == 0:
		return
	var index := selected[0]
	var id := playlist[index]
	playlist[index] = playlist[index - 1]
	playlist[index - 1] = id
	playlist_index = playlist.find(playback.current_track_id)
	_refresh_queue()
	queue_list.select(index - 1)
	_save()


func _sync_source() -> void:
	var original := app.audio_controller
	playback.music_pack = original.music_pack
	playback.reference_root = original.reference_root
	playback.original_media_enabled = original.original_media_enabled
	playback.soundtrack_folder = original.soundtrack_folder
	playback.set_music_soundfont(app.preferences.music_soundfont, app.preferences.music_soundfont_path)
	playback.set_background_audio(original.background_audio)
	playback.application_has_focus = original.application_has_focus
	playback.set_volumes(original.music_volume * volume.value / 100.0, 0.0)


func play_track(id: int) -> void:
	status.text = ""
	if app.document_state.city != null and not app.document_state.city.music_enabled():
		status.text = tr("Enable Music in Options to play a track.")
		return
	_switch_serial += 1
	var serial := _switch_serial
	if _fade != null:
		_fade.kill()
	_sync_source()
	active = true
	playback.music_paused = false
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, 0.0, 0.15)
	_fade.tween_method(playback.set_music_output_gain, playback.music_output_gain, 0.0, 0.15)
	await _fade.finished
	if serial != _switch_serial:
		return
	if not playback.play_music_track(id, false, true):
		automatic()
		status.text = tr("This music track is not available.")
		return
	playlist_index = playlist.find(id)
	_refresh_queue()
	_fade = create_tween()
	_fade.tween_method(playback.set_music_output_gain, 0.0, 1.0, 0.2)


func step(direction: int, finished_track := -1) -> void:
	var ids := playlist.duplicate()
	if ids.is_empty():
		for index in library.item_count:
			ids.append(int(library.get_item_metadata(index)))
	if ids.is_empty():
		return
	var index := ids.find(finished_track if finished_track >= 0 else playback.current_track_id)
	if index < 0:
		index = playlist_index
	play_track(ids[posmod(index + direction, ids.size())])


func _toggle_pause() -> void:
	if not active:
		var selected := library.get_selected_items()
		if not selected.is_empty():
			play_track(int(library.get_item_metadata(selected[0])))
		else:
			step(1)
	else:
		playback._set_music_paused(not playback.music_paused)


func automatic() -> void:
	status.text = ""
	_switch_serial += 1
	if _fade != null:
		_fade.kill()
	active = false
	playback.stop_music()
	_fade = create_tween()
	_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, volume.value / 100.0, 0.2)


func _volume_changed(_value: float) -> void:
	if playback != null:
		_sync_source()
		if not active:
			if _fade != null:
				_fade.kill()
			app.audio_controller.set_music_output_gain(volume.value / 100.0)
	_save()


func _recover_failed_playback() -> void:
	if active and not playback.music_paused and not playback.music_playback_is_active():
		automatic()
		status.text = tr("This music track is not available.")


func _process(delta: float) -> void:
	if playback == null:
		return
	if _effects_dirty:
		_effects_save_delay -= delta
		if _effects_save_delay <= 0.0:
			_save_effects()
	if active:
		if app.document_state.city != null and not app.document_state.city.music_enabled():
			automatic()
		else:
			var target_volume := app.audio_controller.music_volume * volume.value / 100.0
			if not is_equal_approx(playback.music_volume, target_volume):
				playback.set_volumes(target_volume, 0.0)
			playback.application_has_focus = app.audio_controller.application_has_focus
			playback.background_audio = app.audio_controller.background_audio
			playback.focus_paused = app.audio_controller.focus_paused
			playback._sync_music_pause()
	_refresh_elapsed += delta
	if not visible or _refresh_elapsed < 0.25:
		return
	_refresh_elapsed = 0.0
	var player: CityAudioController = playback if active else app.audio_controller
	var track := track_name(player.current_track_id) if player.current_track_id >= 10000 else tr("No track playing")
	now_playing.text = tr("Paused: %s") % track if player.music_paused else tr("Playing: %s") % track
	if not active:
		now_playing.text = tr("Automatic music") + " — " + now_playing.text


func _save() -> void:
	config.set_value("player", "favorites", favorites.duplicate())
	config.set_value("player", "queue", playlist.duplicate())
	config.set_value("player", "gain", volume.value / 100.0)
	var error := config.save(storage_path)
	if error != OK:
		status.text = tr("Cannot save music preferences: %s") % error_string(error)


func _refresh_names() -> void:
	playlist_names.clear()
	if config.has_section("playlists"):
		for name in config.get_section_keys("playlists"):
			playlist_names.add_item(name)


func _save_playlist() -> void:
	var name := playlist_name.text.strip_edges()
	if name.is_empty():
		status.text = tr("Enter a playlist name first.")
		return
	config.set_value("playlists", name, playlist.duplicate())
	_save()
	_refresh_names()


func _load_playlist() -> void:
	if playlist_names.selected < 0:
		return
	var name := playlist_names.get_item_text(playlist_names.selected)
	playlist = _track_ids(config.get_value("playlists", name, []))
	playlist_name.text = name
	playlist_index = playlist.find(playback.current_track_id)
	_refresh_queue()
	_save()


func _exit_tree() -> void:
	_save_effects()
	if is_instance_valid(app.audio_controller):
		app.audio_controller.set_music_output_gain(1.0)


func _save_effects() -> void:
	if not _effects_dirty:
		return
	_effects_dirty = false
	var error := AppSettingsStore.save_values(app.preferences.music_volume, app.preferences.effects_volume,
		app.preferences.fullscreen, app.preferences.settings_path)
	if error != OK:
		status.text = tr("Cannot save music preferences: %s") % error_string(error)


func handle_media_key(key: int) -> bool:
	match key:
		KEY_MEDIAPLAY:
			_toggle_pause()
		KEY_MEDIANEXT:
			step(1)
		KEY_MEDIAPREVIOUS:
			step(-1)
		KEY_MEDIASTOP:
			playback._set_music_paused(true)
		_:
			return false
	return true
