class_name MultiplayerDelta
extends RefCounted
## Reliable ordered state deltas. Full states establish or repair a baseline.
## Fixed-size pages keep large changed map payloads bounded; unchanged fields,
## history samples and ownership pages do not travel again.
const PAGE := 4096
const CACHE_BYTES := 64 * 1024 * 1024
var states: Dictionary = {}
var sequence := 0
var failed := false
var full_bytes := 0
var delta_bytes := 0

func encode(state: Dictionary) -> Dictionary:
	sequence += 1
	var key := str(state.get("view_owner", "city"))
	var previous: Dictionary = states.get(key, {})
	var result: Dictionary
	if previous.is_empty():
		result = state.duplicate()
		result["wire_id"] = sequence
		result["wire_key"] = key
	else:
		var fields := {}
		var pages := {}
		var removed: Array = []
		for field: String in state:
			if state[field] == previous.get(field):
				continue
			if field in ["city", "owners"] and previous.has(field):
				var value: Variant = state[field]
				var old: Variant = previous[field]
				var changed: Array = []
				var length: int = value.length() if value is String else value.size()
				var old_length: int = old.length() if old is String else old.size()
				for start in range(0, length, PAGE):
					var chunk: Variant = value.substr(start, PAGE) if value is String else value.slice(start, start + PAGE)
					var before: Variant = old.substr(start, PAGE) if old is String else old.slice(start, start + PAGE)
					if start >= old_length or chunk != before:
						changed.append([start, chunk])
				pages[field] = {"length": length, "chunks": changed}
			else:
				fields[field] = state[field]
		for field: String in previous:
			if field not in ["wire_id", "wire_key"] and not state.has(field):
				removed.append(field)
		result = {"type": "state_delta", "wire_id": sequence, "wire_key": key,
			"base": previous.wire_id, "fields": fields, "pages": pages, "removed": removed}
	remember(key, state.merged({"wire_id": sequence, "wire_key": key}, true))
	return result

func decode(message: Dictionary) -> Dictionary:
	failed = false
	if not CoopWorld.whole_number(message.get("wire_id"), 1, 9007199254740991) or not message.get("wire_key") is String:
		failed = true
		return {}
	var key: String = message.wire_key
	if message.get("type") == "state":
		remember(key, message)
		return message
	var before: Dictionary = states.get(key, {})
	if before.is_empty() or before.get("wire_id") != message.get("base") or not message.get("fields") is Dictionary or not message.get("pages") is Dictionary or not message.get("removed") is Array:
		failed = true
		return {}
	var result := before.duplicate()
	result.merge(message.fields, true)
	for field: Variant in message.removed:
		result.erase(field)
	for field: Variant in message.pages:
		if field not in ["city", "owners"] or not before.has(field):
			failed = true
			return {}
		var patch: Variant = message.pages[field]
		var maximum := MultiplayerStateStream.MAX_BYTES * 2 if field == "city" else 4096 * 4096
		if not patch is Dictionary or not CoopWorld.whole_number(patch.get("length"), 0, maximum) or not patch.get("chunks") is Array:
			failed = true
			return {}
		var changes := {}
		for part: Variant in patch.chunks:
			if not part is Array or part.size() != 2 or not CoopWorld.whole_number(part[0], 0, maxi(0, int(patch.length) - 1)) or int(part[0]) % PAGE != 0 or changes.has(int(part[0])):
				failed = true
				return {}
			if (field == "city" and not part[1] is String) or (field == "owners" and not part[1] is Array):
				failed = true
				return {}
			var count: int = part[1].length() if field == "city" else part[1].size()
			if count != mini(PAGE, int(patch.length) - int(part[0])):
				failed = true
				return {}
			changes[int(part[0])] = part[1]
		var strings := PackedStringArray()
		var array: Array = []
		for start in range(0, int(patch.length), PAGE):
			var count := mini(PAGE, int(patch.length) - start)
			if field == "city":
				var part: String = changes.get(start, str(before[field]).substr(start, count))
				if part.length() != count:
					failed = true
					return {}
				strings.append(part)
			else:
				var part: Array = changes.get(start, before[field].slice(start, start + count))
				if part.size() != count:
					failed = true
					return {}
				array.append_array(part)
		result[field] = "".join(strings) if field == "city" else array
	result["type"] = "state"
	result["wire_id"] = message.wire_id
	result["wire_key"] = key
	remember(key, result)
	return result

func remember(key: String, state: Dictionary) -> void:
	states.erase(key)
	states[key] = state.duplicate(true)
	var bytes := 0
	for item: Dictionary in states.values():
		bytes += str(item.get("city", "")).length() * 4 + item.get("owners", []).size() * 8
	while states.size() > 1 and (bytes > CACHE_BYTES or states.size() > 2):
		var oldest: String = states.keys()[0]
		var item: Dictionary = states[oldest]
		bytes -= str(item.get("city", "")).length() * 4 + item.get("owners", []).size() * 8
		states.erase(oldest)
