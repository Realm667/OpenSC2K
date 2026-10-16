class_name CityPreviewStore
extends RefCounted
## Optional presentation data. Never rewrite an original city to create a preview.

const ENTRY := "preview.png"
const MAX_BYTES := 2 * 1024 * 1024
const MAX_SIZE := Vector2i(768, 512)
const CACHE_VERSION := "city-preview-1"
const CACHE_LIMIT := 96


static func decode(bytes: PackedByteArray) -> Image:
	# Inspect PNG dimensions before asking the decoder to allocate pixel memory.
	if bytes.size() < 33 or bytes.size() > MAX_BYTES:
		return null
	if bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return null
	if bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return null
	var width := _big_u32(bytes, 16)
	var height := _big_u32(bytes, 20)
	if width < 1 or height < 1 or width > MAX_SIZE.x or height > MAX_SIZE.y:
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK else null


static func _big_u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


static func embedded(path: String) -> Image:
	var archive := read_members(path, {ENTRY: MAX_BYTES})
	return decode(archive.get("data", {}).get(ENTRY, PackedByteArray()))


static func read_members(path: String, limits: Dictionary) -> Dictionary:
	# Read only small presentation/header members, never the dense terrain planes.
	# ZIPReader has no bounded read API. Check the central-directory size first.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 22 or file.get_length() > Sc2xDocument.MAX_ARCHIVE_BYTES:
		return {}
	var tail_size := mini(file.get_length(), 65557)
	file.seek(file.get_length() - tail_size)
	var tail := file.get_buffer(tail_size)
	var end := -1
	for offset in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(offset) == 0x06054b50 and offset + 22 + tail.decode_u16(offset + 20) == tail.size():
			end = offset
			break
	if end < 0 or tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0:
		return {}
	var count := tail.decode_u16(end + 10)
	var directory_size := tail.decode_u32(end + 12)
	var directory_offset := tail.decode_u32(end + 16)
	if count > 4096 or directory_size > 1024 * 1024 or directory_offset + directory_size > file.get_length() - 22:
		return {}
	file.seek(directory_offset)
	var directory := file.get_buffer(directory_size)
	file.close()
	var cursor := 0
	var sizes := {}
	var allowed := {}
	for _index in count:
		if cursor + 46 > directory.size() or directory.decode_u32(cursor) != 0x02014b50:
			return {}
		var name_size := directory.decode_u16(cursor + 28)
		var next := cursor + 46 + name_size + directory.decode_u16(cursor + 30) + directory.decode_u16(cursor + 32)
		if next > directory.size():
			return {}
		var name := directory.slice(cursor + 46, cursor + 46 + name_size).get_string_from_utf8()
		if sizes.has(name):
			return {}
		sizes[name] = directory.decode_u32(cursor + 24)
		if limits.has(name) and sizes[name] <= limits[name] and directory.decode_u32(cursor + 20) <= limits[name]:
			allowed[name] = sizes[name]
		cursor = next
	if not sizes.has(Sc2xDocument.METADATA_ENTRY):
		return {}
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {}
	var data := {}
	for name: String in allowed:
		var bytes := reader.read_file(name)
		if bytes.size() == allowed[name]:
			data[name] = bytes
	reader.close()
	return {"sizes": sizes, "data": data}


static func cache_root() -> String:
	return AppPaths.path("cache/city-previews")


static func cache_path(digest: String, graphics_key: String) -> String:
	return cache_root().path_join((CACHE_VERSION + digest + graphics_key).sha256_text() + ".png")


static func cached(digest: String, graphics_key: String) -> Image:
	if digest.is_empty():
		return null
	var file := FileAccess.open(cache_path(digest, graphics_key), FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return null
	return decode(file.get_buffer(file.get_length()))


static func store(digest: String, graphics_key: String, image: Image) -> void:
	if digest.is_empty() or image == null:
		return
	var bytes := image.save_png_to_buffer()
	if bytes.size() > MAX_BYTES or DirAccess.make_dir_recursive_absolute(cache_root()) != OK:
		return
	var path := cache_path(digest, graphics_key)
	var temporary := path + ".%d.tmp" % OS.get_thread_caller_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
	var entries: Array[Dictionary] = []
	for name in DirAccess.get_files_at(cache_root()):
		if name.ends_with(".png"):
			var full_path := cache_root().path_join(name)
			entries.append({"path": full_path, "time": FileAccess.get_modified_time(full_path)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for index in maxi(0, entries.size() - CACHE_LIMIT):
		DirAccess.remove_absolute(entries[index].path)
