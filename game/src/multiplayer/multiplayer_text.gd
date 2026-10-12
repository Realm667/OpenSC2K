class_name MultiplayerText
extends RefCounted
## Compatibility entry point. All translations and formatted-message handling
## live in the central AppLocalization catalog service.


static func setup() -> void:
	AppLocalization.ensure_loaded()


static func message(value: String) -> String:
	return AppLocalization.message(value)
