class_name NumberedFrameSequence
extends RefCounted
## Discover contiguous *_001.png, *_002.png, ... once during pack loading.
## The filename order is the playback order; every source frame lasts 125 ms.

const FPS := 8
const MAX_FRAMES := 32

var error := ""


func resolve(record: Dictionary, exists: Callable) -> Dictionary:
	error = ""
	if record.has("animation") or not exists.is_valid():
		return record
	var first: Variant = record.get("artwork_rgba", record.get("png"))
	if not first is String or not first.ends_with("_001.png"):
		return record
	var paths: Array[String] = [first]
	for number in range(2, MAX_FRAMES + 2):
		var path := _frame_path(first, number)
		if not exists.call(path):
			break
		if number > MAX_FRAMES:
			error = "Numbered animation exceeds 32 source frames"
			return {}
		paths.append(path)
	if paths.size() == 1:
		return record
	var spec := {"format": "rgba" if record.has("artwork_rgba") else "indexed", "frames": paths, "fps": FPS}
	var light: Variant = record.get("lightmap", "")
	if light is String and light.ends_with("_001.png") and exists.call(_frame_path(light, 2)):
		var masks: Array[String] = [light]
		for number in range(2, paths.size() + 1):
			var path := _frame_path(light, number)
			if not exists.call(path):
				error = "Numbered lightmap sequence must cover every artwork frame"
				return {}
			masks.append(path)
		if exists.call(_frame_path(light, paths.size() + 1)):
			error = "Numbered lightmap sequence exceeds the artwork sequence"
			return {}
		spec.lightmaps = masks
	var resolved := record.duplicate()
	resolved.animation = spec
	return resolved


static func _frame_path(first: String, number: int) -> String:
	return first.trim_suffix("001.png") + "%03d.png" % number
