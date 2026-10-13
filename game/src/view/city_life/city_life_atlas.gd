class_name CityLifeAtlas
extends RefCounted
## Pack occupied world squares into one reusable artwork/emission atlas. Empty
## city pixels never need clearing or uploading, and all squares share a draw batch.
@warning_ignore_start("integer_division")

const EDGE := 64
var image: Image
var texture: ImageTexture
var emission: Image
var emission_texture: ImageTexture
var destinations: Array[Rect2i] = []
var sources: Array[Rect2i] = []
var capacity := 0
var source_scale := 1
var scaled_occluders: Dictionary[int, Image] = {}


func compose(bounds: Rect2i, entries: Array[Dictionary], night: bool) -> void:
	var wanted_scale := 1
	for entry in entries:
		var master: Image = entry.get("master", entry.sprite)
		wanted_scale = maxi(wanted_scale, master.get_width() / entry.sprite.get_width())
	if wanted_scale != source_scale:
		source_scale = wanted_scale
		capacity = 0
		image = null
		scaled_occluders.clear()
	var live_occluders: Dictionary[int, bool] = {}
	var squares: Dictionary[Vector2i, Array] = {}
	for entry in entries:
		var clipped := Rect2i(entry.origin, entry.sprite.get_size()).intersection(bounds)
		if not clipped.has_area():
			continue
		var first := (clipped.position - bounds.position) / EDGE
		var last := (clipped.end - Vector2i.ONE - bounds.position) / EDGE
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var square := Vector2i(x, y)
				if not squares.has(square):
					squares[square] = []
				# Input is already in painter order, including partially faded figures.
				squares[square].append(entry)
	if squares.size() > capacity:
		capacity = maxi(16, nearest_po2(squares.size()))
		var columns := 16 if capacity <= 1024 else 64
		image = Image.create(columns * EDGE * source_scale, maxi(1, ceili(float(capacity) / columns)) * EDGE * source_scale, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)
	if image == null:
		capacity = 16
		image = Image.create(16 * EDGE * source_scale, EDGE * source_scale, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)
	if night and (emission == null or emission.get_size() != image.get_size()):
		emission = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
		emission_texture = ImageTexture.create_from_image(emission)
	image.fill(Color.TRANSPARENT)
	if night:
		emission.fill(Color.TRANSPARENT)
	destinations.clear()
	sources.clear()
	var columns := image.get_width() / (EDGE * source_scale)
	for square in squares:
		var slot := destinations.size()
		var world := Rect2i(bounds.position + square * EDGE, Vector2i.ONE * EDGE).intersection(bounds)
		var target := Rect2i(Vector2i(slot % columns, slot / columns) * EDGE * source_scale, world.size * source_scale)
		destinations.append(Rect2i(world.position - bounds.position, world.size))
		sources.append(target)
		for entry: Dictionary in squares[square]:
			var sprite: Image = CityLifeGpu._scaled(entry.get("master", entry.sprite), entry.sprite.get_size() * source_scale)
			var lamps: Image = entry.get("master_lamps", entry.lamps)
			if lamps != null:
				lamps = CityLifeGpu._scaled(lamps, sprite.get_size())
			var occluders: Array = entry.occluders
			if source_scale > 1:
				occluders = []
				for original: Dictionary in entry.occluders:
					var id: int = original.image.get_instance_id()
					live_occluders[id] = true
					if not scaled_occluders.has(id):
						scaled_occluders[id] = CityLifeGpu._scaled(original.image, original.image.get_size() * source_scale)
					occluders.append({"image": scaled_occluders[id], "origin": original.origin * source_scale})
			CityLifeCanvas.stamp(image, world.position * source_scale - target.position, sprite, entry.origin * source_scale,
				occluders, entry.opacity, emission if night else null, lamps, target)
	for id in scaled_occluders.keys():
		if not live_occluders.has(id):
			scaled_occluders.erase(id)
	texture.update(image)
	if night:
		emission_texture.update(emission)
