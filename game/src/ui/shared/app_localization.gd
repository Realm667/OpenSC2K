class_name AppLocalization
extends RefCounted
## The interface language. Source text and message keys stay English; a
## translation changes only what the interface shows. Saved settings, cities,
## tool IDs, and report IDs do not change.
##
## Pretendard (SIL OFL 1.1, https://github.com/orioncactus/pretendard) supplies
## the Hangul glyphs. It is a fallback of the interface fonts, so Latin text
## keeps its usual font.

const DEFAULT := "en"
# language code -> name in that language. Each code other than English has a
# translation in res://assets/localization
const LANGUAGES: Dictionary[String, String] = {
	"en": "English", "de": "Deutsch", "es": "Español", "fr": "Français", "it": "Italiano", "ko": "한국어",
	"pt_BR": "Português (Brasil)",
}
const TRANSLATIONS: Dictionary[String, String] = {
	"de": "res://assets/localization/de.po",
	"es": "res://assets/localization/es.po",
	"fr": "res://assets/localization/fr.po",
	"it": "res://assets/localization/it.po",
	"ko": "res://assets/localization/ko.po",
	"pt_BR": "res://assets/localization/pt_BR.po",
}
const REGULAR_FONT = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
const BOLD_FONT = preload("res://assets/fonts/pretendard/Pretendard-Bold.otf")

static var _loaded := false
static var _message_patterns: Array[Dictionary] = []


static func normalize(value: Variant) -> String:
	return str(value) if LANGUAGES.has(str(value)) else DEFAULT


# The language codes in the order of the Settings list.
static func codes() -> Array[String]:
	return LANGUAGES.keys()


static func ensure_loaded() -> void:
	if not _loaded:
		for code: String in TRANSLATIONS:
			TranslationServer.add_translation(load(TRANSLATIONS[code]) as Translation)
		_loaded = true


static func select(value: String) -> void:
	ensure_loaded()
	TranslationServer.set_locale(normalize(value))


# Legacy network feedback arrives already formatted in the source language.
# Translate its template locally; never translate player names or saved data.
static func message(value: String) -> String:
	ensure_loaded()
	var translated := str(TranslationServer.translate(value))
	if translated != value or TranslationServer.get_locale().begins_with("en"):
		return translated
	if _message_patterns.is_empty():
		var sources: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/formatted_messages.json"))
		for source: String in sources:
			var pattern := "^"
			var types: Array[String] = []
			var index := 0
			while index < source.length():
				var character := source[index]
				if character == "%" and index + 1 < source.length():
					var next := source[index + 1]
					if next in ["d", "s"]:
						types.append(next)
						pattern += "(-?[0-9]+)" if next == "d" else "(.*?)"
						index += 2
						continue
					if next == "%":
						index += 1
				pattern += ("\\" if character in "\\.^$|?*+()[]{}" else "") + character
				index += 1
			_message_patterns.append({"regex": RegEx.create_from_string(pattern + "$"), "source": source, "types": types})
	for pattern: Dictionary in _message_patterns:
		var found: RegExMatch = pattern.regex.search(value)
		if found == null:
			continue
		var arguments: Array = []
		for index in pattern.types.size():
			arguments.append(int(found.get_string(index + 1)) if pattern.types[index] == "d" else found.get_string(index + 1))
		return str(TranslationServer.translate(pattern.source)) % arguments
	return value


# `font` with the Hangul fallback font. `bold` selects the bold fallback.
static func with_fallback(font: Font, bold := false) -> Font:
	if font == null:
		return null

	var fallback: Font = BOLD_FONT if bold else REGULAR_FONT

	if not fallback in font.fallbacks:
		font.fallbacks = font.fallbacks + [fallback]

	return font
