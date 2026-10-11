class_name MultiplayerLandRules
extends RefCounted
## Shared geometry for previews and authoritative purchases. Tiles use x * size + y.
@warning_ignore_start("integer_division")

static func neighbours(tile: int, size: int) -> Array[int]:
	var result: Array[int] = []
	if tile >= size:
		result.append(tile - size)
	if tile < size * (size - 1):
		result.append(tile + size)
	if tile % size > 0:
		result.append(tile - 1)
	if tile % size < size - 1:
		result.append(tile + 1)
	return result

static func connected(candidates: Array, owners: Variant, owner: int, size: int, allow_first := false) -> Array[int]:
	var pending := {}
	for tile: int in candidates:
		pending[tile] = true
	var queue: Array[int] = []
	for tile: int in candidates:
		for next: int in neighbours(tile, size):
			if int(owners[next]) == owner:
				queue.append(tile)
				pending.erase(tile)
				break
	if queue.is_empty() and allow_first and not candidates.is_empty() and not owners.has(owner):
		queue.append(int(candidates[0]))
		pending.erase(queue[0])
	var cursor := 0
	while cursor < queue.size():
		var tile := queue[cursor]
		cursor += 1
		for next: int in neighbours(tile, size):
			if pending.has(next):
				pending.erase(next)
				queue.append(next)
	return queue

static func purchasable(city: CityState, owners: Variant, protection: Variant, owner: int, selected: Array, water: bool) -> Array[int]:
	var candidates: Array = []
	for tile: int in selected:
		var reserved := int(protection[tile]) if protection.size() == owners.size() else 0
		if int(owners[tile]) == 0 and reserved in [0, owner] and (water or not city.is_water(tile / city.map_size, tile % city.map_size)):
			candidates.append(tile)
	return connected(candidates, owners, owner, city.map_size, true)

static func components(owners: Variant, owner: int, size: int, removed: Dictionary = {}) -> int:
	var remaining := {}
	for tile in owners.size():
		if int(owners[tile]) == owner and not removed.has(tile):
			remaining[tile] = true
	var count := 0
	while not remaining.is_empty():
		count += 1
		var queue: Array[int] = [remaining.keys()[0]]
		remaining.erase(queue[0])
		var cursor := 0
		while cursor < queue.size():
			var tile := queue[cursor]
			cursor += 1
			for next: int in neighbours(tile, size):
				if remaining.has(next):
					remaining.erase(next)
					queue.append(next)
	return count

static func transfer_error(world: SharedWorld, seller: String, buyer: String, tiles: Array) -> String:
	var from := world.actors.find(seller) + 1
	var to := world.actors.find(buyer) + 1
	var removed := {}
	for tile: int in tiles:
		if world.protection[tile] not in [0, from]:
			return "Another player's reservation and public corridors cannot be traded."
		removed[tile] = true
	if connected(tiles, world.owners, to, world.city.map_size).size() != tiles.size():
		return "This parcel does not connect to the buyer's city."
	if components(world.owners, from, world.city.map_size, removed) > components(world.owners, from, world.city.map_size):
		return "This sale would split the seller's remaining land."
	return ""
