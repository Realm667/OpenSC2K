class_name MultiplayerLaunchMenu
extends RefCounted

var owner_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return owner_ref.get_ref()
var role: OptionButton
var host_fields: VBoxContainer
var address_box: VBoxContainer
var password_label: Label
var action: Button
var shared_fields: VBoxContainer
var land_price: SpinBox
var goal_fields: VBoxContainer
var goal_picker: OptionButton
var goal_target: SpinBox

func _init(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)

func setup(body: VBoxContainer) -> void:
	MultiplayerText.setup()
	ApplicationMultiplayer.label(body, tr("LAN / direct IP · up to 8 players · matching game versions required."))
	coop.lobby = VBoxContainer.new()
	body.add_child(coop.lobby)
	role = OptionButton.new()
	role.add_item(tr("Host game"))
	role.add_item(tr("Join / Reconnect"))
	coop.lobby.add_child(role)
	var identity := HBoxContainer.new()
	coop.lobby.add_child(identity)
	var names := column(identity, 2)
	coop.player = ApplicationMultiplayer.field(names, tr("Player name"), "Mayor")
	var colors := column(identity, 1)
	ApplicationMultiplayer.label(colors, tr("Player colour"))
	var swatches := HBoxContainer.new()
	colors.add_child(swatches)
	var selection := ButtonGroup.new()
	coop.color_picker = ColorPickerButton.new()
	coop.color_picker.color = Color("46b4ff")
	coop.color_picker.edit_alpha = false
	coop.color_picker.text = "…"
	coop.color_picker.tooltip_text = tr("Custom colour…")
	coop.color_picker.custom_minimum_size = Vector2(34, 28)
	for value in ["46b4ff", "ff9c40", "66cf79", "e77ba8", "c7a0ff", "ffe173"]:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = selection
		button.custom_minimum_size = Vector2(22, 28)
		var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		image.fill(Color(value))
		button.icon = ImageTexture.create_from_image(image)
		button.tooltip_text = "#" + value
		button.button_pressed = value == "46b4ff"
		swatches.add_child(button)
		button.pressed.connect(func() -> void:
			coop.color_picker.color = Color(value)
			coop.color_picker.color_changed.emit(Color(value)))
		coop.color_picker.color_changed.connect(func(color: Color) -> void:
			button.set_pressed_no_signal(color.to_html(false) == value))
	swatches.add_child(coop.color_picker)
	host_fields = VBoxContainer.new()
	coop.lobby.add_child(host_fields)
	ApplicationMultiplayer.label(host_fields, tr("Game mode"))
	coop.mode_picker = OptionButton.new()
	for title in ["Co-op", "Competitive Shared", "Competitive Region"]:
		coop.mode_picker.add_item(tr(title))
	host_fields.add_child(coop.mode_picker)
	ApplicationMultiplayer.label(host_fields, tr("City"))
	coop.city_picker = OptionButton.new()
	coop.city_picker.add_item(tr("New city"))
	coop.city_picker.add_item(tr("Saved city"))
	host_fields.add_child(coop.city_picker)
	coop.use_current = CheckBox.new()
	coop.use_current.text = tr("Create a copy")
	coop.use_current.tooltip_text = tr("Keep the selected save unchanged and save this game separately.")
	coop.use_current.button_pressed = true
	host_fields.add_child(coop.use_current)
	shared_fields = VBoxContainer.new()
	host_fields.add_child(shared_fields)
	ApplicationMultiplayer.label(shared_fields, tr("Neutral land price per tile"))
	land_price = SpinBox.new()
	land_price.min_value = 0
	land_price.max_value = 1000
	land_price.value = 5
	land_price.prefix = "$"
	shared_fields.add_child(land_price)
	var note := ApplicationMultiplayer.label(shared_fields, tr("Each city receives a separate starter land allowance for up to 1,024 tiles (at most a quarter of the map). City funds stay intact. Saved games retain their rules."))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_fields = VBoxContainer.new()
	host_fields.add_child(goal_fields)
	ApplicationMultiplayer.label(goal_fields, tr("Victory goal"))
	goal_picker = OptionButton.new()
	for title in ["Endless game", "Population", "Wealth (funds minus debt)"]:
		goal_picker.add_item(tr(title))
	goal_fields.add_child(goal_picker)
	goal_target = SpinBox.new()
	goal_target.min_value = 1
	goal_target.max_value = 2147483647
	goal_target.value = 10000
	goal_fields.add_child(goal_target)
	goal_picker.item_selected.connect(func(index: int) -> void:
		goal_target.value = 100000 if index == 2 else 10000
		update())
	var network := HBoxContainer.new()
	coop.lobby.add_child(network)
	address_box = column(network, 2)
	coop.address = ApplicationMultiplayer.field(address_box, tr("Host address"), "127.0.0.1")
	var ports := column(network, 1)
	ApplicationMultiplayer.label(ports, tr("TCP port"))
	coop.port = SpinBox.new()
	coop.port.min_value = 1024
	coop.port.max_value = 65535
	coop.port.value = 20000
	ports.add_child(coop.port)
	password_label = ApplicationMultiplayer.label(coop.lobby, "")
	coop.join_code = LineEdit.new()
	coop.join_code.secret = true
	coop.lobby.add_child(coop.join_code)
	action = ApplicationMultiplayer.button(coop.lobby, "", func() -> void:
		if role.selected == 0:
			coop.start_host()
		else:
			coop.start_join())
	role.item_selected.connect(func(_index: int) -> void: update())
	coop.mode_picker.item_selected.connect(func(_index: int) -> void: update())
	coop.city_picker.item_selected.connect(func(_index: int) -> void:
		coop.selected_city_path = ""
		update())
	update()

func update() -> void:
	var hosting := role.selected == 0
	host_fields.visible = hosting
	address_box.visible = not hosting
	password_label.text = tr("Password (optional)") if hosting else tr("Password")
	action.text = tr("Create game") if hosting else tr("Join / Reconnect")
	coop.use_current.visible = coop.city_picker.selected == 1
	shared_fields.visible = coop.mode_picker.selected == 1 and coop.city_picker.selected == 0
	goal_fields.visible = coop.mode_picker.selected != 0 and coop.city_picker.selected == 0
	goal_target.visible = goal_picker.selected != 0
	fit.call_deferred()

func fit() -> void:
	if not is_instance_valid(coop.panel):
		return
	var available := coop.app.get_viewport().get_visible_rect().size
	var height := int(coop.lobby.get_combined_minimum_size().y) + 115
	coop.panel.size = Vector2i(mini(700, int(available.x) - 40), mini(height, int(available.y) - 70))

static func column(parent: Control, ratio: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = ratio
	parent.add_child(box)
	return box
