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
	var center := origin + Vector2i.ONE * (width / 2)
	var stride := width + 1
	var wet_prefix := PackedInt32Array()
	var occupied_prefix := PackedInt32Array()
	wet_prefix.resize(stride * stride)
	occupied_prefix.resize(stride * stride)
	for x in width:
		for y in width:
			var index := (x + 1) * stride + y + 1
			wet_prefix[index] = wet_prefix[index - 1] + wet_prefix[index - stride] - wet_prefix[index - stride - 1] + int(city.is_water(origin.x + x, origin.y + y))
			occupied_prefix[index] = occupied_prefix[index - 1] + occupied_prefix[index - stride] - occupied_prefix[index - stride - 1] + int(owners[(origin.x + x) * size + origin.y + y] != 0)
	# Each candidate is a complete near-square rectangle. Water stays inside the
	# parcel and retains the established half-land weight; no shoreline clipping.
	var best := Rect2i()
	var best_units := 2147483647
	var best_shape := INF
	var best_land := 0
	var best_water := 0
	for w in range(1, width + 1):
		for h in range(maxi(1, ceili(w * 0.8)), mini(width, floori(w * 1.25)) + 1):
			if w * h < amount or w * h > maxi(amount * 2 + width, 4):
				continue
			var start := center - Vector2i(w, h) / 2
			if origin.x == 0:
				start.x = 0
			elif origin.x + width == size:
				start.x = size - w
			if origin.y == 0:
				start.y = 0
			elif origin.y + width == size:
				start.y = size - h
			var rect := Rect2i(start - origin, Vector2i(w, h))
			var water := rectangle_sum(wet_prefix, stride, rect)
			var land := w * h - water
			var blocked := rectangle_sum(occupied_prefix, stride, rect) > 0
			var units := land * 2 + water
			var shape := absf(log(float(w) / h))
			if not blocked and land > 0 and units >= amount * 2 and (units < best_units or (units == best_units and shape < best_shape)):
				best = Rect2i(start, Vector2i(w, h))
				best_units = units
				best_shape = shape
				best_land = land
				best_water = water
	if best.size == Vector2i.ZERO:
		return {}
	var tiles: Array[int] = []
	for x in range(best.position.x, best.end.x):
		for y in range(best.position.y, best.end.y):
			tiles.append(x * size + y)
	var sector := Rect2i(origin, Vector2i.ONE * width)
	var expanded := best
	while expanded.get_area() < ceili(best.get_area() * 1.5):
		var next := expanded.grow(1).intersection(sector)
		if next == expanded:
			break
		expanded = next
	var reserve: Array[int] = []
	for x in range(expanded.position.x, expanded.end.x):
		for y in range(expanded.position.y, expanded.end.y):
			if not best.has_point(Vector2i(x, y)) and owners[x * size + y] == 0:
				reserve.append(x * size + y)
	return {"tiles": tiles, "reserve": reserve, "land": best_land, "water": best_water, "center": best.get_center(), "slot": slot}

static func rectangle_sum(prefix: PackedInt32Array, stride: int, rect: Rect2i) -> int:
	return prefix[rect.end.x * stride + rect.end.y] - prefix[rect.position.x * stride + rect.end.y] - prefix[rect.end.x * stride + rect.position.y] + prefix[rect.position.x * stride + rect.position.y]

static func legacy_make(city: CityState, owners: PackedInt32Array, slot: int, amount: int) -> Dictionary:
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
