extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func buy(world: SharedWorld, actor: String, first: Array, last: Array) -> Dictionary:
	var request := {"kind": "land_buy", "revision": world.revision, "start": first, "finish": last}
	var quote := world.command(actor, request)
	if quote.has("choices"):
		request.merge(quote.choices[0].fields, true)
	return world.command(actor, request)


func run() -> void:
	var a := "a".repeat(48)
	var b := "b".repeat(48)
	var world := SharedWorld.new()
	check(world.open(Sc2xDocument.create_empty(32, "Shared test").document), "open shared")
	check(world.add_player(a).is_empty(), "host municipality")
	var add_error := world.add_player(b)
	check(add_error.is_empty(), "independent municipalities: " + add_error)
	if not add_error.is_empty():
		quit(1)
		return
	var initial: int = world.municipalities[b].city.funds()
	check(buy(world, a, [2, 2], [12, 12]).ok, "neutral land purchase")
	check(world.municipalities[b].city.funds() == initial, "land cost charged only to buyer")
	check(buy(world, b, [2, 2], [12, 12]).ok, "foreign land creates purchase request")
	check(world.municipalities[b].city.funds() == initial, "failed purchase charges nothing")
	check(buy(world, a, [25, 25], [25, 25]).ok, "disconnected land allowed")
	var build := {"kind": "build", "revision": world.revision, "group": 9, "tool": 0,
		"start": [5, 5], "finish": [5, 5], "path": [[5, 5]], "dragged": false}
	check(world.command(a, build).ok, "owner can zone")
	check(not world.command(b, build).ok, "other player cannot zone owned tile")
	check(world.municipalities[b].city.zones[world.city.index_of(5, 5)] == 0, "other economy does not simulate owner's zones")
	var snapshot := world.snapshot_for(b)
	var shown := Sc2File.new()
	check(shown.parse(Marshalls.base64_to_raw(snapshot.city)), "shared visible map parses")
	check(CityState.from_document(shown).zones[world.city.index_of(5, 5)] != 0, "other city visible on common map")
	var rates := Array(BudgetPhase.funding_values(world.municipalities[a].city))
	rates[0] = 19
	check(world.command(a, {"kind": "budget", "revision": world.revision, "policy": 0, "values": rates, "auto": true}).ok, "municipal tax policy")
	check(BudgetPhase.funding_values(world.municipalities[b].city)[0] != 19, "other municipal taxes unaffected")
	var offer_id := str(world.next_offer)
	var funds_a: int = world.municipalities[a].city.funds()
	var funds_b: int = world.municipalities[b].city.funds()
	check(world.command(a, {"kind": "land_offer", "start": [5, 5], "finish": [5, 5], "price": 100, "revision": world.revision}).ok, "owner offers developed parcel")
	check(world.command(b, {"kind": "land_accept", "offer": offer_id, "revision": world.revision}).ok, "consensual developed parcel transfer")
	check(world.municipalities[a].city.funds() == funds_a + 100 and world.municipalities[b].city.funds() == funds_b - 100, "atomic purchase accounts")
	check(world.municipalities[a].city.zones[world.city.index_of(5, 5)] == 0 and world.municipalities[b].city.zones[world.city.index_of(5, 5)] != 0, "zone belongs only to buyer's simulation")
	check(not world.command(b, {"kind": "land_accept", "offer": offer_id, "revision": world.revision}).ok, "offer cannot be paid twice")
	check(buy(world, b, [20, 20], [24, 24]).ok, "second municipality territory")
	var fire_request := {"kind": "disaster", "disaster": 7, "point": [5, 5], "revision": world.revision, "policy": world.municipalities[b].policy_revision}
	check(world.command(b, fire_request).ok, "start own disaster")
	check(world.municipalities[b].engine.active_disaster_type != 0, "target municipality in disaster mode")
	check(world.municipalities[a].engine.active_disaster_type == 0, "helper remains outside disaster mode")
	var help := {"kind": "build", "group": 2, "tool": 2, "finish": [20, 20], "revision": world.revision}
	check(world.command(a, help).ok, "own military unit helps neighbor")
	check(world.municipalities[b].dispatch_owners.values().any(func(unit: Dictionary) -> bool: return unit.actor == a.sha256_text()), "foreign assistance retains dispatcher identity")
	check(world.command(a, {"kind": "recall", "revision": world.revision}).ok, "helper can recall own foreign units")
	check(world.municipalities[b].dispatch_owners.is_empty(), "foreign unit removed on recall")
	var record := world.saved_shared()
	var restored := SharedWorld.new()
	check(restored.open(world.template), "restore terrain")
	check(restored.restore_shared(record).is_empty(), "restore municipal state")
	check(restored.owners == world.owners, "ownership survives restore")
	check(restored.municipalities[a].city.funds() == world.municipalities[a].city.funds(), "municipal balance survives restore")
	var host := CoopSession.new()
	root.add_child(host)
	host.token = a
	check(host.host(Sc2xDocument.create_empty(32, "Save test").document, 24587, "", "Alice", "coop", false).is_empty(), "password optional")
	host.requested_speed[b] = 5
	host.requested_speed[a] = 4
	host.apply_speed()
	check(host.world.controller.speed == 4, "passive guest does not cap speed at Turtle")
	host.requested_speed[b] = 1
	host.apply_speed()
	check(host.world.controller.speed == 1, "explicit guest pause respected")
	host.requested_speed[b] = 5
	host.apply_speed()
	check(host.world.controller.speed == 4, "resume restores requested running speed")
	var path := "user://multiplayer-next-save.sc2x"
	check(host.save_city(path).is_empty(), "normal city includes session data")
	var saved := Sc2File.new()
	check(saved.parse(FileAccess.get_file_as_bytes(path)), "normal city loads")
	check(saved.sc2x_extra_entries.has("multiplayer.json"), "embedded session metadata")
	check(host.restore_embedded(saved).is_empty(), "embedded session restored")
	host.stop()
	host.queue_free()
	atmosphere_choices()
	military_ownership()
	transfer_building()
	await shared_network()
	print("Multiplayer next checks: %d failures" % failures)
	quit(1 if failures else 0)


func shared_network() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	var messages: Array = []
	var positions: Array = []
	guest.chat_received.connect(func(entry: Dictionary) -> void: messages.append(entry))
	guest.presence_received.connect(func(value: Array) -> void: positions.assign(value))
	host.cursor_source = func() -> Vector2i: return Vector2i(7, 8)
	check(host.host(Sc2xDocument.create_empty(32, "TCP Shared").document, 0, "", "Alice", "shared", false).is_empty(), "Shared TCP host")
	check(guest.join("127.0.0.1", host.server.get_local_port(), "", "Bob").is_empty(), "Shared TCP guest")
	for frame in 100:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected and guest.latest.get("mode") == "shared", "guest receives Shared map")
	host.send_chat("[b]literal message[/b]")
	guest.send_chat("reply")
	guest.request({"kind": "land_buy", "start": [8, 8], "finish": [10, 10], "price": 90})
	for frame in 60:
		await create_timer(0.01).timeout
		if messages.size() == 2 and positions.size() == 2 and guest.local_revision == host.world.revision:
			break
	check(messages.size() == 2 and messages[1].name == "Bob", "chat sender comes from authenticated member")
	check(positions.any(func(item: Dictionary) -> bool: return item.name == "Alice" and int(item.cursor[0]) == 7 and int(item.cursor[1]) == 8), "remote cursor uses map coordinates: " + str(positions))
	check(host.world.owners[8 * 32 + 8] == 2, "guest land purchase authoritative")
	check(host.latest.roster[1].color == guest.player_color, "host preserves the client's selected colour")
	var document := Sc2File.new()
	document.parse(Marshalls.base64_to_raw(guest.latest.city))
	check(not document.sc2x_extra_entries.has("multiplayer.json"), "private reconnect identities never sent inside public city")
	var path := "user://multiplayer-shared-save.sc2x"
	check(host.save_city(path).is_empty(), "Shared normal save")
	var saved := Sc2File.new()
	check(saved.parse(FileAccess.get_file_as_bytes(path)), "Shared normal load")
	guest.stop()
	check(host.restore_embedded(saved).is_empty(), "Shared embedded municipalities restore")
	check(host.world is SharedWorld and host.world.owners[8 * 32 + 8] == 2, "Shared mode and ownership restored")
	host.stop()
	host.queue_free()
	guest.queue_free()


func transfer_building() -> void:
	var seller := CityState.from_document(Sc2xDocument.create_empty(32, "Seller").document)
	var buyer := CityState.from_document(Sc2xDocument.create_empty(32, "Buyer").document)
	var result := BuildingCommand.apply(seller, 13, 0, Vector2i(10, 10), SimLfsrRandom.new(1), SimRandom.new(1))
	check(result.ok, "build facility for transfer")
	var tiles: Array = []
	for tile in seller.buildings.size():
		if seller.buildings[tile] > 13:
			tiles.append(tile)
	check(tiles.size() > 1, "facility spans multiple tiles")
	if tiles.is_empty():
		return
	var partial := SharedLandTransfer.stage(seller, buyer, [tiles[0]])
	check(not partial.error.is_empty(), "partial building transfer rejected")
	var transfer := SharedLandTransfer.stage(seller, buyer, tiles)
	check(transfer.error.is_empty(), "complete facility transfer succeeds: " + transfer.error)
	if not transfer.error.is_empty():
		return
	for tile: int in tiles:
		check(transfer.seller.buildings[tile] == 0 and transfer.buyer.buildings[tile] == seller.buildings[tile], "facility exists only in buyer municipality")
	var marker := OverlayData.facility_at(transfer.buyer.text_overlays, tiles[0])
	check(OverlayData.is_facility(marker), "facility marker retained after transfer")
	var data: PackedByteArray = transfer.buyer.document.find_chunk("XMIC").decoded_payload
	check((OverlayData.facility_record(marker) + 1) * Sc2MicrosimLayout.RECORD_SIZE <= data.size(), "facility points to buyer record")


func military_ownership() -> void:
	var world := SharedWorld.new()
	var actor := "m".repeat(48)
	check(world.open(Sc2xDocument.create_empty(128, "Military ownership").document), "military terrain")
	check(world.add_player(actor).is_empty(), "military municipality")
	var child: CoopWorld = world.municipalities[actor]
	child.engine.forced_military_base_type = MilitaryProposalPhase.BASE_ARMY
	var seed := child.engine.game_random.state
	check(not world.military_land_error(actor).is_empty(), "military base cannot claim neutral land")
	check(child.engine.game_random.state == seed, "military ownership preview preserves randomness")
	world.owners.fill(1)
	check(world.military_land_error(actor).is_empty(), "military base allowed on owned terrain")


func atmosphere_choices() -> void:
	var encoded := JSON.stringify({"day_enabled": true, "day_mode": 1, "day_hour": 22,
		"season_mode": 2, "season_fixed": 3, "weather_mode": 2, "weather_fixed": 6, "cloud_mode": 4})
	var options := CityVisualEnvironment.normalized_network_options(JSON.parse_string(encoded))
	check(options.day_mode == 1 and options.day_hour == 22, "wire-format fixed time remains fixed")
	check(options.season_mode == 2 and options.season_fixed == 3, "wire-format fixed season retained")
	check(options.weather_mode == 2 and options.weather_fixed == 6 and options.cloud_mode == 4, "wire-format weather/cloud choices retained")
