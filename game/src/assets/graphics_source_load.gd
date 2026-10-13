class_name GraphicsSourceLoad
extends RefCounted
## Decode a private source on a worker. Only the main thread publishes assets.

var thread := Thread.new()
var _mutex := Mutex.new()
var _fraction := 0.0


func start(reference: String, mode: String, folder: String) -> Error:
	return thread.start(func() -> GameAssetSource:
		return GameAssetSource.load_source(reference, mode, folder, "", _report))


func _report(value: float) -> void:
	_mutex.lock()
	_fraction = value
	_mutex.unlock()


func fraction() -> float:
	_mutex.lock()
	var value := _fraction
	_mutex.unlock()
	return value


func finish() -> GameAssetSource:
	return thread.wait_to_finish() as GameAssetSource
