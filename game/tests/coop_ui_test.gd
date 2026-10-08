extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	root.gui_embed_subwindows = true
	var main: CityApplication = load("res://main.tscn").instantiate()
	AppFixture.configure(main)
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.asset_state.assets_ready, "assets loaded")
	check(main.main_menu.visible, "normal startup menu")
	main.main_menu.get_node("Center/Panel/Content/Multiplayer").pressed.emit()
	await process_frame
	check(main.coop.panel.visible, "Multiplayer button opens lobby")
	main.coop.port.min_value = 0
	main.coop.port.value = 0
	main.coop.start_host()
	await process_frame
	check(main.coop.active() and main.coop.mirrored, "host activates a playable city")
	check(not main.main_menu.visible and not main.coop.panel.visible, "city gets input ownership")
	check(main.document_state.city != main.coop.session.world.city, "host display is isolated from authoritative model")
	check(main.simulation_state.frame_simulation == null, "display has no independent simulation worker")
	var display_document := main.document_state.current_document
	main.visual_environment.process(0.0)
	main.visual_environment.weather.clock = 123.0
	# Exercise the region cache even on a headless runner; the GPU run uses its GPU backend.
	main.static_render.invalidate_rendered_city()
	main.map_render.refresh_region_map(true)
	main.tool_state.selected_group = 9
	main.tool_state.selected_subtool = 0
	main.city_edits.apply_map_selection(Vector2i(20, 20), Vector2i(20, 20), [Vector2i(20, 20)], false)
	check(main.coop.session.world.revision == 1, "ordinary map selection reaches host")
	check(main.document_state.city.funds() == main.coop.session.world.city.funds(), "host display updates funds")
	check(main.document_state.current_document == display_document, "snapshot retains display document identity")
	check(main.document_state.city.chunk_revision("XZON") > 0, "received zone increments render revision")
	check(main.render_caches.region_cache.display_city.zones == main.document_state.city.zones, "zone immediately reaches rendered snapshot without a building")
	main.visual_environment.process(0.0)
	check(main.visual_environment.weather.clock == 123.0, "city snapshot does not reset weather clock")
	var guest := CoopSession.new()
	root.add_child(guest)
	guest.join("127.0.0.1", main.coop.session.server.get_local_port(), main.coop.join_code.text, "Guest")
	for _frame in 100:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected, "second player joins the UI-hosted city")
	guest.request({"kind": "build", "group": 9, "tool": 0, "start": [25, 25], "finish": [25, 25], "path": [[25, 25]]})
	for _frame in 100:
		await create_timer(0.01).timeout
		if main.coop.session.world.revision == 2 and guest.local_revision == 2:
			break
	check(main.coop.session.world.revision == 2, "guest builds while host has its own camera")
	check(main.document_state.city.zones == main.coop.session.world.city.zones, "guest edit reaches host view")
	check(main.render_caches.region_cache.display_city.zones == main.document_state.city.zones, "guest zone reaches renderer")
	await rendering_cases(main)
	await weather_cases(main, guest)
	main.reports.on_windows_menu(0)
	check(main.coop.panel.visible, "budget opens shared administration")
	main.coop.budget_values[0].value = 11
	main.coop.send_budget()
	check(BudgetPhase.funding_values(main.coop.session.world.city)[0] == 11, "shared budget UI applies tax")
	main.coop.save_path.text = "user://coop-ui.sc2mp"
	main.coop.save()
	check(FileAccess.file_exists("user://coop-ui.sc2mp"), "UI saves session")
	if DisplayServer.get_name() != "headless":
		main.coop.open()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://coop-menu.png")
	guest.stop()
	guest.queue_free()
	main.coop.leave()
	await process_frame
	check(not main.coop.active() and main.main_menu.visible, "leave returns to singleplayer menu")
	main.queue_free()
	await process_frame
	print("Koop UI checks: %d failures" % failures)
	quit(1 if failures else 0)


func rendering_cases(main: CityApplication) -> void:
	for renderer in ["region", "whole"]:
		if renderer == "whole":
			main.preferences.city_renderer = "cpu"
			main.static_render.invalidate_rendered_city()
			main.map_render.refresh_map()
		var target := Vector2i(30, 30) if renderer == "region" else Vector2i(35, 35)
		main.tool_state.selected_group = CityToolIds.Group.ROADS
		main.tool_state.selected_subtool = 0
		main.city_edits.apply_map_selection(target, target, [target], false)
		for _frame in 100:
			await process_frame
			if main.render_caches.static_display_city.building_id(target.x, target.y) != 0:
				break
		check(main.render_caches.static_display_city.building_id(target.x, target.y) != 0, renderer + " shows road without another edit")
		var road := main.document_state.city.building_id(target.x, target.y)
		main.coop.bulldoze(target)
		var cleared := main.coop.session.world.city.building_id(target.x, target.y)
		check(cleared != road, renderer + " road demolition accepted")
		for _frame in 100:
			await process_frame
			if main.render_caches.static_display_city.building_id(target.x, target.y) == cleared:
				break
		check(main.render_caches.static_display_city.building_id(target.x, target.y) == cleared, renderer + " shows demolition rubble without another edit")


func weather_cases(main: CityApplication, guest: CoopSession) -> void:
	var received: Array[Dictionary] = []
	guest.environment_received.connect(func(value: Dictionary) -> void: received.append(value))
	var weather := main.visual_environment.weather
	main.preferences.visual_enhancements.weather_enabled = true
	main.preferences.visual_enhancements.weather_mode = 2
	main.preferences.visual_enhancements.weather_fixed = CityVisualWeather.Kind.HEAVY_SNOW
	main.visual_environment.process(1.0)
	for _frame in 60:
		await create_timer(0.01).timeout
		if not received.is_empty():
			break
	check(not received.is_empty(), "weather packets arrive independently of city changes")
	if received.is_empty():
		return
	var state: Dictionary = received.back()
	check(int(state.weather[0]) == CityVisualWeather.Kind.HEAVY_SNOW, "guest receives host's weather choice")
	var remote := CityVisualWeather.new(main)
	remote.remote_state = state.weather
	main.preferences.visual_enhancements.weather_fixed = CityVisualWeather.Kind.SUNNY
	remote.process(0.1, 10.0, true, 1.0)
	check(remote.kind == CityVisualWeather.Kind.HEAVY_SNOW and remote.snow == float(state.weather[6]), "remote weather overrides local choice and season")
	check(remote.clock == float(state.weather[7]), "late join receives weather phase")
	remote.remote_state[18] = 5
	remote.process(0.1, 0.0, true, 1.0)
	remote.process(0.1, 0.0, true, 1.0)
	check(is_equal_approx(remote.clock, float(state.weather[7]) + 0.2), "particle animation runs smoothly between packets")
	check(remote.received_thunder == 5, "duplicate weather frames do not replay thunder")
	remote.reset()
	if remote.layer != null:
		remote.layer.queue_free()
	check(weather.clock >= 123.0, "weather keeps advancing across edits")
