class_name MultiplayerStarts
extends RefCounted
## Equal dry-land grants in separated sectors. No money or simulation RNG is used.
@warning_ignore_start("integer_division")

const GRID := 4
var previous: Dictionary = {}
var positions: Dictionary = {}
var round_number := 1
var assigned := false
var handicaps: Dictionary = {}

func prepare(world: SharedWorld, members: Dictionary, commit := true) -> String:
	if assigned:
		return ""
	var size := world.city.map_size
	var width := size / GRID
	var candidates: Array = []
	var protected := PackedInt32Array()
	protected.resize(world.owners.size())
	# Public perimeter plus open-ended access routes leave the interior connected. Existing property
	# is never confiscated when loading an older/imported game.
	for tile in protected.size():
		if world.owners[tile] == 0 and (tile / size < 2 or tile % size < 2 or tile / size >= size - 2 or tile % size >= size - 2):
			protected[tile] = -1
	for slot in GRID * GRID:
		var center := Vector2i(slot / GRID * width + width / 2, slot % GRID * width + width / 2)
		if world is RegionWorld:
			candidates.append({"slot": slot, "tiles": [], "center": center})
			continue
		var allowed := {}
		for x in range(slot / GRID * width + 2, (slot / GRID + 1) * width):
			for y in range(slot % GRID * width + 2, (slot % GRID + 1) * width):
				var tile := world.city.index_of(x, y)
				if world.owners[tile] == 0 and protected[tile] == 0 and not world.city.is_water(x, y):
					allowed[tile] = true
		var largest: Array[int] = []
		while not allowed.is_empty():
			var queue: Array[int] = [allowed.keys()[0]]
			allowed.erase(queue[0])
			var cursor := 0
			while cursor < queue.size():
				var tile := queue[cursor]
				cursor += 1
				for next: int in MultiplayerLandRules.neighbours(tile, size):
					if allowed.has(next):
						allowed.erase(next)
						queue.append(next)
			if queue.size() > largest.size():
				largest = queue
		# BFS prefixes keep the granted land connected.
		candidates.append({"slot": slot, "tiles": largest, "center": center})
	var chosen := {}
	var used: Array[int] = []
	var amount := mini(1024, (width - 2) * (width - 2) / 2)
	for offset in world.actors.size():
		var actor: String = world.actors[(offset + round_number - 1) % world.actors.size()]
		var best := -1
		var score := -1.0
		var handicap: Dictionary = handicaps.get(actor, {})
		var requested := int(handicap.get("tiles", 0))
		for index in candidates.size():
			var candidate: Dictionary = candidates[index]
			if used.has(index) or previous.get(actor, []).has(index):
				continue
			if not world is RegionWorld and candidate.tiles.size() < maxi(16, requested * 2):
				continue
			var spacing := float(size * size)
			for other: int in used:
				spacing = minf(spacing, Vector2(candidate.center).distance_squared_to(candidates[other].center))
			var value := spacing + mini(amount * 2, candidate.tiles.size()) * size
			if value > score:
				best = index
				score = value
		if best < 0:
			return "Not enough connected land for these starts and reserved expansion areas. Adjust handicaps or generate new terrain."
		used.append(best)
		chosen[actor] = candidates[best]
		if not world is RegionWorld and requested == 0:
			amount = mini(amount, candidates[best].tiles.size() / 2)
	if not commit:
		return ""
	world.protection = protected if not world is RegionWorld else world.protection
	for actor: String in world.actors:
		var candidate: Dictionary = chosen[actor]
		var history: Array = previous.get(actor, []).duplicate()
		history.append(candidate.slot)
		previous[actor] = history
		var handicap: Dictionary = handicaps.get(actor, {})
		var grant := int(handicap.get("tiles", 0))
		if grant == 0:
			grant = amount
		var point: Vector2i = candidate.center
		if not world is RegionWorld:
			var owner := world.actors.find(actor) + 1
			var parcel: Array = candidate.tiles.slice(0, grant)
			for tile: int in parcel:
				world.owners[tile] = owner
			if not parcel.is_empty():
				point = Vector2i(int(parcel[0]) / size, int(parcel[0]) % size)
			for tile: int in candidate.tiles.slice(grant, grant * 2):
				world.protection[tile] = owner
		var municipality: CoopWorld = world.municipalities[actor]
		if handicap.has("funds"):
			municipality.city.set_funds(int(handicap.funds))
			municipality.revision += 1
		positions[actor] = {"slot": candidate.slot, "point": [point.x, point.y], "tiles": 0 if world is RegionWorld else grant}
		members[actor]["ranked"] = true
		world.land_allowance[actor] = 0
	if not world is RegionWorld:
		for actor: String in world.actors:
			connect_access(world, world.actors.find(actor) + 1)
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
	return {"handicaps": handicaps.duplicate(true), "round": round_number, "assigned": assigned, "previous": previous.duplicate(true), "positions": positions.duplicate(true)}

static func valid(data: Variant, members: Dictionary, size: int) -> bool:
	if not data is Dictionary or not CoopWorld.whole_number(data.get("round"), 1, 2147483647) or not data.get("assigned") is bool or not data.get("previous") is Dictionary or not data.get("positions") is Dictionary:
		return false
	if not data.get("handicaps", {}) is Dictionary:
		return false
	for actor: Variant in data.get("handicaps", {}):
		var handicap: Variant = data.handicaps[actor]
		if not members.has(actor) or not handicap is Dictionary or not CoopWorld.whole_number(handicap.get("funds"), 0, 2147483647) or not CoopWorld.whole_number(handicap.get("tiles", 0), 0, size * size / 16):
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
	handicaps = data.get("handicaps", {}).duplicate(true)
	round_number = int(data.round)
	assigned = data.assigned
	previous = data.previous.duplicate(true)
	for actor: String in previous:
		previous[actor] = previous[actor].map(func(slot: Variant) -> int: return int(slot))
	positions = data.positions.duplicate(true)

static func connect_access(world: SharedWorld, owner: int) -> void:
	var parents := {}
	var queue: Array[int] = []
	for tile in world.owners.size():
		if world.owners[tile] != owner:
			continue
		for next: int in MultiplayerLandRules.neighbours(tile, world.city.map_size):
			if world.owners[next] == 0 and world.protection[next] in [-1, 0, owner] and not parents.has(next):
				parents[next] = -1
				queue.append(next)
	var cursor := 0
	while cursor < queue.size():
		var tile := queue[cursor]
		cursor += 1
		if world.protection[tile] == -1:
			while tile >= 0:
				world.protection[tile] = -1
				tile = int(parents[tile])
			return
		for next: int in MultiplayerLandRules.neighbours(tile, world.city.map_size):
			if world.owners[next] == 0 and world.protection[next] in [0, owner, -1] and not parents.has(next):
				parents[next] = tile
				queue.append(next)
