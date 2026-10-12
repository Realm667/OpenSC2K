class_name Mp3Title
extends RefCounted
## Read-only, bounded ID3 title reader. Unsupported/corrupt tags use the filename.
## ID3v2.2 TT2, v2.3/v2.4 TIT2 and ID3v1; see https://id3.org/Developer_Information.

const MAX_TAG_BYTES := 1024 * 1024
static var _cache: Dictionary = {}


static func read(path: String) -> String:
	var fallback := path.get_file().get_basename()
	if path.get_extension().to_lower() != "mp3" or not FileAccess.file_exists(path):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var stamp := [FileAccess.get_modified_time(path), file.get_length()]
	if _cache.has(path) and _cache[path].stamp == stamp:
		return _cache[path].title
	var title := ""
	var header := file.get_buffer(10)
	if header.size() == 10 and header.slice(0, 3).get_string_from_ascii() == "ID3":
		var length := _number(header, 6, 4, true)
		if length > 0 and length <= file.get_length() - 10:
			title = _v2(file.get_buffer(mini(length, MAX_TAG_BYTES)), header[3], header[5])
	if title.is_empty() and file.get_length() >= 128:
		file.seek(file.get_length() - 128)
		var legacy := file.get_buffer(128)
		if legacy.slice(0, 3).get_string_from_ascii() == "TAG":
			title = _clean(_latin(legacy.slice(3, 33)))
	if title.is_empty():
		title = fallback
	if _cache.size() >= 4096:
		_cache.clear()
	_cache[path] = {"stamp": stamp, "title": title}
	return title


static func _number(bytes: PackedByteArray, offset: int, count: int, sync := false) -> int:
	if offset < 0 or offset + count > bytes.size():
		return -1
	var value := 0
	for i in range(offset, offset + count):
		if sync and bytes[i] >= 128:
			return -1
		value = (value << (7 if sync else 8)) | bytes[i]
	return value


static func _unsync(bytes: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	for i in bytes.size():
		if i > 0 and bytes[i] == 0 and bytes[i - 1] == 255:
			continue
		result.append(bytes[i])
	return result


static func _v2(bytes: PackedByteArray, version: int, flags: int) -> String:
	if version not in [2, 3, 4] or (version == 2 and flags & 0x40):
		return ""
	if version < 4 and flags & 0x80:
		bytes = _unsync(bytes)
	var offset := 0
	if version >= 3 and flags & 0x40:
		var size := _number(bytes, 0, 4, version == 4)
		if size < 6:
			return ""
		offset = size + (4 if version == 3 else 0)
	var header_size := 6 if version == 2 else 10
	while offset + header_size <= bytes.size():
		var name_size := 3 if version == 2 else 4
		var name := bytes.slice(offset, offset + name_size).get_string_from_ascii()
		var size := _number(bytes, offset + name_size, 3 if version == 2 else 4, version == 4)
		if size <= 0 or size > bytes.size() - offset - header_size:
			return ""
		var frame_flags := bytes[offset + 9] if version >= 3 else 0
		var body := bytes.slice(offset + header_size, offset + header_size + size)
		offset += header_size + size
		if name not in ["TIT2", "TT2"]:
			continue
		# Compressed/encrypted text cannot be treated as plain text.
		if (version == 3 and frame_flags & 0xC0) or (version == 4 and frame_flags & 0x0C):
			continue
		if version == 4 and (flags & 0x80 or frame_flags & 0x02):
			body = _unsync(body)
		var prefix := 1 if (version == 3 and frame_flags & 0x20) or (version == 4 and frame_flags & 0x40) else 0
		if version == 4 and frame_flags & 0x01:
			prefix += 4
		if prefix >= body.size():
			continue
		var text := _clean(_decode(body.slice(prefix)))
		if not text.is_empty():
			return text
	return ""


static func _latin(bytes: PackedByteArray) -> String:
	var result := ""
	for byte in bytes:
		if byte == 0:
			break
		result += String.chr(byte)
	return result


static func _decode(body: PackedByteArray) -> String:
	if body.size() < 2:
		return ""
	var encoding := body[0]
	var bytes := body.slice(1)
	if encoding == 0:
		return _latin(bytes)
	if encoding == 3:
		return _utf8(bytes)
	if encoding not in [1, 2]:
		return ""
	var little := false
	if encoding == 1:
		if bytes.size() < 2 or bytes.slice(0, 2) not in [PackedByteArray([255, 254]), PackedByteArray([254, 255])]:
			return ""
		little = bytes[0] == 255
		bytes = bytes.slice(2)
	if bytes.size() % 2 != 0:
		return ""
	var result := ""
	var offset := 0
	while offset + 1 < bytes.size():
		var unit := bytes[offset] | (bytes[offset + 1] << 8) if little else (bytes[offset] << 8) | bytes[offset + 1]
		offset += 2
		if unit == 0:
			break
		if unit >= 0xD800 and unit <= 0xDBFF:
			if offset + 1 >= bytes.size():
				return ""
			var low := bytes[offset] | (bytes[offset + 1] << 8) if little else (bytes[offset] << 8) | bytes[offset + 1]
			if low < 0xDC00 or low > 0xDFFF:
				return ""
			unit = 0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00
			offset += 2
		elif unit >= 0xDC00 and unit <= 0xDFFF:
			return ""
		result += String.chr(unit)
	return result


static func _utf8(bytes: PackedByteArray) -> String:
	var result := ""
	var i := 0
	while i < bytes.size():
		var first := bytes[i]
		i += 1
		if first == 0:
			break
		var count := 0 if first < 128 else (1 if first >= 0xC2 and first <= 0xDF else (2 if first >= 0xE0 and first <= 0xEF else (3 if first >= 0xF0 and first <= 0xF4 else -1)))
		if count < 0 or i + count > bytes.size():
			return ""
		var point := first & (0x7F >> count) if count > 0 else first
		for j in count:
			if bytes[i + j] & 0xC0 != 0x80:
				return ""
			point = (point << 6) | (bytes[i + j] & 0x3F)
		i += count
		if (count == 1 and point < 128) or (count == 2 and point < 2048) or (count == 3 and point < 65536) or point > 0x10FFFF or (point >= 0xD800 and point <= 0xDFFF):
			return ""
		result += String.chr(point)
	return result


static func _clean(value: String) -> String:
	var result := ""
	for character in value:
		var code := character.unicode_at(0)
		if code >= 32 and code != 127 and code != 0xFEFF:
			result += character
		if result.length() >= 512:
			break
	return result.strip_edges()
