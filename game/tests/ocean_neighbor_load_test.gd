extends SceneTree
## Load repair belongs to the host; received display snapshots stay authoritative.


func _initialize() -> void:
	call_deferred("_run")


func _fixture() -> Sc2File:
	var document: Sc2File = Sc2xDocument.create_empty(16, "Ocean repair").document
	var city := CityState.from_document(document)
	document.set_misc_u32(Sc2MiscLayout.HAS_OCEAN, 1)
	document.set_misc_u32(Sc2MiscLayout.COMPASS, 0)
	for slot in 4:
		document.set_misc_u32(Sc2MiscLayout.NEIGHBORS + slot * 16, slot)
	for y in 16:
		city.set_tile_flag(0, y, Sc2TileFlags.SALT_WATER, true)
	return document


func _run() -> void:
	var document := _fixture()
	var before := document.content_snapshot()
	var world := CoopWorld.new()
	assert(world.open(document), world.error)
	assert(CityNeighbors.name_index(world.city, 2) == 0)
	assert(CityNeighbors.name_index(world.city, 0) == 2)
	assert(not CityNeighbors.repair_ocean_side(world.city), "Host repair is idempotent")
	assert(document.content_snapshot() == before, "Opening the host does not mutate its source")
	var app: CityApplication = load("res://main.tscn").instantiate()
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.main_menu.city_background.set_process(false)
	assert(app.city_session.activate_document(document, null, "", true))
	assert(CityNeighbors.name_index(app.document_state.city, 2) == 0)
	assert(app.document_state.saved_city_snapshot != document.content_snapshot(), "A repaired city stays unsaved")
	app.coop.session.active = true
	assert(app.city_session.activate_document(_fixture(), null, "", true))
	assert(CityNeighbors.name_index(app.document_state.city, 0) == 0, "A display load cannot rewrite host neighbors")
	app.coop.session.active = false
	var message := " Moved the Ocean neighbor to the side of the map with the ocean."
	for language in AppLocalization.codes():
		AppLocalization.select(language)
		if language != "en":
			assert(tr(message) != message, "The repair message is translated in %s" % language)
		assert(tr(message).begins_with(" "), "The appended status keeps its separator")
	AppLocalization.select("en")
	app.queue_free()
	await process_frame
	print("PASS: ocean load repair, unchanged source, dirty state, host authority and translations")
	quit()
