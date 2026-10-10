class_name MultiplayerCompetitionWindows
extends RefCounted

var owner_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return owner_ref.get_ref()
var regions: Window
var region_rows: VBoxContainer
var ending: Window
var end_rows: VBoxContainer
var end_scores := MultiplayerScoreboard.new()
var result_label: Label
var continue_button: Button
var rematch_button: Button
var won_key := ""
var firework_started := 0
var firework_point := Vector2i.ZERO
var region_signature := ""

func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	regions = windows.make_window(tr("Neighbouring cities"))
	region_rows = windows.content(regions)
	ending = windows.make_window(tr("Victory"))
	ending.size = Vector2i(1000, 480)
	end_rows = windows.content(ending)
	result_label = ApplicationMultiplayer.label(end_rows, "")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_scores.setup(end_rows)
	var actions := HBoxContainer.new()
	end_rows.add_child(actions)
	ApplicationMultiplayer.button(actions, tr("Leave game"), windows.coop.confirm_leave)
	continue_button = ApplicationMultiplayer.button(actions, tr("Continue without scoring (endless)"), func() -> void:
		windows.coop.session.request({"kind": "continue_unscored"}))

	rematch_button = ApplicationMultiplayer.button(actions, tr("Rematch · rotate starts"), func() -> void:
		windows.coop.session.request({"kind": "rematch"}))

func open_regions() -> void:
	if windows.state.get("mode") != "region":
		windows.coop.show_message(tr("Neighbouring cities are available in Region mode."))
		return
	refresh_regions()
	regions.popup_centered()

func refresh_regions() -> void:
	var signature := ""
	for player: Dictionary in windows.players:
		signature += "%s|%s|%s|%s;" % [player.id, player.name, player.city, player.get("seat_status", "")]
	if signature == region_signature:
		return
	region_signature = signature
	for child in region_rows.get_children():
		region_rows.remove_child(child)
		child.queue_free()
	var hint := ApplicationMultiplayer.label(region_rows, tr("Visit any city to watch. During disasters you may deploy your own emergency services; other changes remain with its owner."))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for player: Dictionary in windows.players:
		var own := str(player.id) == windows.coop.session.token.sha256_text()
		ApplicationMultiplayer.label(region_rows, "%s · %s · %s · %s" % [player.city, player.name, MultiplayerSeatWindow.status(player.get("seat_status", "reserved")), tr("Region %d") % (int(windows.state.get("starts", {}).get(player.id, {}).get("slot", 0)) + 1)])
		ApplicationMultiplayer.button(region_rows, tr("Return to your city") if own else tr("Visit city"), func() -> void:
			windows.coop.session.request({"kind": "view_city", "seat": player.id})
			regions.hide())

func update(state: Dictionary) -> void:
	if regions.visible:
		refresh_regions()
	var goal: Dictionary = state.get("goal", {})
	var winners: Array = goal.get("winners", [])
	if winners.is_empty() or goal.get("unscored", false):
		ending.hide()
		if winners.is_empty():
			won_key = ""
		return
	var names: Array[String] = []
	for winner: Dictionary in winners:
		names.append("%s (%s)" % [winner.city, winner.name])
	result_label.text = tr("Victory: %s. The game is paused. Leave or let the host continue without scoring.") % ", ".join(names)
	continue_button.disabled = not windows.coop.session.hosting
	rematch_button.disabled = not windows.coop.session.hosting
	end_scores.update(windows.players, true, windows.coop.session.token.sha256_text(), state.get("history", {}))
	var key := JSON.stringify(winners)
	if key != won_key:
		won_key = key
		firework_point = Vector2i(int(winners[0].point[0]), int(winners[0].point[1]))
		firework_started = Time.get_ticks_msec()
		if state.get("mode") == "region" and state.get("view_owner") != winners[0].seat:
			windows.coop.session.request.call_deferred({"kind": "view_city", "seat": winners[0].seat})
		windows.coop.app.camera_input.center_map_on_tile.call_deferred(firework_point)
		windows.open_chat()
		windows.chat_log.add_text(result_label.text + "\n")
		windows.play_cue("joined")
		show_result.call_deferred()

func show_result() -> void:
	ending.popup_centered()
	var screen := windows.coop.app.get_viewport().get_visible_rect().size
	ending.position.y = maxi(0, int(screen.y) - ending.size.y - 20)

func draw_fireworks() -> void:
	if firework_started == 0 or not ending.visible:
		return
	var age := (Time.get_ticks_msec() - firework_started) / 1000.0
	if age > 12.0:
		return
	var map := windows.coop.app.map_view
	var point := MultiplayerMapOverlay.project(map.city, Vector2(firework_point)) * map.camera._view_scale() + map.camera._draw_offset(map.camera._view_scale())
	# Purely visual, deterministic particles: no simulation RNG or disaster edits.
	for burst in 5:
		var phase := fmod(age + burst * 0.53, 2.6)
		if phase > 1.8:
			continue
		var origin := point + Vector2((burst - 2) * 52, -90 - (burst % 2) * 45)
		for spark in 18:
			var angle := TAU * spark / 18.0 + burst * 0.2
			var direction := Vector2(cos(angle), sin(angle))
			var position := origin + direction * phase * 56 + Vector2(0, phase * phase * 20)
			var color := Color.from_hsv(fmod(burst * 0.23, 1.0), 0.7, 1.0, 1.0 - phase / 1.8)
			windows.overlay.draw_line(position - direction * 6, position, color, 2.5, true)

func close() -> void:
	regions.hide()
	ending.hide()
	won_key = ""
	firework_started = 0
