extends SceneTree

var failures := 0
var A := "a".repeat(48)
var B := "b".repeat(48)
var C := "c".repeat(48)

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func make_world(region := false) -> SharedWorld:
	var world: SharedWorld = RegionWorld.new() if region else SharedWorld.new()
	check(world.open(Sc2xDocument.create_empty(32, "Competition").document), "open fixture")
	for actor: String in [A, B, C]:
		check(world.add_player(actor).is_empty(), "create municipality")
	return world

func run() -> void:
	timed(false)
	timed(true)
	reservations()
	print("Multiplayer timed score and reservation consent test: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func timed(region: bool) -> void:
	var world := make_world(region)
	var members := {A: {"name": "Alice"}, B: {"name": "Bob"}, C: {"name": "Late", "ranked": false}}
	var goal := MultiplayerGoal.new()
	goal.kind = "timed_score"
	goal.duration_days = 300
	world.city.set_age_in_days(150)
	world.city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 100)
	world.city.set_funds(2000)
	world.municipalities[B].city.set_funds(3000)
	world.municipalities[C].city.set_funds(2000000)
	check(not goal.evaluate(world, members) and goal.start_age == -1, "lobby does not start the clock")
	goal.begin(world)
	check(goal.end_year == world.city.founding_year() + 1 and goal.start_age == 150, "duration starts from actual date")
	check(goal.city_value(world.city, A, null) == 3000, "population and wealth combine without rounding")
	world.city.document.set_misc_u32(Sc2MiscLayout.BONDS, 1)
	var loans := MultiplayerLoans.new()
	loans.contracts.append({"borrower": A, "status": "active", "principal": 10000, "arrears": 17})
	check(goal.city_value(world.city, A, loans) == 3000 - BondCommand.BOND_VALUE - 10017, "bank and player debt including arrears deducted")
	world.city.document.set_misc_u32(Sc2MiscLayout.BONDS, 0)
	world.city.set_age_in_days(449)
	check(not goal.evaluate(world, members) and goal.elapsed_days == 299, "no early victory")
	check(not goal.evaluate(world, members) and goal.elapsed_days == 299, "paused clock does not advance on repeated evaluation")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(goal.saved()))
	check(MultiplayerGoal.valid(saved, 32), "timed state validates after JSON roundtrip")
	var restored := MultiplayerGoal.new()
	restored.restore(saved)
	restored.begin(world)
	check(restored.start_age == 150, "reconnect cannot extend deadline")
	world.city.set_age_in_days(450)
	check(restored.evaluate(world, members) and restored.winners.size() == 2, "exact deadline shares tied victory; late city excluded")
	check(restored.final_scores.size() == 2 and restored.final_scores[A.sha256_text()] == 3000, "final standings freeze exact scores")
	world.city.set_funds(123456)
	world.city.set_age_in_days(451)
	check(not restored.evaluate(world, members) and restored.final_scores[A.sha256_text()] == 3000, "later changes cannot alter result or announce again")
	check(MultiplayerGoal.valid(restored.saved(), 32), "completed contest can be saved")
	var invalid := restored.saved()
	invalid.duration_days = 0
	check(not MultiplayerGoal.valid(invalid, 32), "invalid duration rejected")
	invalid = restored.saved()
	invalid.elapsed_days = 299
	check(not MultiplayerGoal.valid(invalid, 32), "premature saved victory rejected")
	TranslationServer.set_locale("en")
	check(MultiplayerGoal.points(-1) == "−0.001" and MultiplayerGoal.points(3010) == "3.01", "exact fractional and negative points displayed")
	TranslationServer.set_locale("de")
	check(MultiplayerGoal.points(1234567) == "1.234,567", "localized point precision")
	goal.reset_clock(world)
	goal.begin(world)
	world.city.set_age_in_days(goal.start_age + 300)
	world.city.set_funds(2001)
	check(goal.evaluate(world, members) and goal.winners.size() == 1 and goal.winners[0].seat == A.sha256_text(), "one dollar advantage is not rounded to tie")
	goal.winners.clear()
	goal.reset_clock(world)
	check(goal.start_age == -1 and goal.elapsed_days == 0 and goal.final_scores.is_empty(), "rematch resets clock and frozen scores")
	var running := make_world(region)
	goal.begin(running)
	running.set_shared_speed(GameSpeedController.Speed.CHEETAH)
	for frame in 1500:
		goal.advance(running, 0.25)
		if running.city.age_in_days() >= 300:
			break
	check(running.city.age_in_days() == 300 and running.municipalities[B].city.age_in_days() == 300, "long simulation frame stops exactly on deadline for every city: %d, %d (%s)" % [running.city.age_in_days(), running.municipalities[B].city.age_in_days(), running.error])
	check(running.controller.speed == GameSpeedController.Speed.CHEETAH, "deadline snapshot preserves host speed")

func command(world: SharedWorld, actor: String, message: Dictionary) -> Dictionary:
	message["revision"] = world.revision
	return world.command(actor, message)

func reservations() -> void:
	var world := make_world()
	var tile := world.city.index_of(10, 10)
	var adjacent := world.city.index_of(9, 10)
	world.owners[adjacent] = 2
	world.protection[tile] = 1
	world.protection[tile + 1] = 1
	world.protection[tile + 2] = -1
	world.land_allowance[B] = 100000
	var funds_a: int = world.city.funds()
	var funds_b: int = world.municipalities[B].city.funds()
	var request := {"kind": "land_request", "start": [10, 10], "finish": [10, 10], "price": 0}
	check(command(world, B, {"kind": "land_buy", "start": [10, 10], "finish": [10, 10]}).ok and world.owners[tile] == 0, "direct purchase cannot bypass reservation")
	check(not command(world, C, request).ok, "detached buyer cannot request reserved land")
	check(command(world, B, request).ok, "adjacent buyer can request reserved land")
	var key := str(world.next_offer - 1)
	check(world.offers[key].price == world.land_price and world.protection[tile] == 1, "client amount ignored; request preserves reservation")
	check(world.municipalities[B].city.funds() == funds_b, "request charges nothing")
	check(not command(world, B, request).ok, "duplicate request rejected")
	check(not command(world, B, {"kind": "land_accept", "offer": key}).ok, "buyer cannot self-approve")
	check(not command(world, C, {"kind": "land_accept", "offer": key}).ok, "third player cannot approve")
	check(not command(world, A, {"kind": "land_counter", "offer": key, "price": 0}).ok, "fixed payment cannot be counteroffered")
	var copy := SharedWorld.new()
	copy.open(world.template)
	check(copy.restore_shared(JSON.parse_string(JSON.stringify(world.saved_shared()))).is_empty() and copy.offers[key].reservation, "pending consent survives save and restore")
	check(command(copy, A, {"kind": "land_accept", "offer": key}).ok, "restored owner can approve")
	check(command(world, A, {"kind": "land_decline", "offer": key}).ok and world.protection[tile] == 1, "decline retains full protection")
	check(command(world, B, request).ok, "buyer can send new request")
	key = str(world.next_offer - 1)
	world.municipalities[B].city.set_funds(0)
	check(not command(world, A, {"kind": "land_accept", "offer": key}).ok and world.protection[tile] == 1 and world.owners[tile] == 0, "insufficient funds changes neither reservation nor owner")
	world.municipalities[B].city.set_funds(funds_b)
	world.owners[adjacent] = 0
	check(not command(world, A, {"kind": "land_accept", "offer": key}).ok, "adjacency checked again at acceptance")
	world.owners[adjacent] = 2
	world.protection[tile] = 3
	check(not command(world, A, {"kind": "land_accept", "offer": key}).ok, "obsolete consent cannot release a new owner's reservation")
	world.protection[tile] = 1
	check(command(world, A, {"kind": "land_accept", "offer": key}).ok, "reserving player approves exact parcel")
	check(world.owners[tile] == 2 and world.protection[tile] == 0 and world.protection[tile + 1] == 1, "only approved parcel changes ownership and loses reservation")
	check(world.city.funds() == funds_a and world.municipalities[B].city.funds() == funds_b - world.land_price and world.land_allowance[B] == 100000, "normal field price goes to game, not seller or starting allowance")
	check(not command(world, A, {"kind": "land_accept", "offer": key}).ok, "approval cannot charge twice")
	check(not command(world, B, {"kind": "land_request", "start": [10, 12], "finish": [10, 12]}).ok, "public corridor cannot be released")
	# Owned land with the seller's reservation remains an ordinary consensual sale.
	world.owners[tile + 1] = 1
	check(command(world, B, {"kind": "land_request", "start": [10, 11], "finish": [10, 11], "price": 123}).ok, "owned protected parcel can be negotiated")
	key = str(world.next_offer - 1)
	check(command(world, A, {"kind": "land_accept", "offer": key}).ok, "owned protected parcel transfers with seller consent")
	check(world.city.funds() == funds_a + 123 and world.protection[tile + 1] == 0, "owned parcel payment goes to seller and clears reservation")
