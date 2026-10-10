class_name MultiplayerSeatWindow
extends RefCounted

var owner_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return owner_ref.get_ref()
var window: Window
var body: VBoxContainer
var lobby: Dictionary = {}
var city_name := ""


func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	window = windows.make_window("Player seats")
	body = windows.content(window)
	windows.coop.session.seat_lobby_received.connect(receive_lobby)
	windows.coop.session.seats_changed.connect(func() -> void:
		refresh()
		for entry: Dictionary in windows.coop.session.seats.pending.values():
			if not str(entry.seat).is_empty() and not window.visible:
				window.popup_centered()
				break)


func receive_lobby(data: Dictionary) -> void:
	lobby = data
	windows.coop.panel.hide()
	refresh()
	window.popup_centered()


func open() -> void:
	refresh()
	window.popup_centered()


func refresh() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var session := windows.coop.session
	if session.hosting:
		add_text(tr("Disconnected seats remain reserved until you approve a replacement."))
		for row: Dictionary in session.roster():
			add_text("%s · %s · %s" % [row.name, row.city, status(row.seat_status)])
		for peer: int in session.seats.pending:
			var request: Dictionary = session.seats.pending[peer]
			if str(request.seat).is_empty():
				continue
			add_text(tr("%s requests the seat of %s.") % [request.name, session.members[request.seat].name])
			var row := HBoxContainer.new()
			body.add_child(row)
			ApplicationMultiplayer.button(row, tr("Approve takeover"), func() -> void: session.seats.decide(peer, true))
			ApplicationMultiplayer.button(row, tr("Decline takeover"), func() -> void: session.seats.decide(peer, false))
	elif session.connected:
		for row: Dictionary in session.latest.get("roster", []):
			add_text("%s · %s · %s" % [row.name, row.city, status(row.get("seat_status", "reserved"))])
	else:
		add_text(tr("Choose a new player seat or request an unoccupied seat. The host must approve takeovers."))
		if lobby.get("waiting", false):
			add_text(tr("Waiting for the host to approve your seat request."))
		if lobby.get("shared", false):
			var field := ApplicationMultiplayer.field(body, tr("Name of your new city"), city_name)
			field.placeholder_text = windows.coop.player.text
			field.max_length = Sc2xMetadata.MAX_NAME_CODE_POINTS
			field.text_changed.connect(func(value: String) -> void: city_name = value)
		var create := ApplicationMultiplayer.button(body, tr("Create new player seat"), func() -> void: choose("new"))
		create.disabled = not lobby.get("new_allowed", false)
		for seat: Dictionary in lobby.get("seats", []):
			var text := "%s · %s · %s" % [seat.name, seat.city, status(seat.status)]
			ApplicationMultiplayer.button(body, tr("Request seat: %s") % text, func() -> void: choose(seat.id))
		ApplicationMultiplayer.button(body, tr("Cancel joining"), windows.coop.leave)


func choose(id: String) -> void:
	var session := windows.coop.session
	if session.active and not session.connected and session.channels.has(0):
		session.channels[0].send({"type": "seat_choice", "seat": id, "city_name": city_name})
		session.channels[0].flush()


func add_text(value: String) -> void:
	var label := ApplicationMultiplayer.label(body, value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func status(value: String) -> String:
	match value:
		"connected":
			return TranslationServer.translate("Connected")
		"unoccupied":
			return TranslationServer.translate("Unoccupied")
	return TranslationServer.translate("Reserved for reconnection")
