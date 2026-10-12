class_name ApplicationQualityOfLife
extends Node

const MENU_LAYOUTS := CityMenuBar.MENU_WORKSPACES
const MENU_MUSIC_BOX := CityMenuBar.MENU_MUSIC_BOX
const WORKSPACES := ["Building", "Finances", "City analysis"]

var app: CityApplication
var memory: WindowLayoutMemory
var layouts: QolDialog
var workspace_choice: OptionButton
var layout_status: Label
var music_box: MusicBoxDialog
var report_windows: Dictionary[int, Window] = {}


func _init(application: CityApplication) -> void:
	app = application


func _ready() -> void:
	memory = WindowLayoutMemory.new()
	memory.storage_path = app.preferences.settings_path + ".layouts.cfg"
	memory.save_failed.connect(app.interface.show_error)
	# Observe the whole application, including windows added later.
	app.add_child(memory)
	report_windows = {0: app.city_dialogs.budget_dialog, 1: app.city_dialogs.ordinance_window,
		2: app.city_dialogs.population_window, 3: app.city_dialogs.industry_window,
		4: app.city_dialogs.graph_window, 5: app.city_dialogs.simnation_window, 6: app.city_dialogs.city_map_window}
	app.city_menu_bar.windows_menu_requested.connect(_menu)
	_build_layout_dialog()
	music_box = MusicBoxDialog.new(app)
	app.add_child(music_box)


func _menu(id: int) -> void:
	if id == MENU_LAYOUTS:
		layouts.popup_centered(Vector2i(500, 290))
	elif id == MENU_MUSIC_BOX:
		music_box.open()


func _build_layout_dialog() -> void:
	layouts = QolDialog.new()
	layouts.title = "Workspaces"
	layouts.label("Window positions are remembered automatically.", "HelpLabel")
	layouts.label("Arrange your city windows, then save their positions and visibility in a workspace.")
	workspace_choice = OptionButton.new()
	for name in WORKSPACES:
		workspace_choice.add_item(name)
	layouts.column.add_child(workspace_choice)
	var actions := layouts.row()
	layouts.button(actions, "Save workspace", _save_layout)
	layouts.button(actions, "Restore workspace", _restore_layout)
	layouts.button(layouts.row(), "Reset window positions", memory.reset_positions)
	layout_status = layouts.label("", "HelpLabel")
	app.add_child(layouts)


func _save_layout() -> void:
	var visible_ids: Array[int] = []
	for id in report_windows:
		if report_windows[id].visible:
			visible_ids.append(id)
	if memory.save_workspace(WORKSPACES[workspace_choice.selected], memory.capture(), visible_ids):
		layout_status.text = tr("Workspace saved.")


func _restore_layout() -> void:
	var saved: Variant = memory.config.get_value("workspaces", WORKSPACES[workspace_choice.selected], {})
	if not saved is Dictionary or not saved.get("geometry", {}) is Dictionary or not saved.get("visible", []) is Array:
		return
	if saved.is_empty():
		layout_status.text = tr("Save this workspace first.")
		return
	if app.document_state.city == null:
		layout_status.text = tr("Load a city before restoring a workspace.")
		return
	if app.city_dialogs.blocks_simulation():
		layout_status.text = tr("Close the current dialog before restoring a workspace.")
		return
	# Use normal open actions so report data is refreshed and budget rules stay intact.
	for id in report_windows:
		if id in saved.visible:
			app.reports.on_windows_menu(id)
		elif id != 0:
			report_windows[id].hide()
	memory.apply_geometry.call_deferred(saved.geometry)
	layout_status.text = tr("Workspace restored.")
