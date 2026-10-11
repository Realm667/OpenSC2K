extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")
var failures := 0
var app: CityApplication

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in 12:
		await process_frame

func check_fit(window: Window, body: Control, description: String) -> void:
	var available := app.get_viewport().get_visible_rect().size
	check(window.size.y <= available.y - 68, description + " stays inside screen")
	var content_bottom := body.position.y + body.get_combined_minimum_size().y
	var scroll := body.get_parent() as ScrollContainer
	if window.size.y < available.y - 72:
		check(content_bottom <= scroll.size.y + 1, description + " does not clip the bottom action")
		check(scroll.size.y - content_bottom < 20, description + " has no empty lower area")

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1440, 1000)
	app = load("res://main.tscn").instantiate()
	AppFixture.configure(app)
	root.add_child(app)
	await settle()
	for theme in ["dark", "light"]:
		AppUiTheme.select(theme)
		for locale in ["en", "de"]:
			TranslationServer.set_locale(locale)
			for role in [0, 1]:
				app.coop.launch.role.select(role)
				for mode in [0, 1, 2]:
					app.coop.mode_picker.select(mode)
					app.coop.launch.update()
					app.coop.open()
					await settle()
					check_fit(app.coop.panel, app.coop.lobby.get_parent(), "%s %s role %d mode %d" % [theme, locale, role, mode])
	app.coop.panel.hide()
	app.coop.windows.seats.open()
	await settle()
	check_fit(app.coop.windows.seats.window, app.coop.windows.seats.body, "empty seat picker")
	app.coop.windows.seats.window.hide()
	app.coop.port.min_value = 0
	app.coop.port.value = 0
	app.coop.mode_picker.select(1)
	app.coop.host_document(Sc2xDocument.create_empty(32, "Drag check").document)
	app.coop.session.waiting_for_start = false
	app.coop.session.request({"kind": "speed", "speed": 2})
	await settle()
	app.map_view.selection_start = Vector2i(3, 3)
	app.map_view.selection_end = Vector2i(6, 6)
	app.preferences.visual_enhancements.weather_enabled = true
	app.preferences.visual_enhancements.weather_mode = 1
	app.preferences.visual_enhancements.pause_freezes = true
	var before := app.visual_environment.weather.clock
	app.visual_environment.process(0.25)
	check(app.visual_environment.weather.clock > before, "held tool does not freeze weather")
	check(app.visual_environment.network_snapshot().weather[20] == 0, "held tool does not send a pause to clients")
	check(not app.map_view.layers.environment_parameters.get("water_frozen", true), "held tool does not freeze water")
	app.coop.session.request({"kind": "speed", "speed": 1})
	app.visual_environment.process(0.25)
	check(app.visual_environment.network_snapshot().weather[20] == 1, "explicit host pause still freezes weather")
	app.map_view.selection_start = Vector2i(-1, -1)
	app.coop.windows.open_scoreboard()
	await settle()
	check_fit(app.coop.windows.scoreboard, app.coop.windows.score_rows, "scoreboard")
	check(app.coop.windows.scores.picker is HFlowContainer and app.coop.windows.scores.metric_picker is HFlowContainer, "both statistics selectors are wrapping tabs")
	app.coop.windows.scores.picker.select(6)
	app.coop.windows.scores.rebuild()
	await settle()
	check_fit(app.coop.windows.scoreboard, app.coop.windows.score_rows, "history")
	app.coop.leave()
	app.queue_free()
	await process_frame
	print("Multiplayer dialog checks: %d failures" % failures)
	quit(1 if failures else 0)
