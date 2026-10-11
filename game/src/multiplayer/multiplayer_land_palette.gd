class_name MultiplayerLandPalette
extends RefCounted
## Match the standard child-tool palette; retain the terrain water artwork.

static func water_icon(graphics: CityUiGraphics) -> Texture2D:
	var image := TerrainToolIcons.terrain_action(graphics, "water").get_image()
	var bounds := Rect2i()
	var found := false
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.1 and pixel.b > 0.25 and pixel.b > pixel.r * 1.4 and pixel.b > pixel.g * 1.2:
				var dot := Rect2i(x, y, 1, 1)
				bounds = bounds.merge(dot) if found else dot
				found = true
	if not found:
		return null
	# Keep the blue drop and its one-source-pixel outline, excluding its arrow.
	bounds = bounds.grow(2).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return ImageTexture.create_from_image(image.get_region(bounds))

static func action_icon(selling: bool, water: bool, drop: Texture2D) -> Texture2D:
	var source: Texture2D = preload("res://src/multiplayer/icons/land_sell.svg") if selling else preload("res://src/multiplayer/icons/land_buy.svg")
	var image := Image.create(48, 36, false, Image.FORMAT_RGBA8)
	image.blend_rect(source.get_image(), Rect2i(0, 0, 40, 36), Vector2i.ZERO)
	if water and drop != null:
		var badge := drop.get_image()
		badge.resize(12, 20, Image.INTERPOLATE_NEAREST)
		image.blend_rect(badge, Rect2i(0, 0, 12, 20), Vector2i(35, 0))
	return PixelArtTexture.wrap(ImageTexture.create_from_image(image))

static func setup(windows: MultiplayerWindows, body: VBoxContainer) -> void:
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := ApplicationMultiplayer.label(body, windows.tr("Land trade"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 13)
	windows.allowance_label = ApplicationMultiplayer.label(body, "")
	windows.allowance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	windows.allowance_label.add_theme_font_size_override("font_size", 13)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 96
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_constant_override("separation", 3)
	scroll.add_child(items)
	var group := ButtonGroup.new()
	var drop := water_icon(windows.coop.app.asset_state.asset_source.assets.city_ui_graphics)
	for index in 4:
		var selling := index >= 2
		var water := index % 2 == 1
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 52
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = "ArtworkButton"
		button.icon = action_icon(selling, water, drop)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = windows.tr("Sell land") if selling else windows.tr("Buy land")
		button.text += "\n" + (windows.tr("Include water") if water else windows.tr("Land only"))
		button.clip_text = true
		button.tooltip_text = button.text.replace("\n", " · ")
		items.add_child(button)
		windows.land_tool_buttons.append(button)
		button.pressed.connect(func() -> void:
			windows.include_water = water
			windows.select_land("land_offer" if selling else "land_buy"))
