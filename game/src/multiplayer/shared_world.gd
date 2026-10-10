class_name SharedWorld
extends CoopWorld
## One physical terrain, separate municipal simulations and budgets.
## Each municipality simulates only its own infrastructure and zoned buildings.

const LAND_PRICE := 10
const TILE_CHUNKS := {"ALTM": 2, "XTER": 1, "XBLD": 1, "XZON": 1, "XUND": 1, "XBIT": 1}
var municipalities: Dictionary = {}
var actors: Array[String] = []
var owners := PackedInt32Array()
var template: Sc2File
var offers: Dictionary = {}
var next_offer := 1
var host_actor := ""
var snapshot_cache: Dictionary = {}


func open(document: Sc2File) -> bool:
	if not super.open(document):
		return false
	template = document.duplicate_document()
	template.sc2x_extra_entries.erase("multiplayer.json")
	owners.resize(city.map_size * city.map_size)
	owners.fill(0)
	return true


func add_player(actor: String) -> String:
	if municipalities.has(actor):
		return ""
	if actors.size() >= 8:
		return "The shared map already has eight municipalities."
	var document := template.duplicate_document()
	# Imported development belongs to the initial municipality. Guests get fresh
	# accounts and the same natural terrain, never a copy of the host's debts/assets.
	if not actors.is_empty():
		document = EmptyCityTemplate.create(template.map_size)
		var starting_year := city.founding_year() if city.founding_year() in NewCitySetup.STARTING_YEARS else 1900
		var fresh := NewCitySetup.create(document, document.city_name(), "Mayor", clampi(city.difficulty(), 1, 3), starting_year, SimRandom.new(actors.size() + 1))
		if not fresh.ok:
			return fresh.error
		document = Sc2xDocument.from_new_city(fresh.document, "City %d" % (actors.size() + 1), "Mayor").document
		for id in ["ALTM", "XTER", "XBIT"]:
			document.find_chunk(id).set_decoded_payload(template.find_chunk(id).decoded_payload.duplicate())
		var natural := template.find_chunk("XBLD").decoded_payload.duplicate()
		for index in natural.size():
			if natural[index] > 13:
				natural[index] = 0
		document.find_chunk("XBLD").set_decoded_payload(natural)
		for field in [Sc2MiscLayout.START_YEAR, Sc2MiscLayout.DIFFICULTY, Sc2MiscLayout.NO_DISASTERS]:
			document.set_misc_u32(field, template.misc_u32(field))
	var child := CoopWorld.new()
	if not child.open(document):
		return child.error
	child.city.set_age_in_days(city.age_in_days())
	child.engine.clock.city_days = city.age_in_days()
	child.controller.accumulator_msec = controller.accumulator_msec
	child.controller.subtick_counter = controller.subtick_counter
	municipalities[actor] = child
	actors.append(actor)
	revision += 1
	snapshot_cache.clear()
	if host_actor.is_empty():
		host_actor = actor
		city = child.city
		engine = child.engine
		controller = child.controller
		for tile in owners.size():
			if child.city.buildings[tile] > 13 or child.city.zones[tile] != 0 or child.city.underground[tile] != 0:
				owners[tile] = 1
	return ""


func set_shared_speed(value: int) -> void:
	for child: CoopWorld in municipalities.values():
		child.controller.set_speed(value)
	snapshot_cache.clear()


func advance(delta: float) -> void:
	for child: CoopWorld in municipalities.values():
		if child.controller.interaction_blocked or child.controller.terminal_blocked:
			return
	var changed := false
	var emergency := false
	for child: CoopWorld in municipalities.values():
		emergency = emergency or child.engine.active_disaster_type != 0
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		if emergency and child.engine.active_disaster_type == 0:
			continue
		var before := child.revision
		var before_document := child.city.document.duplicate_document(true)
		child.advance(delta)
		if child.revision != before:
			for tile: int in changed_tiles(before_document, child.city.document):
				tile_versions[tile] = revision + 1
		changed = changed or child.revision != before
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller
	if changed:
		revision += 1


func command(actor: String, request: Dictionary) -> Dictionary:
	if not municipalities.has(actor):
		return rejected("No municipality is assigned to this player.")
	if not whole_number(request.get("revision"), 0, revision):
		return rejected("Invalid map revision.")
	if request.get("kind") in ["land_buy", "land_offer", "land_accept"]:
		return land_command(actor, request)
	if request.get("kind") == "recall":
		for municipality: CoopWorld in municipalities.values():
			var things := municipality.city.document.find_chunk("XTHG").decoded_payload.duplicate()
			var text := municipality.city.text_overlays.duplicate()
			for key: String in municipality.dispatch_owners.keys():
				if municipality.dispatch_owners[key].actor == actor.sha256_text():
					remove_dispatch(things, text, int(key))
					municipality.dispatch_owners.erase(key)
			municipality.city.document.find_chunk("XTHG").set_decoded_payload(things)
			municipality.city.document.find_chunk("XTXT").set_decoded_payload(text)
			municipality.city.resync_mirrors(["XTXT"])
			municipality.revision += 1
		revision += 1
		return accepted("Your emergency units were recalled.")
	var child: CoopWorld = municipalities[actor]
	var local := request.duplicate(true)
	local.revision = child.revision
	if request.get("kind") == "disaster" and point_valid(request.get("point")):
		var target := point(request.point)
		if owners[city.index_of(target.x, target.y)] != actors.find(actor) + 1:
			return rejected("Manual disasters can only be started in your own municipality.")
	if request.get("kind") == "build" and request.get("group") == CityToolIds.Group.DISPATCH:
		return help_disaster(actor, request)
	if request.get("kind") in ["build", "sign"]:
		if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
			return rejected("Invalid map position.")
		var area := selected_tiles(request)
		var owner := actors.find(actor) + 1
		for tile: int in area:
			if owners[tile] != owner:
				return rejected("Buy this land before building here.")
			if tile_versions[tile] > int(request.revision):
				return rejected("This area changed. Review it before building.")
		for path_point: Variant in request.get("path", []):
			if not point_valid(path_point) or owners[city.index_of(int(path_point[0]), int(path_point[1]))] != owner:
				return rejected("The complete path must stay on your own land.")
		var before := child.city.document.duplicate_document()
		var before_stats := child.statistics.duplicate(true)
		var before_revision := child.revision
		var before_versions := child.tile_versions.duplicate()
		var before_dispatch := child.dispatch_owners.duplicate(true)
		var result := child.command(actor, local)
		if not result.get("ok", false):
			return result
		for tile: int in changed_tiles(before, child.city.document):
			if owners[tile] != owner:
				child.city = CityState.from_document(before)
				child.engine.city = child.city
				Sc2xCheckpoint.restore(child.controller, before.sc2x_metadata)
				child.statistics = before_stats
				child.revision = before_revision
				child.tile_versions = before_versions
				child.dispatch_owners = before_dispatch
				child.undo_document = null
				return rejected("The complete building or terrain edit must fit on your land.")
		statistics[actor] = child.statistics.get(actor, {})
		revision += 1
		for tile: int in changed_tiles(before, child.city.document):
			tile_versions[tile] = revision
		return result
	if request.get("kind") == "undo":
		return rejected("Undo is unavailable after ownership transactions in Shared.")
	if request.get("kind") == "decision" and request.get("accept") == true and child.engine.pending_interaction == "military_proposal":
		var land_error := military_land_error(actor)
		if not land_error.is_empty():
			return rejected(land_error)
	var result := child.command(actor, local)
	if result.get("ok", false):
		revision += 1
	return result


func help_disaster(actor: String, request: Dictionary) -> Dictionary:
	if not point_valid(request.get("finish")) or not whole_number(request.get("tool"), 0, 2):
		return rejected("Invalid emergency service target.")
	var target := point(request.finish)
	var owner := owners[city.index_of(target.x, target.y)]
	if owner == 0:
		return rejected("This land has no municipality to assist.")
	var receiver: CoopWorld = municipalities[actors[owner - 1]]
	var sender: CoopWorld = municipalities[actor]
	if receiver != sender and receiver.engine.active_disaster_type == 0:
		return rejected("Emergency assistance is available during a disaster.")
	var available := DispatchCommand.availability(sender.city)
	if not available.ok:
		return rejected(available.error)
	var tool := int(request.tool)
	var capacity: int = [available.police, available.fire, available.military][tool]
	if sender.engine.active_disaster_type != 0:
		capacity = sender.engine.dispatch_capacity[tool]
	if capacity <= 0:
		return rejected("Your city has no available units of this type.")
	var deployed := 0
	for municipality: CoopWorld in municipalities.values():
		for unit: Dictionary in municipality.dispatch_owners.values():
			if unit.actor == actor.sha256_text() and int(unit.type) == tool:
				deployed += 1
	if deployed >= capacity:
		return rejected("Your available units are already deployed. Recall them before redeploying.")
	var candidate := CityState.copy_for_edit(receiver.city)
	var existing := 0
	var things := candidate.document.find_chunk("XTHG").decoded_payload
	var type: int = [Sc2ThingLayout.Type.POLICE, Sc2ThingLayout.Type.FIRE, Sc2ThingLayout.Type.MILITARY][tool]
	for record in ThingData.count(things):
		if ThingData.read(things, record * ThingData.RECORD_SIZE) == type:
			existing += 1
	var capacity_override := Vector3i.ONE * (existing + 1)
	var edit := DispatchCommand.apply(candidate, CityToolIds.Group.DISPATCH, tool, target, existing, {}, capacity_override)
	if not edit.ok:
		return rejected(edit.error)
	receiver.city = candidate
	receiver.engine.city = candidate
	receiver.revision += 1
	receiver.dispatch_owners[str(edit.thing_index)] = {"actor": actor.sha256_text(), "position": [target.x, target.y], "type": tool}
	revision += 1
	return accepted("Emergency service deployed.")


func selected_tiles(request: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	var first := point(request.start)
	var last := point(request.finish)
	for x in range(mini(first.x, last.x), maxi(first.x, last.x) + 1):
		for y in range(mini(first.y, last.y), maxi(first.y, last.y) + 1):
			result.append(city.index_of(x, y))
	return result


func land_command(actor: String, request: Dictionary) -> Dictionary:
	var child: CoopWorld = municipalities[actor]
	if request.kind == "land_accept":
		var key := str(request.get("offer", ""))
		if not offers.has(key):
			return rejected("This offer is no longer available.")
		var offer: Dictionary = offers[key]
		if offer.seller == actor:
			return rejected("You already own this land.")
		for tile: int in offer.tiles:
			if owners[tile] != actors.find(offer.seller) + 1:
				return rejected("Land ownership changed; nothing was charged.")
		if child.city.funds() < int(offer.price):
			return rejected("Insufficient funds.")
		var seller: CoopWorld = municipalities[offer.seller]
		if seller.city.funds() + int(offer.price) > 2147483647:
			return rejected("The seller's balance would exceed the supported limit.")
		if seller.engine.active_disaster_type != 0 or child.engine.active_disaster_type != 0:
			return rejected("Finish disaster response before transferring a municipality's land.")
		var transfer := SharedLandTransfer.stage(seller.city, child.city, offer.tiles)
		if not transfer.error.is_empty():
			return rejected(transfer.error)
		child.city = transfer.buyer
		child.engine.city = child.city
		seller.city = transfer.seller
		seller.engine.city = seller.city
		child.city.set_funds(child.city.funds() - int(offer.price))
		seller.city.set_funds(seller.city.funds() + int(offer.price))
		for tile: int in offer.tiles:
			owners[tile] = actors.find(actor) + 1
			tile_versions[tile] = revision + 1
		child.undo_document = null
		seller.undo_document = null
		child.revision += 1
		seller.revision += 1
		city = municipalities[host_actor].city
		offers.erase(key)
		revision += 1
		return accepted("Land purchased from its owner.")
	if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
		return rejected("Invalid land selection.")
	var tiles := selected_tiles(request)
	var expected_owner := 0 if request.kind == "land_buy" else actors.find(actor) + 1
	for tile: int in tiles:
		if owners[tile] != expected_owner:
			return rejected("The entire selection must have the same owner. Nothing was charged.")
	var price := tiles.size() * LAND_PRICE
	if request.kind == "land_offer":
		if not whole_number(request.get("price"), 0, 2147483647):
			return rejected("Invalid offer price.")
		price = int(request.price)
		offers[str(next_offer)] = {"seller": actor, "tiles": Array(tiles), "price": price}
		next_offer += 1
		revision += 1
		return accepted("Land offer published. Another player can accept it.")
	if request.get("price") != price:
		return choice_result("Buy %d tiles for $%d? Balance afterwards: $%d." % [tiles.size(), price, child.city.funds() - price], request,
			[{"label": "Buy — $%d" % price, "fields": {"price": price}}])
	if child.city.funds() < price:
		return rejected("Insufficient funds.")
	child.city.set_funds(child.city.funds() - price)
	for tile: int in tiles:
		owners[tile] = actors.find(actor) + 1
		tile_versions[tile] = revision + 1
	revision += 1
	return accepted("Land purchased.")


func snapshot_for(actor: String) -> Dictionary:
	if snapshot_cache.get(actor, {}).get("revision", -1) == revision:
		return snapshot_cache[actor].duplicate(true)
	var child: CoopWorld = municipalities.get(actor, municipalities[host_actor])
	var result := child.snapshot()
	var document := child.city.document.duplicate_document()
	for id: String in TILE_CHUNKS:
		var data := document.find_chunk(id).decoded_payload.duplicate()
		var stride: int = TILE_CHUNKS[id]
		for index in actors.size():
			var source: PackedByteArray = municipalities[actors[index]].city.document.find_chunk(id).decoded_payload
			for tile in owners.size():
				if owners[tile] == index + 1:
					for byte in stride:
						data[tile * stride + byte] = source[tile * stride + byte]
		document.find_chunk(id).set_decoded_payload(data)
	compose_records(document, actor)
	var encoded := Sc2xDocument.encode(document)
	if not encoded.ok:
		return {"error": encoded.error}
	result.city = Marshalls.raw_to_base64(encoded.data)
	result.revision = revision
	result["mode"] = "shared"
	result["owners"] = Array(owners)
	result["owner_ids"] = actors.map(func(value: String) -> String: return value.sha256_text())
	result["dispatch_owners"] = {}
	result["disasters"] = []
	for owner: String in actors:
		var municipality: CoopWorld = municipalities[owner]
		for key: String in municipality.dispatch_owners:
			result.dispatch_owners[owner.sha256_text() + key] = municipality.dispatch_owners[key]
		if municipality.engine.active_disaster_type != 0:
			var location := owners.find(actors.find(owner) + 1)
			for tile in owners.size():
				if owners[tile] == actors.find(owner) + 1 and OverlayData.marker_at(municipality.city.text_overlays, tile) != 0:
					location = tile
					break
			result.disasters.append({"owner": owner.sha256_text(), "type": municipality.engine.active_disaster_type,
				"point": [location / city.map_size, location % city.map_size]})
	snapshot_cache[actor] = result.duplicate(true)
	return result


func compose_records(document: Sc2File, viewing_actor: String) -> void:
	var text := document.find_chunk("XTXT").decoded_payload.duplicate()
	var things := document.find_chunk("XTHG").decoded_payload.duplicate()
	var facilities := document.find_chunk("XMIC").decoded_payload.duplicate()
	var labels := document.find_chunk("XLAB").decoded_payload.duplicate()
	var next_sign := maxi(Sc2OverlayLayout.EXTRA_SIGN, labels.size() / Sc2LabelLayout.RECORD_SIZE)
	for actor: String in actors:
		if actor == viewing_actor:
			continue
		var child: CoopWorld = municipalities[actor]
		var source_text := child.city.text_overlays
		var source_things := child.city.document.find_chunk("XTHG").decoded_payload
		var source_facilities := child.city.document.find_chunk("XMIC").decoded_payload
		var source_labels := child.city.document.find_chunk("XLAB").decoded_payload
		var thing_base := ThingData.count(things)
		var facility_base := facilities.size() / Sc2MicrosimLayout.RECORD_SIZE
		var expanded := PackedByteArray()
		expanded.resize((thing_base + ThingData.count(source_things)) * Sc2ThingLayout.EXTENDED_RECORD_SIZE)
		for record in thing_base:
			for byte in ThingData.RECORD_SIZE:
				ThingData.write(expanded, record * ThingData.RECORD_SIZE + byte, ThingData.read(things, record * ThingData.RECORD_SIZE + byte))
		for record in ThingData.count(source_things):
			for byte in ThingData.RECORD_SIZE:
				ThingData.write(expanded, (record + thing_base) * ThingData.RECORD_SIZE + byte, ThingData.read(source_things, record * ThingData.RECORD_SIZE + byte))
			var label_offset := (record + thing_base) * ThingData.RECORD_SIZE + Sc2ThingLayout.Field.LABEL
			var link := ThingData.read(expanded, label_offset)
			if OverlayData.is_thing(link):
				ThingData.write(expanded, label_offset, OverlayData.thing_id(OverlayData.thing_record(link) + thing_base))
			elif OverlayData.is_facility(link):
				ThingData.write(expanded, label_offset, OverlayData.facility_id(OverlayData.facility_record(link) + facility_base))
		things = expanded
		facilities.append_array(source_facilities)
		var signs := {}
		for tile in owners.size():
			if owners[tile] != actors.find(actor) + 1:
				continue
			var marker := OverlayData.marker_at(source_text, tile)
			var facility := OverlayData.facility_at(source_text, tile)
			var object := OverlayData.object(source_text, tile) if OverlayData.is_layered(source_text) else OverlayData.read(source_text, tile)
			OverlayData.set_marker_at(text, tile, marker if not OverlayData.is_facility(marker) and not OverlayData.is_thing(marker) and not OverlayData.is_sign(marker) else 0)
			if OverlayData.is_layered(text):
				OverlayData.set_facility(text, tile, 0)
				OverlayData.set_object(text, tile, 0)
			if OverlayData.is_facility(facility):
				OverlayData.write(text, tile, OverlayData.facility_id(OverlayData.facility_record(facility) + facility_base))
			if OverlayData.is_thing(object):
				OverlayData.write(text, tile, OverlayData.thing_id(OverlayData.thing_record(object) + thing_base))
			var sign_id := OverlayData.read(source_text, tile)
			if OverlayData.is_sign(sign_id):
				if not signs.has(sign_id):
					signs[sign_id] = next_sign
					labels.resize((next_sign + 1) * Sc2LabelLayout.RECORD_SIZE)
					for byte in Sc2LabelLayout.RECORD_SIZE:
						labels[next_sign * Sc2LabelLayout.RECORD_SIZE + byte] = source_labels[sign_id * Sc2LabelLayout.RECORD_SIZE + byte]
					next_sign += 1
				OverlayData.write(text, tile, signs[sign_id])
	for pair in [["XTXT", text], ["XTHG", things], ["XMIC", facilities], ["XLAB", labels]]:
		var chunk := document.find_chunk(pair[0])
		chunk.expected_decoded_size = pair[1].size()
		chunk.set_decoded_payload(pair[1])


func snapshot() -> Dictionary:
	return snapshot_for(host_actor) if not host_actor.is_empty() else super.snapshot()


func saved_shared() -> Dictionary:
	var cities := {}
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		var checkpoint_error := Sc2xCheckpoint.save_error(child.controller)
		if not checkpoint_error.is_empty():
			return {"error": checkpoint_error}
		cities[actor] = {"state": child.snapshot(), "statistics": child.statistics,
			"dispatch": Array(child.dispatch_cycles), "dispatch_owners": child.dispatch_owners,
			"dispatch_initialized": child.dispatch_initialized, "dispatch_points": child.saved_dispatch_points()}
	return {"owners": Array(owners), "actors": actors, "host": host_actor,
		"cities": cities, "offers": offers, "next_offer": next_offer,
		"template": Marshalls.raw_to_base64(Sc2xDocument.encode(template).data)}


func restore_shared(data: Dictionary) -> String:
	if not data.get("actors") is Array or data.actors.is_empty() or data.actors.size() > 8 or not data.get("cities") is Dictionary or not data.get("owners") is Array or data.owners.size() != owners.size():
		return "Invalid shared municipalities."
	if not data.get("host") is String or not data.actors.has(data.host):
		return "Invalid shared host."
	var restored := {}
	for actor: Variant in data.actors:
		if not actor is String or actor.length() != 48 or restored.has(actor) or not data.cities.get(actor) is Dictionary:
			return "Invalid municipality identity."
		var record: Dictionary = data.cities[actor]
		if not record.get("state") is Dictionary or not record.state.get("city") is String:
			return "Missing municipality city."
		if not record.get("statistics") is Dictionary or not record.get("dispatch_owners") is Dictionary or not record.get("dispatch") is Array or record.dispatch.size() != 3:
			return "Invalid municipality service state."
		for cycle: Variant in record.dispatch:
			if not whole_number(cycle, 0, 2147483647):
				return "Invalid municipality dispatch cycle."
		var document := Sc2File.new()
		var child := CoopWorld.new()
		if not document.parse(Marshalls.base64_to_raw(record.state.city)) or document.map_size != city.map_size or not child.open(document):
			return "Invalid municipality checkpoint."
		child.statistics = record.get("statistics", {})
		child.dispatch_owners = record.get("dispatch_owners", {})
		child.dispatch_cycles = PackedInt32Array(record.get("dispatch", [0, 0, 0]))
		var dispatch := CoopWorld.read_dispatch_points(record.get("dispatch_points", []), city.map_size)
		if not dispatch.error.is_empty():
			return dispatch.error
		child.dispatch_slot_points = dispatch.points
		child.dispatch_initialized = record.get("dispatch_initialized") == true
		restored[actor] = child
	for owner: Variant in data.owners:
		if not whole_number(owner, 0, restored.size()):
			return "Invalid land owner."
	var restored_template := Sc2File.new()
	if not data.get("template") is String or not restored_template.parse(Marshalls.base64_to_raw(data.template)) or restored_template.map_size != city.map_size:
		return "Invalid shared terrain."
	if not data.get("offers") is Dictionary or not whole_number(data.get("next_offer"), 1, 2147483647):
		return "Invalid land offers."
	for key: Variant in data.offers:
		var offer: Variant = data.offers[key]
		if not key is String or not offer is Dictionary or not restored.has(offer.get("seller")) or not whole_number(offer.get("price"), 0, 2147483647) or not offer.get("tiles") is Array or offer.tiles.is_empty() or offer.tiles.size() > owners.size():
			return "Invalid land offer."
		var unique := {}
		for tile: Variant in offer.tiles:
			if not whole_number(tile, 0, owners.size() - 1) or unique.has(int(tile)):
				return "Invalid land offer area."
			unique[int(tile)] = true
	municipalities = restored
	actors.assign(data.actors)
	owners = PackedInt32Array(data.owners)
	host_actor = data.host
	template = restored_template
	offers = data.get("offers", {})
	next_offer = int(data.get("next_offer", 1))
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller
	statistics.clear()
	for actor: String in actors:
		statistics[actor] = municipalities[actor].statistics.get(actor, {"builds": 0, "spent": 0})
	snapshot_cache.clear()
	return ""


static func remove_dispatch(things: PackedByteArray, text: PackedByteArray, record: int) -> void:
	var offset := record * ThingData.RECORD_SIZE
	var x := ThingData.read(things, offset + Sc2ThingLayout.Field.X)
	var y := ThingData.read(things, offset + Sc2ThingLayout.Field.Y)
	var edge := int(sqrt(OverlayData.count(text)))
	if x >= 0 and y >= 0 and x < edge and y < edge:
		OverlayData.lift_object(text, things, record, x * edge + y, 0)
	ThingData.write(things, offset, 0)


func military_land_error(actor: String) -> String:
	var child: CoopWorld = municipalities[actor]
	# Preview with copied city/random state: a civic proposal must obey the same
	# ownership rule as a player's building, without consuming a random draw.
	var candidate := CityState.copy_for_edit(child.city)
	var random := GameLcgRandom.new(child.engine.game_random.state)
	var proposal := MilitaryProposalPhase.resolve(candidate, true, random, false, child.engine.forced_military_base_type)
	if not proposal.ok:
		return proposal.error
	for tile: int in changed_tiles(child.city.document, candidate.document):
		if owners[tile] != actors.find(actor) + 1:
			return "The proposed military base extends outside your land. Buy its land first or decline the proposal."
	return ""
