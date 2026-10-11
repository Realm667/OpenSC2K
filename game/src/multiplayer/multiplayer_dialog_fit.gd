class_name MultiplayerDialogFit
extends Node
## Fit the contents plus real themed chrome, after container layout settles.

var window: Window
var body: Control
var preferred_width := 680
var pending := 3

static func bind(target: Window, content: Control, width := 680) -> MultiplayerDialogFit:
	var fitter := MultiplayerDialogFit.new()
	fitter.window = target
	fitter.body = content
	fitter.preferred_width = width
	target.add_child(fitter)
	target.set_meta("multiplayer_fit", fitter)
	content.minimum_size_changed.connect(fitter.schedule)
	content.theme_changed.connect(fitter.schedule)
	target.visibility_changed.connect(fitter.schedule)
	target.get_parent().get_viewport().size_changed.connect(fitter.schedule)
	return fitter

func schedule() -> void:
	pending = 3

func _process(_delta: float) -> void:
	if pending <= 0 or not window.visible:
		return
	pending -= 1
	var available := window.get_parent().get_viewport().get_visible_rect().size
	var chrome := Vector2.ZERO
	var ancestor := body.get_parent()
	while ancestor != window:
		if ancestor is PanelContainer:
			chrome += ancestor.get_theme_stylebox("panel").get_minimum_size()
		elif ancestor is MarginContainer:
			chrome += Vector2(ancestor.get_theme_constant("margin_left") + ancestor.get_theme_constant("margin_right"), ancestor.get_theme_constant("margin_top") + ancestor.get_theme_constant("margin_bottom"))
		ancestor = ancestor.get_parent()
	var scale_factor := window.content_scale_factor
	window.min_size = Vector2i(mini(420, int(available.x) - 40), 100)
	var desired := Vector2i(mini(preferred_width, int(available.x) - 40), mini(ceili((body.get_combined_minimum_size().y + chrome.y) * scale_factor) + 2, int(available.y) - 70))
	# Rounded content measurements can alternate by a pixel as scrollbars settle.
	if absi(window.size.x - desired.x) > 1 or absi(window.size.y - desired.y) > 2:
		window.size = desired
	if window.get_meta("center_after_fit", false):
		window.position = Vector2i((available - Vector2(window.size)) * 0.5)
	# A newly enlarged dialog must also stay within the viewport.
	window.position = Vector2i(clampi(window.position.x, 20, maxi(20, int(available.x) - window.size.x - 20)), clampi(window.position.y, 36, maxi(36, int(available.y) - window.size.y - 34)))
