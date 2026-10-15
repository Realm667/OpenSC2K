class_name TrueColorPackImage
extends RefCounted
## Literal pixels plus optional logical material addresses for legacy geometry.
## Masks store the address in red; their alpha is coverage, never a visual color.


static func decode(source: Image, palette: Sc2Palette, semantic: Image = null) -> IndexedImageResult:
	if source == null or source.is_empty() or palette == null or not palette.is_valid():
		return IndexedImageResult.failure("Invalid PNG pixels or palette")
	if semantic != null and semantic.get_size() != source.get_size():
		return IndexedImageResult.failure("Invalid PNG pixels or palette")
	var result := IndexedImageResult.new()
	result.ok = true
	result.width = source.get_width()
	result.height = source.get_height()
	result.palette = palette
	result.image = source
	result.pixels.resize(result.width * result.height)
	var colors := source.get_data()
	var mask := semantic.get_data() if semantic != null else PackedByteArray()
	for pixel in result.pixels.size():
		var offset := pixel * 4
		result.pixels[pixel] = -1 if colors[offset + 3] == 0 else (int(mask[offset]) if not mask.is_empty() and mask[offset + 3] > 0 else 0)
	return result
