extends SceneTree

const Main = preload("res://src/main.gd")


func _initialize() -> void:
	var host := Main.new()
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	host.simulation_state.speed_controller = GameSpeedController.new(SimulationEngine.new(city, 1, 2, 3))
	for linked in [true, false]:
		host.preferences.visual_enhancements.speed_link = linked
		for speed in range(GameSpeedController.Speed.TURTLE, GameSpeedController.Speed.AFRICAN_SWALLOW + 1):
			host.simulation_state.speed_controller.set_speed(speed)
			var before := SimulationSnapshot.stamp(host.simulation_state.speed_controller)
			host.palette_clock.cycle_ticks = 0
			host.palette_clock.elapsed_msec = 0.0
			# No simulation result is delivered, as with a pending worker job.
			for frame in 61:
				host.frame._advance_palette_animation(1.0 / 60.0, false)
			var factor: float = [1.0, 1.5, 2.0, 3.0][speed - 2] if linked else 1.0
			var elapsed := host.palette_clock.cycle_ticks * GameSpeedController.BASE_TICK_MSEC + host.palette_clock.elapsed_msec
			assert(is_equal_approx(elapsed, 1000.0 * 61.0 / 60.0 * factor), "Display speed must use the selected cosmetic factor exactly once")
			host.frame._advance_palette_animation(-1.0, false)
			assert(SimulationSnapshot.stamp(host.simulation_state.speed_controller) == before, "Animation cannot advance simulation state")
	host.frame._advance_palette_animation(1.0, true)
	assert(host.palette_clock.cycle_ticks == 5, "Modal pause freezes display clock")
	host.simulation_state.speed_controller.set_speed(GameSpeedController.Speed.PAUSED)
	host.frame._advance_palette_animation(1.0, false)
	assert(host.palette_clock.cycle_ticks == 5, "Paused speed freezes display clock")
	host.free()
	print("PASS: linked and unlinked display speeds, independent palette clock, simulation isolation and pause")
	quit()
