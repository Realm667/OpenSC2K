class_name CitySignAtlas
extends RefCounted
## Rasterize enamel boards once. Lettering is drawn at screen resolution.
## Pages update only when labels, native view size, or artwork density change.

const PAGE_SIZE := 1024
var pages: Array[SubViewport] = []
var slots: Dictionary = {}
var signature: Array = []
var build_count := 0


func prepare(parent: Node, entries: Array[CityMapSigns.Entry], view: int, density: int, font: Font) -> void:
	var labels: Array[String] = []
	for entry in entries:
		if not labels.has(entry.label):
			labels.append(entry.label)
	labels.sort()
	var next_signature := [view, density, labels]
	if signature == next_signature:
		return
	signature = next_signature
	build_count += 1
	for page in pages:
		page.queue_free()
	pages.clear()
	slots.clear()
	var painter: Painter
	var cursor := Vector2i.ZERO
	var row_height := 0
	for label in labels:
		var font_size := maxi(1, roundi(CityMapSigns._em_size(font, CityMapSigns.ENAMEL_FONT_HEIGHTS[view])))
		var width := ceilf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var layout := CityMapSigns.sign_layout(Vector2.ZERO, width, view)
		var bounds := layout.bounds()
		var cell_size := Vector2i(ceilf(bounds.size.x), ceilf(bounds.size.y)) * density
		if cursor.x + cell_size.x > PAGE_SIZE:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		if painter == null or cursor.y + cell_size.y > PAGE_SIZE:
			var page := SubViewport.new()
			page.disable_3d = true
			page.transparent_bg = true
			page.size = Vector2i(maxi(PAGE_SIZE, cell_size.x), maxi(PAGE_SIZE, cell_size.y))
			page.render_target_update_mode = SubViewport.UPDATE_ONCE
			page.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			parent.add_child(page)
			pages.append(page)
			painter = Painter.new()
			painter.density = density
			page.add_child(painter)
			cursor = Vector2i.ZERO
			row_height = 0
		var slot := Slot.new()
		slot.page = pages.size() - 1
		slot.region = Rect2i(cursor, cell_size)
		slot.bounds = bounds
		slot.face = layout.face
		slot.text_width = width
		slots[label] = slot
		painter.cells.append({"label": label, "layout": layout, "origin": Vector2(cursor) / density - bounds.position})
		painter.queue_redraw()
		cursor.x += cell_size.x
		row_height = maxi(row_height, cell_size.y)
	# Keep only the used part of each page, including the transparent gutters.
	for index in pages.size():
		var used := Vector2i(2, 2)
		for slot: Slot in slots.values():
			if slot.page == index:
				used = used.max(slot.region.end)
		pages[index].size = used


class Slot extends RefCounted:
	var page: int
	var region: Rect2i
	var bounds: Rect2
	var face: Transform2D
	var text_width: float


class Painter extends Node2D:
	var cells: Array[Dictionary] = []
	var density: int


	func _draw() -> void:
		for cell in cells:
			var layout: CityMapSigns.Layout = cell.layout
			var origin: Vector2 = cell.origin
			draw_set_transform(origin * density, 0.0, Vector2.ONE * density)
			draw_rect(layout.post, Color("4a5850"))
			draw_rect(Rect2(layout.post.position, Vector2(0.5, layout.post.size.y)), Color("889180"))
			var p := layout.face.origin
			var w := layout.face_size.x
			var h := layout.face_size.y
			var right := p + Vector2(w, w * 0.5)
			draw_colored_polygon(PackedVector2Array([p, right, right + Vector2(2, -1), p + Vector2(2, -1)]), Color("78887c"))
			draw_colored_polygon(PackedVector2Array([right, right + Vector2(2, -1), right + Vector2(2, h - 1), right + Vector2(0, h)]), Color("3c4944"))
			var transform := layout.face
			transform.origin += origin
			draw_set_transform_matrix(transform.scaled(Vector2.ONE * density))
			draw_rect(Rect2(Vector2.ZERO, layout.face_size), Color("35463f"))
			draw_rect(Rect2(Vector2.ONE, layout.face_size - Vector2.ONE * 2), Color("536e61"))
			draw_rect(Rect2(1, 1, w - 2, 0.5), Color("778d7e"))
			draw_rect(Rect2(2, h * 0.5, 0.75, 0.75), Color("a9b1a0"))
			draw_rect(Rect2(w - 3, h * 0.5, 0.75, 0.75), Color("a9b1a0"))
		draw_set_transform_matrix(Transform2D.IDENTITY)
