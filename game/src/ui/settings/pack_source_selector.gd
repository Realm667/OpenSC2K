class_name PackSourceSelector
extends OptionButton
## A menu over the existing path field, so external and missing paths survive.

var kind := ""
var path_edit: LineEdit
var status_label: Label


func bind(source_kind: String, edit: LineEdit, label: Label) -> void:
	kind = source_kind
	path_edit = edit
	status_label = label
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	fit_to_longest_item = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_selected.connect(_select_source)
	path_edit.text_changed.connect(func(_value: String) -> void: sync_selection())
	rescan()


func rescan(library_root := AppPaths.root()) -> void:
	clear()
	add_item(tr("None") if kind == "hd" else tr("Automatic"))
	set_item_metadata(0, "")
	select(0)
	var chosen := PackLibrary.normalized(path_edit.text.strip_edges(), kind)
	var entries := PackLibrary.selection_entries(kind, chosen, library_root)
	var counts := {}
	for item in entries:
		counts[item.name] = int(counts.get(item.name, 0)) + 1
	for item in entries:
		var display := str(item.name)
		if counts[item.name] > 1:
			var source := str(item.path).get_base_dir() if kind in PackLibrary.FORMATS else str(item.path)
			var base := ProjectSettings.globalize_path(library_root).replace("\\", "/").simplify_path()
			display += " — " + source.trim_prefix(base + "/")
		if not str(item.error).is_empty():
			display = tr("%s (unavailable)") % display
		add_item(display)
		var index := item_count - 1
		set_item_metadata(index, item.path)
		set_item_tooltip(index, str(item.path) + ("\n" + str(item.error) if not str(item.error).is_empty() else ""))
		set_item_disabled(index, not str(item.error).is_empty())
		if _same_path(str(item.path), chosen):
			select(index)
			status_label.text = item.error
			status_label.tooltip_text = str(item.path) + "\n" + str(item.error)
	tooltip_text = get_item_tooltip(selected)


func sync_selection() -> void:
	var chosen := PackLibrary.normalized(path_edit.text.strip_edges(), kind)
	for index in item_count:
		if _same_path(str(get_item_metadata(index)), chosen):
			select(index)
			return
	# Keep text typed for an external source; it is validated on submission.
	select(-1)


func _same_path(first: String, second: String) -> bool:
	return first.nocasecmp_to(second) == 0 if OS.has_feature("windows") else first == second


func _select_source(index: int) -> void:
	path_edit.text = str(get_item_metadata(index))
	status_label.text = ""
	tooltip_text = get_item_tooltip(index)
