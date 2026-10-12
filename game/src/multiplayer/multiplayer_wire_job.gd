class_name MultiplayerWireJob
extends RefCounted
## A job owns only copied plain data. No scene, live city, socket or file access.
var task := -1
var input: Dictionary = {}
var bytes := PackedByteArray()
var decoded: Dictionary = {}
var failed := false
var full := false
var delta: MultiplayerDelta
var baseline_failed := false


func start_state(value: Dictionary, codec: MultiplayerDelta, decoding := false) -> void:
	delta = codec
	start(value, decoding)


func start(value: Dictionary, decoding := false) -> void:
	input = value.duplicate(true)
	full = value.get("type") == "state"
	task = WorkerThreadPool.add_task(unpack if decoding else pack, false, "Multiplayer state codec")


func ready() -> bool:
	return task >= 0 and WorkerThreadPool.is_task_completed(task)


func finish() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
	input.clear()


func pack() -> void:
	if delta != null:
		input = delta.encode(input)
		full = input.get("type") == "state"
	var raw := JSON.stringify(input).to_utf8_buffer()
	if raw.size() > MultiplayerStateStream.MAX_BYTES:
		failed = true
		return
	# Small deltas do not need a compression envelope.
	if raw.size() < 4096:
		bytes = raw
		return
	bytes = JSON.stringify({"type": "packed_state", "bytes": raw.size(),
		"sha256": digest(raw), "data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}).to_utf8_buffer()


func unpack() -> void:
	if input.get("type") in ["state", "state_delta"]:
		decode_state(input)
		return
	if not CoopWorld.whole_number(input.get("bytes"), 2, MultiplayerStateStream.MAX_BYTES) or not input.get("data") is String or input.data.length() > MultiplayerStateStream.MAX_BYTES or not input.get("sha256") is String:
		failed = true
		return
	var raw := Marshalls.base64_to_raw(input.data).decompress(int(input.bytes), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(input.bytes) or digest(raw) != input.sha256:
		failed = true
		return
	var value: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not value is Dictionary or value.get("type") not in ["state", "state_delta"]:
		failed = true
		return
	decode_state(value)


func decode_state(value: Dictionary) -> void:
	decoded = delta.decode(value) if delta != null else value
	baseline_failed = delta != null and delta.failed


static func digest(value: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(value)
	return hash.finish().hex_encode()
