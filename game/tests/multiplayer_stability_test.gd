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
	check(world.owners[world.city.index_of(2, 4)] == 1 and world.owners[world.city.index_of(2, 5)] == 1, "neutral subset purchased")
	check(world.municipalities.a.city.funds() == funds - 5, "only eligible area charged after allowance")
	request.revision = world.revision
	check(world.command("a", request).ok and world.municipalities.a.city.funds() == funds - 5, "repeated overlapping selection costs nothing")

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
	check(await until(func() -> bool: return host.world.municipalities[guest.token].city.funds() == own_funds + 1000), "debug funds applied to requesting city")
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
	check(await until(func() -> bool: return host.disconnected_pause and not guest.connected), "unexpected disconnect pauses host")
	check(await until(func() -> bool: return guest.connected), "automatic reconnect restores original identity")
	check(host.world.municipalities.size() == 2 and host.world.municipalities[guest.token].city.funds() == own_funds + 1000, "reconnect preserves city and funds")
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
