extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in 20:
		await create_timer(0.01).timeout

func await_lobby_view(host: CoopSession, guest: CoopSession) -> void:
	# Ready refers to the displayed roster generation. A fixed sleep can race
	# the next state broadcast under parallel CPU/GPU validation load.
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if guest.connected and int(guest.latest.get("lobby", {}).get("generation", -1)) == host.lobby_generation:
			return
		await create_timer(0.02).timeout
	check(false, "client received the current lobby generation")

func run() -> void:
	for mode in ["coop", "shared", "region"]:
		await lobby_case(mode)
	check(MultiplayerGoalHud.value({"funds": 50000, "debt": 20000}, "wealth") == 30000, "HUD subtracts all debt")
	check(MultiplayerGoalHud.value({"population": 321}, "population") == 321, "HUD population")
	print("Multiplayer lobby checks: %d failures" % failures)
	quit(1 if failures else 0)

func lobby_case(mode: String) -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	for node in [host, guest]:
		root.add_child(node)
	check(host.host(Sc2xDocument.create_empty(32, "Lobby").document, 0, "", "Host", mode).is_empty(), "host lobby " + mode)
	check(host.waiting_for_start and host.world.controller.speed == 1, "host paused before first guest")
	var before := host.world.city.document.serialize().data
	host.request({"kind": "speed", "speed": 5})
	host.request({"kind": "disaster", "disaster": 7, "point": [5, 5]})
	host.request({"kind": "lobby_ready", "ready": true})
	host.request({"kind": "lobby_start"})
	check(host.waiting_for_start, "cannot start alone")
	await settle()
	check(host.world.city.document.serialize().data == before, "lobby blocks clock and commands")
	guest.player_color = "c7a0ff"
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	await settle()
	check(guest.connected and guest.latest.get("lobby", {}).get("waiting", false), "guest receives lobby")
	check(host.members[guest.token].color == "c7a0ff", "exact guest colour retained")
	check(not host.lobby_ready.get(host.token, false), "new participant resets host readiness")
	await await_lobby_view(host, guest)
	host.request({"kind": "lobby_ready", "ready": true})
	guest.request({"kind": "lobby_ready", "ready": true})
	await settle()
	check(host.can_start_lobby(), "both ready permits start")
	guest.request({"kind": "lobby_start"})
	await settle()
	check(host.waiting_for_start, "guest cannot start")
	guest.request({"kind": "lobby_ready", "ready": false})
	await settle()
	host.request({"kind": "lobby_start"})
	check(host.waiting_for_start, "readiness withdrawal prevents start")
	var saved := host.city_checkpoint()
	check(saved.error.is_empty(), "save pre-start lobby")
	guest.stop()
	await settle()
	check(host.restore_embedded(saved.document).is_empty(), "restore pre-start game")
	check(host.waiting_for_start and host.lobby_ready.is_empty(), "save does not persist stale readiness")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	await settle()
	await await_lobby_view(host, guest)
	host.request({"kind": "lobby_ready", "ready": true})
	guest.request({"kind": "lobby_ready", "ready": true})
	await settle()
	host.request({"kind": "lobby_start"})
	await settle()
	check(not host.waiting_for_start and not guest.latest.lobby.waiting, "both peers enter running game")
	check(host.world.controller.speed == 2 and int(guest.latest.speed) == 2, "shared initial speed")
	guest.request({"kind": "speed", "speed": 1})
	await settle()
	check(host.world.controller.speed == 2, "guest cannot pause host simulation")
	host.request({"kind": "speed", "speed": 4})
	await settle()
	check(host.world.controller.speed == 4 and int(guest.latest.speed) == 4, "host speed reaches clients without slowest-client veto")
	host.request({"kind": "speed", "speed": 2})
	if mode == "region":
		guest.request({"kind": "view_city", "seat": host.token.sha256_text()})
		await settle()
		check(guest.latest.visiting and guest.latest.view_owner == host.token.sha256_text(), "TCP guest spectates host city")
		var before_build := host.world.city.zones.duplicate()
		guest.request({"kind": "build", "group": 9, "tool": 0, "start": [7, 7], "finish": [7, 7]})
		await settle()
		check(host.world.city.zones == before_build, "remote spectator cannot change host city")
		host.goal.kind = "wealth"
		host.goal.target = 45000
		host.world.municipalities[guest.token].city.set_funds(50000)
		host.world.revision += 1
		await settle()
		check(not host.goal.blocked(), "target requires full holding year")
		host.world.municipalities[guest.token].city.set_age_in_days(host.world.municipalities[guest.token].city.age_in_days() + CityCalendar.DAYS_PER_YEAR)
		await settle()
		check(host.goal.blocked() and guest.latest.goal.winners[0].seat == guest.token.sha256_text(), "TCP victory reaches all players")
		check(host.world.controller.speed == 1, "victory stops simulation")
		guest.request({"kind": "continue_unscored"})
		await settle()
		check(host.goal.blocked(), "only host can release victory")
		host.request({"kind": "continue_unscored"})
		await settle()
		check(not host.goal.blocked() and guest.latest.goal.unscored, "host continues endless on both peers")
		var old_positions := host.starts.positions.duplicate(true)
		guest.request({"kind": "rematch"})
		await settle()
		check(not host.waiting_for_start, "guest cannot force a rematch")
		host.request({"kind": "rematch"})
		await settle()
		check(host.waiting_for_start and guest.latest.lobby.waiting and host.lobby_ready.is_empty(), "rematch returns everyone to unready lobby")
		await await_lobby_view(host, guest)
		host.request({"kind": "lobby_ready", "ready": true})
		guest.request({"kind": "lobby_ready", "ready": true})
		await settle()
		host.request({"kind": "lobby_start"})
		await settle()
		check(host.starts.positions[host.token].slot != old_positions[host.token].slot and host.starts.positions[guest.token].slot != old_positions[guest.token].slot, "real session rotates both starts")
		check(host.goal.winners.is_empty() and host.goal.holding.is_empty(), "rematch resets victory hold")
		var checkpoint := host.city_checkpoint()
		check(checkpoint.error.is_empty(), "competition checkpoint serializes")
		var verify := CoopSession.new()
		root.add_child(verify)
		verify.host(Sc2xDocument.create_empty(32, "Verify").document, 0, "", "Verify", "region")
		check(verify.restore_embedded(checkpoint.document).is_empty(), "competition rules and starts restore")
		check(verify.starts.previous == host.starts.previous and verify.goal.hold_days == CityCalendar.DAYS_PER_YEAR, "repeated starts remain prohibited after reload")
		verify.stop()
		verify.queue_free()
	guest.stop()
	host.stop()
	guest.queue_free()
	host.queue_free()
	await process_frame
