class_name MultiplayerStartParcel
extends RefCounted
## Deterministic compact connected parcels. Water counts as half a land tile.
@warning_ignore_start("integer_division")

static func standard(size: int) -> int:
	return mini(1024, (size / 4 - 2) ** 2 / 2)

static func make(city: CityState, owners: PackedInt32Array, slot: int, amount: int) -> Dictionary:
	var size := city.map_size
	var width := size / 4
	var origin := Vector2i(slot / 4 * width, slot % 4 * width)
	var center := origin + Vector2i(width / 2, width / 2)
	# Border seats may touch the actual map edge; no artificial perimeter strip.
	if origin.x == 0:
		center.x = 0
	elif origin.x + width == size:
		center.x = size - 1
	if origin.y == 0:
		center.y = 0
	elif origin.y + width == size:
		center.y = size - 1
	var seed := -1
	var distance := INF
	for x in range(origin.x, origin.x + width):
		for y in range(origin.y, origin.y + width):
			var tile := x * size + y
			if owners[tile] != 0 or city.is_water(x, y) or not allowed(Vector2i(x, y), origin, width):
				continue
			var d := Vector2(center).distance_squared_to(Vector2(x, y))
			if d < distance:
				distance = d
				seed = tile
	if seed < 0:
		return {}
	center = Vector2i(seed / size, seed % size)
	var queue: Array = []
	var seen := {seed: true}
	push(queue, [0.0, seed])
	var tiles: Array[int] = []
	var land := 0
	var water := 0
	var units := 0
	while not queue.is_empty() and units < amount * 2:
		var tile: int = pop(queue)[1]
		tiles.append(tile)
		var wet := city.is_water(tile / size, tile % size)
		water += 1 if wet else 0
		land += 0 if wet else 1
		units += 1 if wet else 2
		for next: int in MultiplayerLandRules.neighbours(tile, size):
			var point := Vector2i(next / size, next % size)
			if seen.has(next) or owners[next] != 0 or not allowed(point, origin, width):
				continue
			seen[next] = true
			var delta := Vector2(point - center)
			var aspect := 0.8 + float(slot % 5) * 0.1
			var cost := delta.x * delta.x * aspect + delta.y * delta.y / aspect
			cost += sin(float(point.x * 3 + slot)) * width * 0.12
			push(queue, [cost, next])
	if units < amount * 2:
		return {}
	# A full outer ring, rather than a second BFS prefix attached to one side.
	var owned := {}
	for tile: int in tiles:
		owned[tile] = true
	var reserve: Array[int] = []
	var frontier := tiles.duplicate()
	var reserved := {}
	while not frontier.is_empty() and reserve.size() < ceili(tiles.size() * 0.5):
		var next_ring: Array[int] = []
		for tile: int in frontier:
			for next: int in MultiplayerLandRules.neighbours(tile, size):
				var point := Vector2i(next / size, next % size)
				if owned.has(next) or reserved.has(next) or owners[next] != 0 or not allowed(point, origin, width):
					continue
				reserved[next] = true
				next_ring.append(next)
		reserve.append_array(next_ring)
		frontier = next_ring
	return {"tiles": tiles, "reserve": reserve, "land": land, "water": water, "center": center, "slot": slot}

static func allowed(point: Vector2i, origin: Vector2i, width: int) -> bool:
	return Rect2i(origin, Vector2i.ONE * width).has_point(point) and (origin.x == 0 or point.x > origin.x) and (origin.y == 0 or point.y > origin.y)

static func push(heap: Array, value: Array) -> void:
	heap.append(value)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if float(heap[parent][0]) <= float(value[0]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = value

static func pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and float(heap[child + 1][0]) < float(heap[child][0]):
			child += 1
		if float(last[0]) <= float(heap[child][0]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result
