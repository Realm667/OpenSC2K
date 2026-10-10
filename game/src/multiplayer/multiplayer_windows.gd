class_name MultiplayerWindows
extends RefCounted
## Local windows and map annotations; they never mutate the authoritative city.

var owner_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return owner_ref.get_ref()
var menu: MenuButton
var scoreboard: Window
var score_rows: VBoxContainer
var chat: Window
var chat_log: RichTextLabel
var chat_input: LineEdit
var unread := 0
var players: Array = []
var state: Dictionary = {}
var overlay: Control
var land_action := ""
var land_offer_price := -1
var known_disasters: Array = []
var alarm: AudioStreamPlayer
var territory_key: Array = []
var territory_lines: Dictionary = {}
var own_disaster := 0
var decision_key := ""
var decision_dialog: AcceptDialog


func _init(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)


func setup() -> void:
	var row := coop.app.city_menu_bar.newspaper_menu.get_parent()
	menu = MenuButton.new()
	menu.text = "Multiplayer"
	row.add_child(menu)
	row.move_child(menu, coop.app.city_menu_bar.newspaper_menu.get_index() + 1)
	var popup := menu.get_popup()
	for title in ["Scoreboard", "Chat", "Spiel erstellen / Beitreten", "Verbindungspause aufheben", "Partie verlassen", "Land kaufen", "Land anbieten", "Landangebote"]:
		popup.add_item(title)
	popup.id_pressed.connect(func(id: int) -> void:
		match id:
			0:
				open_scoreboard()
			1:
				open_chat()
			2:
				coop.open()
			3:
				coop.session.release_disconnect_pause()
			4:
				coop.confirm_leave()
			5:
				select_land("land_buy")
			6:
				select_land("land_offer")
			7:
				open_offers()
	)
	scoreboard = make_window("Scoreboard")
	score_rows = content(scoreboard)
	chat = make_window("Multiplayer — Chat")
	var chat_body := content(chat)
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.selection_enabled = true
	chat_log.scroll_following = true
	chat_body.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.max_length = 500
	chat_input.placeholder_text = "Nachricht an alle Spieler …"
	chat_body.add_child(chat_input)
	chat_input.text_submitted.connect(func(text: String) -> void:
		coop.session.send_chat(text)
		chat_input.clear())
	coop.session.chat_received.connect(receive_chat)
	coop.session.presence_received.connect(func(value: Array) -> void:
		players = value
		overlay.queue_redraw())
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coop.app.map_view.add_child(overlay)
	overlay.draw.connect(draw_markers)
	coop.app.map_view.viewport_changed.connect(overlay.queue_redraw)
	alarm = AudioStreamPlayer.new()
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050)
	for index in 11025:
		var frequency := 660.0 if index < 5512 else 880.0
		var envelope := sin(PI * fmod(float(index), 5512.0) / 5512.0)
		samples.encode_s16(index * 2, int(sin(TAU * frequency * index / 22050.0) * envelope * 6000.0))
	wave.data = samples
	alarm.stream = wave
	coop.app.add_child(alarm)


func make_window(title: String) -> Window:
	var window := Window.new()
	window.title = title
	window.theme = AppUiTheme.current()
	window.size = Vector2i(680, 400)
	window.min_size = Vector2i(420, 240)
	window.visible = false
	window.close_requested.connect(window.hide)
	coop.app.add_child(window)
	return window


func content(window: Window) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


func open_scoreboard() -> void:
	refresh_scores()
	scoreboard.popup_centered()


func update_state(value: Dictionary) -> void:
	state = value
	players = value.get("roster", players)
	if scoreboard.visible:
		refresh_scores()
	overlay.queue_redraw()
	var pending: String = str(value.get("pending", ""))
	var active_disaster := int(value.get("disaster", 0))
	if active_disaster != 0 and own_disaster == 0:
		coop.app.effects_audio.play_sound_ids([520])
		coop.show_message("Katastrophe in deiner Stadt: Einsatzkräfte über die normale Werkzeugleiste entsenden.")
	own_disaster = active_disaster
	if pending == "annual_budget":
		coop.show_message("Der Jahreshaushalt wartet auf Bestätigung unter Windows → Budget.")
	var key := pending + str(value.get("policy", 0)) if value.get("blocked", false) else ""
	if key != decision_key:
		decision_key = key
		if is_instance_valid(decision_dialog):
			decision_dialog.queue_free()
		if pending == "military_proposal":
			coop.refresh_budget()
			coop.app.budget.open_military_proposal()
		elif not key.is_empty() and pending != "annual_budget":
			decision_dialog = AcceptDialog.new()
			decision_dialog.dialog_text = "Die Mitteilung der Militärverwaltung bestätigen und fortsetzen." if pending == "military_notice" else "Die Simulation hat eine abschließende Meldung. Bestätigen, um die Stadt weiter zu betrachten."
			coop.app.add_child(decision_dialog)
			var policy: int = int(value.get("policy", 0))
			decision_dialog.confirmed.connect(func() -> void: coop.session.request({"kind": "decision", "accept": true, "policy": policy}))
			decision_dialog.popup_centered()
	var disasters: Array = value.get("disasters", [])
	for disaster: Dictionary in disasters:
		if disaster.owner == coop.session.token.sha256_text() or known_disasters.has(disaster.owner):
			continue
		var name := "Nachbarstadt"
		for item: Dictionary in players:
			if item.get("id") == disaster.owner:
				name = str(item.name)
		coop.show_message("Katastrophe bei %s — Gebiet (%d, %d). Eigene Einsatzkräfte können helfen." % [name, int(disaster.point[0]), int(disaster.point[1])])
		if coop.app.document_state.city != null and coop.app.document_state.city.sound_enabled():
			alarm.volume_db = linear_to_db(clampf(float(coop.app.preferences.effects_volume), 0.0, 1.0))
			alarm.play()
	known_disasters.clear()
	for disaster: Dictionary in disasters:
		known_disasters.append(disaster.owner)


func refresh_scores() -> void:
	for child in score_rows.get_children():
		score_rows.remove_child(child)
		child.queue_free()
	var shared: bool = state.get("mode", "coop") == "shared"
	ApplicationMultiplayer.label(score_rows, "Spieler · Verbindung · Bauaktionen · Bauausgaben" + (" · Einwohner · Kasse" if shared else ""))
	for item: Dictionary in players:
		var line := ApplicationMultiplayer.label(score_rows, "%s · %s · %d · $%d" % [
			str(item.get("name", "")), "Verbunden" if item.get("online", false) else "Getrennt",
			int(item.get("builds", 0)), int(item.get("spent", 0))] + (" · %d · $%d" % [int(item.get("population", 0)), int(item.get("funds", 0))] if shared else ""))
		line.add_theme_color_override("font_color", Color(CoopSession.valid_color(item.get("color"))))
	if coop.mirrored and state.get("mode", "coop") == "coop":
		var city := coop.app.document_state.city
		ApplicationMultiplayer.label(score_rows, "Gemeinsame Stadt: %d Einwohner · Kasse $%d" % [city.population(), city.funds()])


func open_chat() -> void:
	unread = 0
	menu.get_popup().set_item_text(1, "Chat")
	chat.popup_centered()
	chat_input.grab_focus()


func receive_chat(entry: Dictionary) -> void:
	chat_log.push_color(Color(CoopSession.valid_color(entry.get("color"))))
	chat_log.add_text(str(entry.get("name", "")) + ": ")
	chat_log.pop()
	chat_log.add_text(str(entry.get("text", "")) + "\n")
	if chat_log.get_line_count() > 250:
		chat_log.remove_paragraph(0)
	if not chat.visible:
		unread += 1
		menu.get_popup().set_item_text(1, "Chat (%d)" % unread)


func draw_markers() -> void:
	if not coop.active() or not coop.mirrored:
		return
	var map := coop.app.map_view
	var scale: float = map.camera._view_scale()
	var offset: Vector2 = map.camera._draw_offset(scale)
	var font := ThemeDB.fallback_font
	if state.get("mode") == "shared":
		update_territories()
		overlay.draw_set_transform(offset, 0.0, Vector2.ONE * scale)
		for id: String in territory_lines:
			for item: Dictionary in players:
				if item.get("id") == id:
					overlay.draw_multiline(territory_lines[id], Color(CoopSession.valid_color(item.get("color")), 0.6), 1.5 / scale, true)
		overlay.draw_set_transform(Vector2.ZERO)
	for item: Dictionary in players:
		if not item.get("online", false) or item.get("id") == coop.session.token.sha256_text():
			continue
		var position: Variant = item.get("cursor")
		if not position is Array or position.size() != 2:
			continue
		var target := Vector2i(int(position[0]), int(position[1]))
		if map.city.index_of(target.x, target.y) < 0:
			continue
		var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, target.x, target.y)
		if polygon.size() != 4:
			continue
		var center := (polygon[0] + polygon[1] + polygon[2] + polygon[3]) * 0.25 * scale + offset
		var color := Color(CoopSession.valid_color(item.get("color")))
		overlay.draw_circle(center, 6, color)
		overlay.draw_string_outline(font, center + Vector2(10, -5), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		overlay.draw_string(font, center + Vector2(10, -5), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	for unit: Dictionary in state.get("dispatch_owners", {}).values():
		var target := Vector2i(int(unit.position[0]), int(unit.position[1]))
		var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, target.x, target.y)
		for item: Dictionary in players:
			if item.get("id") != unit.get("actor"):
				continue
			var outline := PackedVector2Array()
			for point in polygon:
				outline.append(point * scale + offset)
			if not outline.is_empty():
				outline.append(outline[0])
				overlay.draw_polyline(outline, Color(CoopSession.valid_color(item.get("color"))), 3.0, true)
				if target == map.hover_tile:
					overlay.draw_string_outline(font, outline[0] + Vector2(8, -8), str(item.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
					overlay.draw_string(font, outline[0] + Vector2(8, -8), str(item.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(CoopSession.valid_color(item.get("color"))))


func close() -> void:
	chat.hide()
	chat_log.clear()
	scoreboard.hide()
	players.clear()
	state.clear()
	known_disasters.clear()
	own_disaster = 0
	decision_key = ""
	if is_instance_valid(decision_dialog):
		decision_dialog.queue_free()
	land_action = ""
	unread = 0
	menu.get_popup().set_item_text(1, "Chat")
	territory_key.clear()
	territory_lines.clear()
	overlay.queue_redraw()


func update_territories() -> void:
	var city := coop.app.document_state.city
	var ownership: Array = state.get("owners", [])
	var key := [ownership.hash(), city.chunk_revision("ALTM"), city.compass_rotation()]
	if key == territory_key:
		return
	territory_key = key
	territory_lines.clear()
	var ids: Array = state.get("owner_ids", [])
	for tile in ownership.size():
		var owner := int(ownership[tile])
		if owner <= 0 or owner > ids.size():
			continue
		@warning_ignore("integer_division")
		var point := Vector2i(tile / city.map_size, tile % city.map_size)
		var border := false
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = point + direction
			var index := city.index_of(neighbor.x, neighbor.y)
			if index < 0 or int(ownership[index]) != owner:
				border = true
		if not border:
			continue
		var polygon := CityIsometricRenderer.terrain_surface_polygon(city, point.x, point.y)
		var lines: PackedVector2Array = territory_lines.get(ids[owner - 1], PackedVector2Array())
		for edge in polygon.size():
			lines.append(polygon[edge])
			lines.append(polygon[(edge + 1) % polygon.size()])
		territory_lines[ids[owner - 1]] = lines


func select_land(action: String) -> void:
	if state.get("mode") != "shared":
		coop.show_message("Landhandel ist im Shared-Modus verfügbar.")
		return
	land_action = action
	land_offer_price = -1
	coop.app.current_tool.select_tool_group(CityToolIds.Group.RESIDENTIAL)
	coop.show_message("Markiere das gewünschte Gebiet. Der Preis wird vor dem Kauf bestätigt.")
	if action == "land_offer":
		var window := make_window("Verkaufspreis")
		var body := content(window)
		var price := SpinBox.new()
		price.max_value = 2147483647
		body.add_child(price)
		ApplicationMultiplayer.button(body, "Preis festlegen und Gebiet markieren", func() -> void:
			land_offer_price = int(price.value)
			window.queue_free())
		window.popup_centered()


func open_offers() -> void:
	var window := make_window("Landangebote")
	var body := content(window)
	for offer: Dictionary in state.get("offers", []):
		ApplicationMultiplayer.button(body, "%s: %d Felder für $%d kaufen" % [offer.name, offer.count, offer.price], func() -> void:
			coop.session.request({"kind": "land_accept", "offer": offer.id})
			window.queue_free())
	window.popup_centered()
