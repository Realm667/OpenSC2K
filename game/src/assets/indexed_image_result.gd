class_name IndexedImageResult
extends RefCounted

var ok := false
var error := ""
var width := 0
var height := 0
var pixels := PackedInt32Array()
var colors: Array[Color] = []
var palette: Sc2Palette
var top_down := false
var remapped_color_count := 0
var image: Image
var rows := 0
var consumed := 0


static func failure(message: String) -> IndexedImageResult:
	var result := IndexedImageResult.new()
	result.error = message

	return result


func render_image() -> Image:
	if image != null:
		return image
	return Sc2SpriteArchive.entry_from_indices(0, width, height, pixels).create_image(palette).image
