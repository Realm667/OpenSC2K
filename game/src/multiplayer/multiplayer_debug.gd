class_name MultiplayerDebug
extends RefCounted
## Debug mutations use the same authoritative actor-to-city mapping as tools.

static func execute(session: CoopSession, actor: String, request: Dictionary) -> Dictionary:
	if actor != session.token:
		return CoopWorld.rejected("Only the host can use debug actions.")
	var world: CoopWorld = session.world.municipalities[actor] if session.world is SharedWorld else session.world
	var city := world.city
	var before_state := audit_value(world, str(request.get("action", "")))
	var document := city.document
	var action: String = str(request.get("action", ""))
	if action in ["no_disasters", "end_disaster", "run_to_date"] and actor != session.token:
		return CoopWorld.rejected("Only the host can control disasters and simulation time.")
	var result: CityDebugActions.Result
	match action:
		"add_funds", "set_funds":
			if not CoopWorld.whole_number(request.get("value"), -2147483648, 2147483647):
				return CoopWorld.rejected("Invalid debug value.")
			result = CityDebugActions.add_funds(city, int(request.value)) if action == "add_funds" else CityDebugActions.set_funds(city, int(request.value))
		"unlock":
			result = CityDebugActions.unlock_everything(city, document)
		"no_disasters":
			if not request.get("value") is bool:
				return CoopWorld.rejected("Invalid debug value.")
			result = CityDebugActions.set_no_disasters(city, request.value)
		"end_disaster":
			result = CityDebugActions.end_disaster(city, document, world.engine)
		"military":
			if not CoopWorld.whole_number(request.get("value"), 0, 5):
				return CoopWorld.rejected("Invalid debug value.")
			result = CityDebugActions.offer_military_base(world.controller, int(request.value))
		"remove_things":
			if not CoopWorld.whole_number(request.get("value"), 0, CityDebugActions.DELETE_KINDS.size() - 1):
				return CoopWorld.rejected("Invalid debug value.")
			result = CityDebugActions.remove_moving_things(city, document, CityDebugActions.DELETE_KINDS[int(request.value)][1])
		"maxis", "spawn", "nessie":
			if not world.point_valid(request.get("point")):
				return CoopWorld.rejected("Invalid debug value.")
			var point := world.point(request.point)
			if action == "maxis":
				result = CityDebugActions.dispatch_maxis_man(city, document, point)
			elif action == "nessie":
				result = CityDebugActions.summon_nessie(city, document, world.engine, point, Time.get_ticks_usec() & 0x7fffffff)
			else:
				if not CoopWorld.whole_number(request.get("value"), 0, 4):
					return CoopWorld.rejected("Invalid debug value.")
				result = CityDebugActions.spawn_moving_thing(city, document, world.engine, int(request.value), point, Time.get_ticks_usec() & 0x7fffffff)
		"run_to_date":
			if not CoopWorld.whole_number(request.get("month"), 1, 12) or not CoopWorld.whole_number(request.get("day"), 1, 25) or not CoopWorld.whole_number(request.get("year"), city.current_year(), 9999) or not CoopWorld.whole_number(request.get("value"), 1, 5):
				return CoopWorld.rejected("Invalid debug value.")
			var target := CityDebugActions.age_for_date(city, int(request.month), int(request.day), int(request.year))
			if target <= city.age_in_days():
				return CoopWorld.rejected("Choose a date after the current date.")
			world.controller.pause_at_day = target
			session.requested_speed[session.token] = maxi(2, int(request.value))
			session.disconnected_pause = false
			session.apply_speed()
			session.announce_admin(actor, city.city_name(), "Debug · " + action.replace("_", " "), str(city.age_in_days()), str(target))
			return CoopWorld.accepted("Debug action applied to your city.")
		_:
			return CoopWorld.rejected("Invalid debug action.")
	if not result.ok:
		return CoopWorld.rejected(result.error)
	world.undo_document = null
	world.revision += 1
	if world != session.world:
		session.world.revision += 1
	session.statistics_cache.clear()
	session.announce_admin(actor, city.city_name(), "Debug · " + action.replace("_", " "), before_state, audit_value(world, action))
	return CoopWorld.accepted("Debug action applied to your city.")

static func audit_value(world: CoopWorld, action: String) -> String:
	match action:
		"add_funds", "set_funds":
			return "$%d" % world.city.funds()
		"no_disasters":
			return "Enabled" if world.city.no_disasters_enabled() else "Disabled"
		"unlock":
			var misc: PackedByteArray = world.city.document.find_chunk("MISC").decoded_payload
			return "Progression: %d · Reward flags: %d" % [BinaryData.read_u32_be(misc, ToolAvailability.MISC_PROGRESSION), BinaryData.read_u32_be(misc, ToolAvailability.MISC_GRANTED_REWARDS)]
		"end_disaster":
			return str(world.engine.active_disaster_type)
		"military":
			return world.engine.pending_interaction
	return "Buildings: %d · Moving objects: %d" % [world.city.buildings.size() - world.city.buildings.count(0), ThingData.count(world.city.document.find_chunk("XTHG").decoded_payload)]
