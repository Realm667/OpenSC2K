class_name MultiplayerText
extends RefCounted
## Feature-local PO catalog uses the locale selected by AppLocalization in the
## integrated build, without importing the independent language feature branch.

static var loaded := false
static var patterns: Array = []

static func setup() -> void:
	if loaded:
		return
	var translation := load("res://assets/localization/multiplayer.de.po") as Translation
	TranslationServer.add_translation(translation)
	for source in translation.get_message_list():
		if not "%" in source:
			continue
		var pattern := "^"
		var types: Array = []
		var index := 0
		while index < source.length():
			var character := source[index]
			if character == "%" and index + 1 < source.length() and source[index + 1] in ["d", "s"]:
				types.append(source[index + 1])
				pattern += "(-?[0-9]+)" if source[index + 1] == "d" else "(.*?)"
				index += 2
				continue
			pattern += ("\\" if character in "\\.^$|?*+()[]{}" else "") + character
			index += 1
		patterns.append({"regex": RegEx.create_from_string(pattern + "$"), "source": source, "types": types})
	loaded = true

static func message(value: String) -> String:
	setup()
	var translated := str(TranslationServer.translate(value))
	if translated != value or not TranslationServer.get_locale().begins_with("de"):
		return translated
	for pattern: Dictionary in patterns:
		var found: RegExMatch = pattern.regex.search(value)
		if found == null:
			continue
		var arguments: Array = []
		for index in pattern.types.size():
			arguments.append(int(found.get_string(index + 1)) if pattern.types[index] == "d" else found.get_string(index + 1))
		return str(TranslationServer.translate(pattern.source)) % arguments
	return value
