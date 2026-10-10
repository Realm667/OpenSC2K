class_name MultiplayerStatistics
extends RefCounted
## Read-only snapshots; displayed values never change the simulation.

static func capture(world: CoopWorld, actor: String) -> Dictionary:
	var own: CoopWorld = world.municipalities[actor] if world is SharedWorld else world
	var city := own.city
	var result := {"city": city.city_name(), "population": city.population(), "funds": city.funds(),
		"balance": BudgetReport.capture(city, BudgetPhase.funding_values(city)).ytd_cash,
		"debt": city.document.misc_u32(Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE,
		"builds": own.statistics.get(actor, {}).get("builds", 0),
		"spent": own.statistics.get(actor, {}).get("spent", 0),
		"land": 0, "built": 0, "residential": 0, "commercial": 0, "industrial": 0,
		"bought": null, "sold": null, "units": 0, "aid": 0}
	for tile in city.buildings.size():
		if world is SharedWorld and not world is RegionWorld and world.owners[tile] != world.actors.find(actor) + 1:
			continue
		result.land += 1
		if city.buildings[tile] > 13:
			result.built += 1
		var zone := int(city.zones[tile]) & 15
		if zone in [1, 2]:
			result.residential += 1
		elif zone in [3, 4]:
			result.commercial += 1
		elif zone in [5, 6]:
			result.industrial += 1
	if world is SharedWorld:
		result.bought = world.land_statistics.get(actor, {}).get("bought")
		result.sold = world.land_statistics.get(actor, {}).get("sold")
		for owner: String in world.municipalities:
			for unit: Dictionary in world.municipalities[owner].dispatch_owners.values():
				if unit.get("actor") == actor.sha256_text():
					result.units += 1
					if owner != actor:
						result.aid += 1
	else:
		for unit: Dictionary in world.dispatch_owners.values():
			if unit.get("actor") == actor.sha256_text():
				result.units += 1
	return result
