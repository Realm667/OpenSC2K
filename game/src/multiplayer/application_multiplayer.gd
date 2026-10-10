class_name ApplicationMultiplayer
extends RefCounted
## Connects the ordinary city tools to the shared host, while retaining a private view.

var app: CityApplication
var session: CoopSession
var panel: Window
var lobby: VBoxContainer
var player: LineEdit
var address: LineEdit
var port: SpinBox
var join_code: LineEdit
var use_current: CheckBox
var status: Label
var message: Label
var policy_at_open := 0
var original_document: Sc2File
var original_save_path := ""
var original_saved_snapshot := PackedByteArray()
var original_saved_once := false
var mirrored := false
var last_city_bytes := ""
var sign_dialog: ConfirmationDialog
var sign_text: LineEdit
var pending_sign: Dictionary = {}
var leave_dialog: ConfirmationDialog
var menu_button: MenuButton
var windows: MultiplayerWindows
var launch: MultiplayerLaunchMenu
var color_picker: ColorPickerButton
var mode_picker: OptionButton
var city_picker: OptionButton
var city_file: FileDialog
var pending_new_city := false
var selected_city_path := ""
var multiplayer_save_path := ""
var identity_signature := ""
var selection_revision := 0
var exit_action := ""


func _init(application: CityApplication) -> void:
	app = application


func active() -> bool:
	return session != null and session.active


func setup() -> void:
	session = CoopSession.new()
	session.environment_source = app.visual_environment.network_snapshot
	session.environment_received.connect(app.visual_environment.receive_network_weather)
	app.add_child(session)
	session.state_received.connect(receive_state)
	session.cursor_source = func() -> Vector2:
		return MultiplayerMapOverlay.local_cursor(app) if mirrored and app.map_view.visible else Vector2(-1, -1)
	session.feedback.connect(show_message)
	session.action_sounds.connect(app.effects_audio.play_sound_ids)
	session.remote_action_sound.connect(play_remote_action)
	session.choice_requested.connect(show_choices)
	panel = Window.new()
	panel.theme = AppUiTheme.current()
	panel.title = "Multiplayer"
	panel.size = Vector2i(650, 650)
	panel.min_size = Vector2i(480, 240)
	panel.close_requested.connect(panel.hide)
	panel.hide()
	app.add_child(panel)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	background.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	launch = MultiplayerLaunchMenu.new(self)
	launch.setup(body)
	city_file = FileDialog.new()
	city_file.access = FileDialog.ACCESS_FILESYSTEM
	city_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	city_file.filters = PackedStringArray(["*.sc2x, *.sc2, *.SC2, *.sc2mp ; Städte"])
	city_file.current_dir = AppPaths.path("cities")
	city_file.file_selected.connect(host_saved_city)
	app.add_child(city_file)
	status = label(body, "")
	status.hide()
	message = label(body, "")
	message.hide()
	sign_dialog = ConfirmationDialog.new()
	sign_dialog.theme = AppUiTheme.current()
	sign_dialog.title = "Gemeinsames Schild"
	sign_text = LineEdit.new()
	sign_text.max_length = 120
	sign_text.custom_minimum_size.x = 400
	sign_dialog.add_child(sign_text)
	app.add_child(sign_dialog)
	sign_dialog.confirmed.connect(func() -> void:
		pending_sign["text"] = sign_text.text
		session.request(pending_sign.duplicate(true)))
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.theme = AppUiTheme.current()
	leave_dialog.dialog_text = "Sitzung verlassen? Nicht gespeicherte Änderungen gehen beim Host verloren.\nAls Host trennst du dabei alle Mitspieler."
	leave_dialog.confirmed.connect(func() -> void:
		var quitting := exit_action == "quit"
		leave()
		if quitting:
			app.get_tree().quit())
	leave_dialog.canceled.connect(func() -> void: exit_action = "")
	app.add_child(leave_dialog)
	windows = MultiplayerWindows.new(self)
	windows.setup()
	app.city_dialogs.city_save_dialog.canceled.connect(func() -> void: exit_action = "")
	menu_button = windows.menu
	app.main_menu.multiplayer_requested.connect(open)
	load_identity()


func open() -> void:
	if active() and session.connected:
		windows.open_scoreboard()
		return
	lobby.show()
	launch.update()
	panel.popup_centered()


func remember_city() -> void:
	if active():
		return
	original_document = app.document_state.current_document
	original_save_path = app.document_state.current_save_path
	original_saved_snapshot = app.document_state.saved_city_snapshot.duplicate()
	original_saved_once = app.document_state.current_city_saved_once
	if original_document != null:
		if app.simulation_state.frame_simulation != null:
			app.simulation_state.frame_simulation.close()
			app.simulation_state.frame_simulation = null
		Sc2xCheckpoint.capture(app.simulation_state.speed_controller, original_document.sc2x_metadata)
		original_document = original_document.duplicate_document()


func start_host() -> void:
	if active() or not can_start():
		return
	if city_picker.selected == 1:
		if not selected_city_path.is_empty():
			host_saved_city(selected_city_path)
			return
		city_file.popup_centered_ratio(0.8)
		return
	remember_city()
	pending_new_city = true
	panel.hide()
	app.new_city.open_new_city_dialog()


func host_document(document: Sc2File) -> void:
	if not document.is_sc2x():
		var converted := Sc2xDocument.from_legacy(document)
		if not converted.ok:
			show_message(converted.error)
			return
		document = converted.document
	session.player_color = color_picker.color.to_html(false)
	session.host_land_price = int(launch.land_price.value)
	session.host_starter_tiles = 1024
	session.host_goal_kind = ["endless", "population", "wealth"][launch.goal_picker.selected]
	session.host_goal_target = int(launch.goal_target.value)
	var result := session.host(document, int(port.value), join_code.text, player.text, ["coop", "shared", "region"][mode_picker.selected])
	if not result.is_empty():
		show_message(result)
		return
	pending_new_city = false
	save_identity()
	panel.hide()
	show_message("Partie läuft auf Port %d. Wähle eine Spielgeschwindigkeit." % int(port.value))


func host_saved_city(path: String) -> void:
	remember_city()
	selected_city_path = path
	multiplayer_save_path = "" if use_current.button_pressed else path
	if path.get_extension().to_lower() == "sc2mp":
		var error := session.resume_session(path, int(port.value), join_code.text, player.text)
		if not error.is_empty():
			show_message(error)
		return
	var document := Sc2File.new()
	if not document.parse(FileAccess.get_file_as_bytes(path)):
		show_message(document.parse_error)
		return
	host_document(document)
	if session.hosting and document.sc2x_extra_entries.has("multiplayer.json"):
		var error := session.restore_embedded(document)
		if not error.is_empty():
			leave()
			show_message(error)


func start_join() -> void:
	if not can_start():
		return
	remember_city()
	session.player_color = color_picker.color.to_html(false)
	var result := session.join(address.text.strip_edges(), int(port.value), join_code.text, player.text, "choose")
	show_message(result if not result.is_empty() else "Verbinde mit dem Host …")
	save_identity()


func receive_state(state: Dictionary) -> void:
	windows.update_state(state)
	if not str(state.get("error", "")).is_empty():
		show_message(str(state.error))
	if last_city_bytes == state.city:
		app.simulation_state.speed_controller.speed = int(state.get("speed", 1))
		app.frame.sync_speed_ui()
		return
	var document := Sc2File.new()
	if not document.parse(Marshalls.base64_to_raw(state.city)) or not document.is_sc2x() or document.map_size not in Sc2File.MAP_SIZES:
		show_message("Ungültiger Stadtzustand vom Host. Sitzung beenden und neu verbinden.")
		return
	last_city_bytes = state.city
	if mirrored:
		# Camera-follow and audio choices belong to this player.
		var local_city := CityState.from_document(document)
		local_city.set_auto_goto_enabled(app.document_state.city.auto_goto_enabled())
		local_city.set_sound_enabled(app.document_state.city.sound_enabled())
		local_city.set_music_enabled(app.document_state.city.music_enabled())
	if not mirrored:
		if not app.city_session.activate_document(document, null, "Multiplayer verbunden", true):
			return
		if app.simulation_state.frame_simulation != null:
			app.simulation_state.frame_simulation.close()
			app.simulation_state.frame_simulation = null
		mirrored = true
		refresh_budget()
		panel.hide()
	else:
		var edit := EditCommandResult.new()
		edit.ok = true
		var previous := app.document_state.current_document
		var map_changed := false
		for index in document.chunks.size():
			var chunk := document.chunks[index]
			var old := previous.find_chunk(chunk.chunk_id)
			if old != null:
				chunk.mutation_revision = old.mutation_revision
			if old == null or old.decoded_payload != chunk.decoded_payload:
				chunk.mark_mutated()
				edit.changed_ids.append(chunk.chunk_id)
				edit.old_payloads[chunk.chunk_id] = old.decoded_payload if old != null else PackedByteArray()
				edit.new_payloads[chunk.chunk_id] = chunk.decoded_payload
				if chunk.chunk_id not in ["MISC", "XTHG", "XGRP", "CNAM"]:
					map_changed = true
			elif old != null:
				document.chunks[index] = old
		# Keep the display city's identity. Render caches and cosmetic clocks use it
		# to distinguish an edit from opening a different city.
		for field_name in ["chunks", "source_bytes", "sc2x_metadata", "sc2x_compat_labels",
				"sc2x_object_ids", "sc2x_object_kinds", "sc2x_object_names", "sc2x_extensions",
				"sc2x_text_orders", "sc2x_preserved", "sc2x_extra_entries", "sc2x_unsupported_features",
				"sc2x_converted_from", "large_version"]:
			previous.set(field_name, document.get(field_name))
		previous.rebuild_chunk_cache()
		app.document_state.city.resync_mirrors(edit.changed_ids)
		app.simulation_state.simulation_engine.clock.city_days = app.document_state.city.age_in_days()
		Sc2xCheckpoint.restore(app.simulation_state.speed_controller, previous.sc2x_metadata)
		if map_changed:
			app.static_render.refresh_after_city_edit(edit)
		app.moving_sprites.refresh_moving_things()
		app.interface.refresh_details()
	app.simulation_state.speed_controller.speed = int(state.get("speed", 1))
	app.frame.sync_speed_ui()
	save_identity()


func apply_selection(start: Vector2i, finish: Vector2i, path: Array[Vector2i], dragged: bool) -> void:
	if windows.land_action != "":
		session.request({"kind": windows.land_action, "start": [start.x, start.y], "finish": [finish.x, finish.y], "price": windows.land_offer_price, "include_water": windows.include_water})
		return
	var group := app.tool_state.selected_group
	if group == CityToolIds.Group.QUERY:
		app.query_choices.open_query(finish)
		return
	if group == CityToolIds.Group.CENTERING:
		app.camera_input.center_map_on_tile(finish)
		return
	var positions: Array = []
	for target in path:
		positions.append([target.x, target.y])
	var command := {"kind": "build", "group": group, "tool": app.tool_state.selected_subtool,
		"start": [start.x, start.y], "finish": [finish.x, finish.y], "path": positions,
		"dragged": dragged, "underground": app.view_state.overlay_mode == CityViewMode.Mode.UNDERGROUND}
	if dragged:
		command["revision"] = selection_revision
	if group == CityToolIds.Group.SIGNS:
		command["kind"] = "sign"
		command["revision"] = session.local_revision
		pending_sign = command
		sign_text.max_length = mini(120, app.document_state.current_document.name_limit())
		sign_text.text = CitySignTable.text_at(app.document_state.city, finish)
		sign_dialog.popup_centered()
	else:
		session.request(command)


func bulldoze(point: Vector2i) -> void:
	session.request({"kind": "build", "group": 0, "tool": 0, "start": [point.x, point.y],
		"finish": [point.x, point.y], "path": [[point.x, point.y]], "dragged": false})


func request_speed(value: int) -> void:
	if not session.hosting:
		return
	if value > GameSpeedController.Speed.PAUSED:
		app.simulation_state.resume_speed = value
	session.request({"kind": "speed", "speed": value})


func refresh_budget() -> void:
	policy_at_open = session.local_policy


func send_decision(accepted: bool) -> void:
	session.request({"kind": "decision", "accept": accepted, "policy": policy_at_open})


func save(as_copy := false) -> void:
	if not session.hosting:
		show_message("Der Host speichert die gemeinsame Partie.")
		return
	if as_copy or multiplayer_save_path.is_empty() or not multiplayer_save_path.ends_with(".sc2x"):
		app.city_files.open_save_dialog()
	else:
		save_to(multiplayer_save_path)


func save_to(path: String) -> void:
	if not path.to_lower().ends_with(".sc2x"):
		path = path.get_basename() + ".sc2x"
	var error := session.save_city(path)
	if not error.is_empty():
		exit_action = ""
		app.interface.show_error(MultiplayerText.message(error))
	if error.is_empty():
		multiplayer_save_path = path
		if exit_action == "quit":
			session.stop()
			app.get_tree().quit()
	show_message(error if not error.is_empty() else "Multiplayer-Spielstand gespeichert: " + path)


func confirm_leave() -> void:
	exit_action = ""
	leave_dialog.popup_centered()


func leave() -> void:
	session.stop()
	mirrored = false
	last_city_bytes = ""
	panel.hide()
	multiplayer_save_path = ""
	windows.close()
	if original_document != null:
		app.city_session.activate_document(original_document, null, "Multiplayer verlassen", true)
		app.document_state.current_save_path = original_save_path
		app.document_state.saved_city_snapshot = original_saved_snapshot
		app.document_state.current_city_saved_once = original_saved_once
	else:
		app.visual_preparation.reset()
		app.document_state.city = null
		app.document_state.current_document = null
		app.simulation_state.speed_controller = null
		app.simulation_state.simulation_engine = null
		app.map_render.refresh_map(false)
		app.interface.show_main_menu()


func show_message(text: String) -> void:
	text = MultiplayerText.message(text)
	message.text = text
	app.interface.show_status(text)


func show_choices(result: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.theme = AppUiTheme.current()
	dialog.title = MultiplayerText.message(str(result.message))
	dialog.get_ok_button().text = "Cancel"
	var list := VBoxContainer.new()
	dialog.add_child(list)
	app.add_child(dialog)
	for choice: Variant in result.choices:
		if not choice is Dictionary or not choice.get("fields") is Dictionary:
			continue
		var command: Dictionary = result.request.duplicate(true)
		command.merge(choice.fields, true)
		button(list, MultiplayerText.message(str(choice.get("label", "Choose"))), func() -> void:
			session.request(command)
			dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func load_identity() -> void:
	var config := ConfigFile.new()
	if config.load(AppPaths.path("multiplayer-client.cfg")) != OK:
		return
	var stored: String = str(config.get_value("client", "token", ""))
	if stored.length() == 48:
		session.token = stored
		session.credential = stored
	player.text = str(config.get_value("client", "name", "Mayor"))
	address.text = str(config.get_value("client", "address", "127.0.0.1"))
	port.value = float(config.get_value("client", "port", 20000))
	color_picker.color = Color(CoopSession.valid_color(config.get_value("client", "color", "46b4ff")))
	color_picker.color_changed.emit(color_picker.color)


func can_start() -> bool:
	if active():
		return not session.hosting
	if app.tool_state.landscape_editor:
		show_message("Beende zuerst die Landschaftserstellung mit Start City.")
		return false
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		show_message(error)
		return false
	if player.text.strip_edges().is_empty() or player.text.length() > 32 or join_code.text.length() > 64:
		show_message("Verwende einen Spielernamen mit 1–32 Zeichen und ein optionales Passwort mit höchstens 64 Zeichen.")
		return false
	return true


func save_identity() -> void:
	var signature := str([session.credential, player.text, address.text, port.value, color_picker.color])
	if signature == identity_signature:
		return
	identity_signature = signature
	var config := ConfigFile.new()
	config.set_value("client", "token", session.credential)
	config.set_value("client", "name", player.text)
	config.set_value("client", "address", address.text)
	config.set_value("client", "port", int(port.value))
	config.set_value("client", "color", color_picker.color.to_html(false))
	config.save(AppPaths.path("multiplayer-client.cfg"))


static func label(parent: Node, text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.custom_minimum_size.x = 120
	parent.add_child(control)
	return control


static func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control


static func field(parent: Node, title: String, value: String) -> LineEdit:
	label(parent, title)
	var control := LineEdit.new()
	control.text = value
	parent.add_child(control)
	return control


func request_exit(action: String) -> void:
	if exit_action == "quit":
		return
	if action != "quit":
		confirm_leave()
		return
	exit_action = "quit"
	if not session.hosting:
		leave_dialog.popup_centered()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Quit multiplayer")
	dialog.dialog_text = tr("Save the multiplayer game before quitting? All connected players will be disconnected.")
	dialog.ok_button_text = tr("Save and quit")
	dialog.add_button(tr("Quit without saving"), false, "discard")
	app.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		save())
	dialog.custom_action.connect(func(value: StringName) -> void:
		if value == &"discard":
			session.stop()
			app.get_tree().quit())
	dialog.canceled.connect(func() -> void:
		exit_action = ""
		dialog.queue_free())
	dialog.popup_centered()

var remote_audio_gate := WaveSoundGate.new()
var remote_audio_time := 0

func play_remote_action(event: Dictionary) -> void:
	if not mirrored or app.document_state.city == null or not event.get("point") is Array or event.point.size() != 2 or not event.get("sounds") is Array:
		return
	if session.latest.get("mode") == "region" and event.get("view_owner") != session.latest.get("view_owner"):
		return
	for coordinate: Variant in event.point:
		if not CoopWorld.whole_number(coordinate, 0, app.document_state.city.map_size - 1):
			return
	var map := app.map_view
	var point := MultiplayerMapOverlay.project(map.city, Vector2(event.point[0], event.point[1])) * map.camera._view_scale() + map.camera._draw_offset(map.camera._view_scale())
	var view := map.camera_view_rect
	if view.size == Vector2.ZERO:
		view = Rect2(Vector2.ZERO, map.size)
	var gain := remote_gain(point, view)
	if gain <= 0:
		return
	var sounds: Array[int] = []
	for value: Variant in event.sounds.slice(0, 32):
		if CoopWorld.whole_number(value, 500, 529):
			sounds.append(int(value))
	var now := Time.get_ticks_msec()
	remote_audio_gate.advance(now - remote_audio_time)
	remote_audio_time = now
	# Remote construction must never suppress the local player's own feedback.
	app.audio_controller.play_sound_events(SoundEvent.from_ids(sounds), app.document_state.city.sound_enabled(), app.view_state.overlay_mode, app.static_render.city_view_size(), false, gain, remote_audio_gate)

static func remote_gain(point: Vector2, view: Rect2) -> float:
	var nearest := point.clamp(view.position, view.end)
	var distance := point.distance_to(nearest) / maxf(1.0, view.size.x)
	return pow(maxf(0.0, 1.0 - distance / 2.0), 2)
