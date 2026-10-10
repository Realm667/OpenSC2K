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

func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	window = windows.make_window(tr("Game lobby"))
	window.size = Vector2i(660, 430)
	window.min_size = Vector2i(400, 300)
	var body := windows.content(window)
	summary = ApplicationMultiplayer.label(body, "")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster = Tree.new()
	roster.hide_root = true
	roster.columns = 3
	roster.column_titles_visible = true
	roster.scroll_horizontal_enabled = false
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	if not lobby.get("waiting", false):
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
	roster.clear()
	var root := roster.create_item()
	for player: Dictionary in state.get("roster", []):
		var row := roster.create_item(root)
		row.set_text(0, player.name)
		row.set_custom_color(0, Color.from_string(player.color, Color.WHITE))
		row.set_text(1, player.city)
		row.set_text(2, tr("Offline") if not player.online else tr("Ready") if player.get("ready", false) else tr("Not ready"))
		for column in 3:
			row.set_tooltip_text(column, row.get_text(column))
		if player.id == session.token.sha256_text():
			own_ready = player.get("ready", false)
	ready.text = tr("Not ready") if own_ready else tr("Ready")
	start.visible = session.hosting
	start.disabled = not lobby.get("can_start", false)
	if not window.visible:
		window.popup_centered.call_deferred()
