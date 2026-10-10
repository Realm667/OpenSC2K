class_name MultiplayerRegionCard
extends Button
## A selectable region tile, using only actual city-seat statistics.
var player: Dictionary = {}
var region := 0

func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	text = "%s · %s\n%s\n%s: %s · %s" % [tr("Region %d") % region, player.city, player.name, tr("Population"), str(player.get("population", 0)), MultiplayerSeatWindow.status(player.get("seat_status", "reserved"))]
	var color := Color.from_string(player.get("color", "46b4ff"), Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.2 if state == "normal" else 0.35)
		style.border_color = color
		style.set_border_width_all(2)
		style.content_margin_left = 12
		style.content_margin_right = 12
		add_theme_stylebox_override(state, style)
