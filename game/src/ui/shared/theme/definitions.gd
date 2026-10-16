class_name AppUiThemeDefinitions
extends RefCounted


static func build(value: String, files := false, translucent_menus := true) -> Theme:
	var dark := value == "dark"
	var result := _dark_theme() if dark else _light_file_dialog_theme() if files else _light_theme()
	result.set_color("default_color", "RichTextLabel", result.get_color("font_color", "Label"))

	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		var border := Color("555c66") if dark else Color("383838")

		if "disabled" in icon_name:
			border = Color("848e9a") if dark else Color("606060")

		var icon := result.get_icon(icon_name, "CheckBox") if result.has_icon(icon_name, "CheckBox") \
				else ThemeDB.get_default_theme().get_icon(icon_name, "CheckBox")
		result.set_icon(icon_name, "CheckBox", _bordered_check_box(icon, border))

	# spinbox has separate arrow buttons; button icon colors do not reach them
	for direction in ["up", "down"]:
		for state in ["", "_hover", "_pressed", "_disabled"]:
			var ink := Color("e0e5eb") if dark else Color("303030")

			if state == "_disabled":
				ink.a = 0.45

			result.set_color(direction + state + "_icon_modulate", "SpinBox", ink)

		for state in ["", "_hovered", "_pressed", "_disabled"]:
			var background := Color("1a1a1a") if dark else Color("c0c0c0")

			if state == "_hovered":
				background = Color("343a42") if dark else Color("d0d0d0")
			elif state == "_pressed":
				background = Color("3c4526") if dark else Color("a0a0a0")

			result.set_stylebox(direction + "_background" + state, "SpinBox", create_box(background, Color.TRANSPARENT, 0, 0, 0))

	# map keys remain readable over city artwork, independent of the ui theme
	result.set_type_variation("MapLegend", "Panel")
	var legend := create_box(Color(0.06, 0.08, 0.12, 0.78 if translucent_menus else 1.0), Color.TRANSPARENT, 0, 12, 12)
	legend.set_corner_radius_all(6)
	result.set_stylebox("panel", "MapLegend", legend)
	result.set_color("font_color", "MapLegend", Color("eeeeee"))

	var tooltip := create_box(Color(0.03, 0.04, 0.05, 0.80 if translucent_menus else 1.0), Color.TRANSPARENT, 0, 7, 5)
	tooltip.set_corner_radius_all(3)
	result.set_stylebox("panel", "TooltipPanel", tooltip)
	result.set_color("font_color", "TooltipLabel", Color.WHITE)

	# godot's file toolbar and menubutton have their own native theme types
	for type_name in ["MenuButton", "FlatButton", "FlatMenuButton"]:
		if type_name != "MenuButton":
			result.set_type_variation(type_name, "Button")

		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			result.set_stylebox(state, type_name, result.get_stylebox(state, "Button") if result.has_stylebox(state, "Button")
					else ThemeDB.get_default_theme().get_stylebox(state, "Button"))

		for color_name in result.get_color_list("Button"):
			result.set_color(color_name, type_name, result.get_color(color_name, "Button"))
		if dark and type_name == "MenuButton":
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var box := _copy_style(result, type_name, state)
				box.content_margin_left = 3
				box.content_margin_right = 3
				result.set_stylebox(state, type_name, box)

	result.set_type_variation("ArtworkButton", "Button")

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		result.set_color("icon_" + state + "_color", "ArtworkButton", Color.WHITE)

	result.set_type_variation("HelpLabel", "Label")
	result.set_color("font_color", "HelpLabel", Color("ccd3db") if dark else Color("505050"))
	result.set_type_variation("WarningLabel", "Label")
	result.set_color("font_color", "WarningLabel", Color("ffcf70") if dark else Color("805000"))
	result.set_type_variation("ErrorLabel", "Label")
	result.set_color("font_color", "ErrorLabel", Color("ff7777") if dark else Color("d02020"))
	result.set_type_variation("SuccessLabel", "Label")
	result.set_color("font_color", "SuccessLabel", Color("64db99") if dark else Color("16803a"))

	result.set_color("error", "AppPalette", Color("ff7777") if dark else Color("d02020"))
	result.set_color("warning", "AppPalette", Color("ffcf70") if dark else Color("805000"))
	result.set_color("map_canvas", "AppPalette", Color("202830"))
	result.set_color("canvas", "AppPalette", Color("292d33") if dark else Color("c0c0c0"))
	result.set_color("ink", "AppPalette", Color("e0e5eb") if dark else Color("202020"))
	result.set_color("paper", "AppPalette", Color("1a1a1a") if dark else Color.WHITE)
	result.set_color("chart_accent", "AppPalette", Color("dcf85e") if dark else Color("000080"))
	result.set_color("grid", "AppPalette", Color("41474f") if dark else Color("dddddd"))
	result.set_color("border", "AppPalette", Color("555c66") if dark else Color("484848"))

	# preserve scene layout padding while sharing the approved panel appearance
	for entry in [
		["PanelPadding0_0_0_0", 0, 0, 0, 0],
		["PanelPadding44_34_44_34", 44, 34, 44, 34],
		["PanelPadding5_2_5_2", 5, 2, 5, 2],
		["PanelPadding5_3_5_3", 5, 3, 5, 3],
		["PanelPadding8_8_8_8", 8, 8, 8, 8],
	]:
		result.set_type_variation(entry[0], "PanelContainer")
		var box := _copy_style(result, "PanelContainer", "panel")
		box.content_margin_left = entry[1]
		box.content_margin_top = entry[2]
		box.content_margin_right = entry[3]
		box.content_margin_bottom = entry[4]
		result.set_stylebox("panel", entry[0], box)

	result.set_type_variation("MainMenuPanel", "PanelContainer")
	var menu := _copy_style(result, "PanelPadding44_34_44_34", "panel")
	# the shared glass shader mixes these tints with the blurred city background
	menu.bg_color.a = (0.68 if dark else 0.75) if translucent_menus else 1.0
	result.set_stylebox("panel", "MainMenuPanel", menu)

	result.set_type_variation("CityToolbarPanel", "Panel")
	var toolbar := _copy_style(result, "PanelPadding5_3_5_3", "panel")
	toolbar.bg_color.a = (0.78 if dark else 0.75) if translucent_menus else 1.0
	toolbar.border_width_left = 0
	toolbar.border_width_top = 0
	toolbar.border_width_bottom = 0
	result.set_stylebox("panel", "CityToolbarPanel", toolbar)

	result.set_type_variation("CityMenuBarPanel", "PanelContainer")
	var menu_bar := _copy_style(result, "PanelPadding5_2_5_2", "panel")
	menu_bar.border_width_top = 0
	menu_bar.border_width_left = 0
	menu_bar.border_width_right = 0
	result.set_stylebox("panel", "CityMenuBarPanel", menu_bar)

	result.set_type_variation("CityStatusBarPanel", "PanelContainer")
	var status_bar := _copy_style(result, "PanelPadding5_3_5_3", "panel")
	status_bar.border_width_bottom = 0
	status_bar.border_width_left = 0
	status_bar.border_width_right = 0
	result.set_stylebox("panel", "CityStatusBarPanel", status_bar)

	_apply_shared_layout(result, dark)
	# Explicit action roles keep their existing position and signal connections.
	for role in ["PrimaryButton", "SecondaryButton"]:
		result.set_type_variation(role, "Button")
		if not dark:
			continue
		result.set_font("font", role, _website_font(600))
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, "Button", state)
			if state != "disabled":
				box.bg_color = Color("dcf85e") if role == "PrimaryButton" else Color("367074")
				if state == "hover":
					box.bg_color = box.bg_color.lightened(0.1)
				elif state in ["pressed", "hover_pressed"]:
					box.bg_color = box.bg_color.darkened(0.1)
				box.border_color = box.bg_color
			result.set_stylebox(state, role, box)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			result.set_color(color_name, role, Color("1a1a1a") if role == "PrimaryButton" else Color.WHITE)

	# Icon-only category buttons need more artwork space than text buttons.
	# Keep the zoom/rotation buttons and their native icon sizing unchanged.
	result.set_type_variation("ToolbarCategoryButton", "ArtworkButton")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := _copy_style(result, "Button", state)
		box.set_content_margin_all(3)
		result.set_stylebox(state, "ToolbarCategoryButton", box)
	return result


static func _apply_shared_layout(result: Theme, dark: bool) -> void:
	# Common rhythm, readable fields and keyboard focus across both themes.
	for type_name in ["HBoxContainer", "VBoxContainer"]:
		result.set_constant("separation", type_name, 8)
	result.set_constant("h_separation", "GridContainer", 10)
	result.set_constant("v_separation", "GridContainer", 8)
	result.set_type_variation("DialogMargin", "MarginContainer")
	for side in ["left", "top", "right", "bottom"]:
		result.set_constant("margin_" + side, "DialogMargin", 12)
	result.set_type_variation("SectionHeading", "Label")
	result.set_font("font", "SectionHeading", result.get_font("title_font", "Window"))
	result.set_font_size("font_size", "SectionHeading", 16)
	result.set_color("font_color", "SectionHeading", result.get_color("ink", "AppPalette"))
	result.set_type_variation("UtilityPanel", "PanelContainer")
	result.set_stylebox("panel", "UtilityPanel", create_box(result.get_color("canvas", "AppPalette"),
		result.get_color("border", "AppPalette"), 1, 14, 14))
	var focus := create_box(Color.TRANSPARENT, Color("dcf85e") if dark else Color("164b83"), 2, 0, 0)
	if dark:
		focus.set_corner_radius_all(3)
	for type_name in ["Button", "OptionButton", "LineEdit", "TextEdit", "ItemList", "Tree"]:
		result.set_stylebox("focus", type_name, focus)
	if dark:
		for type_name in ["CheckBox", "CheckButton", "TabBar", "TabContainer"]:
			result.set_stylebox("tab_focus" if type_name.begins_with("Tab") else "focus", type_name, focus)
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, type_name, state)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 5
			box.content_margin_bottom = 5
			result.set_stylebox(state, type_name, box)


static func _light_theme() -> Theme:
	var result := _base_light_theme()
	result.set_stylebox("panel", "TabContainer", create_box(Color("c0c0c0"), Color("808080"), 1, 12, 12))

	var tab_hovered := _copy_style(result, "TabContainer", "tab_hovered")
	tab_hovered.border_color = Color("808080")
	tab_hovered.border_width_top = 1
	result.set_stylebox("tab_hovered", "TabContainer", tab_hovered)

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var button_box := _copy_style(result, "Button", state)
		button_box.border_color = Color("383838") if state != "disabled" else Color("606060")
		button_box.set_border_width_all(2)
		result.set_stylebox(state, "Button", button_box)

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		result.set_color("icon_" + state + "_color", "Button", Color("303030"))

	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.set_color(state, "LinkButton", Color("0000cc"))

	for type_name in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var empty := StyleBoxEmpty.new()
			empty.content_margin_left = 4
			empty.content_margin_right = 4
			empty.content_margin_top = 4
			empty.content_margin_bottom = 4
			result.set_stylebox(state, type_name, empty)

		result.set_color("font_disabled_color", type_name, Color("606060"))

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled", "normal_mirrored", "hover_mirrored",
		"pressed_mirrored", "disabled_mirrored"]:
		var option_box := _copy_style(result, "OptionButton", state)
		option_box.set_corner_radius_all(0)
		result.set_stylebox(state, "OptionButton", option_box)

	for type_name in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]:
			var field := _copy_style(result, "OptionButton", "normal")
			var original := _copy_style(result, type_name, state)

			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				field.set_content_margin(side, original.get_content_margin(side))

			if state == "read_only":
				field.bg_color = Color("c8c8c8")

			result.set_stylebox(state, type_name, field)

		result.set_stylebox("focus", type_name, _copy_style(result, "OptionButton", "focus"))
		result.set_color("font_color", type_name, result.get_color("font_color", "OptionButton"))
		result.set_color("font_placeholder_color", type_name, Color("606060"))
		result.set_color("caret_color", type_name, Color("101010"))

	result.set_icon("clear", "LineEdit", _tinted_icon(ThemeDB.get_default_theme().get_icon("clear", "LineEdit"), Color("383838")))
	result.set_color("font_uneditable_color", "LineEdit", Color("505050"))
	result.set_color("font_readonly_color", "TextEdit", Color("505050"))

	for type_name in ["HSlider", "VSlider"]:
		result.set_icon("tick", type_name, _tinted_icon(ThemeDB.get_default_theme().get_icon("tick", type_name), Color("505050")))

	result.set_stylebox("background", "ProgressBar", create_box(Color("d0d0d0"), Color("484848"), 1, 1, 1))
	result.set_stylebox("fill", "ProgressBar", create_box(Color("769302"), Color("769302"), 0, 0, 0))

	for state in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus", "cursor", "cursor_unfocused"]:
		var selection := _copy_style(result, "ItemList", state)
		selection.set_corner_radius_all(0)
		result.set_stylebox(state, "ItemList", selection)

	for state in ["title_button_normal", "title_button_hover", "title_button_pressed"]:
		var heading := _copy_style(result, "Tree", state)
		heading.set_corner_radius_all(0)
		result.set_stylebox(state, "Tree", heading)

	for type_name in ["ItemList", "Tree"]:
		for color_name in ["font_color", "font_hovered_color", "font_selected_color", "font_hovered_selected_color"]:
			result.set_color(color_name, type_name, Color("eeeeee"))

	result.set_color("title_button_color", "Tree", Color("eeeeee"))
	result.set_stylebox("panel", "PanelContainer", create_box(Color("dedede"), Color("808080"), 1, 8, 8))

	return result


# Website demo/03 palette. Only presentation changes; scene layouts stay intact.
static func _dark_theme() -> Theme:
	var result := ThemeDB.get_default_theme().duplicate() as Theme
	var surface := Color("292d33")
	var inset := Color("1a1a1a")
	var border := Color("555c66")
	var ink := Color("e0e5eb")
	var accent := Color("dcf85e")
	var font := _website_font()
	var heading := _website_font(700)
	result.default_font = font
	result.default_font_size = 13
	for type_name in result.get_type_list():
		for font_name in result.get_font_list(type_name):
			if font_name == "mono_font":
				continue
			var weight := 700 if "bold" in font_name or "title" in font_name else 400
			result.set_font(font_name, type_name, _website_font(weight, "italics" in font_name))
		for size_name in result.get_font_size_list(type_name):
			result.set_font_size(size_name, type_name, 13)
		for color_name in result.get_color_list(type_name):
			if color_name.begins_with("font_") and not "outline" in color_name and not "shadow" in color_name:
				result.set_color(color_name, type_name, Color("8b929b") if "disabled" in color_name else ink)
	result.set_font("title_font", "Window", heading)
	# Montserrat is wider than the former font. Keep all existing menu entries
	# and metric fields within the base viewport without moving them.
	result.set_font_size("font_size", "MenuButton", 12)
	result.set_color("title_color", "Window", Color.WHITE)
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	for type_name in ["Panel", "PanelContainer", "AcceptDialog", "PopupPanel", "PopupMenu", "TabContainer"]:
		var panel := _copy_style(result, type_name, "panel")
		panel.bg_color = surface
		panel.border_color = border
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(3)
		result.set_stylebox("panel", type_name, panel)
	var container := create_box(surface, border, 1, 8, 8)
	container.set_corner_radius_all(3)
	result.set_stylebox("panel", "PanelContainer", container)
	var tab_panel := _copy_style(result, "TabContainer", "panel")
	tab_panel.set_content_margin_all(12)
	result.set_stylebox("panel", "TabContainer", tab_panel)
	for type_name in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			var tab := _copy_style(result, type_name, state)
			tab.bg_color = Color("343a42") if state == "tab_hovered" else surface
			tab.border_color = accent if state == "tab_selected" else border
			tab.set_border_width_all(0)
			tab.border_width_bottom = 2 if state == "tab_selected" else 1
			tab.set_corner_radius_all(0)
			result.set_stylebox(state, type_name, tab)
		result.set_color("font_selected_color", type_name, accent)
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, type_name, state)
			box.bg_color = inset
			box.border_color = border
			if state == "hover":
				box.bg_color = Color("343a42")
			elif state in ["pressed", "hover_pressed"]:
				box.bg_color = Color("3c4526")
				box.border_color = accent
			elif state == "disabled":
				box.bg_color = surface
			box.set_border_width_all(1)
			box.set_corner_radius_all(3)
			result.set_stylebox(state, type_name, box)
			if type_name == "OptionButton" and state != "hover_pressed":
				result.set_stylebox(state + "_mirrored", type_name, box)
	for type_name in ["CheckBox", "CheckButton"]:
		for color_name in ["checkbox_checked_color", "checkbox_unchecked_color", "button_checked_color", "button_unchecked_color"]:
			result.set_color(color_name, type_name, Color.WHITE)
		for icon_name in result.get_icon_list(type_name):
			var icon := result.get_icon(icon_name, type_name)
			var checked := not "unchecked" in icon_name and "checked" in icon_name
			var tint := accent if checked else Color("ccd3db")
			if "disabled" in icon_name:
				tint = Color("8b929b")
			if icon is DPITexture:
				result.set_icon(icon_name, type_name, _recolored_svg(icon, func(color: Color) -> Color:
					return tint if color.get_luminance() > 0.4 else inset, false))
	for type_name in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]:
			var field := _copy_style(result, type_name, state)
			field.bg_color = inset
			field.border_color = border
			field.set_border_width_all(1)
			field.set_corner_radius_all(3)
			result.set_stylebox(state, type_name, field)
		result.set_color("caret_color", type_name, accent)
		result.set_color("font_placeholder_color", type_name, Color("ccd3db"))
		result.set_color("selection_color", type_name, Color("367074"))
	for type_name in ["ItemList", "Tree"]:
		var panel := _copy_style(result, type_name, "panel")
		panel.bg_color = inset
		panel.border_color = border
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(3)
		result.set_stylebox("panel", type_name, panel)
		for state in result.get_stylebox_list(type_name):
			if not ("selected" in state or state.begins_with("cursor") or state == "hovered"):
				continue
			var selection := create_box(Color("363f27"), accent, 0, 4, 4)
			selection.border_width_left = 3
			result.set_stylebox(state, type_name, selection)
		result.set_color("font_selected_color", type_name, accent)
		result.set_color("font_hovered_selected_color", type_name, accent)
		result.set_color("guide_color", type_name, Color("41474f"))
	result.set_stylebox("hover", "PopupMenu", create_box(Color("363f27"), accent, 0, 4, 4))
	for type_name in ["HSeparator", "VSeparator"]:
		var separator := StyleBoxLine.new()
		separator.color = Color("41474f")
		separator.thickness = 1
		separator.vertical = type_name == "VSeparator"
		result.set_stylebox("separator", type_name, separator)
	for type_name in ["HSlider", "VSlider"]:
		for state in ["grabber_area", "grabber_area_highlight"]:
			var track := _copy_style(result, type_name, state)
			track.bg_color = accent
			track.border_color = accent
			result.set_stylebox(state, type_name, track)
		for icon_name in ["grabber", "grabber_highlight"]:
			result.set_icon(icon_name, type_name, _tinted_icon(result.get_icon(icon_name, type_name), accent))
	result.set_stylebox("background", "ProgressBar", create_box(inset, border, 1, 1, 1))
	result.set_stylebox("fill", "ProgressBar", create_box(accent, accent, 0, 0, 0))
	result.set_color("font_color", "ProgressBar", ink)
	for state in ["embedded_border", "embedded_unfocused_border"]:
		var window := _copy_style(result, "Window", state)
		window.bg_color = surface
		window.border_color = surface
		window.set_corner_radius_all(3)
		result.set_stylebox(state, "Window", window)
	return result


static func _website_font(weight := 400, italic := false) -> Font:
	var font := FontVariation.new()
	font.base_font = preload("res://assets/fonts/montserrat/Montserrat.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if italic:
		font.variation_transform = Transform2D(Vector2.RIGHT, Vector2(-0.2, 1.0), Vector2.ZERO)
	return AppLocalization.with_fallback(font, weight >= 600)


static func _copy_style(source: Theme, type_name: String, state: String) -> StyleBoxFlat:
	var style := source.get_stylebox(
		state,
		type_name,
	) if source.has_stylebox(state, type_name) else ThemeDB.get_default_theme().get_stylebox(state, type_name)

	return style.duplicate() as StyleBoxFlat


static func _tinted_icon(texture: Texture2D, color: Color) -> Texture2D:
	# keep a scalable icon sharp at every UI scale
	if texture is DPITexture:
		return _recolored_svg(texture, func(_color: Color) -> Color: return color, true)

	var image := texture.get_image()

	if image == null:
		return texture

	var maximum_alpha := 0.0

	for y in image.get_height():
		for x in image.get_width():
			maximum_alpha = maxf(maximum_alpha, image.get_pixel(x, y).a)

	if maximum_alpha == 0.0:
		return texture

	for y in image.get_height():
		for x in image.get_width():
			var pixel := color
			pixel.a *= image.get_pixel(x, y).a / maximum_alpha
			image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(image)


# rewrites each SVG color through recolor. full_opacity scales the opacities so
# that the most opaque part is fully opaque, like a tint of the rasterized icon
static func _recolored_svg(texture: DPITexture, recolor: Callable, full_opacity: bool) -> DPITexture:
	var source := texture.get_source()
	var colors := RegEx.create_from_string("#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\b")
	source = _replace_matches(source, colors, func(found: RegExMatch) -> String:
		return "#" + (recolor.call(Color.html(found.get_string())) as Color).to_html(false))

	if full_opacity:
		# the drawn icon gives the largest opacity, including parts without an
		# opacity of their own
		var image := texture.get_image()
		var maximum := 0.0

		for y in image.get_height():
			for x in image.get_width():
				maximum = maxf(maximum, image.get_pixel(x, y).a)

		if maximum > 0.0 and maximum < 1.0:
			var opacities := RegEx.create_from_string("(fill-opacity|stroke-opacity|opacity)=\"([0-9.]+)\"")
			source = _replace_matches(source, opacities, func(found: RegExMatch) -> String:
				return "%s=\"%s\"" % [found.get_string(1), minf(1.0, found.get_string(2).to_float() / maximum)])

	return DPITexture.create_from_string(source, texture.base_scale, texture.saturation, texture.color_map)


# outlines the square box so that it stays visible against the panel color
static func _bordered_check_box(texture: Texture2D, border: Color) -> Texture2D:
	if not texture is DPITexture:
		return texture

	var svg := texture as DPITexture
	var source := svg.get_source().replace("<rect ", "<rect stroke=\"#%s\" stroke-width=\"1\" " % border.to_html(false))

	return DPITexture.create_from_string(source, svg.base_scale, svg.saturation, svg.color_map)


static func _replace_matches(text: String, pattern: RegEx, replacement: Callable) -> String:
	var result := ""
	var end := 0

	for found in pattern.search_all(text):
		result += text.substr(end, found.get_start() - end) + str(replacement.call(found))
		end = found.get_end()

	return result + text.substr(end)


static func _light_file_dialog_theme() -> Theme:
	var result := _light_theme()
	var native := ThemeDB.get_default_theme()

	for icon_name in native.get_icon_list("FileDialog"):
		result.set_icon(icon_name, "FileDialog", _tinted_icon(native.get_icon(icon_name, "FileDialog"), Color("383838")))

	for type_name in ["OptionButton", "LineEdit"]:
		for icon_name in native.get_icon_list(type_name):
			result.set_icon(icon_name, type_name, _tinted_icon(native.get_icon(icon_name, type_name), Color("383838")))

	for icon_name in ["arrow", "arrow_collapsed", "arrow_collapsed_mirrored", "select_arrow", "updown"]:
		result.set_icon(icon_name, "Tree", _tinted_icon(native.get_icon(icon_name, "Tree"), Color("383838")))

	result.set_color("caret_color", "LineEdit", Color("383838"))
	result.set_color("font_placeholder_color", "LineEdit", Color("606060"))
	result.set_color("font_uneditable_color", "LineEdit", Color("505050"))
	result.set_color("title_button_color", "Tree", Color("383838"))

	for type_name in ["Label", "Button", "OptionButton", "CheckBox", "LineEdit", "ItemList", "Tree", "PopupMenu"]:
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color",
			"font_disabled_color", "font_selected_color", "font_hovered_color", "font_hovered_selected_color"]:
			result.set_color(color_name, type_name, Color("383838"))

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		result.set_color("icon_" + state + "_color", "Button", Color("383838"))

	for type_name in ["Tree", "ItemList", "PopupMenu"]:
		result.set_stylebox("panel", type_name, create_box(Color("dedede"), Color("808080"), 1, 4, 4))

		for state in ["selected", "selected_focus", "hovered", "hovered_selected", "hovered_selected_focus", "hover"]:
			result.set_stylebox(state, type_name, create_box(Color("aec8e5"), Color("6a88aa"), 1, 4, 4))

	result.set_color("folder_icon_color", "FileDialog", Color.WHITE)
	result.set_color("file_icon_color", "FileDialog", Color.WHITE)

	return result


static func create_box(
	background: Color,
	border: Color,
	width: int,
	horizontal_margin := 5,
	vertical_margin := 3
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = horizontal_margin
	box.content_margin_top = vertical_margin
	box.content_margin_right = horizontal_margin
	box.content_margin_bottom = vertical_margin

	return box


static func _base_light_controls() -> Theme:
	var result := Theme.new()
	result.default_font_size = 13
	result.default_font = _interface_font()

	result.set_color("font_color", "Label", Color("101010"))
	result.set_color("font_color", "Button", Color("101010"))
	result.set_color("font_hover_color", "Button", Color("101010"))
	result.set_color("font_pressed_color", "Button", Color("101010"))
	result.set_color("font_hover_pressed_color", "Button", Color("101010"))
	result.set_color("font_focus_color", "Button", Color("101010"))
	result.set_color("font_color", "OptionButton", Color("101010"))

	result.set_stylebox(
		"normal", "Button", create_box(Color("c0c0c0"), Color("ffffff"), 2)
	)
	result.set_stylebox(
		"hover", "Button", create_box(Color("d0d0d0"), Color("ffffff"), 2)
	)
	result.set_stylebox(
		"pressed", "Button", create_box(Color("a0a0a0"), Color("404040"), 2)
	)
	result.set_stylebox(
		"hover_pressed", "Button", create_box(Color("b8b8b8"), Color("404040"), 2)
	)
	result.set_stylebox(
		"focus", "Button", create_box(Color("c0c0c0"), Color("000000"), 1)
	)

	result.set_stylebox(
		"normal", "OptionButton", create_box(Color("ffffff"), Color("808080"), 2)
	)
	result.set_stylebox(
		"hover", "OptionButton", create_box(Color("ffffff"), Color("000080"), 2)
	)
	result.set_stylebox(
		"pressed", "OptionButton", create_box(Color("e0e0e0"), Color("404040"), 2)
	)

	result.set_stylebox(
		"normal", "PanelContainer", create_box(Color("c0c0c0"), Color("808080"), 1)
	)

	return result


static func _base_light_theme() -> Theme:
	var result := _base_light_controls()
	result.set_stylebox("panel", "AcceptDialog", create_box(Color("c0c0c0"), Color("808080"), 2, 12, 12))

	return result


# The default font, with Hangul glyphs from the fallback font of AppLocalization.
static func _interface_font() -> Font:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font

	return AppLocalization.with_fallback(font)
