class_name MultiplayerStarts
extends RefCounted
## Equal dry-land grants in separated sectors. No money or simulation RNG is used.
@warning_ignore_start("integer_division")

const GRID := 4
var previous: Dictionary = {}
var positions: Dictionary = {}
var round_number := 1
var assigned := false

func prepare(world: SharedWorld, members: Dictionary, commit := true) -> String:
	if assigned:
		return ""
	var candidates: Array = []
	var size := world.city.map_size
	var width := size / GRID
	for slot in GRID * GRID:
		var tiles: Array[int] = []
		var center := Vector2i((slot / GRID) * width + width / 2, (slot % GRID) * width + width / 2)
		if world is RegionWorld:
			candidates.append({"slot": slot, "tiles": tiles, "center": center})
			continue
		var center_height := world.city.land_altitude(center.x, center.y)
		# Search outwards and retain only a bounded set to rank. Large maps must
		# not sort a million candidate tiles for each of sixteen sectors.
		var enough := mini(2048, width * width)
		for radius in range(width / 2 + 1):
			var ring: Array[Vector2i] = []
			for dx in range(-radius, radius + 1):
				ring.append(center + Vector2i(dx, -radius))
				if radius > 0:
					ring.append(center + Vector2i(dx, radius))
			for dy in range(-radius + 1, radius):
				ring.append(center + Vector2i(-radius, dy))
				ring.append(center + Vector2i(radius, dy))
			for point: Vector2i in ring:
				if point.x < (slot / GRID) * width or point.x >= (slot / GRID + 1) * width or point.y < (slot % GRID) * width or point.y >= (slot % GRID + 1) * width:
					continue
				var tile := world.city.index_of(point.x, point.y)
				if world.owners[tile] == 0 and not world.city.is_water(point.x, point.y):
					tiles.append(tile)
			if tiles.size() >= enough:
				break
		# Prefer compact, level land within each equally sized geographical sector.
		tiles.sort_custom(func(a: int, b: int) -> bool:
			var pa := Vector2i(a / size, a % size)
			var pb := Vector2i(b / size, b % size)
			var va := pa.distance_squared_to(center) + absi(world.city.land_altitude(pa.x, pa.y) - center_height) * width
			var vb := pb.distance_squared_to(center) + absi(world.city.land_altitude(pb.x, pb.y) - center_height) * width
			return va < vb if va != vb else a < b)
		candidates.append({"slot": slot, "tiles": tiles, "center": center})
	var chosen: Dictionary = {}
	var used: Array[int] = []
	var amount := mini(1024, width * width)
	# Rotate seat order too: the same player must not always choose first.
	for offset in world.actors.size():
		var actor: String = world.actors[(offset + round_number - 1) % world.actors.size()]
		var best := -1
		var best_score := -1.0
		for index in candidates.size():
			var candidate: Dictionary = candidates[index]
			if used.has(index) or previous.get(actor, []).has(index):
				continue
			if not world is RegionWorld and candidate.tiles.size() < mini(16, amount):
				continue
			var spacing := float(size * size)
			for other: int in used:
				spacing = minf(spacing, Vector2(candidate.center).distance_squared_to(candidates[other].center))
			var score := spacing + mini(amount, candidate.tiles.size()) * size
			if score > best_score:
				best = index
				best_score = score
		if best < 0:
			return "No unused fair starting positions remain. Create a new game with new terrain."
		used.append(best)
		chosen[actor] = candidates[best]
		if not world is RegionWorld:
			amount = mini(amount, candidates[best].tiles.size())
	if not commit:
		return ""
	# All validation precedes mutation. Imported possessions are retained.
	for actor: String in world.actors:
		var candidate: Dictionary = chosen[actor]
		var history: Array = previous.get(actor, []).duplicate()
		history.append(candidate.slot)
		previous[actor] = history
		positions[actor] = {"slot": candidate.slot, "point": [candidate.center.x, candidate.center.y], "tiles": 0 if world is RegionWorld else amount}
		members[actor]["ranked"] = true
		world.land_allowance[actor] = 0
		if not world is RegionWorld:
			for tile: int in candidate.tiles.slice(0, amount):
				world.owners[tile] = world.actors.find(actor) + 1
	world.revision += 1
	world.tile_versions.fill(world.revision)
	world.snapshot_cache.clear()
	assigned = true
	return ""

func public_positions() -> Dictionary:
	var result := {}
	for actor: String in positions:
		result[actor.sha256_text()] = positions[actor].duplicate(true)
	return result

func saved() -> Dictionary:
	return {"round": round_number, "assigned": assigned, "previous": previous.duplicate(true), "positions": positions.duplicate(true)}

static func valid(data: Variant, members: Dictionary, size: int) -> bool:
	if not data is Dictionary or not CoopWorld.whole_number(data.get("round"), 1, 2147483647) or not data.get("assigned") is bool or not data.get("previous") is Dictionary or not data.get("positions") is Dictionary:
		return false
	for actor: Variant in data.previous:
		if not members.has(actor) or not data.previous[actor] is Array or data.previous[actor].size() > GRID * GRID:
			return false
		var seen := {}
		for slot: Variant in data.previous[actor]:
			if not CoopWorld.whole_number(slot, 0, GRID * GRID - 1) or seen.has(int(slot)):
				return false
			seen[int(slot)] = true
	for actor: Variant in data.positions:
		var item: Variant = data.positions[actor]
		if not members.has(actor) or not item is Dictionary or not CoopWorld.whole_number(item.get("slot"), 0, GRID * GRID - 1) or not CoopWorld.whole_number(item.get("tiles"), 0, size * size) or not item.get("point") is Array or item.point.size() != 2:
			return false
		for value: Variant in item.point:
			if not CoopWorld.whole_number(value, 0, size - 1):
				return false
	return true

func restore(data: Dictionary) -> void:
	round_number = int(data.round)
	assigned = data.assigned
	previous = data.previous.duplicate(true)
	for actor: String in previous:
		previous[actor] = previous[actor].map(func(slot: Variant) -> int: return int(slot))
	positions = data.positions.duplicate(true)
