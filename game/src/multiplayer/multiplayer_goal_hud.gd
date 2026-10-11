class_name MultiplayerGoalHud
extends RefCounted
## Per-city target and leadership progress; presentation only.
@warning_ignore_start("integer_division")

var panel: PanelContainer
var title: Label
var owner_ref: WeakRef
var home: Button
var visit_frame: Panel
var rows: VBoxContainer
var signature := ""

func _init(windows: MultiplayerWindows) -> void:
	owner_ref = weakref(windows)
	panel = PanelContainer.new()
	panel.z_index = 2
	panel.theme = AppUiTheme.current()
	windows.coop.app.map_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var goal_icon := TextureRect.new()
	goal_icon.texture = preload("res://src/multiplayer/icons/goal.svg")
	goal_icon.custom_minimum_size = Vector2(20, 20)
	goal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	goal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(goal_icon)
	title = ApplicationMultiplayer.label(heading, "")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size.x = 0
	var stats := ApplicationMultiplayer.button(heading, tr("Statistics"), windows.open_scoreboard)
	stats.icon = preload("res://src/multiplayer/icons/statistics.svg")
	stats.add_theme_constant_override("icon_max_width", 18)
	stats.tooltip_text = tr("Open scoreboard")
	home = ApplicationMultiplayer.button(windows.coop.app.map_view, tr("Return to your city"), func() -> void:
		windows.coop.session.request({"kind": "view_city", "seat": windows.coop.session.token.sha256_text()}))
	home.z_index = 3
	home.hide()
	visit_frame = Panel.new()
	visit_frame.z_index = 1
	visit_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	windows.coop.app.map_view.add_child(visit_frame)
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color.TRANSPARENT
	glow.border_color = Color(0.4, 0.75, 1.0, 0.55)
	glow.set_border_width_all(2)
	glow.shadow_color = Color(0.3, 0.7, 1.0, 0.22)
	glow.shadow_size = 6
	visit_frame.add_theme_stylebox_override("panel", glow)
	visit_frame.hide()
	title.clip_text = true
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	body.add_child(rows)
	panel.hide()

func layout(view: Rect2) -> void:
	panel.size = Vector2(minf(420, maxf(0, view.size.x - 16)), panel.get_combined_minimum_size().y)
	panel.position = Vector2(view.end.x - panel.size.x - 8, view.position.y + 8)
	visit_frame.position = view.position + Vector2(3, 3)
	visit_frame.size = view.size - Vector2(6, 6)
	home.size = home.get_combined_minimum_size()
	home.position = view.end - home.size - Vector2(12, 12)

static func value(player: Dictionary, kind: String) -> int:
	return int(player.get("population", 0)) if kind == "population" else int(player.get("funds", 0)) - int(player.get("debt", 0))

func update(state: Dictionary, _actor: String) -> void:
	home.visible = state.get("visiting", false)
	visit_frame.visible = home.visible
	panel.visible = state.get("mode") in ["shared", "region"] and not state.get("lobby", {}).get("waiting", false)
	if not panel.visible:
		return
	var goal: Dictionary = state.get("goal", {})
	var kind: String = goal.get("kind", "endless")
	var endless: bool = kind == "endless" or goal.get("unscored", false)
	var visible_players: Array = []
	for player: Dictionary in state.get("roster", []):
		visible_players.append([player.id, player.name, player.get("color"), player.get("ranked", true), value(player, kind)])
	var key := JSON.stringify([goal, visible_players, state.get("view_owner"), TranslationServer.get_locale()])
	if key == signature:
		return
	signature = key
	title.text = tr("Endless game · no scoring") if goal.get("unscored", false) else tr("Endless game") if endless else "%s · %s" % [tr("Population") if kind == "population" else tr("Net wealth"), number(int(goal.get("target", 1)), kind)]
	title.text = tr("Game goal") + ": " + title.text
	title.tooltip_text = title.text
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if endless and state.get("mode") != "region":
		return
	var target := maxi(1, int(goal.get("target", 1)))
	var required := maxi(1, int(goal.get("hold_days", 300)))
	for player: Dictionary in state.get("roster", []):
		var current := value(player, kind)
		var ranked: bool = player.get("ranked", true)
		var days := mini(required, int(goal.get("holding", {}).get(player.id, {}).get("days", 0)))
		var color := Color.from_string(player.get("color", "46b4ff"), Color.WHITE) if ranked else Color(0.5, 0.5, 0.5)
		var line := HBoxContainer.new()
		rows.add_child(line)
		var row := Control.new()
		row.custom_minimum_size.y = 20
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(row)
		if state.get("mode") == "region":
			var windows: MultiplayerWindows = owner_ref.get_ref()
			var visit := ApplicationMultiplayer.button(line, "", func() -> void:
				windows.coop.session.request({"kind": "view_city", "seat": player.id}))
			visit.icon = preload("res://src/multiplayer/icons/visit.svg")
			visit.add_theme_constant_override("icon_max_width", 16)
			visit.tooltip_text = tr("Visit city") + ": " + str(player.city)
			visit.disabled = player.id == state.get("view_owner")
			for style_name in ["normal", "hover", "pressed", "disabled"]:
				var compact := visit.get_theme_stylebox(style_name).duplicate()
				compact.content_margin_top = 0
				compact.content_margin_bottom = 0
				visit.add_theme_stylebox_override(style_name, compact)
		var progress := bar(row, Color(color, 0.6), 0.0 if endless else clampf(float(current) / target, 0, 1))
		if not endless and ranked and (current >= target or days > 0):
			bar(row, Color(color, 1.0), float(days) / required, true)
		var text := Label.new()
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 6
		text.offset_right = -6
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		text.add_theme_color_override("font_color", Color.WHITE)
		text.add_theme_constant_override("outline_size", 0)
		text.add_theme_font_size_override("font_size", 14)
		text.text = str(player.name)
		var amount := Label.new()
		amount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		amount.offset_right = -6
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount.add_theme_constant_override("outline_size", 0)
		amount.add_theme_font_size_override("font_size", 14)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount.text = "%s / %s" % [number(current, kind), number(target, kind)]
		if days > 0 and goal.get("rule", "continuous") == "leadership":
			amount.text = tr("Leadership: %s / %d years") % [String.num(float(days) / CityCalendar.DAYS_PER_YEAR, 1).replace(".", ",") if TranslationServer.get_locale().begins_with("de") else String.num(float(days) / CityCalendar.DAYS_PER_YEAR, 1), required / CityCalendar.DAYS_PER_YEAR]
		elif days > 0:
			amount.text = tr("Target held: %d / %d game days") % [days, required]
		if not ranked:
			amount.text = tr("Unranked")
		amount.visible = not endless
		row.add_child(amount)
		text.offset_right = -maxf(6, amount.get_minimum_size().x + 12)

		if endless:
			text.text = player.name
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		var status := tr("Below target") if current < target else tr("Tied lead") if goal.get("tied", false) else tr("Leading") if goal.get("leader", "") == player.id else tr("Overtaken")
		if goal.get("rule", "continuous") == "continuous":
			status = tr("Below target") if current < target else tr("Target reached")
		row.tooltip_text = status + "\n" + "%s: %s / %s\n%s" % [player.name, number(current, kind), number(target, kind), (tr("Leadership: %d / %d game days") if goal.get("rule", "continuous") == "leadership" else tr("Target held: %d / %d game days")) % [days, required] if ranked else tr("Unranked · city founded after the start")]
	if goal.get("rule", "continuous") == "continuous":
		panel.tooltip_text = tr("Stay at or above the target for one full game year. Dropping below resets the timer.")
		return
	panel.tooltip_text = tr("Reach the target and accumulate %d years as sole leader. Earned time is kept.") % (required / CityCalendar.DAYS_PER_YEAR)

static func bar(parent: Control, color: Color, fraction: float, transparent := false) -> ProgressBar:
	var result := ProgressBar.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.show_percentage = false
	result.value = fraction * 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	result.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.set_corner_radius_all(4)
	background.bg_color = Color.TRANSPARENT if transparent else Color(0.08, 0.1, 0.12, 0.9)
	result.add_theme_stylebox_override("background", background)
	parent.add_child(result)
	return result

static func number(amount: int, kind: String) -> String:
	return MultiplayerScoreboard.money(amount) if kind == "wealth" else MultiplayerScoreboard.number(amount)
