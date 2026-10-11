class_name MultiplayerStartLobby
extends RefCounted
## The host owns readiness and start; this window only submits requests.

var owner_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return owner_ref.get_ref()
var window: Window
var roster: Tree
var summary: Label
var ready: Button
var start: Button
var own_ready := false
var hint: Label
var leave_button: Button
var body: VBoxContainer
var waiting := false
var roster_signature := ""

func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	window = windows.make_window(tr("Game lobby"))
	window.size = Vector2i(660, 430)
	window.min_size = Vector2i(400, 300)
	body = windows.content(window)
	window.visibility_changed.connect(func() -> void:
		if is_instance_valid(windows.chat):
			windows.dock_chat(window.visible and waiting))
	summary = ApplicationMultiplayer.label(body, "")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster = Tree.new()
	roster.hide_root = true
	roster.select_mode = Tree.SELECT_SINGLE
	roster.cell_selected.connect(func() -> void:
		var row := roster.get_selected()
		if row != null and roster.get_selected_column() == 1 and row.is_editable(1):
			roster.edit_selected.call_deferred())
	roster.item_edited.connect(func() -> void:
		var row := roster.get_edited()
		if row != null and roster.get_edited_column() == 1 and row.is_editable(1):
			windows.coop.session.request({"kind": "rename_city", "name": row.get_text(1)})
			roster_signature = "")
	roster.columns = 3
	roster.column_titles_visible = true
	roster.scroll_horizontal_enabled = false
	roster.size_flags_vertical = Control.SIZE_FILL
	roster.set_column_title(0, tr("Player"))
	roster.set_column_title(1, tr("City"))
	roster.set_column_title(2, tr("Status"))
	for column in 3:
		roster.set_column_clip_content(column, true)
	body.add_child(roster)
	hint = ApplicationMultiplayer.label(body, "")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	body.add_child(actions)
	ready = ApplicationMultiplayer.button(actions, tr("Ready"), func() -> void:
		windows.coop.session.request({"kind": "lobby_ready", "ready": not own_ready}))
	start = ApplicationMultiplayer.button(actions, tr("Start game"), func() -> void:
		windows.coop.session.request({"kind": "lobby_start"}))
	leave_button = ApplicationMultiplayer.button(actions, tr("Leave game"), windows.coop.confirm_leave)

func update(state: Dictionary) -> void:
	var lobby: Dictionary = state.get("lobby", {})
	waiting = lobby.get("waiting", false)
	if not waiting:
		window.hide()
		return
	var session := windows.coop.session
	window.title = tr("Game lobby")
	for column in 3:
		roster.set_column_title(column, tr(["Player", "City", "Status"][column]))
	hint.text = tr("At least two players must join. Everyone confirms Ready; the host then starts the game. Changes to the player list reset readiness.")
	start.text = tr("Start game")
	leave_button.text = tr("Leave game")
	var mode := tr("Co-op") if state.get("mode", "coop") == "coop" else tr("Competitive Region") if state.get("mode") == "region" else tr("Competitive Shared")
	var goal: Dictionary = state.get("goal", {})
	var target := tr("Endless game") if goal.get("kind", "endless") == "endless" else "%s: %s" % [tr("Population") if goal.kind == "population" else tr("Net wealth"), MultiplayerGoalHud.number(int(goal.target), goal.kind)]
	summary.text = "%s · %s\n%s" % [mode, target, tr("Simulation and construction begin together after the host starts.")]
	if state.get("mode", "coop") != "coop":
		summary.text += "\n" + tr("Rules are fixed at start: hold the target for one game year; late-founded cities are unranked. Shared starts receive equal land grants.")
	var signature := JSON.stringify(state.get("roster", []).map(func(player: Dictionary) -> Array: return [player.id, player.name, player.city, player.online, player.get("ready", false), player.color]))
	if signature != roster_signature and not editing_city():
		roster_signature = signature
		roster.clear()
		var root := roster.create_item()
		for player: Dictionary in state.get("roster", []):
			var row := roster.create_item(root)
			row.set_text(0, player.name)
			row.set_custom_color(0, Color.from_string(player.color, Color.WHITE))
			row.set_text(1, player.city)
			row.set_text(2, tr("Offline") if not player.online else tr("Ready") if player.get("ready", false) else tr("Not ready"))
			row.set_custom_color(2, Color("66cf79") if player.get("ready", false) and player.online else Color("ff9c40"))
			for column in 3:
				row.set_tooltip_text(column, row.get_text(column))
			if player.id == session.token.sha256_text():
				own_ready = player.get("ready", false)
				row.set_editable(1, true)
				row.set_tooltip_text(1, tr("Click your city name to rename it before the game starts."))
	ready.text = tr("Not ready") if own_ready else tr("Ready")
	start.visible = session.hosting
	start.disabled = not lobby.get("can_start", false)
	roster.custom_minimum_size.y = maxi(80, roster.get_root().get_child_count() * 28 + 32)
	if window.visible:
		windows.fit_content.call_deferred(window, body, 760)
	if not window.visible:
		show_if_waiting.call_deferred()

func show_if_waiting() -> void:
	if waiting and windows.coop.active():
		roster.custom_minimum_size.y = maxi(80, roster.get_root().get_child_count() * 28 + 32)
		window.popup_centered()
		windows.fit_content.call_deferred(window, body, 760)


func editing_city() -> bool:
	# Tree's built-in text editor is an internal popup, not a public is_editing API.
	for child in roster.get_children(true):
		if child is Window and child.visible:
			return true
	return false
