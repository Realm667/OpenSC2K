class_name MultiplayerDisplayJob
extends RefCounted
## Prepare a complete display transaction on private data, never on a live city.
var task := -1
var state: Dictionary = {}
var previous: Dictionary = {}
var before: Sc2File
var document: Sc2File
var edit := EditCommandResult.new()
var elapsed_usec := 0


func start(value: Dictionary, old_state: Dictionary, old_document: Sc2File) -> void:
	state = value.duplicate(true)
	previous = old_state.duplicate(true)
	before = old_document.duplicate_document(true)
	task = WorkerThreadPool.add_task(prepare, false, "Multiplayer display transaction")


func prepare() -> void:
	var started := Time.get_ticks_usec()
	document = MultiplayerDocument.restore(state, previous, before)
	if document != null:
		edit.ok = true
		for chunk in document.chunks:
			var old := before.find_chunk(chunk.chunk_id)
			if old == null or old.decoded_payload != chunk.decoded_payload:
				edit.changed_ids.append(chunk.chunk_id)
				edit.old_payloads[chunk.chunk_id] = old.decoded_payload if old != null else PackedByteArray()
				edit.new_payloads[chunk.chunk_id] = chunk.decoded_payload
	elapsed_usec = Time.get_ticks_usec() - started


func ready() -> bool:
	return task >= 0 and WorkerThreadPool.is_task_completed(task)


func finish() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
	task = -1
	before = null
	previous.clear()
