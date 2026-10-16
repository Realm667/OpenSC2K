extends ProgressBar
## Two clipped copies keep the percentage readable on both sides of the fill.

var unfilled_text: Label
var filled_clip: Control
var filled_text: Label


func _ready() -> void:
	add_theme_color_override("font_color", Color.TRANSPARENT)
	add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	unfilled_text = _label(self)
	filled_clip = Control.new()
	filled_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filled_clip.clip_contents = true
	add_child(filled_clip)
	filled_text = _label(filled_clip)
	queue_redraw()


func _label(parent: Node) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _draw() -> void:
	if unfilled_text == null:
		return
	unfilled_text.visible = show_percentage and not indeterminate
	filled_clip.visible = unfilled_text.visible
	var text := "%d%%" % int(ratio * 100.0)
	for label in [unfilled_text, filled_text]:
		label.text = text
		label.size = size
		label.add_theme_font_override("font", get_theme_font("font"))
		label.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	unfilled_text.add_theme_color_override("font_color", get_theme_color("font_color", "Label"))
	filled_text.add_theme_color_override("font_color", Color("1a1a1a"))
	filled_clip.size = Vector2(size.x * ratio, size.y)
