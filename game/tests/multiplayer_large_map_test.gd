extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var world := CoopWorld.new()
	check(world.open(Sc2xDocument.create_empty(256, "Expanded multiplayer").document), "256 map accepted")
	check(world.tile_versions.size() == 256 * 256, "expanded ownership conflict indexes")
	var state := world.snapshot()
	var document := Sc2File.new()
	check(document.parse(Marshalls.base64_to_raw(state.city)) and document.map_size == 256, "expanded checkpoint round trip")
	world = null
	# A transfer larger than the former whole-message limit uses bounded chunks.
	var source := {"type": "state", "city": "abcdef".repeat(800000), "revision": 8}
	var sender := MultiplayerStateStream.new()
	var receiver := MultiplayerStateStream.new()
	var channel := CityTcpChannel.new(StreamPeerTCP.new())
	check(sender.open_output(source), "large stream spooled")
	var result: Dictionary = {}
	for part in 110:
		var done := sender.pump(channel)
		check(channel.output.size() < 128 * 1024, "queue remains bounded independently of map size")
		var packet: Dictionary = JSON.parse_string(channel.output.slice(4).get_string_from_utf8())
		channel.output.clear()
		var value := receiver.receive(packet)
		if not value.is_empty():
			result = value
		if done:
			break
	check(receiver.complete and not receiver.failed and result.get("city") == source.city, "large stream byte-exact reconstruction")
	check(sender.path.is_empty() and receiver.path.is_empty(), "temporary transfers cleaned")
	var malformed := MultiplayerStateStream.new()
	malformed.receive({"type": "state_begin", "bytes": 10, "sha256": "a".repeat(64)})
	malformed.receive({"type": "state_part", "offset": 1, "data": "eA=="})
	check(malformed.failed, "out-of-order stream rejected")
	malformed.close()
	await network_map()
	print("Multiplayer large map checks: %d failures" % failures)
	quit(1 if failures else 0)

func network_map() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	check(host.host(Sc2xDocument.create_empty(512, "Large TCP").document, 0, "", "Host", "shared", false).is_empty(), "large Shared host")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	var deadline := Time.get_ticks_msec() + 30000
	while not guest.connected and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(guest.connected and guest.latest.get("owners", []).size() == 512 * 512, "large city and ownership streamed over real TCP")
	if guest.connected:
		guest.request({"kind": "land_buy", "start": [511, 511], "finish": [511, 511], "price": 10})
		deadline = Time.get_ticks_msec() + 30000
		while int(guest.latest.owners[-1]) == 0 and Time.get_ticks_msec() < deadline:
			await create_timer(0.01).timeout
		check(int(guest.latest.owners[-1]) == 2 and host.world.owners[-1] == 2, "far boundary purchase converges")
	guest.stop()
	host.stop()
	guest.queue_free()
	host.queue_free()
	await process_frame
