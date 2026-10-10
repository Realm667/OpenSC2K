extends SceneTree
## Real commands, ordinary power/transport and native growth in both municipalities.
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)
func run() -> void:
	var setup := NewCitySetup.create(EmptyCityTemplate.create(64), "Growth", "Mayor", 1, 1900, SimRandom.new(42))
	var world := SharedWorld.new()
	check(world.open(Sc2xDocument.from_new_city(setup.document, "Growth", "Mayor").document), "new city opens")
	for actor in ["a", "b"]:
		check(world.add_player(actor).is_empty(), "municipality added")
	for tile in world.owners.size():
		world.owners[tile] = 1 if tile < 32 * 64 else 2
	for actor in ["a", "b"]:
		var offset := 0 if actor == "a" else 32
		var child: CoopWorld = world.municipalities[actor]
		child.city.set_auto_budget_enabled(true)
		child.city.set_no_disasters_enabled(true)
		for spec in [[3,2,8,8,8,8],[6,0,12,7,12,30],[9,0,9,13,11,27],[11,0,13,13,15,27],[3,0,8,11,8,27],[3,0,8,13,15,13]]:
			var request := {"kind":"build", "group":spec[0], "tool":spec[1], "start":[spec[2]+offset,spec[3]], "finish":[spec[4]+offset,spec[5]], "path":[], "dragged":true, "revision":world.revision}
			check(world.command(actor, request).ok, "ordinary construction succeeds")
	world.set_shared_speed(5)
	for tick in 601:
		world.advance(0.2)
	for actor in ["a", "b"]:
		var child: CoopWorld = world.municipalities[actor]
		var homes := 0
		for tile in child.city.buildings.size():
			if child.city.buildings[tile] >= 0x70 and child.city.buildings[tile] <= 0x8b:
				homes += 1
		check(homes > 10 and child.city.age_in_days() >= 600 and child.error.is_empty(), "both municipalities grow real buildings over two years")
		for viewer in ["a", "b"]:
			var doc := Sc2File.new()
			check(doc.parse(Marshalls.base64_to_raw(world.snapshot_for(viewer).city)), "shared snapshot decodes")
			var displayed := CityState.from_document(doc)
			for tile in world.owners.size():
				if world.owners[tile] == world.actors.find(actor)+1:
					check(displayed.buildings[tile] == child.city.buildings[tile], "growth reaches both player views")
	var child: CoopWorld = world.municipalities.b
	child.city.set_auto_budget_enabled(false)
	child.city.set_age_in_days(899)
	child.engine.clock.city_days = 899
	child.city.document.set_misc_u32(Sc2MiscLayout.YEAR_END, 1)
	child.controller.accumulator_msec = 0
	child.controller.simulation_ready = true
	world.snapshot_for("b")
	world.advance(0.001)
	var state := world.snapshot_for("b")
	check(child.controller.interaction_blocked and state.blocked and state.pending == "annual_budget", "between-tick annual decision is published, never hidden behind cached city")
	var budget := {"kind":"budget", "revision":world.revision, "policy":child.policy_revision, "values":Array(BudgetPhase.funding_values(child.city)), "auto":true}
	check(world.command("b", budget).ok, "owner resolves blocking budget")
	var day := child.city.age_in_days()
	world.advance(0.2)
	check(child.city.age_in_days() > day, "shared simulation resumes after decision")
	print("Multiplayer growth checks: %d failures" % failures)
	quit(1 if failures else 0)
