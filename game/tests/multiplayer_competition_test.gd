extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var a := "a".repeat(48)
	var b := "b".repeat(48)
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(64, "Contest").document)
	world.add_player(a)
	world.add_player(b)
	var members := {a: {"name": "Alice"}, b: {"name": "Bob"}}
	var starts := MultiplayerStarts.new()
	var funds := world.city.funds()
	check(starts.prepare(world, members).is_empty(), "fair starts assigned")
	check(world.owners.count(1) == world.owners.count(2) and world.owners.count(1) > 0, "equal starting areas")
	check(world.city.funds() == funds and world.land_allowance[a] == 0, "grant preserves treasury without a second allowance")
	var initial := starts.positions.duplicate(true)
	var saved_starts := starts.saved()
	check(MultiplayerStarts.valid(saved_starts, members, 64), "start positions persist")
	var second := SharedWorld.new()
	second.open(world.template)
	second.add_player(a)
	second.add_player(b)
	starts.assigned = false
	starts.round_number += 1
	check(starts.prepare(second, members).is_empty(), "rematch positions assigned")
	check(starts.positions[a].slot != initial[a].slot and starts.positions[b].slot != initial[b].slot, "neither player repeats a start")
	var loans := MultiplayerLoans.new()
	world.municipalities[a].city.set_funds(50000)
	world.municipalities[b].city.set_funds(1000)
	world.municipalities[b].city.document.set_misc_u32(Sc2MiscLayout.NATIONAL_FEDERAL_RATE, 4)
	check(loans.command(world, b, {"kind": "loan_offer", "seat": a.sha256_text(), "amount": 10000, "rate": 99, "years": 1}).ok, "borrower selects lender and bond principal")
	check(int(loans.contracts[0].rate) == 5 and not loans.contracts[0].has("years"), "game rate replaces client terms")
	check(not loans.command(world, b, {"kind": "loan_accept", "loan": 1}).ok, "borrower cannot approve for lender")
	check(world.municipalities[b].city.funds() == 1000, "proposal transfers no money")
	check(loans.command(world, a, {"kind": "loan_accept", "loan": 1}).ok, "lender accepts")
	check(world.city.funds() == 40000 and world.municipalities[b].city.funds() == 11000 and loans.debt(b) == 10000, "principal transferred once")
	check(not loans.command(world, a, {"kind": "loan_accept", "loan": 1}).ok, "duplicate rejected")
	world.municipalities[b].city.set_age_in_days(300)
	loans.advance(world)
	check(world.city.funds() == 40500 and world.municipalities[b].city.funds() == 10500, "annual bond interest transferred")
	world.municipalities[b].city.set_age_in_days(600)
	loans.advance(world)
	check(world.city.funds() == 41000 and loans.debt(b) == 10000, "no maturity or automatic principal repayment")
	loans.advance(world)
	check(world.city.funds() == 41000, "interest idempotent")
	check(not loans.command(world, a, {"kind":"loan_repay", "loan":1}).ok, "lender cannot withdraw principal")
	check(loans.command(world, b, {"kind":"loan_repay", "loan":1}).ok and loans.debt(b) == 0, "borrower redeems with sufficient funds")
	check(MultiplayerLoans.valid(loans.saved(), members), "new ledger validates")
	var legacy := {"next": 3, "contracts": [{"id":2,"lender":a,"borrower":b,"proposer":a,"amount":1000,"rate":5,"years":2,"principal":700,"arrears":50,"status":"active","next_due":900,"maturity":1200}]}
	check(MultiplayerLoans.valid(legacy, members), "legacy ledger accepted")
	loans.contracts = legacy.contracts
	loans.next_id = 3
	var cash_before: int = world.city.funds() + world.municipalities[b].city.funds()
	loans.migrate(world)
	check(loans.debt(b) == 750 and not loans.contracts[0].has("maturity") and MultiplayerLoans.valid(loans.saved(), members), "migration preserves debt and removes maturity")
	check(cash_before == world.city.funds() + world.municipalities[b].city.funds(), "migration cannot mint or erase funds")
	world.city.set_funds(31000)
	world.city.set_age_in_days(0)
	var goal := MultiplayerGoal.new()
	goal.kind = "wealth"
	goal.target = 30000
	check(not goal.evaluate(world, members, loans), "threshold starts holding year")
	world.city.set_age_in_days(299)
	check(not goal.evaluate(world, members, loans), "one day short cannot win")
	world.city.set_funds(29999)
	goal.evaluate(world, members, loans)
	check(goal.holding.is_empty(), "drop below resets holding time")
	world.city.set_funds(31000)
	goal.evaluate(world, members, loans)
	world.city.set_age_in_days(598)
	check(not goal.evaluate(world, members, loans), "holding year restarts")
	world.city.set_age_in_days(599)
	check(goal.evaluate(world, members, loans), "continuous full year wins")
	var late := MultiplayerGoal.new()
	late.kind = "wealth"
	late.target = 1
	members[a].ranked = false
	members[b].ranked = false
	check(not late.evaluate(world, members, loans) and late.holding.is_empty(), "unranked cities excluded")
	var history := MultiplayerHistory.new()
	var row := MultiplayerStatistics.capture(world, a).merged({"id": a.sha256_text()})
	history.sample(world, [row])
	history.sample(world, [row])
	check(history.series[a.sha256_text()].size() == 1, "one monthly sample, not frame samples")
	world.city.set_age_in_days(625)
	history.sample(world, [row])
	check(history.series[a.sha256_text()].size() == 2 and MultiplayerHistory.valid(history.series, members), "monthly histories validate")
	deltas()
	print("Multiplayer competition checks: %d failures" % failures)
	quit(1 if failures else 0)

func deltas() -> void:
	var sender := MultiplayerDelta.new()
	var receiver := MultiplayerDelta.new()
	var state := {"type": "state", "city": "a".repeat(12000), "owners": [0, 0, 1], "revision": 1, "roster": []}
	var full := sender.encode(state)
	check(receiver.decode(full).city == state.city, "initial full baseline")
	state.city = state.city.substr(0, 5000) + "b" + state.city.substr(5001)
	state.owners = [0, 2, 1]
	state.revision = 2
	var delta := sender.encode(state)
	check(delta.type == "state_delta" and JSON.stringify(delta).length() < JSON.stringify(full).length() / 2, "sparse edits reduce wire bytes")
	var decoded := receiver.decode(delta)
	check(not receiver.failed and decoded.city == state.city and decoded.owners == state.owners, "map and owner pages reconstruct exactly")
	check(receiver.decode(delta).is_empty() and receiver.failed, "stale baseline triggers recovery")
	state.city = "c".repeat(9000)
	var next := sender.encode(state)
	var current := receiver.decode(next)
	check(not receiver.failed and current.city == state.city, "valid next state after duplicate rejection")
	var corrupted := sender.encode(state)
	corrupted.base = -1
	check(receiver.decode(corrupted).is_empty() and receiver.failed, "wrong baseline cannot mutate view")
