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
	main.tool_state.selected_group = 9
	main.tool_state.selected_subtool = 0
	main.city_edits.apply_map_selection(Vector2i(20, 20), Vector2i(20, 20), [Vector2i(20, 20)], false)
	check(main.coop.session.world.revision == 1, "ordinary map selection reaches host")
	check(main.document_state.city.funds() == main.coop.session.world.city.funds(), "host display updates funds")
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
