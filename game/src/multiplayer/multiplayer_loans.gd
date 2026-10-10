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
		if loan.borrower == actor and loan.status in ["active", "settling"]:
			result += int(loan.principal) + int(loan.arrears)
	return result

func quote(world: SharedWorld, borrower: String, amount: int) -> Dictionary:
	if amount < BondCommand.BOND_VALUE or amount % BondCommand.BOND_VALUE != 0:
		return {"ok": false, "rate": 0}
	var candidate := CityState.copy_for_edit(world.municipalities[borrower].city)
	var count := candidate.document.misc_u32(Sc2MiscLayout.BONDS)
	for loan: Dictionary in contracts:
		if loan.borrower == borrower and loan.status == "active":
			count += (int(loan.principal) + BondCommand.BOND_VALUE - 1) / BondCommand.BOND_VALUE
	if count + amount / BondCommand.BOND_VALUE > BondCommand.MAX_BONDS:
		return {"ok": false, "rate": 0}
	candidate.document.set_misc_u32(Sc2MiscLayout.BONDS, count)
	var rate := 0
	for part in amount / BondCommand.BOND_VALUE:
		var issued := BondCommand.issue(candidate, BondCommand.CONFIRMATION_CONFIRMED)
		if not issued.ok or not issued.changed:
			return {"ok": false, "rate": 0}
		rate = issued.rate
	return {"ok": true, "rate": rate}

func command(world: SharedWorld, actor: String, request: Dictionary) -> Dictionary:
	var kind: String = request.kind
	if kind == "loan_offer":
		var lender := ""
		for candidate: String in world.actors:
			if candidate.sha256_text() == request.get("seat") and candidate != actor:
				lender = candidate
		if lender.is_empty() or request.get("lend", false) != false or not CoopWorld.whole_number(request.get("amount"), BondCommand.BOND_VALUE, BondCommand.MAX_BONDS * BondCommand.BOND_VALUE) or contracts.size() >= LIMIT:
			return CoopWorld.rejected("Choose a lender and a principal in $10,000 bond units.")
		var terms := quote(world, actor, int(request.amount))
		if not terms.ok:
			return CoopWorld.rejected("The normal bond credit limit does not permit this loan.")
		contracts.append({"id": next_id, "lender": lender, "borrower": actor, "proposer": actor,
			"amount": int(request.amount), "rate": int(terms.rate), "principal": 0,
			"arrears": 0, "status": "offered", "month": 0, "interest_units": 0, "model": 2})
		next_id += 1
		return CoopWorld.accepted("Loan requested. The lender must approve the game's bond rate.")
	for loan: Dictionary in contracts:
		if loan.id != request.get("loan") or actor not in [loan.lender, loan.borrower]:
			continue
		if kind == "loan_cancel" and loan.status == "offered":
			contracts.erase(loan)
			return CoopWorld.accepted("Loan proposal withdrawn or declined.")
		var lender: CityState = world.municipalities[loan.lender].city
		var borrower: CityState = world.municipalities[loan.borrower].city
		if kind == "loan_accept" and loan.status == "offered" and actor == loan.lender:
			var terms := quote(world, loan.borrower, int(loan.amount))
			if not terms.ok or int(terms.rate) != int(loan.rate):
				return CoopWorld.rejected("The bond rate or credit limit changed. Send a new request.")
			if lender.funds() < int(loan.amount) or borrower.funds() > 2147483647 - int(loan.amount):
				return CoopWorld.rejected("The lender cannot fund this loan or the receiving treasury is full.")
			lender.set_funds(lender.funds() - int(loan.amount))
			borrower.set_funds(borrower.funds() + int(loan.amount))
			loan.principal = loan.amount
			loan.status = "active"
			loan.month = borrower.age_in_days() / CityCalendar.DAYS_PER_MONTH
			touch(world, loan)
			return CoopWorld.accepted("Loan accepted. Interest follows the bond budget; repay the principal when funds permit.")
		if kind == "loan_repay" and loan.status == "active" and actor == loan.borrower:
			advance(world)
			var total := int(loan.principal) + int(loan.arrears)
			if borrower.funds() < total or lender.funds() > 2147483647 - total:
				return CoopWorld.rejected("Insufficient funds to repay this loan.")
			borrower.set_funds(borrower.funds() - total)
			lender.set_funds(lender.funds() + total)
			loan.principal = 0
			loan.arrears = 0
			# Already recorded monthly interest still settles at year end, like bank bonds.
			loan.status = "settling" if int(loan.interest_units) > 0 else "repaid"
			touch(world, loan)
			return CoopWorld.accepted("Loan principal repaid.")
	return CoopWorld.rejected("This loan action is no longer available.")

func advance(world: SharedWorld) -> void:
	for loan: Dictionary in contracts:
		if loan.status not in ["active", "settling"]:
			continue
		var borrower: CityState = world.municipalities[loan.borrower].city
		# Accumulate the same monthly principal × fixed issue rate operands as
		# bank bonds, and settle them at the next January budget boundary.
		var month := borrower.age_in_days() / CityCalendar.DAYS_PER_MONTH
		if world.municipalities[loan.borrower].engine.pending_interaction == "annual_budget" and month % CityCalendar.MONTHS_PER_YEAR == 0:
			month -= 1
		if month <= int(loan.month):
			continue
		while int(loan.month) < month:
			loan.month = int(loan.month) + 1
			loan.interest_units = int(loan.interest_units) + int(loan.principal) * int(loan.rate)
			if int(loan.month) % CityCalendar.MONTHS_PER_YEAR == 0:
				loan.arrears = int(loan.arrears) + int(loan.interest_units) / (100 * CityCalendar.MONTHS_PER_YEAR)
				loan.interest_units = 0
		var lender: CityState = world.municipalities[loan.lender].city
		# Bank budget interest can overdraw a treasury. Retain any unrepresentable
		# transfer as arrears rather than wrapping or creating/destroying money.
		var payment := mini(int(loan.arrears), mini(borrower.funds() + 2147483648, 2147483647 - lender.funds()))
		borrower.set_funds(borrower.funds() - payment)
		lender.set_funds(lender.funds() + payment)
		loan.arrears = int(loan.arrears) - payment
		if int(loan.principal) == 0 and int(loan.arrears) == 0 and int(loan.interest_units) == 0:
			loan.status = "repaid"
		touch(world, loan)

func migrate(world: SharedWorld) -> void:
	for loan: Dictionary in contracts.duplicate():
		if int(loan.get("model", 1)) == 2:
			continue
		# An unaccepted old proposal cannot silently become a different contract.
		if loan.status == "offered":
			contracts.erase(loan)
			continue
		var day: int = world.municipalities[loan.borrower].city.age_in_days()
		var previous_due := int(loan.next_due) - CityCalendar.DAYS_PER_YEAR
		loan.interest_units = int(loan.principal) * int(loan.rate) * clampi((day - previous_due) / CityCalendar.DAYS_PER_MONTH, 0, CityCalendar.MONTHS_PER_YEAR)
		loan.month = day / CityCalendar.DAYS_PER_MONTH
		loan.model = 2
		loan.erase("years")
		loan.erase("maturity")
		loan.erase("next_due")

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
	return {"version": 2, "next": next_id, "contracts": contracts.duplicate(true)}

static func valid(data: Variant, members: Dictionary) -> bool:
	if not data is Dictionary or not CoopWorld.whole_number(data.get("next"), 1, 2147483647) or not data.get("contracts") is Array or data.contracts.size() > LIMIT:
		return false
	var ids := {}
	for loan: Variant in data.contracts:
		if not loan is Dictionary or not members.has(loan.get("lender")) or not members.has(loan.get("borrower")) or loan.lender == loan.borrower or loan.get("proposer") not in [loan.lender, loan.borrower] or loan.get("status") not in ["offered", "active", "settling", "repaid"]:
			return false
		if loan.get("model", 1) == 2:
			for field in ["id", "amount", "rate", "principal", "arrears", "month", "interest_units"]:
				if not CoopWorld.whole_number(loan.get(field), 0, 9007199254740991):
					return false
			if ids.has(int(loan.id)) or int(loan.id) >= int(data.next) or int(loan.amount) < 1 or int(loan.amount) > 10000000 or int(loan.principal) > int(loan.amount) or int(loan.rate) > 65535:
				return false
			ids[int(loan.id)] = true
			continue
		for field in ["id", "amount", "rate", "years", "principal", "arrears", "next_due", "maturity"]:
			if not CoopWorld.whole_number(loan.get(field), 0, 2147483647):
				return false
		if ids.has(int(loan.id)) or int(loan.id) >= int(data.next) or int(loan.amount) < 1 or int(loan.amount) > 10000000 or int(loan.rate) > 25 or int(loan.years) < 1 or int(loan.years) > 50 or int(loan.principal) > int(loan.amount):
			return false
		if loan.status == "active" and (int(loan.next_due) < 1 or int(loan.maturity) < int(loan.next_due) - CityCalendar.DAYS_PER_YEAR or int(loan.maturity) - int(loan.next_due) > int(loan.years) * CityCalendar.DAYS_PER_YEAR):
			return false
		ids[int(loan.id)] = true
	return true
