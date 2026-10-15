class_name MasterFrameAnimation
extends RefCounted
## Compile up to 32 editable RGBA frames into the existing resident GPU strip.
## Holds and ping-pong are expanded once, never on the rendering thread.

@warning_ignore_start("integer_division")

var error := ""


func load_frames(spec: Dictionary, base: Image, emission: Image, read_rgba: Callable, budget: int) -> Dictionary:
	error = ""
	var paths: Variant = spec.get("frames")
	var rate: Variant = spec.get("fps", 8)
	var playback: Variant = spec.get("playback", "loop")
	if not paths is Array or paths.size() < 1 or paths.size() > 32 or not read_rgba.is_valid():
		return _fail("RGBA object animations require one to 32 frames")
	if not (rate is int or rate is float) or not is_finite(float(rate)) or rate != int(rate) or int(rate) not in [5, 8]:
		return _fail("Object animation fps must be 5 or 8")
	if playback not in ["loop", "ping_pong"]:
		return _fail("Object animation playback must be loop or ping_pong")
	var tick := 1000 / int(rate)
	var durations: Variant = spec.get("durations_ms", [])
	if not durations is Array or (not durations.is_empty() and durations.size() != paths.size()):
		return _fail("Object animation duration count differs from frame count")
	var holds: Array[int] = []
	for i in paths.size():
		var duration: Variant = tick if durations.is_empty() else durations[i]
		if not (duration is int or duration is float) or not is_finite(float(duration)):
			return _fail("Invalid object animation duration")
		if duration < tick or duration > tick * 32 or duration != int(duration) or int(duration) % tick != 0:
			return _fail("Object animation durations must be positive multiples of the frame tick")
		holds.append(int(duration) / tick)
	var order: Array[int] = []
	for i in paths.size():
		order.append(i)
	if playback == "ping_pong":
		for i in range(paths.size() - 2, 0, -1):
			order.append(i)
	var sequence: Array[int] = []
	for i in order:
		for repeat in holds[i]:
			sequence.append(i)
	# The native strip contract has at least two frames, even for a still.
	if sequence.size() == 1:
		sequence.append(0)
	var light_paths: Variant = spec.get("lightmaps", [])
	if not light_paths is Array or (not light_paths.is_empty() and light_paths.size() != paths.size()):
		return _fail("Object animation lightmap count differs from frame count")
	if not light_paths.is_empty() and emission == null:
		return _fail("Animated lightmaps require a base lightmap")
	if base == null or base.get_format() != Image.FORMAT_RGBA8:
		return _fail("Object animation base must be RGBA8")
	var size := base.get_size()
	if sequence.size() > 32 or (size.y + 4) * sequence.size() + 4 > 8192:
		return _fail("Object animation exceeds GPU strip limits")
	var bytes := size.x * size.y * 4 * sequence.size() * (2 if emission != null else 1)
	if bytes > budget:
		return _fail("Object animation exceeds the decoded memory budget")
	var art: Array[Image] = []
	var masks: Array[Image] = []
	for i in paths.size():
		if not paths[i] is String or (not light_paths.is_empty() and not light_paths[i] is String):
			return _fail("Object animation paths must be strings")
		var frame: Image = read_rgba.call(paths[i])
		if frame == null or frame.get_size() != size or frame.get_format() != Image.FORMAT_RGBA8:
			return _fail("Object animation frame dimensions or format differ from the base")
		if i == 0 and not _same_pixels(frame, base):
			return _fail("Object animation frame zero must match the base artwork")
		var mask := emission
		if not light_paths.is_empty():
			mask = read_rgba.call(light_paths[i])
			if mask == null:
				return _fail("Object animation lightmap cannot be loaded")
		if mask != null:
			if mask.get_size() != size or mask.get_format() != Image.FORMAT_RGBA8:
				return _fail("Object animation lightmap dimensions or format differ from the base")
			if i == 0 and not _same_pixels(mask, emission):
				return _fail("Object animation lightmap zero must match the base lightmap")
			var colors := frame.get_data()
			var lights := mask.get_data()
			for pixel in range(3, colors.size(), 4):
				if lights[pixel] > 0 and colors[pixel] == 0:
					return _fail("Object animation lightmap extends outside its artwork frame")
		art.append(frame)
		masks.append(mask)
	var strip := Image.create(size.x, size.y * sequence.size(), false, Image.FORMAT_RGBA8)
	var light_strip: Image
	if emission != null:
		light_strip = Image.create(size.x, size.y * sequence.size(), false, Image.FORMAT_RGBA8)
	for i in sequence.size():
		var destination := Vector2i(0, i * size.y)
		strip.blit_rect(art[sequence[i]], Rect2i(Vector2i.ZERO, size), destination)
		if light_strip != null:
			light_strip.blit_rect(masks[sequence[i]], Rect2i(Vector2i.ZERO, size), destination)
	return {"art": strip, "light": light_strip, "frames": sequence.size(), "fps": int(rate), "bytes": bytes}


func _fail(message: String) -> Dictionary:
	error = message
	return {}


static func _same_pixels(first: Image, second: Image) -> bool:
	var a := first.get_data()
	var b := second.get_data()
	if a == b:
		return true
	# Indexed decoding clears hidden RGB; PNG RGBA decoding may retain it.
	# Only fully transparent colors are irrelevant. Alpha and visible RGB match.
	if a.size() != b.size():
		return false
	for pixel in range(0, a.size(), 4):
		if a[pixel + 3] != b[pixel + 3]:
			return false
		if a[pixel + 3] > 0 and (a[pixel] != b[pixel] or a[pixel + 1] != b[pixel + 1] or a[pixel + 2] != b[pixel + 2]):
			return false
	return true
