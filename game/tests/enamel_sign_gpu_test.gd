extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map := CityMapControl.new()
	root.add_child(map)
	var entries: Array[CityMapSigns.Entry] = []
	for label in ["Yestonia 7", "München – 서울", "A long connection name", "Yestonia 7"]:
		var entry := CityMapSigns.Entry.new()
		entry.label = label
		entries.append(entry)
	var atlas := map.signs.atlas
	var original_size := Vector2i.ZERO
	for density in [1, 2, 1]:
		map.signs.set_high_resolution(density == 2)
		atlas.prepare(map, entries, 2, density, map.signs._get_sign_font())
		for frame in 3:
			await RenderingServer.frame_post_draw
		assert(atlas.slots.size() == 3, "Repeated labels share one rasterized sign")
		var slot: CitySignAtlas.Slot = atlas.slots["Yestonia 7"]
		var pixels := atlas.pages[slot.page].get_texture().get_image().get_region(slot.region)
		assert(not pixels.is_invisible(), "The complete sign must reach the GPU atlas")
		if density == 1:
			original_size = pixels.get_size()
		else:
			assert(pixels.get_size() == original_size * 2, "HD increases density without changing placement")
		for y in pixels.get_height():
			for x in pixels.get_width():
				var color := pixels.get_pixel(x, y)
				if x == 0 or y == 0 or x == pixels.get_width() - 1 or y == pixels.get_height() - 1:
					assert(color.a == 0.0, "The sheared board and post must not touch the cell boundary")
				if density == 1:
					assert(color.a == 0.0 or color.a == 1.0, "SC2000 signs retain a hard pixel grid")
				assert(color.r < 0.8 or color.a == 0.0, "Lettering must not be baked into the pixelated board")
		var count := atlas.build_count
		var page := atlas.pages[0]
		atlas.prepare(map, entries, 2, density, map.signs._get_sign_font())
		assert(atlas.build_count == count and atlas.pages[0] == page, "Scrolling reuses rendered pages")
		page.get_child(0).modulate = Color.RED
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		assert(page.get_texture().get_image().get_region(slot.region).get_data() == pixels.get_data(),
			"Prepared pages must not render again every frame")
		var text_view := SubViewport.new()
		text_view.size = Vector2i(600, 400)
		text_view.transparent_bg = true
		text_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		root.add_child(text_view)
		var text := Lettering.new()
		text.signs = map.signs
		text.entry = entries[0]
		text.slot = slot
		text_view.add_child(text)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var lettering := text_view.get_texture().get_image()
		var smooth_pixels := 0
		for y in lettering.get_height():
			for x in lettering.get_width():
				var alpha := lettering.get_pixel(x, y).a
				if alpha > 0.01 and alpha < 0.99:
					smooth_pixels += 1
		assert(smooth_pixels > 100, "Both packs draw smooth screen-resolution text separately from the board")
		text_view.queue_free()
	entries[0].label = "Edited name"
	atlas.prepare(map, entries, 2, 1, map.signs._get_sign_font())
	assert(atlas.slots.has("Edited name"), "Editing text refreshes its cached artwork")
	atlas.prepare(map, [], 2, 1, map.signs._get_sign_font())
	assert(atlas.pages.is_empty() and atlas.slots.is_empty(), "A city without signs releases atlas pages")
	map.queue_free()
	await process_frame
	print("PASS: enamel boards retain bounds and GPU pages; lettering uses independent screen resolution")
	quit()


class Lettering extends Node2D:
	var signs: CityMapSigns
	var entry: CityMapSigns.Entry
	var slot: CitySignAtlas.Slot


	func _draw() -> void:
		signs.draw_text(self, entry, slot, Vector2(200, 350), 4.0, 2)
