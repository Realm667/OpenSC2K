extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func command(world: CoopWorld, actor: String, request: Dictionary) -> Dictionary:
	request["revision"] = world.revision
	return world.command(actor, request)

func run() -> void:
	var a := "a".repeat(48)
	var b := "b".repeat(48)
	var world := RegionWorld.new()
	check(world.open(Sc2xDocument.create_empty(32, "Region test").document), "open region")
	check(world.add_player(a).is_empty() and world.add_player(b).is_empty(), "independent region cities")
	var build := {"kind": "build", "group": 9, "tool": 0, "start": [5, 5], "finish": [5, 5], "path": [[5, 5]], "dragged": false}
	check(command(world, a, build.duplicate(true)).ok, "region does not require land purchase")
	check(world.municipalities[b].city.zones[5 * 32 + 5] == 0, "building does not leak into neighbour")
	var visit := build.duplicate(true)
	visit.view_owner = b.sha256_text()
	check(not command(world, a, visit).ok, "spectator cannot build in neighbour")
	check(command(world, b, {"kind": "disaster", "disaster": 7, "point": [5, 5], "policy": 0}).ok, "region neighbour disaster")
	world.municipalities[a].city.document.set_misc_u32(Sc2MiscLayout.MILITARY_BASE_TYPE, 2)
	var help := command(world, a, {"kind": "build", "group": 2, "tool": 2, "finish": [6, 6], "view_owner": b.sha256_text()})
	check(help.ok, "own military assists viewed region: " + str(help.message))
	check(world.municipalities[a].engine.active_disaster_type == 0, "helper outside disaster mode")
	var viewing := world.snapshot_region(a, b)
	check(viewing.visiting and viewing.disaster == 0 and viewing.disasters.size() == 1, "spectator receives neighbour alert without own disaster")
	check(not viewing.dispatch_owners.is_empty() and viewing.dispatch_owners.values()[0].actor == a.sha256_text(), "aid retains owner marker")
	var state := world.saved_shared()
	var restored := RegionWorld.new()
	restored.open(world.template)
	check(restored.restore_shared(state).is_empty(), "region cities saved and restored")
	check(restored.municipalities[a].city.zones == world.municipalities[a].city.zones, "owner city retained")
	check(restored.municipalities[b].dispatch_owners == world.municipalities[b].dispatch_owners, "foreign aid persists")
	var goal := MultiplayerGoal.new()
	goal.kind = "wealth"
	goal.target = 30000
	var members := {a: {"name": "Alice"}, b: {"name": "Bob"}}
	world.municipalities[a].city.set_funds(45000)
	world.municipalities[a].city.document.set_misc_u32(Sc2MiscLayout.BONDS, 2)
	check(not goal.evaluate(world, members), "wealth subtracts debt")
	world.municipalities[a].city.set_funds(50000)
	check(not goal.evaluate(world, members), "goal begins one-year hold")
	world.municipalities[a].city.set_age_in_days(world.municipalities[a].city.age_in_days() + CityCalendar.DAYS_PER_YEAR)
	check(goal.evaluate(world, members) and goal.winners[0].seat == a.sha256_text(), "net wealth target declares winner")
	check(not goal.evaluate(world, members), "victory emitted once")
	check(goal.blocked(), "victory pauses until decision")
	goal.unscored = true
	check(not goal.blocked(), "unscored continuation releases end pause")
	var loaded_goal := MultiplayerGoal.new()
	loaded_goal.restore(goal.saved())
	check(loaded_goal.unscored and loaded_goal.winners == goal.winners, "victory history survives save")
	land_allowance()
	print("Multiplayer region checks: %d failures" % failures)
	quit(1 if failures else 0)

func land_allowance() -> void:
	var world := SharedWorld.new()
	world.land_price = 5
	world.starter_tiles = 1024
	world.open(Sc2xDocument.create_empty(32, "Land allowance").document)
	var actor := "c".repeat(48)
	world.add_player(actor)
	var funds := world.city.funds()
	var flags := world.city.document.find_chunk("XBIT").decoded_payload.duplicate()
	flags[2 * 32 + 2] |= Sc2TileFlags.WATER
	world.city.document.find_chunk("XBIT").set_decoded_payload(flags)
	world.city.resync_mirrors(["XBIT"])
	var dry := {"kind": "land_buy", "start": [2, 2], "finish": [2, 3], "price": 5}
	check(command(world, actor, dry).ok, "dry rectangle ignores water")
	check(world.owners[2 * 32 + 2] == 0 and world.owners[2 * 32 + 3] == 1, "only dry tile owned")
	check(world.city.funds() == funds and world.land_allowance[actor] == 1275, "separate starter allowance protects treasury")
	check(command(world, actor, {"kind": "land_buy", "start": [2, 2], "finish": [2, 2], "include_water": true, "price": 5}).ok, "explicit water purchase")
	check(world.owners[2 * 32 + 2] == 1 and world.land_allowance[actor] == 1270, "water charged only when selected")
	var record := world.saved_shared()
	var loaded := SharedWorld.new()
	loaded.open(world.template)
	check(loaded.restore_shared(record).is_empty() and loaded.land_allowance == world.land_allowance and loaded.land_price == 5, "price and allowance persist")
