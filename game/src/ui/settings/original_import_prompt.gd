class_name OriginalImportPrompt
extends ConfirmationDialog
## One shared decision before the existing importer. No selects no new sources.

signal import_chosen(activate: bool)


func _ready() -> void:
	theme = AppUiTheme.current()
	title = "Import original assets"
	dialog_text = "Would you like to import SimCity 2000 data?"
	dialog_autowrap = true
	exclusive = true
	ok_button_text = "Yes, and activate"
	cancel_button_text = "No"
	add_button("Yes", false, "import")
	confirmed.connect(func() -> void: import_chosen.emit(true))
	custom_action.connect(func(action: StringName) -> void:
		if action == &"import":
			hide()
			import_chosen.emit(false))


static func first_start(settings_path: String, data_root: String) -> bool:
	# An old profile must never be treated as a first start, even if it predates
	# the marker. Existing imported packs also identify a previous installation.
	if FileAccess.file_exists(settings_path):
		return false
	for path in ["packs", "pack/sc2000"]:
		var folder := data_root.path_join(path)
		if DirAccess.dir_exists_absolute(folder) and not DirAccess.get_directories_at(folder).is_empty():
			return false
	return true


static func remember(settings_path: String) -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("data", "import_prompt_seen", true)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	return config.save(settings_path)
