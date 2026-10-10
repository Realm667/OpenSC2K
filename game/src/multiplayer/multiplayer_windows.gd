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
var chat: PanelContainer
var scores := MultiplayerScoreboard.new()
var market: MultiplayerLandMarket
var map_overlay := MultiplayerMapOverlay.new()
var land_button: Button
var chat_seen: Dictionary = {}
var event_seen: Dictionary = {}
var tones: Dictionary = {}
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
var own_disaster := 0
var decision_key := ""
var decision_dialog: AcceptDialog


func _init(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)


func setup() -> void:
	MultiplayerText.setup()
	var row := coop.app.city_menu_bar.newspaper_menu.get_parent()
	menu = MenuButton.new()
	menu.text = "Multiplayer"
	row.add_child(menu)
	row.move_child(menu, coop.app.city_menu_bar.newspaper_menu.get_index() + 1)
	var popup := menu.get_popup()
	for title in ["Scoreboard", "Chat", "Host / Join game", "Release disconnect pause", "Leave game", "Buy land", "Offer land", "Land offers"]:
		popup.add_item(tr(title))
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
	scoreboard.size = Vector2i(1080, 520)
	scores.setup(score_rows)
	market = MultiplayerLandMarket.new(self)
	chat = PanelContainer.new()
	chat.theme = AppUiTheme.current()
	chat.mouse_filter = Control.MOUSE_FILTER_STOP
	coop.app.map_view.add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chat.offset_left = 8
	chat.offset_right = 408
	chat.offset_top = -184
	chat.offset_bottom = -8
	chat.hide()
	var chat_body := VBoxContainer.new()
	chat.add_child(chat_body)
	var heading := HBoxContainer.new()
	chat_body.add_child(heading)
	var title := ApplicationMultiplayer.label(heading, tr("Multiplayer chat"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hide_button := Button.new()
	hide_button.text = "−"
	hide_button.tooltip_text = tr("Hide chat")
	heading.add_child(hide_button)
	hide_button.pressed.connect(chat.hide)
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.selection_enabled = true
	chat_log.scroll_following = true
	chat_body.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.max_length = 500
	chat_input.placeholder_text = tr("Message all players…")
	chat_body.add_child(chat_input)
	chat_input.text_submitted.connect(func(text: String) -> void:
		coop.session.send_chat(text)
		chat_input.clear())
	chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			chat_input.release_focus()
			chat_input.accept_event())
	coop.session.chat_received.connect(receive_chat)
	coop.session.player_event.connect(receive_player_event)
	coop.session.presence_received.connect(func(value: Array) -> void:
		players = value
		map_overlay.receive(value)
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
	for kind in ["chat", "joined", "left"]:
		var player := AudioStreamPlayer.new()
		player.max_polyphony = 4
		player.stream = cue(kind)
		coop.app.add_child(player)
		tones[kind] = player
	land_button = Button.new()
	land_button.icon = preload("res://assets/ui/buy_land.svg")
	land_button.theme_type_variation = "ArtworkButton"
	land_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	land_button.custom_minimum_size = Vector2(32, 32)
	land_button.toggle_mode = true
	land_button.tooltip_text = tr("Buy land")
	land_button.hide()
	var signs := coop.app.city_toolbar.toolbar_buttons[CityToolIds.Group.SIGNS]
	signs.get_parent().add_child(land_button)
	signs.get_parent().move_child(land_button, signs.get_index())
	land_button.pressed.connect(func() -> void: select_land("land_buy"))
	coop.app.get_tree().process_frame.connect(tick)


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
	if state.is_empty():
		chat.show()
	state = value
	players = value.get("roster", players)
	map_overlay.receive(players)
	land_button.visible = value.get("mode") == "shared"
	land_button.get_parent().columns = 3 if land_button.visible else 2
	market.refresh(value)
	if scoreboard.visible:
		refresh_scores()
	overlay.queue_redraw()
	var pending: String = str(value.get("pending", ""))
	var active_disaster := int(value.get("disaster", 0))
	if active_disaster != 0 and own_disaster == 0:
		coop.app.effects_audio.play_sound_ids([520])
		coop.show_message(tr("Disaster in your city: deploy emergency services from the normal toolbar."))
	own_disaster = active_disaster
	if pending == "annual_budget":
		coop.show_message(tr("The annual budget awaits confirmation under Windows → Budget."))
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
			decision_dialog.dialog_text = tr("Acknowledge the military administration notice to continue.") if pending == "military_notice" else tr("The simulation has a final notice. Acknowledge it to continue viewing the city.")
			coop.app.add_child(decision_dialog)
			var policy: int = int(value.get("policy", 0))
			decision_dialog.confirmed.connect(func() -> void: coop.session.request({"kind": "decision", "accept": true, "policy": policy}))
			decision_dialog.popup_centered()
	var disasters: Array = value.get("disasters", [])
	for disaster: Dictionary in disasters:
		if disaster.owner == coop.session.token.sha256_text() or known_disasters.has(disaster.owner):
			continue
		var name := tr("Neighbouring city")
		for item: Dictionary in players:
			if item.get("id") == disaster.owner:
				name = str(item.name)
		coop.show_message(tr("Disaster at %s — area (%d, %d). Your emergency services can help.") % [name, int(disaster.point[0]), int(disaster.point[1])])
		if coop.app.document_state.city != null and coop.app.document_state.city.sound_enabled():
			alarm.volume_db = linear_to_db(clampf(float(coop.app.preferences.effects_volume), 0.0, 1.0))
			alarm.play()
	known_disasters.clear()
	for disaster: Dictionary in disasters:
		known_disasters.append(disaster.owner)


func refresh_scores() -> void:
	scores.update(players, state.get("mode") == "shared", coop.session.token.sha256_text())


func open_chat() -> void:
	unread = 0
	menu.get_popup().set_item_text(1, "Chat")
	chat.show()
	chat_input.grab_focus()


func receive_chat(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if not id.is_empty() and chat_seen.has(id):
		return
	chat_seen[id] = true
	if chat_seen.size() > 512:
		chat_seen.erase(chat_seen.keys()[0])
	if not entry.get("history", false) and entry.get("sender") != coop.session.token.sha256_text():
		play_cue("chat")
		chat.show()
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
		var boundaries := map_overlay.boundaries(coop.app, state)
		overlay.draw_set_transform(offset, 0.0, Vector2.ONE * scale)
		for id: String in boundaries:
			for item: Dictionary in players:
				if item.get("id") == id and not boundaries[id].is_empty():
					overlay.draw_multiline(boundaries[id], Color(CoopSession.valid_color(item.get("color")), 0.8), 1.5 / scale, true)
		if Time.get_ticks_msec() < map_overlay.highlight_until:
			for tile: int in map_overlay.highlight:
				@warning_ignore("integer_division")
				var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, tile / map.city.map_size, tile % map.city.map_size)
				overlay.draw_colored_polygon(polygon, Color(1, 0.95, 0.45, 0.32))
		overlay.draw_set_transform(Vector2.ZERO)
	for item: Dictionary in players:
		if item.get("id") == coop.session.token.sha256_text() or not map_overlay.cursors.has(item.id):
			continue
		var center := MultiplayerMapOverlay.project(map.city, map_overlay.cursors[item.id].position) * scale + offset
		var color := Color(CoopSession.valid_color(item.get("color")))
		overlay.draw_circle(center, 5, color)
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
	chat_seen.clear()
	event_seen.clear()
	map_overlay.cursors.clear()
	map_overlay.cached_key.clear()
	map_overlay.highlight.clear()
	market.initialized = false
	market.known.clear()
	market.signature = ""
	if is_instance_valid(market.window):
		market.window.hide()
	cancel_land()
	land_button.hide()
	land_button.get_parent().columns = 2
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
	overlay.queue_redraw()


func select_land(action: String) -> void:
	if state.get("mode") != "shared":
		coop.show_message(tr("Land trading is available in Shared mode."))
		return
	coop.app.current_tool.select_tool_group(CityToolIds.Group.QUERY)
	land_action = action
	land_offer_price = -1
	coop.app.city_toolbar.land_mode = true
	coop.app.city_toolbar.child_palette.hide()
	for button in coop.app.city_toolbar.toolbar_buttons:
		button.set_pressed_no_signal(false)
	land_button.set_pressed_no_signal(true)
	coop.app.current_tool.update_edit_state()
	coop.show_message(tr("Select an area. Confirm the price before buying or sending a purchase request."))
	if action == "land_offer":
		var window := make_window(tr("Sale price"))
		var body := content(window)
		var price := SpinBox.new()
		price.max_value = 2147483647
		body.add_child(price)
		ApplicationMultiplayer.button(body, tr("Set price and select area"), func() -> void:
			land_offer_price = int(price.value)
			window.queue_free())
		window.popup_centered()


func open_offers() -> void:
	market.open()


func cancel_land() -> void:
	land_action = ""
	coop.app.city_toolbar.land_mode = false
	coop.app.city_toolbar.child_palette.show()
	if is_instance_valid(land_button):
		land_button.set_pressed_no_signal(false)


func tick() -> void:
	if not coop.active() or not coop.mirrored:
		return
	map_overlay.step(coop.app.get_process_delta_time())
	var view: Rect2 = coop.app.map_view.camera_view_rect
	if view.size == Vector2.ZERO:
		view = Rect2(Vector2.ZERO, coop.app.map_view.size)
	chat.offset_left = view.position.x + 8
	chat.offset_right = minf(chat.offset_left + 400, view.end.x - 8)
	chat.offset_top = view.end.y - coop.app.map_view.size.y - 184
	chat.offset_bottom = view.end.y - coop.app.map_view.size.y - 8
	overlay.queue_redraw()


func receive_player_event(event: Dictionary) -> void:
	var id := str(event.get("id", ""))
	if event_seen.has(id):
		return
	event_seen[id] = true
	if event_seen.size() > 256:
		event_seen.erase(event_seen.keys()[0])
	var kind := str(event.get("kind"))
	var text := tr("%s joined the game.") if kind == "joined" else (tr("%s left the game.") if kind == "left" else tr("%s lost the connection. The game is paused."))
	text = text % str(event.get("name", ""))
	chat_log.add_text(text + "\n")
	coop.show_message(text)
	play_cue("joined" if kind == "joined" else "left")


func play_cue(kind: String) -> void:
	var city := coop.app.document_state.city
	if city == null or not city.sound_enabled():
		return
	var player: AudioStreamPlayer = tones[kind]
	player.volume_db = linear_to_db(clampf(float(coop.app.preferences.effects_volume), 0.0, 1.0))
	player.play()


static func cue(kind: String) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(8820)
	for index in 4410:
		var time := index / 22050.0
		var frequency := 1046.5 if kind == "chat" else (523.25 if (index < 2205) == (kind == "joined") else 783.99)
		var envelope := pow(sin(PI * fmod(float(index), 2205.0) / 2205.0), 2)
		data.encode_s16(index * 2, int(sin(TAU * frequency * time) * envelope * 3800))
	wave.data = data
	return wave
