extends SceneTree
## Loopback transport and authoritative simulation timings, not GPU/LAN claims.

var failures := 0
var samples: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	return predicate.call()

func run() -> void:
	for mode in ["shared", "region"]:
		for count in [2, 4, 8]:
			await scenario(mode, count)
	print("MULTIPLAYER_LOAD=" + JSON.stringify(samples))
	print("Multiplayer load checks: %d failures" % failures)
	quit(1 if failures else 0)

func scenario(mode: String, count: int) -> void:
	var host := CoopSession.new()
	root.add_child(host)
	check(host.host(Sc2xDocument.create_empty(128, "Load test").document, 0, "", "Host", mode).is_empty(), "listen " + mode)
	var peers: Array[CoopSession] = [host]
	for index in count - 1:
		var guest := CoopSession.new()
		root.add_child(guest)
		peers.append(guest)
		guest.join("127.0.0.1", host.server.get_local_port(), "", "Player %d" % (index + 2))
	check(await wait_for(func() -> bool: return peers.all(func(peer: CoopSession) -> bool: return peer.connected)), "all clients join")
	check(await wait_for(func() -> bool: return peers.all(func(peer: CoopSession) -> bool: return peer.latest.get("lobby", {}).get("generation") == host.lobby_generation)), "all clients see final lobby roster")
	for peer in peers:
		peer.request({"kind": "lobby_ready", "ready": true})
	check(await wait_for(host.can_start_lobby), "all clients ready")
	host.request({"kind": "lobby_start"})
	host.request({"kind": "speed", "speed": 1})
	check(await wait_for(func() -> bool: return peers.all(func(peer: CoopSession) -> bool: return not peer.latest.get("lobby", {}).get("waiting", true))), "start broadcast")
	for width in [4, 12, 24]:
		var times: Array[float] = []
		var before_bytes := 0
		for channel: CityTcpChannel in host.channels.values():
			before_bytes += channel.bytes_sent
		for peer in peers:
			var slot: Dictionary = host.starts.positions[peer.token]
			var center := Vector2i(int(slot.point[0]), int(slot.point[1]))
			var begin := center - Vector2i(12, 12)
			var end := begin + Vector2i(width - 1, width - 1)
			var start_time := Time.get_ticks_usec()
			peer.request({"kind": "build", "group": CityToolIds.Group.RESIDENTIAL, "tool": 0,
				"start": [begin.x, begin.y], "finish": [end.x, end.y], "path": [], "dragged": false})
			var expected := int(peer.next_command) - 1
			check(await wait_for(func() -> bool: return int(host.members[peer.token].sequence) == expected), "command acknowledged")
			var revision := host.world.revision
			check(await wait_for(func() -> bool: return peer.local_revision >= revision), "changed city converges")
			times.append((Time.get_ticks_usec() - start_time) / 1000.0)
			var city: CityState = host.world.municipalities[peer.token].city
			check(city.zones[city.index_of(end.x, end.y)] != 0, "build was really accepted")
		var after_bytes := 0
		for channel: CityTcpChannel in host.channels.values():
			after_bytes += channel.bytes_sent
		var started := Time.get_ticks_usec()
		host.world.set_shared_speed(2)
		for step in 12:
			host.world.advance(0.25)
		host.world.set_shared_speed(1)
		var simulation_usec := Time.get_ticks_usec() - started
		times.sort()
		samples.append({"mode": mode, "players": count, "developed_zone_tiles_per_city": width * width,
			"median_build_ms": times[times.size() / 2], "maximum_build_ms": times.back(),
			"host_wire_bytes": after_bytes - before_bytes, "simulation_12_updates_ms": simulation_usec / 1000.0,
			"all_peers_static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
	for peer in peers:
		peer.stop()
		peer.queue_free()
	await process_frame
