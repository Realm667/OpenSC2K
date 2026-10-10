class_name MultiplayerHistory
extends RefCounted
## Monthly host samples, bounded independently of match length and network rate.

const LIMIT := 600
const METRICS := ["population", "funds", "debt", "land", "built", "balance"]
var series: Dictionary = {}

func sample(world: CoopWorld, players: Array) -> void:
	for row: Dictionary in players:
		var actor := ""
		if world is SharedWorld:
			for key: String in world.actors:
				if key.sha256_text() == row.id:
					actor = key
		var city: CityState = world.municipalities[actor].city if not actor.is_empty() else world.city
		var month := int(city.age_in_days() / CityCalendar.DAYS_PER_MONTH)
		var samples: Array = series.get(row.id, [])
		if not samples.is_empty() and int(samples.back().month) >= month:
			continue
		var sample := {"month": month, "year": city.founding_year()}
		for metric: String in METRICS:
			sample[metric] = int(row.get(metric, 0))
		samples.append(sample)
		if samples.size() > LIMIT:
			samples.pop_front()
		series[row.id] = samples

static func valid(data: Variant, members: Dictionary) -> bool:
	if not data is Dictionary or data.size() > 8:
		return false
	var ids: Array = members.keys().map(func(actor: String) -> String: return actor.sha256_text())
	for id: Variant in data:
		if not ids.has(id) or not data[id] is Array or data[id].size() > LIMIT:
			return false
		var previous := -1
		for entry: Variant in data[id]:
			if not entry is Dictionary or not CoopWorld.whole_number(entry.get("month"), previous + 1, 2147483647) or not CoopWorld.whole_number(entry.get("year"), 0, 9999):
				return false
			previous = int(entry.month)
			for metric: String in METRICS:
				if not CoopWorld.whole_number(entry.get(metric), -9007199254740991, 9007199254740991):
					return false
	return true
