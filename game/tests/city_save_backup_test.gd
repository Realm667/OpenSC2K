extends SceneTree
## Manual overwrites retain one valid predecessor without changing autosaves.


func _initialize() -> void:
	var folder := OS.get_user_data_dir().path_join("save-backup-tests")
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	for format in ["sc2", "scn", "sc2kfix", "extended"]:
		var document := Sc2xDocument.create_empty(16, "Backup test").document if format == "extended" else EmptyCityTemplate.create()
		if format == "scn":
			var chunk := Sc2Chunk.new()
			chunk.chunk_id = "SCEN"
			var scenario := PackedByteArray()
			scenario.resize(52)
			chunk.set_decoded_payload(scenario)
			document.chunks.append(chunk)
			document.rebuild_chunk_cache()
		var extension: String = "sc2x" if format in ["extended", "sc2kfix"] else format
		var path := folder.path_join(format + "." + extension)
		assert(_save(document, path).ok)
		assert(not FileAccess.file_exists(path + ".bak"), "First save has no predecessor")
		var first := FileAccess.get_file_as_bytes(path)
		document.set_misc_i32(0x14, document.misc_i32(0x14) + 17)
		assert(_save(document, path).ok)
		assert(FileAccess.get_file_as_bytes(path + ".bak") == first)
		var second := FileAccess.get_file_as_bytes(path)
		assert(second != first and Sc2File.load_path(path + ".bak").is_valid())
		document.set_misc_i32(0x14, document.misc_i32(0x14) + 29)
		assert(_save(document, path).ok)
		assert(FileAccess.get_file_as_bytes(path + ".bak") == second, "Backup rotates to the immediate predecessor")
		var latest := FileAccess.get_file_as_bytes(path)
		# Autosaves and other non-manual callers do not rotate the backup.
		var automatic := CityFileStore.prepare(document, path, "")
		assert(not automatic.backup_previous and CityFileStore.write(automatic).ok)
		assert(FileAccess.get_file_as_bytes(path + ".bak") == second)
		var damaged := FileAccess.open(path, FileAccess.WRITE)
		damaged.store_buffer(PackedByteArray([1, 2, 3]))
		damaged.close()
		assert(_save(document, path).ok)
		assert(Sc2File.load_path(path).is_valid())
		assert(FileAccess.get_file_as_bytes(path + ".bak") == second, "A damaged target cannot destroy the last valid backup")
		# A backup destination that cannot be replaced must block the save.
		assert(DirAccess.remove_absolute(path + ".bak") == OK)
		assert(DirAccess.make_dir_absolute(path + ".bak") == OK)
		latest = FileAccess.get_file_as_bytes(path)
		document.set_misc_i32(0x14, document.misc_i32(0x14) + 41)
		assert(not _save(document, path).ok)
		assert(FileAccess.get_file_as_bytes(path) == latest, "Failed backup leaves the original city intact")
		assert(DirAccess.remove_absolute(path + ".bak") == OK)
		if format == "extended":
			var rejected := CityFileStore.prepare(document, path, "")
			rejected.backup_previous = true
			rejected.entries.members[Sc2xDocument.METADATA_ENTRY] = PackedByteArray([1, 2, 3])
			assert(not CityFileStore.write(rejected).ok)
			assert(FileAccess.get_file_as_bytes(path) == latest)
			assert(FileAccess.get_file_as_bytes(path + ".bak") == latest, "Failed new write retains a recoverable predecessor")
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.remove_absolute(path)
	assert(DirAccess.get_files_at(folder).is_empty(), "No staging files remain")
	DirAccess.remove_absolute(folder)
	print("PASS: manual predecessor backups, four save formats, rotation, corrupt targets, blocked backups, failed writes, and autosave exclusion")
	quit()


func _save(document: Sc2File, path: String) -> FileWriteResult:
	var prepared := CityFileStore.prepare(document, path, "")
	assert(prepared.ok, prepared.error)
	prepared.backup_previous = true
	return CityFileStore.write(prepared)