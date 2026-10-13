class_name HdPreparedCache
extends RefCounted
## Content-addressed derived pixels. The version also identifies the filter.

const VERSION := "hd-lanczos-straight-alpha-v1"
const MEMORY_LIMIT := 32 * 1024 * 1024
const DISK_LIMIT := 128 * 1024 * 1024
# Tiny vehicle/person frames are cheaper to retain in RAM than to open hundreds
# of separate files. Persist only conversions large enough to repay file I/O.
const MIN_DISK_BYTES := 16 * 1024
static var _mutex := Mutex.new()
static var _images: Dictionary[String, Image] = {}
static var _bytes := 0
static var _writes := 0


static func digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


static func key(source: Image, size: Vector2i) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([VERSION, source.get_width(), source.get_height(), source.get_format(), source.has_mipmaps(), size]))
	context.update(source.get_data())
	return context.finish().hex_encode()


static func load_image(identifier: String, size: Vector2i) -> Image:
	_mutex.lock()
	var memory: Image = _images.get(identifier)
	_mutex.unlock()
	if memory != null:
		return memory.duplicate()
	var expected := size.x * size.y * 4
	if expected < MIN_DISK_BYTES or expected > MEMORY_LIMIT:
		return null
	var path := AppPaths.path("cache/" + VERSION).path_join(identifier + ".rgba")
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != expected + 32:
		return null
	var checksum := file.get_buffer(32)
	var bytes := file.get_buffer(expected)
	if digest(bytes) != checksum:
		return null
	var result := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	_remember(identifier, result)
	return result


static func _remember(identifier: String, image: Image) -> void:
	_mutex.lock()
	var bytes := image.get_data().size()
	if not _images.has(identifier) and bytes <= MEMORY_LIMIT:
		while _bytes + bytes > MEMORY_LIMIT and not _images.is_empty():
			var oldest: String = _images.keys()[0]
			_bytes -= _images[oldest].get_data().size()
			_images.erase(oldest)
		_images[identifier] = image.duplicate()
		_bytes += bytes
	_mutex.unlock()


static func store_image(identifier: String, image: Image) -> void:
	_remember(identifier, image)
	var bytes := image.get_data()
	if bytes.size() < MIN_DISK_BYTES or bytes.size() > MEMORY_LIMIT:
		return
	var folder := AppPaths.path("cache/" + VERSION)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return
	_mutex.lock()
	var path := folder.path_join(identifier + ".rgba")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file != null:
		file.store_buffer(digest(bytes))
		file.store_buffer(bytes)
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
		_writes += 1
		if _writes % 32 == 0:
			_trim(folder)
	_mutex.unlock()


static func _trim(folder: String) -> void:
	var total := 0
	var files: Array = []
	for name in DirAccess.get_files_at(folder):
		if name.get_extension() != "rgba":
			continue
		var path := folder.path_join(name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var size := file.get_length()
			total += size
			files.append([FileAccess.get_modified_time(path), path, size])
	files.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item in files:
		if total <= DISK_LIMIT:
			break
		if DirAccess.remove_absolute(item[1]) == OK:
			total -= item[2]
