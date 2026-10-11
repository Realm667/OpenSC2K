class_name MultiplayerCursor
extends RefCounted
## Cosmetic presence only: reuse imported cursor pixels without changing the local pointer.

var source: DesktopGraphics
var cache: Dictionary = {}
var land := DesktopGraphics.Cursor.new(preload("res://assets/ui/buy_land_cursor.svg").get_image(), Vector2i(1, 1))


static func valid_tool(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("app") is String:
		return {}
	var group: Variant = value.get("group")
	if not (group is int or group is float) or not is_finite(float(group)) or float(group) != int(group):
		return {}
	var app: String = value.app
	if app == "multiplayer" and int(group) == 1:
		return {"app": app, "group": 1}
	if app != "city" or int(group) < 1000 or int(group) > 3029 or DesktopGraphics.cursor_id(app, int(group)) < 0:
		return {}
	return {"app": app, "group": int(group)}


func artwork(graphics: DesktopGraphics, value: Variant, color: Color) -> Dictionary:
	if source != graphics:
		source = graphics
		cache.clear()
	var tool := valid_tool(value)
	if tool.is_empty():
		return {}
	var key := "%s:%d:%s" % [tool.app, tool.group, color.to_html()]
	if cache.has(key):
		return cache[key]
	var record: DesktopGraphics.Cursor = land if tool.app == "multiplayer" else graphics.cursor(tool.app, tool.group) if graphics != null else null
	if record == null:
		return {}
	if cache.size() >= 256:
		cache.clear()
	cache[key] = {"texture": ImageTexture.create_from_image(tinted(record, color)), "hotspot": record.hotspot}
	return cache[key]


static func tinted(record: DesktopGraphics.Cursor, color: Color) -> Image:
	var result: Image
	if record.image != null:
		result = record.image.duplicate()
		result.convert(Image.FORMAT_RGBA8)
	else:
		result = Image.create(record.masked.width, record.masked.height, false, Image.FORMAT_RGBA8)
	var dark_only := record.image != null
	if record.image != null:
		for y in result.get_height():
			for x in result.get_width():
				var pixel := result.get_pixel(x, y)
				if pixel.a > 0 and maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.2:
					dark_only = false
	for y in result.get_height():
		for x in result.get_width():
			var pixel: Color
			if record.image != null:
				pixel = result.get_pixel(x, y)
			else:
				var at := y * record.masked.width + x
				pixel = record.masked.palette[record.masked.pixels[at]]
				# AND=1/XOR=0 is transparent; XOR artwork becomes a stable coloured mark.
				pixel.a = 0.0 if record.masked.and_mask[at] != 0 and pixel.r + pixel.g + pixel.b < 0.01 else 1.0
			var brightness := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var ink := color if dark_only else Color(0.05, 0.06, 0.07).lerp(color, brightness)
			ink.a = pixel.a
			result.set_pixel(x, y, ink)
	return result
