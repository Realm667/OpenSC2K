class_name CityLifeGpu
extends RefCounted
## Persistent source art and cached mask layers; only small instance buffers move.

@warning_ignore_start("integer_division")

const SHADER := preload("res://src/view/city_life/city_life_gpu.gdshader")
const GROUP := 64
const STRIDE := 8
const CELL := Vector2i(32, 16)
var artwork: ImageTexture
var emission: ImageTexture
var rectangles: Dictionary[int, Rect2i] = {}
var groups: Array[MultiMeshInstance2D] = []
var emissions: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var data: Array[PackedFloat32Array] = []
var textures: Array[ImageTexture] = []
var masks: Array[Texture2DArray] = []
var identities: Array = []
var layer_keys: Array[Dictionary] = []
var cropped: Dictionary[Vector3i, Dictionary] = {}
var blank := Image.create(128, 128, false, Image.FORMAT_RGBA8)
var blend := 1.0
var origin := Vector2i.ZERO
var upload_bytes := 0


func prepare(sprites: CityLifeSprites, lights: CityLifeLights) -> void:
	if artwork != null:
		return
	var image := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	var lamp_image := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	for walking in [false, true]:
		for kind in (1 if walking else 3):
			for variant in 18:
				for direction in 8:
					for phase in (2 if walking else 1):
						var sprite := sprites.sprite(walking, variant, direction, phase, kind)
						var index := rectangles.size()
						var point := Vector2i(index % 32, index / 32) * CELL
						var rect := Rect2i(point, sprite.get_size())
						assert(rect.end.y <= image.get_height())
						image.blit_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), point)
						if not walking:
							lamp_image.blit_rect(lights.lamp_mask(sprite, kind, direction), Rect2i(Vector2i.ZERO, sprite.get_size()), point)
						rectangles[sprite.get_instance_id()] = rect
	artwork = ImageTexture.create_from_image(image)
	emission = ImageTexture.create_from_image(lamp_image)


func render(canvas: CityLifeCanvas, entries: Array[Dictionary]) -> void:
	origin = canvas.source_bounds.position
	upload_bytes = 0
	var count := entries.size()
	while groups.size() * GROUP < count:
		add_group(canvas)
	for group in groups:
		group.multimesh.visible_instance_count = 0
	# Retain each tile's texture layer when depth sorting moves instances.
	for group_index in groups.size():
		var wanted: Dictionary[Vector3i, bool] = {}
		for index in range(group_index * GROUP, mini(count, (group_index + 1) * GROUP)):
			var figure: CityLifeController.Figure = entries[index].figure
			wanted[Vector3i(figure.tile.x, figure.tile.y, figure.enter % 2)] = true
		var assigned: Dictionary = layer_keys[group_index]
		for key in assigned.keys():
			if not wanted.has(key):
				assigned.erase(key)
		var used := assigned.values()
		var free := 0
		for key in wanted:
			if assigned.has(key):
				continue
			while free in used:
				free += 1
			assigned[key] = free
			free += 1
	var live: Dictionary[Vector3i, bool] = {}
	for index in count:
		var entry := entries[index]
		var group := index / GROUP
		var slot := index % GROUP
		var figure: CityLifeController.Figure = entry.figure
		var key := Vector3i(figure.tile.x, figure.tile.y, figure.enter % 2)
		live[key] = true
		var candidates: Array = entry.occluders
		var version: int = candidates[0].image.get_instance_id() if not candidates.is_empty() else 0
		var cached: Dictionary = cropped.get(key, {})
		if cached.is_empty() or cached.version != version:
			var point: Vector2i = canvas._occluder_bounds.get(key, Rect2i(entry.origin, Vector2i.ONE)).position - Vector2i(32, 32)
			var image := blank if candidates.is_empty() else blank.duplicate()
			for candidate: Dictionary in candidates:
				image.blend_rect(candidate.image, Rect2i(Vector2i.ZERO, candidate.image.get_size()), candidate.origin - point)
			cached = {"version": version, "image": image, "origin": point}
			cropped[key] = cached
		var identity: int = cached.image.get_instance_id()
		var layer: int = layer_keys[group][key]
		if identities[group][layer] != identity:
			masks[group].update_layer(cached.image, layer)
			identities[group][layer] = identity
			upload_bytes += 128 * 128 * 4
		var rect := rectangles[entry.sprite.get_instance_id()]
		var at := slot * STRIDE
		var destination: Vector2i = entry.origin - origin
		buffers[group][at] = rect.size.x
		buffers[group][at + 3] = destination.x
		buffers[group][at + 5] = rect.size.y
		buffers[group][at + 7] = destination.y
		var offset := slot * 4
		data[group][offset] = rect.position.x
		data[group][offset + 1] = rect.position.y
		data[group][offset + 2] = rect.size.x
		data[group][offset + 3] = rect.size.y
		data[group][GROUP * 4 + offset] = entry.origin.x
		data[group][GROUP * 4 + offset + 1] = entry.origin.y
		var previous := figure.previous_position if figure.has_previous_position else figure.position
		data[group][GROUP * 4 + offset + 2] = previous.x - figure.position.x
		data[group][GROUP * 4 + offset + 3] = previous.y - figure.position.y
		data[group][GROUP * 8 + offset] = cached.origin.x
		data[group][GROUP * 8 + offset + 1] = cached.origin.y
		data[group][GROUP * 8 + offset + 2] = layer
		data[group][GROUP * 8 + offset + 3] = entry.opacity
		figure.previous_position = figure.position
		figure.has_previous_position = true
		groups[group].multimesh.visible_instance_count += 1
	# Keep only masks used by current figures. The underlying city cache remains warm.
	for key in cropped.keys():
		if not live.has(key):
			cropped.erase(key)
	for index in groups.size():
		groups[index].visible = groups[index].multimesh.visible_instance_count > 0
		if not groups[index].visible:
			continue
		groups[index].multimesh.buffer = buffers[index]
		textures[index].update(Image.create_from_data(GROUP, 3, false, Image.FORMAT_RGBAF, data[index].to_byte_array()))
		upload_bytes += GROUP * (STRIDE + 12) * 4


func sync(app: CityApplication, lights: bool, fraction: float) -> void:
	blend = fraction
	for group in groups:
		var shader := group.material as ShaderMaterial
		app.map_view.layers._apply_environment(shader)
		shader.set_shader_parameter("vehicle_has_emission", lights)
		shader.set_shader_parameter("interpolation", blend)
	for copy in emissions:
		(copy.material as ShaderMaterial).set_shader_parameter("interpolation", blend)


func sync_emission(parent: Node2D) -> void:
	parent.position = origin
	if not emissions.is_empty() and not is_instance_valid(emissions[0]):
		emissions.clear()
	while emissions.size() < groups.size():
		var index := emissions.size()
		var copy := MultiMeshInstance2D.new()
		copy.multimesh = groups[index].multimesh
		copy.material = groups[index].material.duplicate()
		(copy.material as ShaderMaterial).set_shader_parameter("emission_only", true)
		parent.add_child(copy)
		emissions.append(copy)
	for index in emissions.size():
		emissions[index].visible = groups[index].visible
		(emissions[index].material as ShaderMaterial).set_shader_parameter("interpolation", blend)


func add_group(parent: Node2D) -> void:
	var geometry := QuadMesh.new()
	geometry.size = Vector2.ONE
	geometry.center_offset = Vector3(0.5, 0.5, 0)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.mesh = geometry
	mesh.instance_count = GROUP
	var buffer := PackedFloat32Array()
	buffer.resize(GROUP * STRIDE)
	buffers.append(buffer)
	var values := PackedFloat32Array()
	values.resize(GROUP * 12)
	data.append(values)
	var texture := ImageTexture.create_from_image(Image.create_from_data(GROUP, 3, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	textures.append(texture)
	var layers: Array[Image] = []
	layers.resize(GROUP)
	layers.fill(blank)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	masks.append(array)
	var ids := PackedInt64Array()
	ids.resize(GROUP)
	ids.fill(blank.get_instance_id())
	identities.append(ids)
	layer_keys.append({})
	var shader := ShaderMaterial.new()
	shader.shader = SHADER
	shader.set_shader_parameter("artwork", artwork)
	shader.set_shader_parameter("lamps", emission)
	shader.set_shader_parameter("masks", array)
	shader.set_shader_parameter("parameters", texture)
	var node := MultiMeshInstance2D.new()
	node.multimesh = mesh
	node.material = shader
	parent.add_child(node)
	groups.append(node)
