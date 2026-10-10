class_name NewCityPreviewPresentation
extends Control
## Detached, summer-only visual terrain. No simulation or preference mutation.
var presentation: MainMenuPresentation
var palette: Sc2Palette
var elapsed := 0.0
var cycle: ImageTexture
var palette_frame := -1

static func options(saved: Dictionary) -> Dictionary:
	var result := saved.duplicate(true)
	result.merge({"nature_forests_enabled": true, "nature_terrain_enabled": true,
		"water_reflections": 1, "water_waves_enabled": true, "disaster_blending": true,
		"season_enabled": true, "season_mode": 2, "season_fixed": 1,
		"day_enabled": false, "weather_enabled": false, "cloud_enabled": false,
		"fog_enabled": false, "brightmaps": false, "pause_freezes": false,
		"life_cars_enabled": false, "life_people_enabled": false,
		"lut_path": "", "lut_folder": ""}, true)
	return VisualEnhancementOptions.normalize(result)

func setup(result: NewCityTerrainSession.PreviewResult, colors: Sc2Palette, sprites: Sc2SpriteArchive, view_size: int, values: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	palette = colors
	var city := CityState.from_document(result.document.duplicate_document())
	var controller := GameSpeedController.new(SimulationEngine.new(city))
	presentation = MainMenuPresentation.new(self, city, controller, colors, sprites, values, view_size)
	presentation.map.show_behind_parent = false
	presentation.publish(result.landscape_image, ImageTexture.create_from_image(result.landscape_image), city, [])
	cycle = ImageTexture.create_from_image(palette.animation_image(0))
	presentation.animate(cycle)

func _process(delta: float) -> void:
	if presentation == null or not is_visible_in_tree():
		return
	elapsed += delta
	var frame := int(elapsed * 5.0)
	if frame != palette_frame:
		palette_frame = frame
		cycle.update(palette.animation_image(frame))
	var extent := Vector2(presentation.map.city_source.size)
	var zoom := maxf(size.x / extent.x, size.y / extent.y)
	presentation.advance(delta, (size - extent * zoom) * 0.5, zoom)

func _exit_tree() -> void:
	if presentation != null:
		presentation.close()
		presentation = null
