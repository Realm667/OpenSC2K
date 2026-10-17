extends SceneTree


func _initialize() -> void:
	for kind: String in ["graphics", "sound", "music"]:
		var folder := PackLibrary.default_folder(kind)
		assert(FileAccess.file_exists(folder.path_join("pack.json")), "Missing supplied " + kind)
		assert(str(PackLibrary.inspect(kind, folder).error).is_empty(), "Invalid supplied " + kind)
		assert(not PackLibrary.scan(kind).is_empty(), "Supplied pack missing from selector")
	if OS.has_feature("macos"):
		assert(not AppPaths.is_portable(), "macOS must keep personal data outside the signed app")
		assert(not AppPaths.root().begins_with(OS.get_executable_path().get_base_dir().get_base_dir()))
	print("PASS: exported application finds all replacement packs; personal storage is separate")
	quit()
