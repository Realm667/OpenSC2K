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
	check(main.city_dialogs.new_city_dialog.visible, "host opens complete new-city dialog")
	main.new_city.cancel_new_city()
	main.coop.host_document(Sc2xDocument.create_empty(128, "UI test").document)
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
	check(main.city_dialogs.budget_dialog.visible, "budget opens normal city dialog")
	var funding := BudgetPhase.funding_values(main.document_state.city)
	funding[0] = 11
	main.city_dialogs.budget_dialog.open_budget(funding, false, true)
	main.budget.commit_budget()
	main.city_dialogs.budget_dialog.hide()
	check(BudgetPhase.funding_values(main.coop.session.world.city)[0] == 11, "shared budget UI applies tax")
	main.coop.save_to("user://coop-ui.sc2x")
	check(FileAccess.file_exists("user://coop-ui.sc2x"), "UI saves normal city with session")
	main.autosave.directory = OS.get_user_data_dir().path_join("multiplayer-autosave")
	check(main.autosave.save_now(), "host starts complete multiplayer autosave")
	main.autosave.close()
	var automatic := Sc2File.load_path(main.autosave.last_path)
	check(automatic.is_valid() and automatic.sc2x_extra_entries.has("multiplayer.json"), "autosave includes session identities")
	main.menus.on_options_menu(ApplicationMenus.MENU_SOUND_EFFECTS)
	var local_sound := main.document_state.city.sound_enabled()
	main.coop.session.publish()
	check(main.document_state.city.sound_enabled() == local_sound, "local audio choice survives server snapshot")
	if DisplayServer.get_name() != "headless":
		main.coop.open()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://coop-menu.png")
	main.coop.windows.open_chat()
	main.coop.windows.chat_input.text_submitted.emit("Hello from the host")
	check(main.coop.windows.chat_log.get_parsed_text().contains("Hello from the host"), "chat window displays message")
	main.coop.windows.chat.hide()
	check(main.coop.menu_button.get_index() == main.city_menu_bar.newspaper_menu.get_index() + 1, "multiplayer menu follows Newspaper")
	guest.stop()
	guest.queue_free()
	main.coop.leave()
	await process_frame
	check(not main.coop.active() and main.main_menu.visible, "leave returns to singleplayer menu")
	check(not main.visual_preparation.busy and main.visual_preparation.banks.is_empty(), "leave releases pending visual banks before clearing the city")
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
	remote.remote_state[20] = 0
	remote.process(0.1, 0.0, true, 1.0)
	remote.process(0.1, 0.0, true, 1.0)
	check(is_equal_approx(remote.clock, float(state.weather[7]) + 0.2), "particle animation runs smoothly between packets")
	check(remote.received_thunder == 5, "duplicate weather frames do not replay thunder")
	remote.process(0.1, 0.0, true, 1.0, true)
	check(is_equal_approx(remote.clock, float(state.weather[7]) + 0.2), "paused remote particles retain their phase")
	remote.remote_state[20] = 1
	remote.process(0.1, 0.0, true, 1.0)
	check(is_equal_approx(remote.clock, float(state.weather[7]) + 0.2), "host pause freezes guests even with local running speed")
	await cloud_front_cases(main)
	remote.reset()
	if remote.layer != null:
		remote.layer.queue_free()
	check(weather.clock >= 123.0, "weather keeps advancing across edits")


func cloud_front_cases(main: CityApplication) -> void:
	var environment := main.visual_environment
	var speed := main.simulation_state.speed_controller.speed
	main.simulation_state.speed_controller.speed = GameSpeedController.Speed.TURTLE
	main.map_view.interaction.panning = true
	check(main.frame._simulation_suspended(), "camera drag still suspends local simulation")
	check(environment.network_snapshot().weather[20] == 0, "camera drag must not broadcast a weather pause")
	main.simulation_state.speed_controller.speed = GameSpeedController.Speed.PAUSED
	check(environment.network_snapshot().weather[20] == 1, "real pause is still sent during camera drag")
	main.map_view.interaction.panning = false
	main.simulation_state.speed_controller.speed = speed
	var options := main.preferences.visual_enhancements
	options.cloud_enabled = true
	options.cloud_mode = CityCloudSituations.Type.CIRRUS + 1
	options.weather_fixed = CityVisualWeather.Kind.DRY_STORM
	options.weather_strength = 0.6
	environment.process(1.0)
	var clouds := environment.clouds
	clouds.situations.current = CityCloudSituations.Type.STRATUS
	clouds.situations.target = CityCloudSituations.Type.FOG
	clouds.situations.blend = 0.4
	clouds.situations.hold_clock = 730.0
	clouds.situations.duration = 90.0
	clouds.fog = 0.15
	clouds.fog_overlay.drift = Vector2(23, 41)
	clouds.storminess = 0.7
	clouds.precipitation_readiness = 0.25
	var state := environment.network_snapshot()
	environment.receive_network_weather(state)
	check(environment.remote_weather == state, "complete host atmosphere passes packet validation")
	var invalid := state.duplicate(true)
	invalid.clouds[5] = 99
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "invalid cloud type cannot enter the renderer")
	invalid = state.duplicate(true)
	invalid.weather[20] = 2
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "invalid pause flag rejected")
	invalid = state.duplicate(true)
	invalid.clouds[7] = NAN
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "nonfinite cloud transition rejected")
	environment.remote_weather.clear()
	var remote_clouds := CityVisualClouds.new(main)
	remote_clouds.remote_state = state.clouds
	remote_clouds.process(0.1, 0.1, true, Color.WHITE, 0.0, CityVisualWeather.Kind.DRY_STORM)
	check(remote_clouds.situations.current == CityCloudSituations.Type.STRATUS and remote_clouds.situations.target == CityCloudSituations.Type.FOG, "host cloud types override guest fixed type")
	check(is_equal_approx(remote_clouds.situations.blend, 0.4), "late join receives cloud atlas transition")
	check(remote_clouds.field == CityCloudSituations.ATLASES[CityCloudSituations.Type.STRATUS], "guest uses host atlas")
	check(is_equal_approx(float(remote_clouds.parameters.cloud_type_blend), smoothstep(0.0, 1.0, 0.4)), "shader receives synchronized blend")
	check(is_equal_approx(remote_clouds.precipitation_readiness, 0.25), "host cloud cover controls guest precipitation")
	check(remote_clouds.fog_overlay.drift == Vector2(23, 41), "low mist receives host world phase")
	var remote := CityVisualWeather.new(main)
	remote.remote_state = state.weather
	remote.process(1.0, 1.0, true, 1.0)
	check(remote.kind == CityVisualWeather.Kind.DRY_STORM and remote.rain == 0.0 and remote.snow == 0.0, "synchronized dry storm has no residual precipitation")
	var audio := main.audio_controller
	var background := audio.background_audio
	audio.set_background_audio(true)
	var sound_enabled := main.document_state.city.sound_enabled()
	main.document_state.city.set_sound_enabled(true)
	remote.remote_state[20] = 0
	remote.process(1.0, 1.0, true, 1.0)
	check(remote.audio.wind_gain > 0.0 and remote.audio.rain_gains == Vector2.ZERO, "guest dry storm uses wind without rain audio")
	var wind_gain := remote.audio.wind_gain
	remote.process(1.0, 1.0, true, 1.0, true)
	check(remote.audio.wind_gain == wind_gain and is_instance_valid(remote.audio.wind_player) and remote.audio.wind_player.stream_paused, "guest pause freezes existing wind ambience")
	remote.process(0.1, 0.1, false, 1.0)
	check(remote.rain == 0.0 and remote.snow == 0.0 and remote.tint == Color.WHITE, "guest can disable local weather effects")
	remote.reset()
	if remote.layer != null:
		remote.layer.queue_free()
	audio.set_background_audio(background)
	main.document_state.city.set_sound_enabled(sound_enabled)
	for layer in [remote_clouds.layer, remote_clouds.fog_overlay.layer, remote_clouds.fog_overlay.height_viewport]:
		if layer != null:
			layer.queue_free()
