extends CanvasLayer
## Keep a lightweight, responsive loading screen before loading the main scene.

const MAIN_SCENE := "res://main.tscn"
var overlay: ProgressOverlay
var logo: TextureRect
var progress_panel: PanelContainer
var loading_scene := false


func _ready() -> void:
	get_window().title = "Reticulating Splines"
	overlay = preload("res://src/ui/shared/progress_overlay.tscn").instantiate()
	add_child(overlay)
	overlay.theme = AppUiTheme.current()
	# Cover the scene while it is instantiated, with a fully opaque startup surface.
	overlay.get_node("Shade").color = Color(0.035, 0.047, 0.059, 1)
	logo = TextureRect.new()
	logo.texture = preload("res://assets/branding/reticulating-splines-logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(logo)
	overlay.title_label.hide()
	overlay.detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The standard overlay centers the entire panel. Here the logo is centered,
	# and its progress panel has an independent position immediately below it.
	progress_panel = overlay.get_node("Center/Panel")
	progress_panel.reparent(overlay)
	# Autowrapped text can briefly report a tall minimum before receiving its width.
	progress_panel.minimum_size_changed.connect(progress_panel.reset_size)
	progress_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	progress_panel.grow_horizontal = Control.GROW_DIRECTION_END
	progress_panel.grow_vertical = Control.GROW_DIRECTION_END
	overlay.get_node("Center").hide()
	overlay.resized.connect(_layout_startup)
	overlay.show_progress("Reticulating Splines", "Loading…", 0.0)
	_layout_startup()
	await get_tree().process_frame
	await get_tree().process_frame
	# Present the bar before catalogs, scene construction and asset setup can block.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var settings := ConfigFile.new()
	settings.load(AppPaths.path("settings.cfg"))
	AppLocalization.select(str(settings.get_value("general", "ui_language", AppLocalization.DEFAULT)))
	await _load_application()


func _layout_startup() -> void:
	if logo == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var texture_size := logo.texture.get_size()
	var scale_factor := minf(viewport_size.x * 0.3 / texture_size.x, viewport_size.y * 0.3 / texture_size.y)
	logo.size = texture_size * scale_factor
	logo.position = (viewport_size - logo.size) * 0.5
	progress_panel.custom_minimum_size = Vector2(logo.size.x, 0.0)
	progress_panel.size = Vector2(logo.size.x, 0.0)
	progress_panel.position = Vector2(logo.position.x, logo.position.y + logo.size.y + 16.0)


func _load_application() -> void:
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
