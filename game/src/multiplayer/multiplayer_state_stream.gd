class_name MultiplayerStateStream
extends RefCounted
## Large snapshots are spooled to temporary files, with one small chunk queued
## at a time. The TCP frame/queue limits and host command limit remain unchanged.

const CHUNK_BYTES := 48 * 1024
const MAX_BYTES := Sc2xDocument.MAX_ARCHIVE_BYTES
var path := ""
var file: FileAccess
var size := 0
var offset := 0
var digest := ""
var failed := false
var started := false
var complete := false

func open_output(state: Dictionary) -> bool:
	path = temporary_path()
	file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	size = file.get_length()
	if file.get_error() != OK or size > MAX_BYTES:
		close()
		return false
	digest = FileAccess.get_sha256(path)
	file.seek(0)
	return true

func pump(channel: CityTcpChannel) -> bool:
	if not channel.output.is_empty():
		return false
	if not started:
		started = true
		channel.send({"type": "state_begin", "bytes": size, "sha256": digest})
	elif offset < size:
		var data := file.get_buffer(mini(CHUNK_BYTES, size - offset))
		if data.is_empty():
			channel.failed = true
			return false
		channel.send({"type": "state_part", "offset": offset, "data": Marshalls.raw_to_base64(data)})
		offset += data.size()
	else:
		channel.send({"type": "state_end"})
		close()
		return true
	return false

func receive(message: Dictionary) -> Dictionary:
	match message.get("type"):
		"state_begin":
			if started or not CoopWorld.whole_number(message.get("bytes"), 2, MAX_BYTES) or not message.get("sha256") is String or message.sha256.length() != 64:
				failed = true
				return {}
			size = int(message.bytes)
			digest = message.sha256
			path = temporary_path()
			file = FileAccess.open(path, FileAccess.WRITE_READ)
			failed = file == null
			started = not failed
		"state_part":
			if not started or message.get("offset") != offset or not message.get("data") is String or message.data.length() > CHUNK_BYTES * 4 / 3:
				failed = true
				return {}
			var data := Marshalls.base64_to_raw(message.data)
			if data.is_empty() or data.size() > CHUNK_BYTES or offset + data.size() > size:
				failed = true
				return {}
			file.store_buffer(data)
			offset += data.size()
			failed = file.get_error() != OK
		"state_end":
			if not started or offset != size:
				failed = true
				return {}
			file.flush()
			if file.get_error() != OK or FileAccess.get_sha256(path) != digest:
				failed = true
				return {}
			file.seek(0)
			var result: Variant = JSON.parse_string(file.get_as_text())
			close()
			if not result is Dictionary or result.get("type") != "state":
				failed = true
				return {}
			complete = true
			return result
	return {}

func close() -> void:
	if file != null:
		file.close()
		file = null
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		path = ""

static func temporary_path() -> String:
	return "user://multiplayer-transfer-%s.tmp" % Crypto.new().generate_random_bytes(12).hex_encode()
