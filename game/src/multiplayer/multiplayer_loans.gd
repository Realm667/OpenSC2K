class_name MultiplayerLoans
extends RefCounted
## City-seat contracts; reconnects and controller changes cannot erase obligations.
@warning_ignore_start("integer_division")

const LIMIT := 128
var contracts: Array = []
var next_id := 1

func debt(actor: String) -> int:
	var result := 0
	for loan: Dictionary in contracts:
		if loan.borrower == actor and loan.status == "active":
			result += int(loan.principal) + int(loan.arrears)
	return result

func command(world: SharedWorld, actor: String, request: Dictionary) -> Dictionary:
	var kind: String = request.kind
	if kind == "loan_offer":
		var other := ""
		for candidate: String in world.actors:
			if candidate.sha256_text() == request.get("seat") and candidate != actor:
				other = candidate
		if other.is_empty() or not request.get("lend") is bool or not CoopWorld.whole_number(request.get("amount"), 1, 10000000) or not CoopWorld.whole_number(request.get("rate"), 0, 25) or not CoopWorld.whole_number(request.get("years"), 1, 50) or contracts.size() >= LIMIT:
			return CoopWorld.rejected("Invalid loan terms or contract limit reached.")
		contracts.append({"id": next_id, "lender": actor if request.lend else other,
			"borrower": other if request.lend else actor, "proposer": actor,
			"amount": int(request.amount), "rate": int(request.rate), "years": int(request.years),
			"principal": 0, "arrears": 0, "status": "offered", "next_due": 0, "maturity": 0})
		next_id += 1
		return CoopWorld.accepted("Loan proposal sent. The other player must confirm the fixed terms.")
	for loan: Dictionary in contracts:
		if loan.id != request.get("loan") or actor not in [loan.lender, loan.borrower]:
			continue
		if kind == "loan_cancel" and loan.status == "offered":
			contracts.erase(loan)
			return CoopWorld.accepted("Loan proposal withdrawn or declined.")
		if kind == "loan_accept" and loan.status == "offered" and actor != loan.proposer:
			var lender: CityState = world.municipalities[loan.lender].city
			var borrower: CityState = world.municipalities[loan.borrower].city
			if lender.funds() < int(loan.amount) or borrower.funds() > 2147483647 - int(loan.amount):
				return CoopWorld.rejected("The lender cannot fund this loan or the receiving treasury is full.")
			lender.set_funds(lender.funds() - int(loan.amount))
			borrower.set_funds(borrower.funds() + int(loan.amount))
			loan.principal = loan.amount
			loan.status = "active"
			loan.next_due = borrower.age_in_days() + CityCalendar.DAYS_PER_YEAR
			loan.maturity = borrower.age_in_days() + int(loan.years) * CityCalendar.DAYS_PER_YEAR
			touch(world, loan)
			return CoopWorld.accepted("Loan accepted. Annual interest and the maturity date are fixed.")
	return CoopWorld.rejected("This loan action is no longer available.")

func advance(world: SharedWorld) -> void:
	for loan: Dictionary in contracts:
		if loan.status != "active":
			continue
		var borrower: CityState = world.municipalities[loan.borrower].city
		var lender: CityState = world.municipalities[loan.lender].city
		var day := borrower.age_in_days()
		var changed := false
		# Fixed simple interest, rounded up to whole currency units; no compound
		# interest or hidden overdraft. Unpaid amounts remain visible arrears.
		while day >= int(loan.next_due) and int(loan.next_due) <= int(loan.maturity):
			loan.arrears = int(loan.arrears) + (int(loan.amount) * int(loan.rate) + 99) / 100
			loan.next_due = int(loan.next_due) + CityCalendar.DAYS_PER_YEAR
			changed = true
		var due := int(loan.arrears) + (int(loan.principal) if day >= int(loan.maturity) else 0)
		var payment := mini(due, mini(maxi(0, borrower.funds()), 2147483647 - lender.funds()))
		if payment > 0:
			borrower.set_funds(borrower.funds() - payment)
			lender.set_funds(lender.funds() + payment)
			var interest := mini(payment, int(loan.arrears))
			loan.arrears = int(loan.arrears) - interest
			loan.principal = int(loan.principal) - (payment - interest)
			changed = true
		if int(loan.principal) == 0 and int(loan.arrears) == 0:
			loan.status = "repaid"
		if changed:
			touch(world, loan)

func touch(world: SharedWorld, loan: Dictionary) -> void:
	for actor: String in [loan.lender, loan.borrower]:
		world.municipalities[actor].revision += 1
		world.municipalities[actor].undo_document = null
	world.revision += 1
	world.snapshot_cache.clear()

func public_rows() -> Array:
	var result: Array = []
	for loan: Dictionary in contracts:
		var row := loan.duplicate()
		for key in ["lender", "borrower", "proposer"]:
			row[key] = str(row[key]).sha256_text()
		result.append(row)
	return result

func saved() -> Dictionary:
	return {"next": next_id, "contracts": contracts.duplicate(true)}

static func valid(data: Variant, members: Dictionary) -> bool:
	if not data is Dictionary or not CoopWorld.whole_number(data.get("next"), 1, 2147483647) or not data.get("contracts") is Array or data.contracts.size() > LIMIT:
		return false
	var ids := {}
	for loan: Variant in data.contracts:
		if not loan is Dictionary or not members.has(loan.get("lender")) or not members.has(loan.get("borrower")) or loan.lender == loan.borrower or loan.get("proposer") not in [loan.lender, loan.borrower] or loan.get("status") not in ["offered", "active", "repaid"]:
			return false
		for field in ["id", "amount", "rate", "years", "principal", "arrears", "next_due", "maturity"]:
			if not CoopWorld.whole_number(loan.get(field), 0, 2147483647):
				return false
		if ids.has(int(loan.id)) or int(loan.id) >= int(data.next) or int(loan.amount) < 1 or int(loan.amount) > 10000000 or int(loan.rate) > 25 or int(loan.years) < 1 or int(loan.years) > 50 or int(loan.principal) > int(loan.amount):
			return false
		if loan.status == "active" and (int(loan.next_due) < 1 or int(loan.maturity) < int(loan.next_due) - CityCalendar.DAYS_PER_YEAR or int(loan.maturity) - int(loan.next_due) > int(loan.years) * CityCalendar.DAYS_PER_YEAR):
			return false
		ids[int(loan.id)] = true
	return true
