class_name MultiplayerLandMarket
extends RefCounted
## Exact parcels and prices always require the other party's consent.
@warning_ignore_start("integer_division")
var windows_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return windows_ref.get_ref()
var window: Window
var body: VBoxContainer
var entries_box: VBoxContainer
var tabs: MultiplayerTabs
var signature := ""
var known: Dictionary = {}
var initialized := false
var unread := 0
var detail: Window
var map_detail: PanelContainer

func _init(owner: MultiplayerWindows) -> void:
	windows_ref = weakref(owner)

func refresh(state: Dictionary) -> void:
	var entries: Array = state.get("offers", []).duplicate(true)
	entries.append_array(state.get("land_history", []))
	var current := JSON.stringify(entries)
	if current == signature:
		return
	signature = current
	var identity := windows.coop.session.token.sha256_text()
	for record: Dictionary in entries:
		var key := str(record.id) + str(record.status)
		if initialized and not known.has(key) and (identity in [record.seller, record.buyer] or record.buyer == ""):
			unread += 1
		known[key] = true
	initialized = true
	var popup := windows.menu.get_popup()
	popup.set_item_text(popup.get_item_index(7), tr("Land trade") + (" · %d" % unread if unread > 0 else ""))
	if is_instance_valid(window) and window.visible:
		rebuild()

func open() -> void:
	if not is_instance_valid(window):
		window = windows.make_window(tr("Land trade"))
		window.size.x = 760
		body = windows.content(window)
		tabs = MultiplayerTabs.new()
		body.add_child(tabs)
		for title in ["Inbox", "Outbox", "History"]:
			tabs.add_item(tr(title))
		tabs.item_selected.connect(func(_index: int) -> void: rebuild())
		entries_box = VBoxContainer.new()
		body.add_child(entries_box)
	unread = 0
	windows.menu.get_popup().set_item_text(windows.menu.get_popup().get_item_index(7), tr("Land trade"))
	rebuild()
	window.popup_centered()

func rebuild() -> void:
	for child in entries_box.get_children():
		entries_box.remove_child(child)
		child.queue_free()
	var identity := windows.coop.session.token.sha256_text()
	var entries: Array = windows.state.get("offers", []).duplicate(true)
	entries.append_array(windows.state.get("land_history", []))
	var count := 0
	for record: Dictionary in entries:
		var closed: bool = record.status != "Open"
		var mine: bool = record.get("initiator", record.seller) == identity
		var relevant: bool = identity in [record.seller, record.buyer] or record.buyer == ""
		if not relevant or (tabs.selected == 2) != closed or (not closed and (tabs.selected == 1) != mine):
			continue
		count += 1
		var panel := PanelContainer.new()
		panel.theme = AppUiTheme.current()
		var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_width_left = 4
		style.border_color = Color("ffa451") if record.buyer != "" else Color("65c78e")
		style.content_margin_left = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)
		entries_box.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var request: bool = record.buyer != "" and record.get("initiator") == record.buyer
		ApplicationMultiplayer.label(box, "↔ " + tr("Purchase request") if request else "▣ " + tr("Land sale offer"))
		var parties := RichTextLabel.new()
		parties.fit_content = true
		parties.scroll_active = false
		box.add_child(parties)
		for id: String in [record.seller, record.buyer]:
			if id == record.buyer:
				parties.add_text(" → ")
			if id.is_empty():
				parties.add_text(tr("Any player"))
			for player: Dictionary in windows.players:
				if player.id == id:
					parties.push_color(Color(CoopSession.valid_color(player.color)))
					parties.add_text(str(player.name) + " · " + str(player.city) + "  ")
					parties.pop()
		ApplicationMultiplayer.label(box, tr("%d tiles · %s: %s · %s per tile") % [record.count, tr("You receive") if identity == record.seller else tr("You pay"), MultiplayerScoreboard.money(record.price), ("≈ " if int(record.price) % maxi(1, int(record.count)) != 0 else "") + MultiplayerScoreboard.money(int(record.price) / maxi(1, int(record.count)))])
		ApplicationMultiplayer.label(box, "◷ " + ((tr("Your response required") if record.get("awaiting") == identity else tr("Awaiting response")) if not closed else tr(record.status)))
		var actions := HFlowContainer.new()
		box.add_child(actions)
		add_action(actions, tr("Show on map"), func() -> void: show_on_map(record))
		add_action(actions, tr("Review"), func() -> void: review(record))
	if count == 0:
		ApplicationMultiplayer.label(entries_box, tr("No entries."))
	windows.fit_content.call_deferred(window, body, 760)

func parcel_preview(parent: Control, tiles: Array) -> void:
	var city := windows.coop.app.document_state.city
	var image := CityMinimap.create_image(city, windows.coop.app.asset_state.palette)
	for tile: int in tiles:
		var point := Vector2i(tile / city.map_size, tile % city.map_size)
		point = Vector2i(Vector2(point) * float(image.get_width()) / city.map_size)
		image.set_pixelv(point, Color("ffe16b"))
	var preview := TextureRect.new()
	preview.texture = ImageTexture.create_from_image(image)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(180, 160)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(preview)

func review(record: Dictionary) -> void:
	if is_instance_valid(detail):
		detail.queue_free()
	detail = windows.make_window(tr("Review land trade"))
	var box := windows.content(detail)
	parcel_preview(box, record.tiles)
	var identity := windows.coop.session.token.sha256_text()
	var receive: bool = identity == record.seller
	var funds := windows.coop.app.document_state.city.funds()
	ApplicationMultiplayer.label(box, tr("%d tiles · %s: %s") % [record.count, tr("You receive") if receive else tr("You pay"), MultiplayerScoreboard.money(record.price)])
	ApplicationMultiplayer.label(box, tr("Balance after transfer: %s") % MultiplayerScoreboard.money(funds + int(record.price) * (1 if receive else -1)))
	var actions := HFlowContainer.new()
	box.add_child(actions)
	add_action(actions, tr("Show on map"), func() -> void: show_on_map(record))
	if record.status == "Open":
		var awaiting: String = record.get("awaiting", "")
		if identity == awaiting or (awaiting.is_empty() and identity != record.seller):
			add_action(actions, tr("Accept"), func() -> void: submit_record("land_accept", record))
			add_action(actions, tr("Counteroffer"), func() -> void: counter(record))
			if not str(record.buyer).is_empty():
				add_action(actions, tr("Decline"), func() -> void: submit_record("land_decline", record))
		if identity == record.get("initiator", record.seller):
			add_action(actions, tr("Change price"), func() -> void: counter(record))
			add_action(actions, tr("Withdraw"), func() -> void: submit_record("land_withdraw", record))
	detail.popup_centered()

func confirm(record: Dictionary) -> void:
	review(record)

func submit_record(kind: String, record: Dictionary) -> void:
	windows.coop.session.request({"kind": kind, "offer": record.id})
	if is_instance_valid(detail):
		detail.hide()

func counter(record: Dictionary) -> void:
	var dialog := windows.make_window(tr("Counteroffer"))
	var box := windows.content(dialog)
	ApplicationMultiplayer.label(box, tr("Total price · the other player must confirm"))
	var price := SpinBox.new()
	price.max_value = 2147483647
	price.value = record.price
	box.add_child(price)
	add_action(box, tr("Send counteroffer"), func() -> void:
		windows.coop.session.request({"kind": "land_counter", "offer": record.id, "price": int(price.value)})
		dialog.queue_free()
		detail.hide())
	dialog.popup_centered()

func show_on_map(record: Dictionary) -> void:
	var map := windows.coop.app.map_view
	windows.map_overlay.highlight = record.tiles.duplicate()
	windows.map_overlay.highlight_until = Time.get_ticks_msec() + 3600000
	windows.coop.app.camera_input.center_map_on_tile(tile_bounds(record.tiles, map.city.map_size).get_center())
	if is_instance_valid(window):
		window.hide()
	if is_instance_valid(detail):
		detail.hide()
	if is_instance_valid(map_detail):
		map_detail.queue_free()
	map_detail = PanelContainer.new()
	map_detail.z_index = 3
	map.add_child(map_detail)
	map_detail.position = map.camera_view_rect.position + Vector2(12, 12)
	var box := VBoxContainer.new()
	map_detail.add_child(box)
	ApplicationMultiplayer.label(box, tr("%s · %d tiles · %s") % [record.name, record.count, MultiplayerScoreboard.money(record.price)])
	add_action(box, tr("Review"), func() -> void: review(record))
	add_action(box, tr("Close"), func() -> void:
		windows.map_overlay.highlight.clear()
		map_detail.queue_free())

func select_parcel(start: Vector2i, finish: Vector2i) -> void:
	var state := windows.state
	var owners: Array = state.get("owners", [])
	var ids: Array = state.get("owner_ids", [])
	var city := windows.coop.app.document_state.city
	var groups := {}
	for x in range(maxi(0, mini(start.x, finish.x)), mini(city.map_size - 1, maxi(start.x, finish.x)) + 1):
		for y in range(maxi(0, mini(start.y, finish.y)), mini(city.map_size - 1, maxi(start.y, finish.y)) + 1):
			var tile := city.index_of(x, y)
			var owner := int(owners[tile])
			if not groups.has(owner):
				groups[owner] = []
			groups[owner].append(tile)
	if groups.has(0) and windows.land_action == "land_buy":
		windows.coop.session.request({"kind": "land_buy", "start": [start.x, start.y], "finish": [finish.x, finish.y], "include_water": windows.include_water})
		return
	groups.erase(0)
	if groups.size() == 1:
		var owner: int = groups.keys()[0]
		open_parcel(owner, groups[owner], start, finish)
	elif groups.size() > 1:
		var chooser := windows.make_window(tr("Choose a parcel"))
		var box := windows.content(chooser)
		ApplicationMultiplayer.label(box, tr("This selection contains several owners. Choose one parcel to negotiate."))
		for owner: int in groups:
			var name := ""
			for player: Dictionary in windows.players:
				if player.id == ids[owner - 1]:
					name = player.name
			add_action(box, tr("%s · %d tiles") % [name, groups[owner].size()], func() -> void:
				open_parcel(owner, groups[owner], start, finish)
				chooser.queue_free())
		chooser.popup_centered()

func open_parcel(owner: int, tiles: Array, start: Vector2i, finish: Vector2i) -> void:
	var name := ""
	for player: Dictionary in windows.players:
		if player.id == windows.state.owner_ids[owner - 1]:
			name = player.name
	var dialog := windows.make_window(tr("Offer land") if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else tr("Request land"))
	var box := windows.content(dialog)
	parcel_preview(box, tiles)
	ApplicationMultiplayer.label(box, tr("%s · %d tiles") % [name, tiles.size()])
	ApplicationMultiplayer.label(box, tr("Total price"))
	var price := SpinBox.new()
	price.max_value = 2147483647
	price.value = tiles.size() * int(windows.state.get("land_price", 0))
	box.add_child(price)
	add_action(box, tr("Publish offer") if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else tr("Send request"), func() -> void:
		windows.coop.session.request({"kind": "land_offer" if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else "land_request", "start": [start.x, start.y], "finish": [finish.x, finish.y], "tiles": tiles, "price": int(price.value)})
		dialog.queue_free())
	dialog.popup_centered()
static func tile_bounds(tiles: Array, size: int) -> Rect2i:
	var result := Rect2i()
	var first := true
	for tile: int in tiles:
		var point := Vector2i(tile / size, tile % size)
		result = Rect2i(point, Vector2i.ONE) if first else result.merge(Rect2i(point, Vector2i.ONE))
		first = false
	return result

static func add_action(parent: Control, title: String, action: Callable) -> void:
	ApplicationMultiplayer.button(parent, title, action)
