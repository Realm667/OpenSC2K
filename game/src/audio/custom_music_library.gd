class_name CustomMusicLibrary
extends RefCounted
## User-owned MP3s. Relative paths keep playlists portable when the game moves.

var folder: String
var tracks: Array[String] = []
var folders: Array[String] = []


func _init(root_folder := "") -> void:
	folder = root_folder if not root_folder.is_empty() else AppPaths.path("music")


static func valid_id(id: String) -> bool:
	if id.is_empty() or id.is_absolute_path() or ":" in id or "\\" in id or id.get_extension().to_lower() != "mp3":
		return false
	for part in id.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true


func refresh() -> void:
	tracks.clear()
	folders.clear()
	_scan("")
	tracks.sort()
	folders.sort()


func _scan(relative: String) -> void:
	var directory := DirAccess.open(folder.path_join(relative))
	if directory == null:
		return
	for name in directory.get_files():
		var id := name if relative.is_empty() else relative.path_join(name)
		if not directory.is_link(name) and valid_id(id):
			tracks.append(id)
	for name in directory.get_directories():
		if not directory.is_link(name):
			var child := name if relative.is_empty() else relative.path_join(name)
			# Installed music packs have their own source in the music box.
			# Keep old custom IDs resolvable without listing the same songs twice.
			if PackLibrary.is_music_package(folder.path_join(child)):
				continue
			folders.append(child)
			_scan(child)


func resolve(id: String) -> String:
	if not valid_id(id):
		return ""
	var path := folder
	for part in id.split("/"):
		var directory := DirAccess.open(path)
		if directory == null or directory.is_link(part):
			return ""
		path = path.path_join(part)
	return path if FileAccess.file_exists(path) else ""
