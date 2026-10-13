class_name VisualArtwork
extends RefCounted
## Optional independent artwork for cosmetic environment and city-life rendering.

const CLOUDS := ["cumulus", "stratus", "altostratus", "cirrus", "cirrocumulus"]
const VEHICLES := ["car", "truck", "bus"]
const MAX_DECODED_BYTES := 768 * 1024 * 1024

class Frame extends RefCounted:
	var image: Image
	var emission: Image
	var season_mask: Image
	var logical_size := Vector2i.ZERO
	var scale := 4

var error := ""
var frames: Dictionary[String, Frame] = {}
var _decoded_bytes := 0


static func load_records(records: Variant, read_image: Callable) -> VisualArtwork:
	var artwork := VisualArtwork.new()
	artwork._load(records, read_image)
	return artwork


func _load(records: Variant, read_image: Callable) -> void:
	if not records is Array or records.is_empty() or records.size() > 2000:
		_fail("visual_artwork must be a nonempty array of at most 2000 records")
		return

	var images: Dictionary[String, Image] = {}
	for record: Variant in records:
		if not record is Dictionary or not record.get("key") is String:
			_fail("Visual artwork records require a string key")
			return
		var key: String = record.key
		if not _valid_key(key) or frames.has(key):
			_fail("Invalid or repeated visual artwork key: %s" % key)
			return
		var size: Variant = record.get("logical_size")
		if not size is Array or size.size() != 2 or not _whole(size[0], 1, 2048) or not _whole(size[1], 1, 2048):
			_fail("Visual artwork logical_size must contain two positive whole dimensions")
			return
		if not _whole(record.get("master_scale"), 4, 4):
			_fail("Visual artwork master_scale must be 4")
			return
		var frame := Frame.new()
		frame.logical_size = Vector2i(size[0], size[1])
		if key.begins_with("woodland/") and frame.logical_size != Vector2i(32, 36):
			_fail("Woodland artwork must retain its 32 by 36 logical frame")
			return
		if key.begins_with("person/") and frame.logical_size != Vector2i(3, 6):
			_fail("Pedestrian artwork must retain its 3 by 6 logical frame")
			return
		frame.image = _image(record.get("png"), read_image, images)
		if frame.image == null:
			return
		if frame.image.get_size() != frame.logical_size * frame.scale:
			_fail("Visual artwork dimensions differ from logical_size times master_scale: %s" % key)
			return
		for field: String in ["lightmap", "season_mask"]:
			if not record.has(field):
				continue
			var mask := _image(record[field], read_image, images)
			if mask == null:
				return
			if mask.get_size() != frame.image.get_size():
				_fail("Visual artwork mask dimensions differ: %s" % key)
				return
			if field == "lightmap":
				frame.emission = mask
			else:
				frame.season_mask = mask
		frames[key] = frame


func _image(path: Variant, read_image: Callable, images: Dictionary[String, Image]) -> Image:
	if not path is String or path.is_empty():
		_fail("Visual artwork PNG path must be a nonempty string")
		return null
	if not images.has(path):
		var image: Image = read_image.call(path)
		if image == null or image.is_empty():
			_fail("Cannot read visual artwork PNG: %s" % path)
			return null
		_decoded_bytes += image.get_width() * image.get_height() * 4
		if _decoded_bytes > MAX_DECODED_BYTES:
			_fail("Visual artwork exceeds the decoded image budget")
			return null
		images[path] = image
	return images[path]


static func _valid_key(key: String) -> bool:
	var parts := key.split("/")
	if parts.size() == 2:
		return ((parts[0] == "cloud" and parts[1] in CLOUDS)
			or (parts[0] == "ground" and _index(parts[1], 1256, 1268)))
	if parts.size() != 4:
		return false
	match parts[0]:
		"vehicle":
			return parts[1] in VEHICLES and _index(parts[2], 0, 17) and _index(parts[3], 0, 7)
		"person":
			return _index(parts[1], 0, 5) and _index(parts[2], 0, 7) and _index(parts[3], 0, 1)
		"woodland":
			return _index(parts[1], 1, 7) and _index(parts[2], 0, 15) and _index(parts[3], 0, 7)
	return false


static func _index(value: String, low: int, high: int) -> bool:
	return value.is_valid_int() and str(int(value)) == value and int(value) >= low and int(value) <= high


static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value >= low and value <= high and value == int(value)


func _fail(message: String) -> void:
	error = message
	frames.clear()
