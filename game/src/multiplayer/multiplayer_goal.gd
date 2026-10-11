class_name MultiplayerGoal
extends RefCounted
## Read-only victory evaluation; only the host controls the simulation speed.

var kind := "endless"
var target := 10000
var winners: Array = []
var unscored := false
var holding: Dictionary = {}
var hold_days := CityCalendar.DAYS_PER_YEAR * 10
var rule := "leadership"
var leader := ""
var tied := false

func blocked() -> bool:
	return not winners.is_empty() and not unscored

func evaluate(world: CoopWorld, members: Dictionary, loans: MultiplayerLoans = null) -> bool:
	if not world is SharedWorld or kind == "endless" or not winners.is_empty() or unscored:
		return false
	var best := -9223372036854775807
	var leaders: Array[String] = []
	for actor: String in world.actors:
		if not members[actor].get("ranked", true):
			continue
		var score := city_value(world.municipalities[actor].city, actor, loans)
		if score > best:
			best = score
			leaders = [actor.sha256_text()]
		elif score == best:
			leaders.append(actor.sha256_text())
	leader = leaders[0] if leaders.size() == 1 and best >= target else ""
	tied = leaders.size() > 1 and best >= target
	for actor: String in world.actors:
		if not members[actor].get("ranked", true):
			continue
		var city: CityState = world.municipalities[actor].city
		var value := city_value(city, actor, loans)
		var key := actor.sha256_text()
		if rule == "leadership":
			if not holding.has(key):
				holding[key] = {"since": city.age_in_days(), "days": 0}
			var elapsed := maxi(0, city.age_in_days() - int(holding[key].since))
			holding[key].since = city.age_in_days()
			if key == leader:
				holding[key].days = mini(hold_days, int(holding[key].days) + elapsed)
		else:
			if value < target:
				holding.erase(key)
				continue
			if not holding.has(key):
				holding[key] = {"since": city.age_in_days(), "days": 0}
			holding[key].days = maxi(0, city.age_in_days() - int(holding[key].since))
		if int(holding[key].days) < hold_days:
			continue
		var tile: int = world.owners.find(world.actors.find(actor) + 1)
		var point := Vector2i(city.map_size / 2, city.map_size / 2)
		if tile >= 0:
			point = Vector2i(tile / city.map_size, tile % city.map_size)
		winners.append({"seat": actor.sha256_text(), "name": members[actor].name, "city": city.city_name(),
			"value": value, "point": [point.x, point.y], "color": members[actor].get("color", "46b4ff")})
	return not winners.is_empty()

func city_value(city: CityState, actor: String, loans: MultiplayerLoans) -> int:
	if kind == "population":
		return city.population()
	return city.funds() - city.document.misc_u32(Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE - (loans.debt(actor) if loans != null else 0)

func saved() -> Dictionary:
	return {"kind": kind, "target": target, "winners": winners.duplicate(true), "unscored": unscored,
		"rule": rule, "leader": leader, "tied": tied, "hold_days": hold_days, "holding": holding.duplicate(true)}

static func valid(data: Variant, size: int) -> bool:
	if data == null:
		return true
	if not data is Dictionary or not data.get("kind") in ["endless", "population", "wealth"] or not CoopWorld.whole_number(data.get("target"), 1, 2147483647) or not data.get("winners") is Array or data.winners.size() > 8 or not data.get("unscored") is bool:
		return false
	if not CoopWorld.whole_number(data.get("hold_days", 0), 0, CityCalendar.DAYS_PER_YEAR * 10) or not data.get("holding", {}) is Dictionary or data.get("holding", {}).size() > 8:
		return false
	if data.get("rule", "continuous") not in ["continuous", "leadership"]:
		return false
	for key: Variant in data.get("holding", {}):
		var entry: Variant = data.holding[key]
		if not key is String or key.length() != 64 or not entry is Dictionary or not CoopWorld.whole_number(entry.get("since"), 0, 2147483647) or not CoopWorld.whole_number(entry.get("days"), 0, 2147483647):
			return false
	for winner: Variant in data.winners:
		if not winner is Dictionary or not winner.get("name") is String or not winner.get("city") is String or not winner.get("seat") is String or not winner.get("point") is Array or winner.point.size() != 2:
			return false
		for axis in winner.point:
			if not CoopWorld.whole_number(axis, 0, size - 1):
				return false
	return true

func restore(data: Variant) -> void:
	if data == null:
		return
	rule = data.get("rule", "continuous")
	leader = data.get("leader", "")
	tied = data.get("tied", false)
	kind = data.kind
	target = int(data.target)
	winners = data.winners.duplicate(true)
	unscored = data.unscored
	# Old saved matches retain the victory rule agreed when they were started.
	hold_days = int(data.get("hold_days", 0))
	holding = data.get("holding", {}).duplicate(true)
