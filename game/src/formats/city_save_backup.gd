class_name CitySaveBackup
extends RefCounted
## Keep one verified predecessor of a manual save. Autosaves opt out.


static func create(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > Sc2xDocument.MAX_ARCHIVE_BYTES:
		return _failure()
	var bytes := source.get_buffer(source.get_length())
	var complete := bytes.size() == source.get_length()
	source.close()
	if not complete:
		return _failure()
	var previous := Sc2File.new()
	# Never replace a good backup with an already damaged city file.
	if not previous.parse(bytes):
		return ""
	# The native writer stages, reads back, checks, and atomically replaces
	# the backup. The current save remains untouched if this fails.
	var result := CityFileStore.write_verified(path + ".bak", bytes)
	return "" if result.ok else _failure()


static func _failure() -> String:
	return TranslationServer.translate("Cannot create the backup. The city was not saved.")
