class_name ApplicationMultiplayer
extends RefCounted
## Connects the ordinary city tools to the shared host, while retaining a private view.

const BUDGET_NAMES := ["Residential tax", "Commercial tax", "Industrial tax", "Ordinances", "Bonds",
	"Police", "Fire", "Health", "Schools", "College", "Roads", "Highways", "Bridges", "Rail", "Subway", "Tunnels"]
var app: CityApplication
var session: CoopSession
var panel: Window
var lobby: VBoxContainer
var controls: VBoxContainer
var player: LineEdit
var address: LineEdit
var port: SpinBox
var join_code: LineEdit
var use_current: CheckBox
var save_path: LineEdit
var status: Label
var message: Label
var budget_values: Array[SpinBox] = []
var auto_budget: CheckBox
var ordinance: OptionButton
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
var menu_button: Button
var identity_signature := ""
var selection_revision := 0


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
	session.feedback.connect(show_message)
	session.choice_requested.connect(show_choices)
	panel = Window.new()
	panel.theme = AppUiTheme.current()
	panel.title = "Multiplayer — Echtzeit-Koop"
	panel.size = Vector2i(650, 650)
	panel.min_size = Vector2i(480, 360)
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
	label(body, "Koop: gleichzeitig bauen, eine Stadt und eine gemeinsame Kasse.\nLAN / direkte IP · bis zu 8 Spieler · gleiche Spielversion erforderlich.\nRegion und Shared sind noch nicht spielbar.")
	lobby = VBoxContainer.new()
	body.add_child(lobby)
	player = field(lobby, "Spielername", "Mayor")
	address = field(lobby, "Host-Adresse (für Beitreten)", "127.0.0.1")
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 20000
	label(lobby, "TCP-Port")
	lobby.add_child(port)
	join_code = field(lobby, "Sitzungscode (auf allen Rechnern gleich)", Crypto.new().generate_random_bytes(4).hex_encode())
	use_current = CheckBox.new()
	use_current.text = "Kopie der geöffneten Stadt verwenden (max. 128 × 128, SC2X)"
	lobby.add_child(use_current)
	var row := HBoxContainer.new()
	lobby.add_child(row)
	button(row, "Koop hosten", start_host)
	button(row, "Beitreten / Wiederverbinden", start_join)
	save_path = field(body, "Sitzungsdatei (.sc2mp; nur der Host speichert)", AppPaths.path("multiplayer/session.sc2mp"))
	button(lobby, "Gespeicherte Sitzung hosten", resume_host)
	status = label(body, "Noch nicht verbunden.")
	message = label(body, "")
	controls = VBoxContainer.new()
	body.add_child(controls)
	var speeds := HBoxContainer.new()
	controls.add_child(speeds)
	for index in 5:
		button(speeds, ["Pause", "Turtle", "Llama", "Cheetah", "Swallow"][index], request_speed.bind(index + 1))
	label(controls, "Jeder kann pausieren. Die langsamste angeforderte Geschwindigkeit gilt.")
	button(controls, "Host: Pause nach Verbindungsabbruch aufheben", session.release_disconnect_pause)
	var actions := HBoxContainer.new()
	controls.add_child(actions)
	button(actions, "Sitzung speichern", save)
	button(actions, "Eigene letzte Änderung zurücknehmen", func() -> void: session.request({"kind": "undo"}))
	button(actions, "Verlassen", confirm_leave)
	label(controls, "Haushalt — Werte laden, bearbeiten, gemeinsam übernehmen")
	button(controls, "Aktuelle Haushaltswerte laden", refresh_budget)
	var grid := GridContainer.new()
	grid.columns = 4
	controls.add_child(grid)
	for index in BudgetPhase.BUDGET_COUNT:
		label(grid, BUDGET_NAMES[index])
		var amount := SpinBox.new()
		amount.min_value = 0
		amount.max_value = 22 if index < 3 else 100
		if index in [3, 4]:
			amount.max_value = 2147483647
		amount.editable = index not in [3, 4]
		amount.suffix = "%"
		grid.add_child(amount)
		budget_values.append(amount)
	auto_budget = CheckBox.new()
	auto_budget.text = "Auto-Budget"
	controls.add_child(auto_budget)
	button(controls, "Haushalt übernehmen / Jahreshaushalt bestätigen", send_budget)
	var bonds := HBoxContainer.new()
	controls.add_child(bonds)
	button(bonds, "Kredit aufnehmen ($10.000)", confirm_bond.bind("bond"))
	button(bonds, "Kredit zurückzahlen", confirm_bond.bind("repay"))
	ordinance = OptionButton.new()
	for title: String in OrdinanceCommand.NAMES:
		ordinance.add_item(title)
	controls.add_child(ordinance)
	var laws := HBoxContainer.new()
	controls.add_child(laws)
	button(laws, "Verordnung aktivieren", send_ordinance.bind(true))
	button(laws, "Verordnung deaktivieren", send_ordinance.bind(false))
	var decisions := HBoxContainer.new()
	controls.add_child(decisions)
	button(decisions, "Offene Entscheidung: Ja / Bestätigen", send_decision.bind(true))
	button(decisions, "Offene Entscheidung: Nein", send_decision.bind(false))
	button(body, "Zur Stadt", panel.hide)
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
	leave_dialog.confirmed.connect(leave)
	app.add_child(leave_dialog)
	menu_button = button(app.city_menu_bar.get_child(0), "Multiplayer", open)
	app.main_menu.multiplayer_requested.connect(open)
	controls.hide()
	load_identity()


func open() -> void:
	lobby.visible = not active() or not session.connected
	controls.visible = active()
	if active():
		refresh_budget()
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
	if active():
		return
	if not can_start():
		return
	var document: Sc2File
	if use_current.button_pressed:
		if app.document_state.current_document == null:
			show_message("Öffne oder erstelle zuerst eine Stadt.")
			return
		if not Sc2xCheckpoint.save_error(app.simulation_state.speed_controller).is_empty():
			show_message("Beende zuerst die offene Simulationsentscheidung.")
			return
		remember_city()
		document = original_document
	else:
		var created := Sc2xDocument.create_empty(128, "Koop City")
		if not created.ok:
			show_message(created.error)
			return
		document = created.document
		remember_city()
	var result := session.host(document, int(port.value), join_code.text, player.text)
	if not result.is_empty():
		show_message(result)
		return
	save_identity()
	panel.hide()
	show_message("Koop läuft. Mitspieler verbinden sich mit deiner LAN-IP, Port %d und Code %s. Wähle eine Geschwindigkeit." % [port.value, join_code.text])


func start_join() -> void:
	if not can_start():
		return
	remember_city()
	var result := session.join(address.text.strip_edges(), int(port.value), join_code.text, player.text)
	show_message(result if not result.is_empty() else "Verbinde mit dem Host …")
	save_identity()


func resume_host() -> void:
	if active():
		return
	if not can_start():
		return
	remember_city()
	var result := session.resume_session(save_path.text, int(port.value), join_code.text, player.text)
	if not result.is_empty():
		show_message(result)
	else:
		save_identity()
		panel.hide()


func receive_state(state: Dictionary) -> void:
	status.text = "%s · %s\n%s%s" % ["Host" if session.hosting else "Verbunden", ", ".join(state.get("players", [])),
		"Offene Entscheidung: " + str(state.get("pending")) if state.get("pending", "") != "" else "Keine offene Entscheidung.",
		"\nPause nach Verbindungsabbruch." if state.get("disconnect_pause", false) else ""]
	if state.get("blocked", false) and state.get("pending", "") == "":
		status.text += "\nSimulationsmeldung: Bestätigen, um fortzusetzen."
	if state.get("terminal", false):
		status.text += "\nSpielende. Die Stadt kann weiter betrachtet und die Sitzung gespeichert werden."
	menu_button.text = "Multiplayer !" if state.get("blocked", false) else "Multiplayer"
	if not str(state.get("error", "")).is_empty():
		show_message(str(state.error))
	if last_city_bytes == state.city:
		app.simulation_state.speed_controller.speed = int(state.get("speed", 1))
		app.frame.sync_speed_ui()
		return
	var document := Sc2File.new()
	if not document.parse(Marshalls.base64_to_raw(state.city)) or not document.is_sc2x() or document.map_size > 128:
		show_message("Ungültiger Stadtzustand vom Host. Sitzung beenden und neu verbinden.")
		return
	last_city_bytes = state.city
	if not mirrored:
		if not app.city_session.activate_document(document, null, "Koop verbunden", true):
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
	if value > GameSpeedController.Speed.PAUSED:
		app.simulation_state.resume_speed = value
	session.request({"kind": "speed", "speed": value})


func refresh_budget() -> void:
	if not mirrored:
		return
	var values := BudgetPhase.funding_values(app.document_state.city)
	for index in mini(values.size(), budget_values.size()):
		budget_values[index].value = values[index]
	auto_budget.button_pressed = app.document_state.city.auto_budget_enabled()
	policy_at_open = session.local_policy


func send_budget() -> void:
	var values: Array[int] = []
	for field_value in budget_values:
		values.append(int(field_value.value))
	session.request({"kind": "budget", "values": values, "auto": auto_budget.button_pressed, "policy": policy_at_open})


func send_ordinance(enabled: bool) -> void:
	session.request({"kind": "ordinance", "ordinance": ordinance.selected, "enabled": enabled, "policy": policy_at_open})


func send_decision(accepted: bool) -> void:
	session.request({"kind": "decision", "accept": accepted, "policy": policy_at_open})


func confirm_bond(kind: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.theme = AppUiTheme.current()
	dialog.dialog_text = "Gemeinsamen Kredit aufnehmen?" if kind == "bond" else "Gemeinsamen Kredit zurückzahlen?"
	app.add_child(dialog)
	var policy := policy_at_open
	dialog.confirmed.connect(func() -> void:
		session.request({"kind": kind, "policy": policy})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func save() -> void:
	if not save_path.text.ends_with(".sc2mp"):
		show_message("Verwende eine eigene Sitzungsdatei mit der Endung .sc2mp.")
		return
	DirAccess.make_dir_recursive_absolute(save_path.text.get_base_dir())
	var result := session.save_session(save_path.text)
	show_message(result if not result.is_empty() else "Sitzung gespeichert: " + save_path.text)


func confirm_leave() -> void:
	leave_dialog.popup_centered()


func leave() -> void:
	session.stop()
	mirrored = false
	last_city_bytes = ""
	panel.hide()
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
	message.text = text
	app.interface.show_status(text)


func show_choices(result: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.theme = AppUiTheme.current()
	dialog.title = str(result.message)
	dialog.get_ok_button().text = "Cancel"
	var list := VBoxContainer.new()
	dialog.add_child(list)
	app.add_child(dialog)
	for choice: Variant in result.choices:
		if not choice is Dictionary or not choice.get("fields") is Dictionary:
			continue
		var command: Dictionary = result.request.duplicate(true)
		command.merge(choice.fields, true)
		button(list, str(choice.get("label", "Choose")), func() -> void:
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
	player.text = str(config.get_value("client", "name", "Mayor"))
	address.text = str(config.get_value("client", "address", "127.0.0.1"))
	port.value = float(config.get_value("client", "port", 20000))
	join_code.text = str(config.get_value("client", "code", join_code.text))


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
	if player.text.strip_edges().is_empty() or player.text.length() > 32 or join_code.text.length() < 4 or join_code.text.length() > 64:
		show_message("Verwende einen Spielernamen mit 1–32 und einen Sitzungscode mit 4–64 Zeichen.")
		return false
	return true


func save_identity() -> void:
	var signature := str([session.token, player.text, address.text, port.value, join_code.text])
	if signature == identity_signature:
		return
	identity_signature = signature
	var config := ConfigFile.new()
	config.set_value("client", "token", session.token)
	config.set_value("client", "name", player.text)
	config.set_value("client", "address", address.text)
	config.set_value("client", "port", int(port.value))
	config.set_value("client", "code", join_code.text)
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
