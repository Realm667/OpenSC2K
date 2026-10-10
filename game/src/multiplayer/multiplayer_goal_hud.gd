class_name MultiplayerGoalHud
extends RefCounted
## Compact read-only competitive progress, anchored inside the map's top right.

var panel: PanelContainer
var title: Button
var own_label: Label
var leader_label: Label
var progress: ProgressBar
var hold: Label

func _init(windows: MultiplayerWindows) -> void:
	panel = PanelContainer.new()
	panel.theme = AppUiTheme.current()
	windows.coop.app.map_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var body := VBoxContainer.new()
	panel.add_child(body)
	title = ApplicationMultiplayer.button(body, "", windows.open_scoreboard)
	title.tooltip_text = tr("Open scoreboard")
	title.clip_text = true
	own_label = ApplicationMultiplayer.label(body, "")
	leader_label = ApplicationMultiplayer.label(body, "")
	for label in [own_label, leader_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 18
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(progress)
	hold = ApplicationMultiplayer.label(body, "")
	hold.autowrap_mode = TextServer.AUTOWRAP_OFF
	hold.clip_text = true
	panel.hide()

func layout(view: Rect2) -> void:
	var width := minf(320, maxf(0, view.size.x - 16))
	panel.size = Vector2(width, panel.get_combined_minimum_size().y)
	panel.position = Vector2(view.end.x - panel.size.x - 8, view.position.y + 8)

static func value(player: Dictionary, kind: String) -> int:
	return int(player.get("population", 0)) if kind == "population" else int(player.get("funds", 0)) - int(player.get("debt", 0))

func update(state: Dictionary, actor: String) -> void:
	panel.visible = state.get("mode") in ["shared", "region"] and not state.get("lobby", {}).get("waiting", false)
	if not panel.visible:
		return
	var goal: Dictionary = state.get("goal", {})
	var kind: String = goal.get("kind", "endless")
	var endless: bool = kind == "endless" or goal.get("unscored", false)
	progress.visible = not endless
	hold.visible = not endless
	own_label.visible = not endless
	leader_label.visible = not endless
	title.text = tr("Endless game · no scoring") if goal.get("unscored", false) else tr("Endless game") if endless else tr("Victory target: %s") % (tr("Population") if kind == "population" else tr("Net wealth"))
	if endless:
		return
	var own := 0
	var ranked := true
	var best := -9223372036854775807
	var names: Array[String] = []
	for player: Dictionary in state.get("roster", []):
		var current := value(player, kind)
		if player.id == actor:
			own = current
			ranked = player.get("ranked", true)
		if not player.get("ranked", true):
			continue
		if current > best:
			best = current
			names.clear()
		if current == best:
			names.append(player.name)
	var target := maxi(1, int(goal.get("target", 1)))
	own_label.text = tr("You: %s / %s") % [number(own, kind), number(target, kind)]
	leader_label.text = tr("Leading: %s · %s") % [", ".join(names), number(best, kind)]
	own_label.tooltip_text = own_label.text
	leader_label.tooltip_text = leader_label.text
	progress.value = clampf(float(own) * 100.0 / target, 0, 100)
	var days := int(goal.get("holding", {}).get(actor, {}).get("days", 0))
	var required := int(goal.get("hold_days", 0))
	hold.text = tr("Target held: %d / %d game days") % [mini(days, required), required] if ranked else tr("Unranked · city founded after the start")
	hold.tooltip_text = tr("Stay at or above the target for one full game year. Dropping below resets the timer.")
	progress.modulate = Color.WHITE if ranked else Color(0.6, 0.6, 0.6)
	panel.tooltip_text = tr("Net wealth = city funds minus outstanding debt.") if kind == "wealth" else tr("Population of your own city.")

static func number(amount: int, kind: String) -> String:
	return MultiplayerScoreboard.money(amount) if kind == "wealth" else str(amount)
