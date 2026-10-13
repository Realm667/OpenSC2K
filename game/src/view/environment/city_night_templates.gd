class_name CityNightTemplates
extends RefCounted
## Reusable road light rasters. Keys contain local geometry and light profiles;
## foreground silhouettes are applied separately at each world position.

const LIMIT := 256
var receivers: Dictionary[Array, Array] = {}
var textures: Dictionary[Array, Texture2D] = {}


func clear() -> void:
	receivers.clear()
	textures.clear()


func receiver(city: CityState, tile: Vector2i, origin: Vector2i, lights: Array[Dictionary], roads: CityLifeLights) -> Array:
	var height := CityLifePaths.edge_height(city, tile, 0)
	var key: Array = [CityLifePaths.ports(city, tile), CityLifePaths.diagonal(city, tile),
		CityLifeLights._project(city, tile, Vector2.ZERO, height) - Vector2(origin), roads.raster_scale]
	for enter in 4:
		key.append(CityLifePaths.edge_height(city, tile, enter) - height)
		for exit in 4:
			key.append(CityLifePaths.can_turn(city, tile, enter, exit))
	for light in lights:
		key.append([light.offset, light.get("enter", -1), light.color, light.radius, light.intensity])
	if receivers.has(key):
		var cached: Array = receivers[key]
		receivers.erase(key)
		receivers[key] = cached
		return cached
	var parts := _rasterize(city, tile, origin, lights, roads)
	if receivers.size() >= LIMIT:
		receivers.erase(receivers.keys()[0])
	receivers[key] = parts
	return parts


func texture(image: Image) -> Texture2D:
	# Identical masked output shares a GPU texture and can use renderer batching.
	# Compare complete bytes, not a hash alone. Visible entries retain references
	# even if an old interned texture leaves this bounded lookup table.
	var key: Array = [image.get_size(), image.get_format(), image.get_data()]
	if textures.has(key):
		var cached: Texture2D = textures[key]
		textures.erase(key)
		textures[key] = cached
		return cached
	var result := ImageTexture.create_from_image(image)
	if textures.size() >= LIMIT:
		textures.erase(textures.keys()[0])
	textures[key] = result
	return result


static func _rasterize(city: CityState, tile: Vector2i, origin: Vector2i, lights: Array[Dictionary], roads: CityLifeLights) -> Array:
	var parts: Array = []
	var edge := 64 * roads.raster_scale
	origin *= roads.raster_scale
	for enter in 4:
		if not CityLifePaths.ports(city, tile) & (1 << enter):
			continue
		var lamps: Array[Dictionary] = []
		for light in lights:
			if light.has("enter") and int(light.enter) != enter and not CityLifePaths.can_turn(city, tile, enter, int(light.enter)):
				continue
			lamps.append({"position": light.position, "color": Color(str(light.color)), "radius": float(light.radius), "intensity": float(light.intensity)})
		var image := NativeVisualRaster.night_receiver(Vector2i(edge, edge), origin, roads._road_patches(city, tile, enter), lamps)
		parts.append({"enter": enter, "image": image})
	return parts
