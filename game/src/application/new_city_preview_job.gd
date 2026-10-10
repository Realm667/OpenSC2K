class_name NewCityPreviewJob
extends RefCounted

# the worker owns its document, random state, images, and rendering cache
var session := NewCityTerrainSession.new()
var thread := Thread.new()
var revision := 0
var view_size := CityIsometricRenderer.VIEW_SMALL
# the preview shrinks to fit this size. a large map is too big for one image
var maximum_size := Vector2i.ZERO
var visual_options: Dictionary = {}
var visual_sprites: Sc2SpriteArchive
var visual_image: Image


func start(
	source: NewCityTerrainSession,
	options: NewCityTerrain.Options,
	palette: Sc2Palette,
	sprites: Sc2SpriteArchive,
	advance_seed: bool,
) -> Error:
	session.begin(
		source.preview_process_cursor if advance_seed else source.preview_process_start,
		source.preview_game_cursor if advance_seed else source.preview_game_start,
	)

	visual_sprites = MainMenuPresentation.copy_graphics(sprites)
	if not visual_options.is_empty():
		CityNatureArtwork.prepare(visual_sprites, palette)
		visual_sprites.visual_seasons.merge(visual_sprites.visual_nature_masks)
		visual_sprites.visual_nature_enabled = true
		visual_sprites.visual_terrain_enabled = true
		visual_sprites.water_reflections = true
		visual_sprites.water_indices = CityWaterLayer.blue_indices(palette)
	return thread.start(_generate.bind(options.copy(), palette, visual_sprites))


func _generate(
	options: NewCityTerrain.Options,
	palette: Sc2Palette,
	sprites: Sc2SpriteArchive,
) -> NewCityTerrainSession.PreviewResult:
	var result := session.generate_preview(options, true)

	if not result.ok:
		return result

	var size := CityIsometricRenderer.output_size_for_view(view_size, result.city.map_size)
	result.landscape_artwork = (not sprites.high_resolution.is_empty()
		and (maximum_size == Vector2i.ZERO or (size.x <= maximum_size.x and size.y <= maximum_size.y)))
	var encoded := not visual_options.is_empty()
	var rendered := CityIsometricRenderer.create_image(result.city,
		Sc2Palette.index_encoding() if encoded else palette, sprites, view_size, 0, false, encoded, false, false,
		Callable(), maximum_size, 0 if encoded else (1 if result.landscape_artwork else 0))
	if rendered.ok and encoded:
		visual_image = rendered.image
		if result.landscape_artwork:
			rendered = CityIsometricRenderer.create_image(result.city, palette, sprites, view_size, 0, false, true, false, false,
				Callable(), maximum_size, 1)

	if not rendered.ok:
		return NewCityTerrainSession.PreviewResult.failure(rendered.error, "preview")

	result.landscape_image = rendered.image
	result.minimap_image = CityMinimap.create_image(result.city, palette, "structures")

	return result


static func preview_view_size(edge: int, target: Vector2) -> int:
	# never enlarge the small sprite set when a more detailed native set fits
	for view in [CityIsometricRenderer.VIEW_SMALL, CityIsometricRenderer.VIEW_MEDIUM]:
		var extent := Vector2(CityIsometricRenderer.output_size_for_view(view, edge))

		if extent.x >= target.x * 2.0 and extent.y >= target.y * 2.0:
			return view

	return CityIsometricRenderer.VIEW_LARGE


# keep twice the dialog size, as `preview_view_size` does
static func preview_maximum_size(target: Vector2) -> Vector2i:
	return Vector2i((target * 2.0).ceil())
