class_name QolDialog
extends Window
## Shared framing for utility windows, using the application's live theme.

var column: VBoxContainer


func _init() -> void:
	visible = false
	wrap_controls = true
	min_size = Vector2i(440, 260)
	size = Vector2i(600, 400)
	theme = AppUiTheme.current()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme_type_variation = "UtilityPanel"
	add_child(panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	close_requested.connect(hide)


func label(text: String, role := "") -> Label:
	var result := Label.new()
	result.text = text
	result.theme_type_variation = role
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size.x = 360
	column.add_child(result)
	return result


func row() -> HBoxContainer:
	var result := HBoxContainer.new()
	column.add_child(result)
	return result


func button(parent: Control, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result
