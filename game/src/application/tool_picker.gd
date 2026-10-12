class_name ApplicationToolPicker
extends RefCounted
## Selects an existing tool without editing the city. Grown buildings select
## their zone; unavailable rewards and inventions stay unavailable.
@warning_ignore_start("integer_division")

const G = CityToolIds.Group
const B = preload("res://src/tools/shared/building_tile_ids.gd")
const NONE := Vector2i(-1, -1)


static func tool_at(city: CityState, point: Vector2i, underground := false) -> Vector2i:
	if city == null or point.x < 0 or point.y < 0 or point.x >= city.map_size or point.y >= city.map_size:
		return NONE

	if underground:
		var below := city.underground_id(point.x, point.y)
		if below >= UndergroundTileIds.SUBWAY_FIRST and below <= UndergroundTileIds.SUBWAY_LAST:
			return Vector2i(G.RAIL, CityToolIds.Rail.SUBWAY)
		if below >= UndergroundTileIds.PIPE_FIRST and below <= UndergroundTileIds.PIPE_LR_SUBWAY_TB:
			return Vector2i(G.WATER, CityToolIds.Water.PIPES)
		if below == UndergroundTileIds.SUBWAY_ENTRANCE:
			return Vector2i(G.RAIL, CityToolIds.Rail.SUBWAY_STATION)
		return NONE

	var building := city.building_id(point.x, point.y)
	for slot: int in BuildingConstants.TILE_BY_TOOL:
		if BuildingConstants.TILE_BY_TOOL[slot] == building:
			return Vector2i(slot / ToolCatalog.MAX_SLOTS_PER_GROUP, slot % ToolCatalog.MAX_SLOTS_PER_GROUP)
	if building >= B.TREES_1 and building <= B.TREES_7:
		return Vector2i(G.LANDSCAPE, CityToolIds.Landscape.TREES)
	if building in [B.HYDRO_POWER_1, B.HYDRO_POWER_2]:
		return Vector2i(G.POWER, CityToolIds.Power.HYDRO)
	if (building >= B.POWER_LINE_STRAIGHT_1 and building <= B.POWER_LINE_CROSSROADS) or building == B.POWER_BRIDGE:
		return Vector2i(G.POWER, CityToolIds.Power.WIRES)
	if ((building >= B.ROAD_STRAIGHT_1 and building <= B.ROAD_CROSSROADS)
			or (building >= B.ROAD_POWER_CROSSING_1 and building <= B.ROAD_RAIL_CROSSING_2)
			or (building >= B.SUSPENSION_BRIDGE_1 and building <= B.RAISING_BRIDGE_OPEN)):
		return Vector2i(G.ROADS, CityToolIds.Roads.ROAD)
	if ((building >= B.RAIL_STRAIGHT_1 and building <= B.RAIL_SLOPE_8)
			or building in [B.RAIL_POWER_CROSSING_1, B.RAIL_POWER_CROSSING_2, B.RAIL_BRIDGE, B.RAIL_BRIDGE_PYLON]):
		return Vector2i(G.RAIL, CityToolIds.Rail.RAIL)
	if building >= B.TUNNEL_ENTRANCE_1 and building <= B.TUNNEL_ENTRANCE_4:
		return Vector2i(G.ROADS, CityToolIds.Roads.TUNNEL)
	if building >= B.HIGHWAY_ONRAMP_1 and building <= B.HIGHWAY_ONRAMP_4:
		return Vector2i(G.ROADS, CityToolIds.Roads.ONRAMP)
	if ((building >= B.HIGHWAY_STRAIGHT_1 and building <= B.HIGHWAY_POWER_CROSSING_2)
			or (building >= B.HIGHWAY_SLOPE_1 and building <= B.REINFORCED_HIGHWAY_BRIDGE)):
		return Vector2i(G.ROADS, CityToolIds.Roads.HIGHWAY)
	if building >= B.RAIL_SUBWAY_ENTRANCE_1 and building <= B.RAIL_SUBWAY_ENTRANCE_4:
		return Vector2i(G.RAIL, CityToolIds.Rail.SUBWAY_TO_RAIL)
	var zone := city.zone_id(point.x, point.y)
	match zone:
		1, 2:
			return Vector2i(G.RESIDENTIAL, zone - 1)
		3, 4:
			return Vector2i(G.COMMERCIAL, zone - 3)
		5, 6:
			return Vector2i(G.INDUSTRIAL, zone - 5)
		8:
			return Vector2i(G.PORTS, CityToolIds.Ports.AIRPORT)
		9:
			return Vector2i(G.PORTS, CityToolIds.Ports.SEAPORT)
	return NONE


static func pick(app: CityApplication, point: Vector2i) -> void:
	if app.tool_state.landscape_editor or app.map_view.selection_start.x >= 0:
		return
	var tool := tool_at(app.document_state.city, point, app.view_state.overlay_mode == CityViewMode.Mode.UNDERGROUND)
	if tool == NONE:
		app.interface.show_status(TranslationServer.translate("No building tool at this location."))
		return
	if not ToolAvailability.is_available(app.document_state.city, tool.x, tool.y):
		app.interface.show_status(TranslationServer.translate("This building tool is not available in this city."))
		return
	app.tool_state.group_subtools[tool.x] = tool.y
	app.current_tool.select_tool_group(tool.x)
	app.current_tool.select_subtool(tool.y)
	app.interface.show_status(TranslationServer.translate("Selected: %s") % TranslationServer.translate(ToolCatalog.tool(tool.x, tool.y).name))
