class_name CityOpenDialog
extends FileDialog
## Preserve Godot's file navigation and add a read-only city preview beside it.

var assets: LoadedAssetState
var preview_panel: PanelContainer
var preview_image: TextureRect
var preview_name: Label
var preview_status: Label
var preview_details: Label
var displayed_details: Dictionary = {}
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
	navigation.size_flags_stretch_ratio = 7.0
	preview_panel = PanelContainer.new()
	preview_panel.name = "CityPreview"
	preview_panel.theme_type_variation = &"InformationPanel"
	preview_panel.custom_minimum_size.x = 240
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 3.0
	_body.add_child(preview_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
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
	preview_details = Label.new()
	preview_details.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(preview_details)
	preview_status = Label.new()
	preview_status.text = "Select a city to preview."
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_status.theme_type_variation = &"HelpLabel"
	rows.add_child(preview_status)
	visibility_changed.connect(_visibility_changed)
	get_parent().get_viewport().size_changed.connect(_layout_preview)


func _layout_preview() -> void:
	if preview_panel != null:
		# The containing viewport is independent of this dialog's minimum size.
		# Basing the minimum on the resulting dialog width feeds size changes
		# back into FileDialog's wrapping and the saved-window bounds clamp.
		_body.vertical = get_parent().get_viewport().get_visible_rect().size.x * 0.8 < 760
		preview_panel.custom_minimum_size = Vector2(0 if _body.vertical else 240,
			160 if _body.vertical else 0)
		preview_panel.size_flags_vertical = Control.SIZE_FILL if _body.vertical else Control.SIZE_EXPAND_FILL
		preview_panel.size_flags_stretch_ratio = 1.0 if _body.vertical else 3.0
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
	if visible and job != null and _job_path == selected_path and not job.cancelled():
		var details := job.details()
		if details != displayed_details:
			displayed_details = details
			_update_details()
	if job != null and job.finished():
		job.join()
		if visible and _job_path == selected_path and not job.cancelled():
			displayed_details = job.details()
			_update_details()
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
		displayed_details = {}
		preview_details.text = ""
		preview_name.text = path.get_file().get_basename() if _is_city(path) else ""
		preview_status.text = "Preparing city preview…" if _is_city(path) else "Select a city to preview."
		if job != null:
			job.cancel()
	if job == null and selected_path != displayed_path and Time.get_ticks_msec() - _requested_msec >= 250 and _is_city(selected_path):
		job = CityPreviewJob.for_assets(assets) if assets != null else CityPreviewJob.new()
		job.path = selected_path
		_job_path = selected_path
		job.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and preview_details != null:
		_update_details()


func _update_details() -> void:
	var info := displayed_details
	if info.is_empty():
		preview_details.text = ""
		return
	if not str(info.get("city_name", "")).is_empty():
		preview_name.text = info.city_name
	var lines := PackedStringArray()
	if info.multiplayer:
		var mode := ""
		match info.get("mode", "unknown"):
			"coop":
				mode = tr("Co-op")
			"shared":
				mode = tr("Competitive Shared")
			"region":
				mode = tr("Competitive Region")
		lines.append(tr("Multiplayer") + (" · " + mode if not mode.is_empty() else ""))
	else:
		lines.append(tr("Single-player city"))
	lines.append(tr("Terrain: %d × %d tiles") % [info.map_size, info.map_size])
	if info.has("year"):
		lines.append(tr("Year: %d") % info.year)
	if info.has("population"):
		lines.append(tr("Population: %s") % DisplayNumberFormat.format(info.population))
	if info.has("funds"):
		lines.append(tr("City funds: %s") % ("$" + DisplayNumberFormat.format(info.funds)))
	if info.has("bank_debt"):
		lines.append(tr("Bank debt: %s") % ("$" + DisplayNumberFormat.format(info.bank_debt)))
	if info.has("players"):
		lines.append(tr("Saved players: %d") % info.players)
	if info.get("separate_finances", false):
		lines.append(tr("Player finances are not shown in this preview."))
	preview_details.text = "\n".join(lines)


func image_for_path(path: String) -> Image:
	return displayed_image if displayed_path == path else null


static func _is_city(path: String) -> bool:
	return path.get_extension().to_lower() in ["sc2", "sc2x", "scn"] and FileAccess.file_exists(path)


func _exit_tree() -> void:
	if job != null:
		job.cancel()
		job.join()
