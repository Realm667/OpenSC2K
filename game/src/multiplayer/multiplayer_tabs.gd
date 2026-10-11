class_name MultiplayerTabs
extends HFlowContainer
## Wrapping tabs keep every statistics view reachable without horizontal scrolling.

signal item_selected(index: int)
var selected := 0
var buttons: Array[Button] = []
var group := ButtonGroup.new()

func add_item(title: String) -> void:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.button_group = group
	var index := buttons.size()
	buttons.append(button)
	add_child(button)
	button.set_pressed_no_signal(index == selected)
	button.pressed.connect(func() -> void:
		select(index)
		item_selected.emit(index))

func select(index: int) -> void:
	if index < 0 or index >= buttons.size():
		return
	selected = index
	for item in buttons.size():
		buttons[item].set_pressed_no_signal(item == index)
