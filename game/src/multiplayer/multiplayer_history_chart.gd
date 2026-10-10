class_name MultiplayerHistoryChart
extends Control
## Shared axes and player colours; missing history is never fabricated as zero.

var series: Dictionary = {}
var players: Array = []
var metric := "population"
var points: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void: tooltip_text = "")

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var closest := 144.0
	tooltip_text = ""
	for point: Dictionary in points:
		var distance: float = event.position.distance_squared_to(point.position)
		if distance < closest:
			closest = distance
			tooltip_text = point.text

func _draw() -> void:
	points.clear()
	var font := get_theme_default_font()
	var ink := get_theme_color("font_color", "Label")
	var area := Rect2(90, 18, maxf(1, size.x - 108), maxf(1, size.y - 65))
	var low := 0.0
	var high := 1.0
	var first := 2147483647
	var last := 0
	for row: Dictionary in players:
		for sample: Dictionary in series.get(row.id, []):
			first = mini(first, int(sample.month))
			last = maxi(last, int(sample.month))
			low = minf(low, float(sample.get(metric, 0)))
			high = maxf(high, float(sample.get(metric, 0)))
	if first > last:
		draw_string(font, Vector2(15, 35), tr("History begins when the game starts; a new sample is recorded each month."), HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 14, ink)
		return
	for index in 5:
		var fraction := index / 4.0
		var y := area.end.y - fraction * area.size.y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(ink, 0.15))
		var value := int(lerpf(low, high, fraction))
		var label := MultiplayerScoreboard.money(value) if metric in ["funds", "debt", "balance"] else MultiplayerScoreboard.number(value)
		draw_string(font, Vector2(0, y + 5), label, HORIZONTAL_ALIGNMENT_RIGHT, 82, 12, ink)
	for row: Dictionary in players:
		var color := Color(CoopSession.valid_color(row.get("color"))) if row.get("ranked", true) else Color(0.6, 0.6, 0.6)
		var line := PackedVector2Array()
		for sample: Dictionary in series.get(row.id, []):
			var value := int(sample.get(metric, 0))
			var point := Vector2(area.position.x + (int(sample.month) - first) * area.size.x / maxi(1, last - first), area.end.y - (value - low) * area.size.y / (high - low))
			line.append(point)
			var date := "%d/%d" % [int(sample.month) % 12 + 1, int(sample.year) + int(sample.month) / 12]
			points.append({"position": point, "text": "%s · %s · %s: %s" % [row.name, date, tr(MultiplayerScoreboard.COLUMNS[metric]), MultiplayerScoreboard.number(value)]})
		if line.size() > 1:
			draw_polyline(line, color, 2.0, true)
		elif line.size() == 1:
			draw_circle(line[0], 3, color)
	for month: int in [first, last]:
		var x := area.position.x + (month - first) * area.size.x / maxi(1, last - first)
		draw_string(font, Vector2(clampf(x - 35, 0, size.x - 80), area.end.y + 23), tr("Month %d") % (month + 1), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, ink)
