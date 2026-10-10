class_name MultiplayerGoalHud
extends RefCounted
## Per-city goal and continuous-hold progress; presentation only.

var panel: PanelContainer
var title: Button
var rows: VBoxContainer
var signature := ""

func _init(windows: MultiplayerWindows) -> void:
	panel = PanelContainer.new()
	panel.z_index = 2
	panel.theme = AppUiTheme.current()
	windows.coop.app.map_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var body := VBoxContainer.new()
	panel.add_child(body)
	title = ApplicationMultiplayer.button(body, "", windows.open_scoreboard)
	title.tooltip_text = tr("Open scoreboard")
	title.clip_text = true
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	body.add_child(rows)
	panel.hide()

func layout(view: Rect2) -> void:
	panel.size = Vector2(minf(320, maxf(0, view.size.x - 16)), panel.get_combined_minimum_size().y)
	panel.position = Vector2(view.end.x - panel.size.x - 8, view.position.y + 8)

static func value(player: Dictionary, kind: String) -> int:
	return int(player.get("population", 0)) if kind == "population" else int(player.get("funds", 0)) - int(player.get("debt", 0))

func update(state: Dictionary, _actor: String) -> void:
	panel.visible = state.get("mode") in ["shared", "region"] and not state.get("lobby", {}).get("waiting", false)
	if not panel.visible:
		return
	var goal: Dictionary = state.get("goal", {})
	var kind: String = goal.get("kind", "endless")
	var endless: bool = kind == "endless" or goal.get("unscored", false)
	var visible_players: Array = []
	for player: Dictionary in state.get("roster", []):
		visible_players.append([player.id, player.name, player.get("color"), player.get("ranked", true), value(player, kind)])
	var key := JSON.stringify([goal, visible_players, TranslationServer.get_locale()])
	if key == signature:
		return
	signature = key
	title.text = tr("Endless game · no scoring") if goal.get("unscored", false) else tr("Endless game") if endless else "%s · %s" % [tr("Population") if kind == "population" else tr("Net wealth"), number(int(goal.get("target", 1)), kind)]
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if endless:
		return
	var target := maxi(1, int(goal.get("target", 1)))
	var required := maxi(1, int(goal.get("hold_days", 300)))
	for player: Dictionary in state.get("roster", []):
		var current := value(player, kind)
		var ranked: bool = player.get("ranked", true)
		var days := mini(required, int(goal.get("holding", {}).get(player.id, {}).get("days", 0)))
		var color := Color.from_string(player.get("color", "46b4ff"), Color.WHITE) if ranked else Color(0.5, 0.5, 0.5)
		var row := Control.new()
		row.custom_minimum_size.y = 26
		rows.add_child(row)
		var progress := bar(row, Color(color, 0.6), clampf(float(current) / target, 0, 1))
		if current >= target and ranked:
			bar(row, Color(color, 1.0), float(days) / required, true)
		var text := Label.new()
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 6
		text.offset_right = -6
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		text.add_theme_color_override("font_color", Color.WHITE)
		text.add_theme_color_override("font_outline_color", Color.BLACK)
		text.add_theme_constant_override("outline_size", 4)
		text.text = "%s · %s" % [player.name, ("%d / %d d" % [days, required]) if current >= target and ranked else "%d%%" % int(progress.value)]
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		row.tooltip_text = "%s: %s / %s\n%s" % [player.name, number(current, kind), number(target, kind), tr("Target held: %d / %d game days") % [days, required] if ranked else tr("Unranked · city founded after the start")]
	panel.tooltip_text = tr("Stay at or above the target for one full game year. Dropping below resets the timer.")

static func bar(parent: Control, color: Color, fraction: float, transparent := false) -> ProgressBar:
	var result := ProgressBar.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.show_percentage = false
	result.value = fraction * 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	result.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color.TRANSPARENT if transparent else Color(0.08, 0.1, 0.12, 0.9)
	result.add_theme_stylebox_override("background", background)
	parent.add_child(result)
	return result

static func number(amount: int, kind: String) -> String:
	return MultiplayerScoreboard.money(amount) if kind == "wealth" else str(amount)
