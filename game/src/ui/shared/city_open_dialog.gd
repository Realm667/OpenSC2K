class_name CityOpenDialog
extends FileDialog
## Preserve Godot's file navigation and add a read-only city preview beside it.

var assets: LoadedAssetState
var preview_panel: PanelContainer
var preview_image: TextureRect
var preview_name: Label
var preview_status: Label
var selected_path := ""
var displayed_path := ""
var displayed_image: Image
var job: CityPreviewJob
var _job_path := ""
var _requested_msec := 0
var _body: BoxContainer


func _ready() -> void:
	use_native_dialog = false
	mode_overrides_title = false
	title = "Open City"
	var navigation: HSplitContainer
	for child in get_vbox().get_children():
		if child is HSplitContainer:
			navigation = child
			break
	if navigation == null:
		return
	var index := navigation.get_index()
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	get_vbox().add_child(_body)
	get_vbox().move_child(_body, index)
	navigation.reparent(_body)
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel = PanelContainer.new()
	preview_panel.name = "CityPreview"
	preview_panel.theme_type_variation = &"InformationPanel"
	preview_panel.custom_minimum_size.x = 240
	_body.add_child(preview_panel)
	var rows := VBoxContainer.new()
	preview_panel.add_child(rows)
	var heading := Label.new()
	heading.text = "City preview"
	heading.theme_type_variation = &"SectionHeading"
	rows.add_child(heading)
	preview_image = TextureRect.new()
	preview_image.name = "Image"
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview_image.custom_minimum_size.y = 120
	preview_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(preview_image)
	preview_name = Label.new()
	preview_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_name.theme_type_variation = &"SectionHeading"
	rows.add_child(preview_name)
	preview_status = Label.new()
	preview_status.text = "Select a city to preview."
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_status.theme_type_variation = &"HelpLabel"
	rows.add_child(preview_status)
	visibility_changed.connect(_visibility_changed)
	size_changed.connect(_layout_preview)


func _layout_preview() -> void:
	if preview_panel != null:
		# Keep navigation usable at small UI viewports; preview moves below it.
		_body.vertical = size.x < 760
		preview_panel.custom_minimum_size = Vector2(0 if _body.vertical else clampf(size.x * 0.3, 240, 420),
			160 if _body.vertical else 0)
		preview_image.custom_minimum_size.y = 80 if _body.vertical else 120


func _visibility_changed() -> void:
	selected_path = ""
	if not visible and job != null:
		job.cancel()
	if visible:
		_layout_preview()


func _process(_delta: float) -> void:
	if preview_panel == null:
		return
	if job != null and job.finished():
		job.join()
		if visible and _job_path == selected_path and not job.cancelled():
			displayed_path = _job_path
			displayed_image = job.image
			preview_image.texture = ImageTexture.create_from_image(job.image) if job.image != null else null
			preview_status.text = ("Saved city preview" if job.saved_preview else "City overview") if job.image != null else "Preview unavailable. You can still open this city."
		job = null
	if not visible:
		return
	var path := current_path
	if path != selected_path:
		selected_path = path
		_requested_msec = Time.get_ticks_msec()
		displayed_image = null
		displayed_path = ""
		preview_image.texture = null
		preview_name.text = path.get_file().get_basename() if _is_city(path) else ""
		preview_status.text = "Preparing city preview…" if _is_city(path) else "Select a city to preview."
		if job != null:
			job.cancel()
	if job == null and selected_path != displayed_path and Time.get_ticks_msec() - _requested_msec >= 250 and _is_city(selected_path):
		job = CityPreviewJob.for_assets(assets) if assets != null else CityPreviewJob.new()
		job.path = selected_path
		_job_path = selected_path
		job.start()


func image_for_path(path: String) -> Image:
	return displayed_image if displayed_path == path else null


static func _is_city(path: String) -> bool:
	return path.get_extension().to_lower() in ["sc2", "sc2x", "scn"] and FileAccess.file_exists(path)


func _exit_tree() -> void:
	if job != null:
		job.cancel()
		job.join()
