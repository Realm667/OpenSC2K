extends CanvasLayer
## Keep a lightweight, responsive loading screen before loading the main scene.

const MAIN_SCENE := "res://main.tscn"
var overlay: ProgressOverlay
var loading_scene := false


func _ready() -> void:
	get_window().title = "Reticulating Splines"
	var settings := ConfigFile.new()
	settings.load(AppPaths.path("settings.cfg"))
	AppLocalization.select(str(settings.get_value("general", "ui_language", AppLocalization.DEFAULT)))
	overlay = preload("res://src/ui/shared/progress_overlay.tscn").instantiate()
	add_child(overlay)
	overlay.theme = AppUiTheme.current()
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/branding/reticulating-splines-logo.png")
	logo.custom_minimum_size = Vector2(0, 140)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := overlay.get_node("Center/Panel/Rows")
	rows.add_child(logo)
	rows.move_child(logo, 0)
	overlay.show_progress("Reticulating Splines", "Loading…", 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var error := ResourceLoader.load_threaded_request(MAIN_SCENE)
	if error != OK:
		_failed(error_string(error))
		return
	loading_scene = true
	var progress := []
	while ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		overlay.show_progress("Reticulating Splines", "Loading…", float(progress[0]) * 0.3 if not progress.is_empty() else 0.0)
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(MAIN_SCENE) != ResourceLoader.THREAD_LOAD_LOADED:
		_failed(tr("Cannot load the application."))
		return
	var scene := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	loading_scene = false
	var application := scene.instantiate()
	application.set("startup_progress", overlay)
	application.connect("startup_finished", queue_free)
	get_tree().root.add_child(application)
	get_tree().current_scene = application


func _failed(message: String) -> void:
	overlay.show_progress("Reticulating Splines", message, 0.0)


func _exit_tree() -> void:
	# The window can close while the resource worker is still parsing scripts.
	if loading_scene:
		ResourceLoader.load_threaded_get(MAIN_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
