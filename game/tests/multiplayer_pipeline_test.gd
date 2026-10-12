extends SceneTree
## Changed pages, complete asynchronous snapshots, relevance and queue ordering.
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func run() -> void:
	await documents()
	interest()
	summaries()
	await large_display()
	print("Multiplayer pipeline checks: %d failures" % failures)
	quit(1 if failures else 0)


func documents() -> void:
	var source := Sc2xDocument.create_empty(128, "Pipeline").document
	var cache := MultiplayerDocument.new()
	var initial := cache.capture(source).merged({"type": "state", "revision": 0})
	var old := MultiplayerDocument.restore(initial)
	var sender := MultiplayerDelta.new()
	var receiver := MultiplayerDelta.new()
	receiver.decode(sender.encode(initial))
	var chunk := source.find_chunk("XBLD")
	chunk.write_decoded_byte(0, 20)
	chunk.write_decoded_byte(16383, 21)
	var changed := cache.capture(source).merged({"type": "state", "revision": 1})
	var wire := sender.encode(changed)
	var decoded := receiver.decode(wire)
	var restored := MultiplayerDocument.restore(decoded, initial, old)
	check(restored != null and restored.find_chunk("XBLD").decoded_payload == chunk.decoded_payload, "distant changed pages reconstruct exactly")
	var copy := source.duplicate_document(true)
	copy.find_chunk("XBLD").write_decoded_byte(4000, 22)
	var latest := cache.capture(copy).merged({"type": "state", "revision": 2})
	var exact := MultiplayerDocument.restore(receiver.decode(sender.encode(latest)))
	check(exact.find_chunk("XBLD").decoded_payload == copy.find_chunk("XBLD").decoded_payload, "page tracking follows a replaced authoritative document")
	copy.find_chunk("XBLD").decoded_payload[8000] = 23
	copy.find_chunk("XBLD").write_decoded_byte(10, 25)
	latest = cache.capture(copy).merged({"type": "state", "revision": 3})
	exact = MultiplayerDocument.restore(receiver.decode(sender.encode(latest)))
	check(exact.find_chunk("XBLD").decoded_payload[8000] == 23 and exact.find_chunk("XBLD").decoded_payload[10] == 25, "mixed imported raw and tracked edits retain every changed page")
	var job := MultiplayerDisplayJob.new()
	job.start(latest, initial, old)
	old.find_chunk("XBLD").write_decoded_byte(5, 99)
	var deadline := Time.get_ticks_msec() + 5000
	while not job.ready() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(job.ready(), "display preparation completes")
	job.finish()
	check(job.document != null and job.document.find_chunk("XBLD").decoded_payload[5] == 0, "worker never reads subsequently mutated live buffers")
	check(job.edit.changed_ids.has("XBLD") and not job.edit.changed_ids.has("ALTM"), "display transaction identifies only changed chunks")
	check(Sc2xDocument.encode(job.document).data == Sc2xDocument.encode(copy).data, "prepared display checkpoint preserves complete save contents")
	var new_cache := MultiplayerDocument.new()
	copy.find_chunk("XBLD").write_decoded_byte(6000, 24)
	var replaced := new_cache.capture(copy).merged({"type": "state", "revision": 4})
	exact = MultiplayerDocument.restore(receiver.decode(sender.encode(replaced)))
	check(exact.find_chunk("XBLD").decoded_payload == copy.find_chunk("XBLD").decoded_payload, "new capture epoch cannot suppress a changed page")


func interest() -> void:
	var world := CoopWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Interest").document)
	var scheduler := MultiplayerInterest.new()
	check(scheduler.receive("a", {"bounds": [4, 4, 8, 8], "details": false}, 32), "valid viewport accepted")
	check(not scheduler.receive("a", {"bounds": [31, 31, 8, 8], "details": false}, 32), "out-of-map viewport rejected")
	scheduler.published("a", "a", {"revision": 3, "policy": 0}, 1000)
	world.tile_versions[30 * 32 + 30] = 4
	world.revision = 4
	check(not scheduler.due(world, "a", "a", 1200), "distant updates yield to visible work")
	check(scheduler.due(world, "a", "a", 2000), "distant changes cannot starve")
	world.tile_versions[5 * 32 + 5] = 4
	world.revision = 5
	check(scheduler.due(world, "a", "a", 1200), "visible change has immediate publication priority")
	check(scheduler.due(world, "a", "b", 1200), "city switch bypasses old viewport age")
	world.tile_versions.fill(0)
	scheduler.forced["a"] = true
	check(scheduler.due(world, "a", "a", 1200), "own action bypasses relevance delay")
	check(world.revision == 5 and world.city.buildings.count(0) == 1024, "interest scheduling never advances or edits the world")


func summaries() -> void:
	var channel := CityTcpChannel.new(StreamPeerTCP.new())
	channel.send_latest({"type": "summary", "sequence": 1, "values": {"goal": {"target": 10}}})
	channel.send_latest({"type": "summary", "sequence": 2, "values": {"roster": [{"funds": 20}]}})
	check(channel.ephemeral.summary.sequence == 2 and channel.ephemeral.summary.values.has("goal") and channel.ephemeral.summary.values.has("roster"), "coalescing retains unrelated pending summary fields")
	var session := CoopSession.new()
	session.latest = {"revision": 8, "summary_sequence": 4, "goal": {"target": 100}}
	session.accept_state({"type": "state", "revision": 9, "summary_sequence": 3, "goal": {"target": 10}})
	check(session.latest.goal.target == 100 and session.local_revision == 9, "older delayed checkpoint cannot roll back current global summary")
	session.free()


func large_display() -> void:
	var app: CityApplication = load("res://main.tscn").instantiate()
	load("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.coop.port.min_value = 0
	app.coop.port.value = 0
	app.coop.host_document(Sc2xDocument.create_empty(256, "Async display").document)
	app.coop.session.waiting_for_start = false
	var before := app.document_state.city.funds()
	app.coop.session.request({"kind": "build", "group": CityToolIds.Group.WATER,
		"tool": CityToolIds.Water.PUMP, "start": [4, 4], "finish": [4, 4], "path": [], "dragged": false})
	check(not app.coop.windows.pending_builds.is_empty(), "acknowledged build retains its preview until display commit")
	var deadline := Time.get_ticks_msec() + 15000
	while app.coop.display_revision != app.coop.session.world.revision and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	check(app.coop.display_revision == app.coop.session.world.revision, "large display catches up without blocking the main thread")
	check(app.document_state.city.building_id(4, 4) == BuildingSites.tile_for_tool(CityToolIds.Group.WATER, CityToolIds.Water.PUMP) and app.document_state.city.funds() == before - 100, "building and payment become visible in one transaction")
	var revision := app.coop.session.world.revision
	var displayed: Dictionary = app.coop.windows.state.duplicate()
	app.coop.windows.state["view_owner"] = "previous-city"
	app.coop.bulldoze(Vector2i(4, 4))
	check(app.coop.session.world.revision == revision, "coordinates from an old city cannot edit the incoming city")
	app.coop.windows.state = displayed
	app.coop.session.world.city.set_funds(before)
	app.coop.session.world.revision += 1
	app.coop.session.publish()
	app.coop.poll_display()
	app.coop.leave()
	check(app.coop.display_job == null and app.coop.pending_display.is_empty(), "leaving joins preparation and discards queued display state")
	app.queue_free()
	await process_frame
