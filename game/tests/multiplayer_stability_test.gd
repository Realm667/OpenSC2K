extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func until(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	return predicate.call()

func run() -> void:
	stream_delta()
	land_subset()
	land_rules()
	public_corridors()
	nonblocking_decisions()
	await network()
	print("Multiplayer stability checks: %d failures" % failures)
	quit(1 if failures else 0)

func stream_delta() -> void:
	var encoder := MultiplayerDelta.new()
	var decoder := MultiplayerDelta.new()
	var initial := {"type": "state", "city": "a".repeat(180000), "revision": 1}
	decoder.decode(encoder.encode(initial))
	initial.city = "b".repeat(180000)
	initial.revision = 2
	var delta := encoder.encode(initial)
	check(delta.type == "state_delta", "large transfer is a delta")
	var sender := MultiplayerStateStream.new()
	var receiver := MultiplayerStateStream.new()
	check(sender.open_output(delta) and sender.size > MultiplayerStateStream.CHUNK_BYTES, "delta needs multiple chunks")
	receiver.receive({"type": "state_begin", "bytes": sender.size, "sha256": sender.digest})
	var offset := 0
	while offset < sender.size:
		var data := sender.file.get_buffer(mini(MultiplayerStateStream.CHUNK_BYTES, sender.size - offset))
		receiver.receive({"type": "state_part", "offset": offset, "data": Marshalls.raw_to_base64(data)})
		offset += data.size()
	var received := receiver.receive({"type": "state_end"})
	check(receiver.complete and not receiver.failed, "chunked delta survives checksum and type validation")
	if not received.is_empty():
		check(decoder.decode(received).get("city") == initial.city, "large delta reconstructs exact authoritative state")
	sender.close()
	receiver.close()

func land_subset() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Land").document)
	world.add_player("a")
	world.add_player("b")
	world.land_price = 5
	world.land_allowance["a"] = 5
	world.owners[world.city.index_of(2, 2)] = 1
	world.owners[world.city.index_of(2, 3)] = 2
	var funds: int = world.municipalities.a.city.funds()
	var request := {"kind": "land_buy", "revision": world.revision, "start": [2, 2], "finish": [2, 5]}
	var result := world.command("a", request)
	check(result.ok and not result.has("choices"), "mixed ownership buys eligible tiles without confirmation")
	check(world.owners[world.city.index_of(2, 3)] == 2, "foreign ownership preserved")
	check(world.owners[world.city.index_of(2, 4)] == 0 and world.owners[world.city.index_of(2, 5)] == 0, "foreign land blocks disconnected purchases")
	check(world.municipalities.a.city.funds() == funds, "only eligible area charged after allowance")
	request.revision = world.revision
	check(world.command("a", request).ok and world.municipalities.a.city.funds() == funds, "repeated overlapping selection costs nothing")

func network() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	host.host(Sc2xDocument.create_empty(32, "Host city").document, 0, "", "Host", "shared")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	check(await until(func() -> bool: return guest.connected), "guest connected")
	guest.request({"kind": "rename_city", "name": "Guest renamed"})
	check(await until(func() -> bool: return host.world.municipalities[guest.token].city.city_name() == "Guest renamed"), "client lobby rename is authoritative")
	check(host.world.city.city_name() == "Host city", "client rename preserves host city")
	host.waiting_for_start = false
	host.publish()
	await until(func() -> bool: return not guest.latest.lobby.waiting)
	var own_funds: int = host.world.municipalities[guest.token].city.funds()
	var host_funds := host.world.city.funds()
	guest.request({"kind": "debug", "action": "add_funds", "value": 1000})
	await create_timer(0.2).timeout
	check(host.world.municipalities[guest.token].city.funds() == own_funds, "client debug request is denied")
	check(host.world.city.funds() == host_funds, "debug does not credit host")
	guest.request({"kind": "rename_city", "name": "Too late"})
	guest.request({"kind": "disaster", "disaster": 7, "point": [5, 5]})
	await create_timer(0.15).timeout
	check(host.world.municipalities[guest.token].city.city_name() == "Guest renamed", "rename blocked after start")
	check(host.world.municipalities[guest.token].engine.active_disaster_type == 0, "client cannot trigger disaster")
	# Real TCP burst exceeds the previous fixed 40-message threshold.
	for index in 100:
		guest.channels[0].send({"type": "cursor", "position": [index % 32, 4]})
	guest.channels[0].flush()
	await create_timer(0.2).timeout
	check(guest.connected and host.identities.size() == 1, "normal catch-up burst does not disconnect")
	guest.channels[0].close()
	check(await until(func() -> bool: return not guest.connected), "unexpected disconnect is detected without pausing")
	check(await until(func() -> bool: return guest.connected), "automatic reconnect restores original identity")
	check(host.world.municipalities.size() == 2 and host.world.municipalities[guest.token].city.funds() == own_funds, "reconnect preserves city and funds")
	host.request({"kind": "speed", "speed": 3})
	check(not host.disconnected_pause and host.world.controller.speed == 3, "host speed releases disconnect pause")
	host.request({"kind": "speed", "speed": 1})
	check(host.world.controller.speed == 1 and host.world.municipalities[guest.token].controller.speed == 1, "host pause applies to every simulation")
	var ended: Array = []
	guest.session_ended.connect(func() -> void: ended.append(true))
	# Leave is ordered behind a backlog; it must never overwrite partial frames.
	for channel: CityTcpChannel in host.channels.values():
		for index in 50:
			channel.send({"type": "ping", "padding": "x".repeat(4096)})
	host.stop()
	check(await until(func() -> bool: return not ended.is_empty()), "deliberate host end reaches client through pending traffic")
	check(guest.reconnect_until == 0, "host end never triggers automatic reconnect")
	guest.stop()
	await until(func() -> bool: return host.retiring_channels.is_empty() and guest.retiring_channels.is_empty(), 3.0)
	host.queue_free()
	guest.queue_free()

func land_rules() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Rules").document)
	world.add_player("a".repeat(48))
	world.add_player("b".repeat(48))
	world.owners[65] = 1
	world.owners[67] = 2
	world.protection[66] = 2
	var selected := [66, 67, 68]
	check(MultiplayerLandRules.purchasable(world.city, world.owners, world.protection, 1, selected, true).is_empty(), "cannot cross foreign reservation")
	world.protection[66] = 1
	check(MultiplayerLandRules.purchasable(world.city, world.owners, world.protection, 1, selected, true) == [66], "only edge-connected eligible subset")
	check(not MultiplayerLandRules.neighbours(31, 32).has(32), "row wrapping never creates adjacency")
	world.owners[66] = 2
	world.protection[66] = 0
	var request := {"kind": "land_request", "revision": world.revision, "start": [2, 2], "finish": [2, 2], "price": 10}
	check(world.command("a".repeat(48), request).ok, "connected bilateral request opens")
	check(world.command("b".repeat(48), {"kind": "land_counter", "revision": world.revision, "offer": "1", "price": 15}).ok, "seller counter creates a replacement record")
	check(not world.offers.has("1") and world.offers.has("2") and world.offers["2"].price == 15, "old terms invalidated and counterprice retained")
	var a: int = world.municipalities["a".repeat(48)].city.funds()
	var b: int = world.municipalities["b".repeat(48)].city.funds()
	var accept := {"kind": "land_accept", "revision": world.revision, "offer": "2"}
	check(world.command("a".repeat(48), accept).ok, "buyer confirms counter")
	check(world.owners[66] == 1 and world.municipalities["a".repeat(48)].city.funds() == a - 15 and world.municipalities["b".repeat(48)].city.funds() == b + 15, "exact ownership and money transfer")
	accept.revision = world.revision
	check(not world.command("a".repeat(48), accept).ok and world.municipalities["a".repeat(48)].city.funds() == a - 15, "replayed acceptance cannot charge twice")
	world.owners[68] = 2
	world.owners[69] = 2
	check(not MultiplayerLandRules.transfer_error(world, "b".repeat(48), "a".repeat(48), [68]).is_empty(), "seller cannot sell an interior bridge")
	world.protection[67] = -1
	check(not MultiplayerLandRules.transfer_error(world, "b".repeat(48), "a".repeat(48), [67]).is_empty(), "public land cannot be traded")
	var saved := world.saved_shared()
	var restored := SharedWorld.new()
	restored.open(Sc2xDocument.create_empty(32, "Restore").document)
	check(restored.restore_shared(saved).is_empty() and restored.protection == world.protection, "protection persists across saving")

func public_corridors() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Public").document)
	world.add_player("a")
	world.add_player("b")
	for tile in [66, 67, 68]:
		world.protection[tile] = -1
	var request := {"kind": "build", "revision": world.revision, "group": 6, "tool": 0, "path": [], "start": [2, 2], "finish": [2, 4]}
	var result := world.command("a", request)
	check(result.ok, "road construction allowed in public corridor: " + str(result.get("error", "")))
	check(world.municipalities.a.city.buildings[67] > 13 and world.municipalities.a.city.buildings[67] == world.municipalities.b.city.buildings[67], "public roads available to both simulations")
	request.group = 0
	request.revision = world.revision
	check(not world.command("b", request).ok, "players cannot demolish shared access")
	check(world.owners[67] == 0, "public construction never privatizes land")

func nonblocking_decisions() -> void:
	var world := CoopWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Calendar").document)
	var result := CityDebugActions.offer_military_base(world.controller, 2)
	check(result.ok, "military proposal setup")
	world.controller.set_speed(5)
	world.advance(0.1)
	check(world.snapshot_status().pending == "military_proposal", "nonblocking military decision is retained")
	var day := world.city.age_in_days()
	for frame in 5:
		world.advance(0.1)
	check(world.city.age_in_days() > day, "pending dialog does not stop calendar")
	check(world.command("a", {"kind": "decision", "accept": false, "revision": world.revision, "policy": world.policy_revision}).ok, "mayor can still answer retained decision")
