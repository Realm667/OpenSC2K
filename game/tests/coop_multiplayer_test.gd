extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func build_at(position: Vector2i, revision: int, group := 9, tool := 0) -> Dictionary:
	return {"kind": "build", "revision": revision, "group": group, "tool": tool,
		"start": [position.x, position.y], "finish": [position.x, position.y],
		"path": [[position.x, position.y]], "dragged": false}


func run() -> void:
	var source := Sc2xDocument.create_empty(32, "Coop Test").document
	var world := CoopWorld.new()
	check(world.open(source), "open authoritative world")
	var initial_funds := world.city.funds()
	var first := world.command("alice", build_at(Vector2i(5, 5), 0))
	check(first.ok, "first build: " + str(first))
	var second := world.command("bob", build_at(Vector2i(10, 10), 0))
	check(second.ok, "independent simultaneous build: " + str(second))
	check(not world.command("bob", build_at(Vector2i(5, 5), 0, 0)).ok, "stale demolition rejected")
	check(not world.command("alice", {"kind": "undo", "revision": world.revision}).ok, "cannot undo another actor")
	check(world.command("bob", {"kind": "undo", "revision": world.revision}).ok, "own immediately preceding edit can be undone")
	check(world.city.funds() < initial_funds, "shared cost charged")
	check(CityState.from_document(source).funds() == initial_funds, "source document unchanged")
	var funds_before := world.city.funds()
	var malicious := build_at(Vector2i(5, 5), world.revision)
	malicious.start = [-1, 10]
	check(not world.command("alice", malicious).ok, "negative coordinate rejected")
	malicious.start = [5.5, 5]
	check(not world.command("alice", malicious).ok, "fractional coordinate rejected")
	malicious.start = "wrong type"
	check(not world.command("alice", malicious).ok, "invalid coordinate type rejected")
	check(world.city.funds() == funds_before, "rejected commands leave money unchanged")
	var values := Array(BudgetPhase.funding_values(world.city))
	values[0] = 12
	var policy := {"kind": "budget", "revision": world.revision, "policy": 0, "values": values, "auto": true}
	check(world.command("alice", policy).ok, "shared budget accepted")
	check(not world.command("bob", policy).ok, "stale budget rejected")
	world.city.set_funds(0)
	check(not world.command("bob", build_at(Vector2i(15, 15), world.revision)).ok, "insufficient shared funds")
	world.city.set_funds(10000)
	world.controller.set_speed(5)
	var initial_day := world.city.age_in_days()
	for _step in 24:
		world.advance(0.25)
	check(world.city.age_in_days() > initial_day, "host advances the simulation")
	world.controller.set_speed(1)
	var snap := world.snapshot()
	var mirror := Sc2File.new()
	check(mirror.parse(Marshalls.base64_to_raw(snap.city)), "snapshot can be loaded")
	check(CityState.from_document(mirror).funds() == world.city.funds(), "snapshot contains current funds")
	construction_cases(source)
	decision_cases(source)
	await network_cases(source)
	print("Koop multiplayer checks: %d failures" % failures)
	quit(1 if failures else 0)


func construction_cases(source: Sc2File) -> void:
	var world := CoopWorld.new()
	check(world.open(source), "construction world")
	check(not world.command("alice", build_at(Vector2i(3, 3), 0, 2, 2)).ok, "dispatch stays unavailable outside the original disaster mode")
	_begin_dispatch_fixture(world)
	var deployment := world.command("alice", build_at(Vector2i(3, 3), 0, 2, 2))
	check(deployment.ok, "emergency service deployment: %s; capacity %s" % [deployment, world.engine.dispatch_capacity])
	check(world.dispatch_initialized, "dispatch state initialized")
	check(not world.dispatch_slot_points[2].is_empty(), "0.3.0 dispatch keeps the authoritative slot position")
	check(world.command("alice", {"kind": "undo", "revision": world.revision}).ok, "dispatch undo")
	check(not world.dispatch_initialized and world.dispatch_cycles == PackedInt32Array([0, 0, 0]), "dispatch undo restores unit selection")
	check(world.dispatch_slot_points == [{}, {}, {}], "dispatch undo restores slot positions")
	world = CoopWorld.new()
	world.open(source)
	check(world.command("alice", build_at(Vector2i(7, 7), 0)).ok, "zone inside future building footprint")
	var funds := world.city.funds()
	var building := build_at(Vector2i(8, 8), 0, 3, 2)
	var conflict := world.command("bob", building)
	check(not conflict.ok and str(conflict.message).contains("Another player"), "conflict outside clicked tile rejects entire building")
	check(world.city.funds() == funds, "footprint conflict charges nothing")
	building.revision = world.revision
	check(world.command("bob", building).ok, "reviewed building can be placed")
	var river := CityState.from_document(source.duplicate_document())
	for x in range(8, 32):
		var water := x >= 12 and x < 16
		river.set_land_altitude(x, 20, 4 if water else 6)
		river.set_water_altitude(x, 20, 5)
		river.set_tile_flag(x, 20, 4, water)
		river.set_terrain_id(x, 20, (0x21 if x == 12 else 0x10) if water else 0)
	var bridge_world := CoopWorld.new()
	check(bridge_world.open(river.document), "bridge world")
	var bridge := build_at(Vector2i(8, 20), 0, 6, 0)
	bridge.finish = [20, 20]
	bridge.dragged = true
	var proposal := bridge_world.command("alice", bridge)
	check(proposal.has("choices"), "bridge requires an explicit choice")
	check(bridge_world.city.funds() == river.funds(), "bridge proposal changes no money")
	if proposal.has("choices"):
		bridge.merge(proposal.choices[0].fields, true)
		var quote := bridge_world.command("alice", bridge)
		check(quote.has("choices"), "complete route price is confirmed after type selection")
		if not quote.has("choices"):
			return
		bridge.merge(quote.choices[0].fields, true)
		var placed := bridge_world.command("alice", bridge)
		check(placed.ok, "confirmed bridge: " + str(placed))
		check(bridge_world.city.building_id(20, 20) != 0, "bridge drag reaches the far bank")


func decision_cases(source: Sc2File) -> void:
	var annual := CityState.from_document(source.duplicate_document())
	annual.set_age_in_days(299)
	annual.document.set_misc_u32(Sc2MiscLayout.YEAR_END, 1)
	annual.set_auto_budget_enabled(false)
	var world := CoopWorld.new()
	check(world.open(annual.document), "annual world")
	world.controller.set_speed(4)
	world.advance(0.2)
	check(world.engine.pending_interaction == "annual_budget", "year end presents a shared decision")
	check(not Sc2xCheckpoint.save_error(world.controller).is_empty(), "cannot save an incomplete day")
	var request := {"kind": "budget", "values": Array(BudgetPhase.funding_values(world.city)),
		"auto": false, "policy": world.policy_revision, "revision": world.revision}
	check(world.command("alice", request).ok, "annual decision resolves")
	check(world.engine.pending_interaction.is_empty(), "simulation can continue")
	check(not world.command("bob", request).ok, "annual decision cannot resolve twice")
	world.controller.interaction_blocked = true
	check(world.command("alice", {"kind": "decision", "policy": world.policy_revision,
		"revision": world.revision}).ok and not world.controller.interaction_blocked, "nonterminal simulation notice cannot deadlock")


func network_cases(source: Sc2File) -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	var listen_error := host.host(source, 0, "test-code", "Alice", "coop", false)
	check(listen_error.is_empty(), "listen on loopback: " + listen_error)
	if not listen_error.is_empty():
		return
	var port := host.server.get_local_port()
	check(guest.join("127.0.0.1", port, "test-code", "Bob").is_empty(), "connect client")
	for _frame in 100:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected, "TCP handshake and initial city received")
	# Suppress the timer: a successful command must publish in its receive turn.
	host.snapshot_elapsed = -100.0
	guest.request(build_at(Vector2i(12, 12), guest.local_revision))
	for _frame in 60:
		await create_timer(0.01).timeout
		if host.world.revision > 0 and guest.local_revision == host.world.revision:
			break
	check(host.world.revision > 0, "remote command applied on host")
	check(guest.local_revision == host.world.revision, "remote edit published without periodic timer")
	check(guest.latest.get("city") == host.latest.get("city"), "remote snapshot converges")
	var duplicate := build_at(Vector2i(13, 13), host.world.revision)
	duplicate["id"] = 1
	var before := host.world.city.funds()
	check(not host.execute(guest.token, duplicate).ok, "duplicate command rejected")
	check(host.world.city.funds() == before, "duplicate does not charge money")
	guest.channels[0].close()
	for _frame in 60:
		await create_timer(0.01).timeout
		if host.disconnected_pause:
			break
	check(host.disconnected_pause, "disconnect pauses world")
	check(guest.join("127.0.0.1", port, "test-code", "Bob").is_empty(), "reconnect")
	for _frame in 100:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected and guest.next_command == 2, "reconnect preserves identity and sequence")
	_begin_dispatch_fixture(host.world)
	host.request(build_at(Vector2i(3, 3), host.world.revision, 2, 2))
	var dispatch_before := host.world.dispatch_cycles.duplicate()
	var points_before := host.world.saved_dispatch_points()
	var path := "user://coop-test-%d.sc2mp" % OS.get_process_id()
	var save_error := host.save_session(path)
	check(save_error.is_empty(), "save whole session: " + save_error)
	var saved_funds := host.world.city.funds()
	guest.stop()
	host.stop()
	var resume_error := host.resume_session(path, 0, "test-code", "Alice")
	check(resume_error.is_empty(), "resume saved session: " + resume_error)
	if not resume_error.is_empty():
		host.queue_free()
		guest.queue_free()
		return
	check(host.world.city.funds() == saved_funds, "saved city round trip")
	check(host.members.has(guest.token), "save retains participant identities")
	check(host.world.controller.speed == 1, "restored host starts paused")
	check(host.world.dispatch_cycles == dispatch_before and host.world.dispatch_initialized, "save restores emergency service selection")
	check(host.world.saved_dispatch_points() == points_before, "session save restores native dispatch positions")
	check(host.save_session(path).is_empty(), "replace an existing session safely")
	check(FileAccess.file_exists(path + ".bak"), "previous session is retained")
	host.stop()
	host.queue_free()
	guest.queue_free()
	DirAccess.remove_absolute(path)


# Original 0.3.0 enables dispatch only in disaster mode and freezes capacity
# at disaster start. The old fixture tried to send units in a normal city.
func _begin_dispatch_fixture(world: CoopWorld) -> void:
	var chunk := world.city.document.find_chunk("MISC")
	var misc := chunk.decoded_payload.duplicate()
	BinaryData.write_u32_be(misc, Sc2MiscLayout.CITY_MODE, ToolAvailability.DISASTER_CITY_MODE)
	check(chunk.set_decoded_payload(misc), "disaster-mode fixture payload")
	var available := DispatchCommand.begin_disaster(world.city)
	check(available.ok, "original disaster dispatch preparation")
	if available.ok:
		world.engine.dispatch_capacity = available.counts()
		world.engine.dispatch_epoch += 1
