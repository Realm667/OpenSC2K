class_name MultiplayerLandMarket
extends RefCounted

var windows_ref: WeakRef
var window: Window
var body: VBoxContainer
var signature := ""
var known: Dictionary = {}
var initialized := false

func _init(windows: MultiplayerWindows) -> void:
	windows_ref = weakref(windows)

func refresh(state: Dictionary) -> void:
	var entries: Array = state.get("offers", []).duplicate(true)
	entries.append_array(state.get("land_history", []))
	var current := JSON.stringify(entries)
	if current == signature:
		return
	signature = current
	var windows: MultiplayerWindows = windows_ref.get_ref()
	var identity := windows.coop.session.token.sha256_text()
	for record: Dictionary in entries:
		var key := str(record.id) + str(record.status)
		if initialized and not known.has(key) and identity in [record.seller, record.buyer]:
			windows.menu.get_popup().set_item_text(windows.menu.get_popup().get_item_index(7), tr("Land offers") + " •")
			windows.coop.show_message(tr("Land offers updated: %s — %s") % [record.name, (tr("Open land entry") if record.status == "Open" else tr(record.status))])
		known[key] = true
	initialized = true
	if is_instance_valid(window) and window.visible:
		rebuild()

func open() -> void:
	var windows: MultiplayerWindows = windows_ref.get_ref()
	if not is_instance_valid(window):
		window = windows.make_window(tr("Land offers & requests"))
		window.size = Vector2i(850, 560)
		body = windows.content(window)
	windows.menu.get_popup().set_item_text(windows.menu.get_popup().get_item_index(7), tr("Land offers"))
	rebuild()
	window.popup_centered()

func rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var windows: MultiplayerWindows = windows_ref.get_ref()
	var state := windows.state
	var identity := windows.coop.session.token.sha256_text()
	var entries: Array = state.get("offers", []).duplicate(true)
	entries.append_array(state.get("land_history", []))
	ApplicationMultiplayer.label(body, tr("Inspect the highlighted tiles before buying. Foreign land requires its owner's approval."))
	for section in ["Offers", "Purchase requests", "Recent activity"]:
		body.add_child(HSeparator.new())
		var heading := ApplicationMultiplayer.label(body, ("▣  " if section == "Offers" else "↔  " if section == "Purchase requests" else "◷  ") + tr(section))
		heading.add_theme_font_size_override("font_size", 20)
		var count := 0
		for record: Dictionary in entries:
			var closed: bool = record.status != "Open"
			var request: bool = not str(record.buyer).is_empty()
			if (section == "Recent activity") != closed or (not closed and (section == "Purchase requests") != request):
				continue
			if request and identity not in [record.seller, record.buyer]:
				continue
			count += 1
			var panel := PanelContainer.new()
			var style := StyleBoxFlat.new()
			var accent := Color("e6ae59") if request else Color("69b6db")
			style.bg_color = Color(accent, 0.09)
			style.border_color = Color(accent, 0.8)
			style.border_width_left = 4
			style.content_margin_left = 12
			style.content_margin_top = 8
			style.content_margin_bottom = 8
			panel.add_theme_stylebox_override("panel", style)
			body.add_child(panel)
			var box := VBoxContainer.new()
			panel.add_child(box)
			var parties := str(record.name)
			ApplicationMultiplayer.label(box, tr("Purchase request") if request else tr("Land sale offer"))
			if request:
				parties = tr("%s → %s") % [record.buyer_name, record.name]
			ApplicationMultiplayer.label(box, tr("%s · %s tiles · %s · %s") % [parties, MultiplayerScoreboard.number(record.count), MultiplayerScoreboard.money(record.price), (tr("Open land entry") if record.status == "Open" else tr(record.status))])
			var size: int = windows.coop.app.document_state.city.map_size
			var bounds := tile_bounds(record.tiles, size)
			ApplicationMultiplayer.label(box, tr("Area: (%d, %d) to (%d, %d)") % [bounds.position.x, bounds.position.y, bounds.end.x - 1, bounds.end.y - 1])
			var actions := HBoxContainer.new()
			box.add_child(actions)
			add_action(actions, tr("Show on map"), func() -> void:
				windows.map_overlay.highlight = record.tiles.duplicate()
				windows.map_overlay.highlight_until = Time.get_ticks_msec() + 12000
				windows.coop.app.camera_input.center_map_on_tile(bounds.get_center())
				window.hide())
			if closed:
				continue
			if (request and identity == record.seller) or (not request and identity != record.seller):
				add_action(actions, tr("Approve request") if request else tr("Buy"), func() -> void: confirm(record))
			if identity == (record.buyer if request else record.seller):
				add_action(actions, tr("Withdraw request") if request else tr("Withdraw offer"), func() -> void: windows.coop.session.request({"kind": "land_withdraw", "offer": record.id}))
			if request and identity == record.seller:
				add_action(actions, tr("Decline"), func() -> void: windows.coop.session.request({"kind": "land_decline", "offer": record.id}))
		if count == 0:
			ApplicationMultiplayer.label(body, tr("No entries."))

func confirm(record: Dictionary) -> void:
	var windows: MultiplayerWindows = windows_ref.get_ref()
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = tr("Transfer %d tiles for %s between %s and %s?") % [record.count, MultiplayerScoreboard.money(record.price), record.name, record.buyer_name if not str(record.buyer).is_empty() else windows.coop.player.text]
	window.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		windows.coop.session.request({"kind": "land_accept", "offer": record.id})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

static func tile_bounds(tiles: Array, size: int) -> Rect2i:
	var first := true
	var result := Rect2i()
	for tile: int in tiles:
		@warning_ignore("integer_division")
		var point := Vector2i(tile / size, tile % size)
		result = Rect2i(point, Vector2i.ONE) if first else result.merge(Rect2i(point, Vector2i.ONE))
		first = false
	return result

static func add_action(parent: Control, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
