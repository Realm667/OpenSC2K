extends SceneTree
## Optional thumbnails must not change the city, dirty state, or original formats.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AppPaths._root = OS.get_temp_dir().path_join("city-preview-test-%d" % OS.get_process_id())
	var preview := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	preview.fill(Color.CORNFLOWER_BLUE)
	var png := preview.save_png_to_buffer()
	assert(CityPreviewStore.decode(png).get_data() == preview.get_data())
	assert(CityPreviewStore.decode(PackedByteArray([1, 2, 3])) == null)
	var oversized := png.duplicate()
	oversized[16] = 1
	assert(CityPreviewStore.decode(oversized) == null)
	var source := Sc2xDocument.create_empty(16, "Preview test").document
	source.sc2x_extra_entries["custom.dat"] = PackedByteArray([12, 34])
	var snapshot := source.content_snapshot()
	source.sc2x_extra_entries[CityPreviewStore.ENTRY] = png
	assert(source.content_snapshot() == snapshot, "Presentation must not mark the city dirty")
	var output := OS.get_temp_dir().path_join("preview-%d.sc2x" % OS.get_process_id())
	var prepared := CityFileStore.prepare(source, output, "")
	assert(prepared.ok, prepared.error)
	assert(not prepared.entries.members.has(CityPreviewStore.ENTRY), "Autosave drops stale preview")
	assert(prepared.entries.members["custom.dat"] == PackedByteArray([12, 34]))
	CityFileStore.attach_preview(prepared, preview)
	assert(prepared.entries.members.has(CityPreviewStore.ENTRY))
	assert(CityFileStore.write(prepared).ok)
	assert(CityPreviewStore.embedded(output).get_data() == preview.get_data())
	var loaded := Sc2File.load_path(output)
	assert(loaded.is_valid() and loaded.content_snapshot() == prepared.snapshot)
	assert(loaded.sc2x_extra_entries["custom.dat"] == PackedByteArray([12, 34]))
	var reader := CityPreviewJob.new()
	reader.path = output
	reader.run()
	assert(reader.saved_preview and reader.image != null, "Embedded image needs no graphics pack")
	CityFileStore.attach_preview(prepared, null)
	assert(CityFileStore.write(prepared).ok)
	assert(CityPreviewStore.embedded(output) == null)
	source.sc2x_extra_entries[CityPreviewStore.ENTRY] = PackedByteArray([1, 2, 3])
	assert(CityFileStore.write_verified(output, source.serialize().data).ok)
	assert(CityPreviewStore.embedded(output) == null and Sc2File.load_path(output).is_valid(),
		"An invalid preview must not invalidate the city")
	DirAccess.remove_absolute(output)
	var original := EmptyCityTemplate.create()
	var original_bytes := original.serialize().data
	var legacy_path := output.get_basename() + "-legacy.sc2x"
	var legacy := CityFileStore.prepare(original, legacy_path, "")
	assert(legacy.ok and legacy.entries == null)
	CityFileStore.attach_preview(legacy, preview)
	assert(CityFileStore.write(legacy).ok)
	assert(CityPreviewStore.embedded(legacy_path) == null)
	assert(Sc2File.load_path(legacy_path).serialize().data == original_bytes)
	DirAccess.remove_absolute(legacy_path)
	prepared = CityFileStore.prepare(original, output.get_basename() + ".sc2", "")
	CityFileStore.attach_preview(prepared, preview)
	assert(prepared.entries == null and prepared.bytes == original_bytes)
	CityPreviewStore.store("original-digest", "graphics-a", preview)
	assert(CityPreviewStore.cached("original-digest", "graphics-a") != null)
	assert(CityPreviewStore.cached("changed-digest", "graphics-a") == null)
	assert(CityPreviewStore.cached("original-digest", "graphics-b") == null)
	DirAccess.remove_absolute(CityPreviewStore.cache_path("original-digest", "graphics-a"))
	var assets := LoadedAssetState.new()
	assets.palette = FixtureGraphics.pack().palette
	assets.large_sprites = MainMenuPresentation.copy_graphics(FixtureGraphics.pack().large_sprites)
	var job := CityPreviewJob.for_assets(assets)
	job.document = Sc2File.load_path("res://tests/fixtures/cities/generated-128.SC2")
	var before := job.document.serialize().data
	var started := Time.get_ticks_msec()
	job.start()
	while not job.finished():
		await process_frame
	job.join()
	assert(job.image != null)
	assert(job.image.get_width() <= 768 and job.image.get_height() <= 512)
	assert(job.image.get_used_rect().size.x > 0)
	assert(job.document.serialize().data == before, "Rendering must not alter city/RNG bytes")
	var same := CityPreviewJob.for_assets(assets)
	same.prepare_graphics_key()
	assert(same.graphics_key == job.graphics_key)
	print("PREVIEW 128: ", Time.get_ticks_msec() - started, " ms; ", job.image.get_size())
	var large := CityPreviewJob.for_assets(assets)
	large.document = EmptyCityTemplate.create(512)
	started = Time.get_ticks_msec()
	large.start()
	while not large.finished():
		await process_frame
	large.join()
	assert(large.image != null and large.image.get_width() <= 768 and large.image.get_height() <= 512)
	print("PREVIEW 512: ", Time.get_ticks_msec() - started, " ms; ", large.image.get_size())
	assets.large_sprites.visual_nature_enabled = not assets.large_sprites.visual_nature_enabled
	var changed := CityPreviewJob.for_assets(assets)
	changed.prepare_graphics_key()
	assert(changed.graphics_key != same.graphics_key, "Changed nature artwork invalidates cached preview")
	var cancelled := CityPreviewJob.for_assets(assets)
	cancelled.document = original
	cancelled.cancel()
	cancelled.run()
	assert(cancelled.image == null)
	var dialog := FileDialogFactory.city_open()
	root.gui_embed_subwindows = true
	root.add_child(dialog)
	var memory := WindowLayoutMemory.new()
	root.add_child(memory)
	await process_frame
	assert(dialog is CityOpenDialog and dialog.preview_panel != null)
	dialog.popup_centered_ratio(0.8)
	for extent in [Vector2i(900, 560), Vector2i(1100, 700), Vector2i(780, 520)]:
		dialog.size = extent
		dialog.preview_image.texture = ImageTexture.create_from_image(job.image)
		dialog.preview_status.text = "Preview unavailable. You can still open this city."
		for frame in 8:
			memory._process(0.25)
			await process_frame
		var settled := Rect2i(dialog.position, dialog.size)
		var minimum := dialog.get_contents_minimum_size()
		for frame in 20:
			memory._process(0.25)
			await process_frame
			assert(Rect2i(dialog.position, dialog.size) == settled, "City chooser must settle after resizing")
			assert(dialog.get_contents_minimum_size() == minimum, "Preview must not feed a new minimum back into the window")
	dialog.hide()
	dialog.queue_free()
	memory.queue_free()
	await process_frame
	print("PASS: bounded city previews, optional SC2X thumbnail, unchanged original saves, cache invalidation and cancellation")
	quit()
