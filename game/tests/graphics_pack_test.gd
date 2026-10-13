extends SceneTree

@warning_ignore_start("integer_division")

const Fixture = preload("res://tests/indexed_png_test.gd")
const Pack = preload("res://src/assets/graphics_pack.gd")


func _initialize() -> void:
	_check_master_registration()
	var pack_root := "user://graphics-pack-test-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(pack_root) == OK)
	var png := FileAccess.open(pack_root.path_join("sprite.png"), FileAccess.WRITE)
	png.store_buffer(Fixture.FIXTURE.hex_decode())
	png.close()
	var manifest := {
		"format": "opensc2k-graphics", "version": 1, "name": "Independent test",
		"palette": "sprite.png", "scenario_palette": "sprite.png",
		"large_sprites": [{ "id": 1001, "png": "sprite.png" }, { "id": 1001, "png": "sprite.png" }],
		"small_medium_sprites": [{ "id": 1, "png": "sprite.png" }], "ui": {},
	}

	for field in Pack.UI_FIELDS:
		manifest.ui[field] = "sprite.png"

	_write_manifest(pack_root, manifest)
	var loaded := Pack.load_root(pack_root)
	assert(loaded.error.is_empty(), loaded.error)
	assert(Pack.load_root(pack_root.path_join("pack.json")).error.is_empty())
	assert(DirAccess.rename_absolute(pack_root.path_join("pack.json"), pack_root.path_join("manifest.json")) == OK)
	assert(not Pack.load_root(pack_root).error.is_empty(), "Retired manifest filename is not loaded")
	assert(DirAccess.rename_absolute(pack_root.path_join("manifest.json"), pack_root.path_join("pack.json")) == OK)
	assert(loaded.large_sprites.entries.size() == 2)
	assert(not loaded.small_medium_sprites.redraw_small_highway_ground)
	manifest.redraw_small_highway_ground = true
	_write_manifest(pack_root, manifest)
	var with_ground := Pack.load_root(pack_root)
	assert(with_ground.error.is_empty() and with_ground.small_medium_sprites.redraw_small_highway_ground)
	assert(Sc2SpriteArchive.combine([loaded.large_sprites, with_ground.small_medium_sprites]).redraw_small_highway_ground)
	var parsed := Sc2SpriteArchive.new()
	parsed.redraw_small_highway_ground = true
	assert(parsed.parse(PackedByteArray([0, 0])))
	assert(not parsed.redraw_small_highway_ground)
	manifest.redraw_small_highway_ground = 1
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.erase("redraw_small_highway_ground")
	var sprite: Sc2SpriteArchive.SpriteEntry = loaded.large_sprites.find_sprite(1001)
	assert(sprite.duplicate_index == 1)
	assert(sprite.decode_indices().pixels == PackedInt32Array([-1, 1, 171, 172]))
	var indices := sprite.create_image(Sc2Palette.index_encoding())
	assert(indices.image.get_pixel(2, 0).r8 == 171)
	assert(indices.image.get_pixel(0, 0).a8 == 0)
	var returned: PackedInt32Array = sprite.decode_indices().pixels
	returned[1] = 9
	assert(sprite.decode_indices().pixels[1] == 1)
	var other := Sc2SpriteArchive.entry_from_indices(1001, 4, 1, returned)
	assert(sprite.pixel_hash() != other.pixel_hash())
	assert(Sc2SpriteArchive.entry_from_indices(1, 2, 1, PackedInt32Array([256, 0])) == null)
	assert(loaded.ui_images.toolbar_art.get_pixel(2, 0) == Color8(40, 80, 120))
	var assets := OriginalGameAssets.new()
	assert(loaded.apply_to(assets))
	assert(assets.large_sprites == loaded.large_sprites)
	_write_manifest(pack_root, manifest)
	var standalone := GameAssetSource.load_source("", "folder", pack_root)
	assert(standalone.error.is_empty(), standalone.error)
	assert(standalone.assets.large_sprites.find_sprite(1001).decode_indices().pixels == sprite.decode_indices().pixels)

	for bad_path in ["../sprite.png", "/sprite.png", "res://sprite.png", "a\\sprite.png", "./sprite.png"]:
		manifest.palette = bad_path
		_write_manifest(pack_root, manifest)
		var bad := Pack.load_root(pack_root)
		assert(not bad.error.is_empty())
		assert(not bad.apply_to(assets))
		assert(assets.large_sprites == loaded.large_sprites)

	manifest.palette = "missing.png"
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.palette = "sprite.png"
	manifest.large_sprites[0].id = 1.5
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.large_sprites[0].id = 1001
	manifest.ui.erase("toolbar_art")
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.partial = true
	manifest.erase("scenario_palette")
	manifest.small_medium_sprites = []
	_write_manifest(pack_root, manifest)
	var partial := Pack.load_root(pack_root)
	assert(partial.error.is_empty(), partial.error)
	assert(not GameAssetSource.load_source("", "folder", pack_root).error.is_empty(),
		"One sprite size group cannot activate without a base")
	var kept_small := assets.small_medium_sprites
	var kept_scenario := assets.scenario_palette
	var kept_toolbar := assets.toolbar_art
	assert(partial.apply_to(assets))
	assert(assets.small_medium_sprites == kept_small and assets.scenario_palette == kept_scenario and assets.toolbar_art == kept_toolbar)
	# Reject an incompatible palette before changing any active assets.
	var different := Sc2Palette.index_encoding()
	assets.palette = different
	var kept_large := assets.large_sprites
	assert(not Pack.load_root(pack_root).apply_to(assets))
	assert(assets.palette == different and assets.large_sprites == kept_large)
	manifest.large_sprites = []
	_write_manifest(pack_root, manifest)
	assert(not GameAssetSource.load_source("", "folder", pack_root).error.is_empty(), "UI-only packs cannot supply a city on first run")
	assert(Pack.load_root(pack_root).apply_to(assets))
	assert(assets.palette == different and assets.large_sprites == kept_large)
	manifest.ui = {}
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty(), "Empty partial packs are invalid")
	DirAccess.remove_absolute(pack_root.path_join("sprite.png"))
	DirAccess.remove_absolute(pack_root.path_join("pack.json"))
	DirAccess.remove_absolute(pack_root)
	print("PASS: graphics pack loading, duplicate IDs, indexed rendering, UI, invalid packs")
	quit()


func _write_manifest(pack_root: String, manifest: Dictionary) -> void:
	var file := FileAccess.open(pack_root.path_join("pack.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()


func _check_master_registration() -> void:
	var palette := Sc2Palette.index_encoding()
	var decoded := IndexedImageResult.new()
	decoded.ok = true
	decoded.width = 160
	decoded.height = 96
	decoded.palette = palette
	decoded.pixels.resize(160 * 96)
	decoded.pixels.fill(1)
	var reader := func(_path: Variant) -> IndexedImageResult: return decoded
	var translucent := Image.create(160, 96, false, Image.FORMAT_RGBA8)
	translucent.fill(Color(0.2, 0.5, 0.8, 0.65))
	var rgba_reader := func(_path: Variant) -> Image: return translucent
	var record := {"id": 1112, "png": "master.png", "logical_size": [40, 24],
		"visual_registration": [32, 4, 4], "artwork_rgba": "full.png"}
	var master := MasterSpriteSource.new()
	assert(master.load_records([record], reader, palette, rgba_reader), master.error)
	var context := CityGpuBuildContext.new()
	var city := CityState.from_document(EmptyCityTemplate.create(64))
	assert(context.prepare(city, palette, master.large, 2).is_empty(), "Native bridge must accept typed pack registration")
	assert(IsometricGeometry.maximum_sprite_size(master.large) == Vector2i(56, 24), "Bounds must include added bottom padding")
	for view in 3:
		var divisor := 4 >> view
		var archive: Sc2SpriteArchive = master.large if view == 2 else master.small_medium
		var id := view * 500 + 112
		assert(archive.visual_registration[id] == Vector3i(32 / divisor, 4 / divisor, 4 / divisor))
		assert(archive.high_resolution[id].image.get_pixel(80, 48).a8 == translucent.get_pixel(80, 48).a8)
	var classic := Sc2SpriteArchive.new()
	classic.entries.append(master.large.find_sprite(1112))
	classic.entries_by_id[1112] = classic.entries[0]
	assert(Sc2SpriteArchive.combine([master.large, classic]).visual_registration.is_empty(), "replacement pack leaked old registration")
	assert(Sc2SpriteArchive.combine([classic, master.large]).visual_registration[1112] == Vector3i(32, 4, 4))
	assert(classic.visual_registration.is_empty(), "combining packs mutated the original archive")
	for invalid in [[31, 4, 4], [32, -4, 4], [32, 12, 4], [32, 4, 24], [32, 4.5, 4], [32, 4]]:
		var bad := record.duplicate(true)
		bad.visual_registration = invalid
		assert(not MasterSpriteSource.new().load_records([bad], reader, palette, rgba_reader))
	var network := record.duplicate(true)
	network.id = 1029
	assert(not MasterSpriteSource.new().load_records([network], reader, palette, rgba_reader))
	assert(not MasterSpriteSource.new().load_records([record], reader, palette), "RGBA requires a validated reader")
	assert(master.large.parse(PackedByteArray([0, 0])))
	assert(master.large.visual_registration.is_empty(), "archive reload leaked previous pack registration")
