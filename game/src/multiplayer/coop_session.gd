class_name CoopSession
extends Node
## One authoritative host, up to eight simultaneous participants, no client simulation.

signal state_received(state: Dictionary)
signal feedback(message: String)
signal connection_changed
signal choice_requested(result: Dictionary)
signal environment_received(state: Dictionary)
signal chat_received(message: Dictionary)
signal presence_received(players: Array)
signal player_event(event: Dictionary)

const PROTOCOL := 1
const BUILD := "opensc2k-coop-1"
const NETWORK_BUILD := "opensc2k-multiplayer-7"
const MAX_PLAYERS := 8
var world: CoopWorld
var active := false
var hosting := false
var connected := false
var code := ""
var token := Crypto.new().generate_random_bytes(24).hex_encode()
var session_id := ""
var server: TCPServer
var channels: Dictionary[int, CityTcpChannel] = {}
var identities: Dictionary[int, String] = {}
var members: Dictionary = {}
var next_peer := 1
var next_command := 1
var local_revision := 0
var local_policy := 0
var latest: Dictionary = {}
var snapshot_elapsed := 0.0
var heartbeat_elapsed := 0.0
var disconnected_pause := false
var requested_speed: Dictionary = {}
var handshake_started: Dictionary[int, int] = {}
var command_rates: Dictionary[int, Array] = {}
var environment_source: Callable
var environment_elapsed := 0.0
var player_color := "46b4ff"
var cursors: Dictionary = {}
var cursor_updated: Dictionary = {}
var chat_history: Array = []
var presence_elapsed := 0.0
var cursor_source: Callable
var chat_last_sent: Dictionary = {}
var event_sequence := 0
var graceful_peers: Dictionary = {}
var statistics_cache: Dictionary = {}
var statistics_revision := -1



func host(document: Sc2File, port: int, join_code: String, player_name: String, mode := "coop") -> String:
	var candidate: CoopWorld = SharedWorld.new() if mode == "shared" else CoopWorld.new()
	if not candidate.open(document):
		return candidate.error
	var listener := TCPServer.new()
	var result := listener.listen(port)
	if result != OK:
		return "Cannot listen on TCP port %d: %s" % [port, error_string(result)]
	stop()
	world = candidate
	if world is SharedWorld:
		var shared_error: String = world.add_player(token)
		if not shared_error.is_empty():
			listener.stop()
			return shared_error
	server = listener
	code = join_code
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	members[token] = {"name": player_name.left(32), "sequence": 0, "color": player_color}
	requested_speed[token] = 1
	active = true
	hosting = true
	connected = true
	publish()
	connection_changed.emit()
	return ""


func join(address: String, port: int, join_code: String, player_name: String) -> String:
	if active and hosting:
		return "Leave the hosted session first."
	var peer := StreamPeerTCP.new()
	var result := peer.connect_to_host(address, port)
	if result != OK:
		return "Cannot connect: %s" % error_string(result)
	for channel in channels.values():
		channel.close()
	channels.clear()
	active = true
	hosting = false
	connected = false
	code = join_code
	var channel := CityTcpChannel.new(peer)
	channels[0] = channel
	channel.send({"type": "hello", "protocol": PROTOCOL, "build": NETWORK_BUILD, "code": code,
		"token": token, "name": player_name.left(32), "session": session_id, "color": player_color})
	connection_changed.emit()
	return ""


func stop() -> void:
	if active and connected:
		for channel in channels.values():
			channel.send({"type": "leave"})
			channel.flush()
	graceful_peers.clear()
	statistics_cache.clear()
	statistics_revision = -1
	for channel in channels.values():
		channel.close()
	channels.clear()
	identities.clear()
	handshake_started.clear()
	command_rates.clear()
	if server != null:
		server.stop()
	server = null
	world = null
	members.clear()
	cursors.clear()
	cursor_updated.clear()
	chat_history.clear()
	chat_last_sent.clear()
	requested_speed.clear()
	active = false
	connected = false
	hosting = false
	disconnected_pause = false
	latest.clear()
	next_command = 1
	session_id = ""
	connection_changed.emit()


func _process(delta: float) -> void:
	if not active:
		return
	if hosting and server.is_connection_available():
		var peer := server.take_connection()
		if channels.size() >= MAX_PLAYERS - 1:
			peer.disconnect_from_host()
		else:
			channels[next_peer] = CityTcpChannel.new(peer, 65536)
			handshake_started[next_peer] = Time.get_ticks_msec()
			next_peer += 1
	for id: int in channels.keys():
		var channel := channels[id]
		for message in channel.poll():
			if hosting:
				receive_host(id, message)
			else:
				receive_client(message)
		if hosting and not identities.has(id) and Time.get_ticks_msec() - handshake_started.get(id, 0) > 10000:
			channel.failed = true
		if channel.failed:
			drop(id)
	heartbeat_elapsed += delta
	if heartbeat_elapsed >= 2.0:
		heartbeat_elapsed = 0.0
		for channel in channels.values():
			channel.send({"type": "ping"})
	if hosting:
		world.advance(delta)
		snapshot_elapsed += delta
		if snapshot_elapsed >= 0.25:
			snapshot_elapsed = 0.0
			publish()
		environment_elapsed += delta
		if environment_elapsed >= 0.05 and environment_source.is_valid():
			environment_elapsed = 0.0
			var atmosphere: Dictionary = environment_source.call()
			for id: int in identities:
				if channels[id].output.is_empty():
					channels[id].send({"type": "environment", "weather": atmosphere})
	presence_elapsed += delta
	if presence_elapsed >= 0.1:
		presence_elapsed = 0.0
		if cursor_source.is_valid():
			var position: Vector2 = cursor_source.call()
			if hosting:
				cursors[token] = [position.x, position.y]
				cursor_updated[token] = Time.get_ticks_msec()
			elif connected:
				channels[0].send({"type": "cursor", "position": [position.x, position.y]})
		if hosting:
			var players := roster()
			presence_received.emit(players)
			broadcast({"type": "presence", "players": players})
	for channel in channels.values():
		channel.flush()


func receive_host(id: int, message: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var rate: Array = command_rates.get(id, [now, 0])
	if now - int(rate[0]) >= 1000:
		rate = [now, 0]
	rate[1] += 1
	command_rates[id] = rate
	if rate[1] > 40:
		channels[id].failed = true
		return
	if message.get("type") == "ping":
		return
	if not identities.has(id):
		if (message.get("type") != "hello" or message.get("protocol") != PROTOCOL
				or message.get("build") != NETWORK_BUILD or message.get("code") != code
				or not message.get("token") is String or message.token.length() != 48
				or not message.get("name") is String or message.name.is_empty()
				or message.name.length() > 32 or identities.values().has(message.token)
				or message.token == token or (members.size() >= 32 and not members.has(message.token))):
			channels[id].failed = true
			return
		if message.get("session", "") != "" and message.session != session_id:
			channels[id].send({"type": "result", "ok": false, "message": "This is a different session. Leave before joining it."})
			return
		if world is SharedWorld:
			var shared_error: String = world.add_player(message.token)
			if not shared_error.is_empty():
				channels[id].failed = true
				return
		identities[id] = message.token
		if not members.has(message.token):
			members[message.token] = {"name": message.name, "sequence": 0, "color": available_color(message.get("color"))}
		requested_speed[message.token] = 5
		apply_speed()
		channels[id].send({"type": "welcome", "session": session_id, "next": int(members[message.token].sequence) + 1})
		channels[id].send(make_state(message.token))
		for item: Dictionary in chat_history:
			channels[id].send({"type": "chat", "message": item.merged({"history": true}, true)})
		emit_player_event(message.token, "joined", id)
		return
	var actor: String = identities[id]
	if message.get("type") == "leave":
		graceful_peers[id] = true
		channels[id].failed = true
		return
	if message.get("type") == "cursor":
		var position: Variant = message.get("position")
		if position is Array and position.size() == 2 and valid_cursor_number(position[0]) and valid_cursor_number(position[1]):
			cursors[actor] = position
			cursor_updated[actor] = Time.get_ticks_msec()
		return
	if message.get("type") == "chat":
		accept_chat(actor, message.get("text"))
		return
	if message.get("type") != "command":
		channels[id].failed = true
		return
	channels[id].send(execute(identities[id], message))
	# Confirmed edits must not wait for the periodic simulation snapshot.
	publish()


func execute(actor: String, message: Dictionary) -> Dictionary:
	var member: Dictionary = members[actor]
	if not CoopWorld.whole_number(message.get("id"), 1, 2147483647):
		return CoopWorld.rejected("Invalid command identifier.")
	var sequence := int(message.id)
	if sequence <= int(member.sequence):
		return CoopWorld.rejected("This command was already handled; it was not applied again.")
	if sequence != int(member.sequence) + 1:
		return CoopWorld.rejected("Command order changed. Reconnect to synchronize.")
	member.sequence = sequence
	var result: Dictionary
	if message.get("kind") == "speed":
		if not CoopWorld.whole_number(message.get("speed"), 1, 5):
			return CoopWorld.rejected("Invalid speed.")
		requested_speed[actor] = int(message.speed)
		apply_speed()
		result = CoopWorld.accepted("Your requested speed was updated.")
	else:
		result = world.command(actor, message)
	result["id"] = sequence
	return result


func apply_speed() -> void:
	var speed := 5
	for value: int in requested_speed.values():
		speed = mini(speed, value)
	world.controller.set_speed(1 if disconnected_pause else speed)
	if world is SharedWorld:
		world.set_shared_speed(1 if disconnected_pause else speed)


func release_disconnect_pause() -> void:
	if hosting:
		disconnected_pause = false
		apply_speed()
		publish()


func request(command: Dictionary) -> void:
	if not connected:
		feedback.emit("Disconnected. Reconnect before making changes.")
		return
	command["type"] = "command"
	command["id"] = next_command
	command["revision"] = command.get("revision", local_revision)
	command["policy"] = command.get("policy", local_policy)
	next_command += 1
	if hosting:
		var result := execute(token, command)
		feedback.emit(str(result.message))
		if result.has("choices"):
			choice_requested.emit(result)
		publish()
	else:
		channels[0].send(command)
		channels[0].flush()


func receive_client(message: Dictionary) -> void:
	match message.get("type"):
		"welcome":
			if not message.get("session") is String or not CoopWorld.whole_number(message.get("next"), 1, 2147483647):
				channels[0].failed = true
				return
			session_id = message.session
			next_command = int(message.next)
		"state":
			if not message.get("city") is String or not CoopWorld.whole_number(message.get("revision"), 0, 9007199254740991):
				channels[0].failed = true
				return
			connected = true
			accept_state(message)
		"environment":
			if message.get("weather") is Dictionary:
				environment_received.emit(message.weather)
		"result":
			feedback.emit(str(message.get("message", "")))
			if message.get("choices") is Array and message.get("request") is Dictionary:
				choice_requested.emit(message)
		"chat":
			if message.get("message") is Dictionary:
				chat_received.emit(message.message)
		"player_event":
			if message.get("event") is Dictionary:
				player_event.emit(message.event)
		"leave":
			graceful_peers[0] = true
			channels[0].failed = true
		"presence":
			if message.get("players") is Array:
				presence_received.emit(message.players)
		"ping":
			pass
		_:
			channels[0].failed = true


func make_state(recipient := "") -> Dictionary:
	var state: Dictionary = world.snapshot_for(recipient if not recipient.is_empty() else token) if world is SharedWorld else world.snapshot()
	var players: Array[String] = []
	for actor: String in requested_speed:
		players.append("%s (%s)" % [members[actor].name, "paused" if requested_speed[actor] == 1 else "playing"])
	state["players"] = players
	state["roster"] = roster()
	if world is SharedWorld:
		state["offers"] = []
		for key: String in world.offers:
			state.offers.append(public_land_entry(world.offers[key].merged({"id": key, "status": "Open"}, true)))
		state["land_history"] = world.land_history.map(public_land_entry)
	state["disconnect_pause"] = disconnected_pause
	if environment_source.is_valid():
		state["weather"] = environment_source.call()
	return state


func publish() -> void:
	var state := make_state()
	if not state.has("city"):
		feedback.emit(str(state.get("error", "Cannot synchronize the city.")))
		return
	accept_state(state)
	for id: int in identities:
		# Do not accumulate stale snapshots behind a slow client.
		if channels[id].output.size() < CityTcpChannel.IO_BUDGET:
			channels[id].send(make_state(identities[id]) if world is SharedWorld else state)


func accept_state(state: Dictionary) -> void:
	latest = state
	local_revision = int(state.revision)
	local_policy = int(state.get("policy", 0))
	state_received.emit(state)
	if not hosting and state.get("weather") is Dictionary:
		environment_received.emit(state.weather)


func drop(id: int) -> void:
	channels[id].close()
	channels.erase(id)
	handshake_started.erase(id)
	command_rates.erase(id)
	if hosting:
		if identities.has(id):
			var actor: String = identities[id]
			requested_speed.erase(actor)
			cursors.erase(actor)
			cursor_updated.erase(actor)
			identities.erase(id)
			disconnected_pause = true
			world.controller.set_speed(1)
			if world is SharedWorld:
				world.set_shared_speed(1)
			emit_player_event(actor, "left" if graceful_peers.has(id) else "disconnected")
	else:
		connected = false
		for member: Dictionary in latest.get("roster", []):
			if member.get("host", false):
				player_event.emit({"id": session_id + ":host-left", "name": member.name, "kind": "left" if graceful_peers.has(id) else "disconnected"})
		feedback.emit("The host ended the session." if graceful_peers.has(id) else "Connection lost or refused. Check host, port and password, then reconnect. The view is frozen.")
	graceful_peers.erase(id)
	connection_changed.emit()


func save_session(path: String) -> String:
	path = ProjectSettings.globalize_path(path)
	if not hosting:
		return "Only the host saves the shared session."
	var checkpoint_error := Sc2xCheckpoint.save_error(world.controller)
	if not checkpoint_error.is_empty():
		return checkpoint_error
	var data := {"format": "OpenSC2K Koop", "version": PROTOCOL, "build": BUILD,
		"session": session_id, "host": token, "members": members, "state": world.snapshot(),
		"dispatch": Array(world.dispatch_cycles), "dispatch_initialized": world.dispatch_initialized,
		"statistics": world.statistics, "dispatch_owners": world.dispatch_owners}
	if not data.state.has("city"):
		return str(data.state.get("error", "Cannot encode city."))
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write session: %s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not JSON.parse_string(FileAccess.get_file_as_string(temporary)) is Dictionary:
		return "The session could not be written and verified."
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return "Cannot replace the session backup."
		if DirAccess.rename_absolute(path, backup) != OK:
			return "Cannot preserve the previous session."
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return "Cannot install the new session file (%s). The previous save was retained." % error_string(rename_error)
	return ""


func resume_session(path: String, port: int, join_code: String, player_name: String) -> String:
	path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size() > CityTcpChannel.MAX_FRAME:
		return "The session file is missing or too large."
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != PROTOCOL or data.get("build") != BUILD or not data.get("state") is Dictionary:
		return "Unsupported session file."
	if not data.get("host") is String or not data.get("session") is String or not data.get("members") is Dictionary or not data.members.has(data.host):
		return "Invalid session identities."
	for actor: Variant in data.members:
		var member: Variant = data.members[actor]
		if not actor is String or actor.length() != 48 or not member is Dictionary or not member.get("name") is String or not CoopWorld.whole_number(member.get("sequence"), 0, 2147483646):
			return "Invalid session member."
	if not data.state.get("city") is String:
		return "Missing session city."
	if not CoopWorld.whole_number(data.state.get("revision"), 0, 9007199254740990) or data.state.get("pending", "") != "":
		return "The session has no complete simulation checkpoint."
	if not data.get("dispatch") is Array or data.dispatch.size() != 3 or not data.get("dispatch_initialized") is bool:
		return "Invalid emergency service state."
	for value: Variant in data.dispatch:
		if not CoopWorld.whole_number(value, 0, 2147483647):
			return "Invalid emergency service cycle."
	var document := Sc2File.new()
	if not document.parse(Marshalls.base64_to_raw(data.state.city)):
		return document.parse_error
	var host_error := host(document, port, join_code, player_name)
	if not host_error.is_empty():
		return host_error
	token = data.host
	session_id = data.session
	members = data.members
	requested_speed.clear()
	requested_speed[token] = 1
	next_command = int(members[token].sequence) + 1
	world.revision = int(data.state.get("revision", 0)) + 1
	world.tile_versions.fill(world.revision)
	world.dispatch_cycles = PackedInt32Array(data.dispatch)
	world.dispatch_initialized = data.dispatch_initialized
	world.statistics = data.get("statistics", {})
	world.dispatch_owners = data.get("dispatch_owners", {})
	publish()
	return ""


static func valid_color(value: Variant) -> String:
	if value is String and value.length() == 6 and value.is_valid_hex_number(false):
		return value.to_lower()
	return "46b4ff"


func available_color(value: Variant) -> String:
	var wanted := valid_color(value)
	var used: Array = []
	for member: Dictionary in members.values():
		used.append(valid_color(member.get("color")))
	if not used.has(wanted):
		return wanted
	for color in ["ff9c40", "66cf79", "e77ba8", "c7a0ff", "ffe173", "62dbd4", "eeeeee", "b0bf5b"]:
		if not used.has(color):
			return color
	return wanted


func roster() -> Array:
	var result: Array = []
	if statistics_revision != world.revision:
		statistics_cache.clear()
		statistics_revision = world.revision
	for actor: String in members:
		var member: Dictionary = members[actor]
		if not statistics_cache.has(actor):
			statistics_cache[actor] = MultiplayerStatistics.capture(world, actor)
		var row: Dictionary = statistics_cache[actor].duplicate()
		row.merge({"id": actor.sha256_text(), "name": member.name, "host": actor == token,
			"color": valid_color(member.get("color")), "online": requested_speed.has(actor),
			"cursor": cursors.get(actor, [-1, -1]) if Time.get_ticks_msec() - int(cursor_updated.get(actor, 0)) < 3000 else [-1, -1]})
		result.append(row)
	return result


func broadcast(message: Dictionary) -> void:
	for id: int in identities:
		if channels[id].output.size() < CityTcpChannel.IO_BUDGET:
			channels[id].send(message)


func send_chat(text: String) -> void:
	if not connected:
		return
	if hosting:
		accept_chat(token, text)
	else:
		channels[0].send({"type": "chat", "text": text})
		channels[0].flush()


func accept_chat(actor: String, value: Variant) -> void:
	if not value is String or value.strip_edges().is_empty() or value.length() > 500:
		return
	var now := Time.get_ticks_msec()
	if now - int(chat_last_sent.get(actor, -1000)) < 500:
		return
	chat_last_sent[actor] = now
	event_sequence += 1
	var entry := {"id": session_id + ":" + str(event_sequence), "sender": actor.sha256_text(), "name": members[actor].name, "color": valid_color(members[actor].get("color")),
		"text": value.strip_edges(), "time": Time.get_datetime_string_from_system()}
	chat_history.append(entry)
	if chat_history.size() > 100:
		chat_history.pop_front()
	chat_received.emit(entry)
	for id: int in identities:
		channels[id].send({"type": "chat", "message": entry})


func city_checkpoint() -> Dictionary:
	if not hosting:
		return {"error": "Only the host saves the game."}
	var error := Sc2xCheckpoint.save_error(world.controller)
	if not error.is_empty():
		return {"error": error}
	Sc2xCheckpoint.capture(world.controller, world.city.document.sc2x_metadata)
	var document := world.city.document.duplicate_document()
	var data := {"version": 1, "host": token, "session": session_id, "members": members,
		"statistics": world.statistics, "dispatch_owners": world.dispatch_owners,
		"dispatch": Array(world.dispatch_cycles), "dispatch_initialized": world.dispatch_initialized}
	if world is SharedWorld:
		data["shared"] = world.saved_shared()
		if data.shared.has("error"):
			return {"error": data.shared.error}
	document.sc2x_extra_entries["multiplayer.json"] = JSON.stringify(data).to_utf8_buffer()
	return {"error": "", "document": document}


func save_city(path: String) -> String:
	var checkpoint := city_checkpoint()
	if not checkpoint.error.is_empty():
		return checkpoint.error
	var document: Sc2File = checkpoint.document
	var encoded := Sc2xDocument.encode(document)
	if not encoded.ok:
		return encoded.error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write the city."
	file.store_buffer(encoded.data)
	file.flush()
	var result := file.get_error()
	file.close()
	var check := Sc2File.new()
	if result != OK or not check.parse(FileAccess.get_file_as_bytes(temporary)):
		return "Cannot verify the saved city."
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return "Cannot replace the previous backup."
		if DirAccess.rename_absolute(path, backup) != OK:
			return "Cannot back up the previous city."
	if DirAccess.rename_absolute(temporary, path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return "Cannot install the saved city; the previous save was retained."
	return ""


func restore_embedded(document: Sc2File) -> String:
	var data: Variant = JSON.parse_string(document.sc2x_extra_entries.get("multiplayer.json", PackedByteArray()).get_string_from_utf8())
	if not data is Dictionary or data.get("version") != 1 or not data.get("members") is Dictionary:
		return "Invalid multiplayer city data."
	if not data.get("host") is String or not data.members.has(data.host) or not data.get("session") is String:
		return "Invalid multiplayer identities."
	for actor: Variant in data.members:
		var member: Variant = data.members[actor]
		if not actor is String or actor.length() != 48 or not member is Dictionary or not member.get("name") is String or not CoopWorld.whole_number(member.get("sequence"), 0, 2147483646):
			return "Invalid multiplayer member."
	if not data.get("dispatch") is Array or data.dispatch.size() != 3:
		return "Invalid dispatch state."
	for value: Variant in data.dispatch:
		if not CoopWorld.whole_number(value, 0, 2147483647):
			return "Invalid dispatch cycle."
	if not data.get("statistics") is Dictionary or not data.get("dispatch_owners") is Dictionary:
		return "Invalid multiplayer statistics."
	var restored_world: CoopWorld = SharedWorld.new() if data.get("shared") is Dictionary else CoopWorld.new()
	if not restored_world.open(document):
		return restored_world.error
	if restored_world is SharedWorld:
		var shared_error: String = restored_world.restore_shared(data.shared)
		if not shared_error.is_empty():
			return shared_error
		if restored_world.host_actor != data.host or restored_world.actors.size() != data.members.size():
			return "Saved municipalities do not match session members."
		for actor: String in restored_world.actors:
			if not data.members.has(actor):
				return "Missing municipality member."
	world = restored_world
	token = data.host
	session_id = data.session
	members = data.members
	requested_speed.clear()
	requested_speed[token] = 1
	next_command = int(members[token].sequence) + 1
	world.statistics = data.statistics
	world.dispatch_owners = data.dispatch_owners
	world.dispatch_cycles = PackedInt32Array(data.dispatch)
	world.dispatch_initialized = data.get("dispatch_initialized") == true
	publish()
	return ""


func valid_cursor_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= -1.0 and float(value) < world.city.map_size


func emit_player_event(actor: String, kind: String, excluded := -1) -> void:
	event_sequence += 1
	var event := {"id": session_id + ":" + str(event_sequence), "name": members[actor].name, "kind": kind}
	player_event.emit(event)
	for id: int in identities:
		if id != excluded:
			channels[id].send({"type": "player_event", "event": event})


func public_land_entry(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	result["name"] = members.get(record.get("seller", ""), {}).get("name", "")
	result["buyer_name"] = members.get(record.get("buyer", ""), {}).get("name", "")
	result["seller"] = str(record.get("seller", "")).sha256_text()
	result["buyer"] = str(record.buyer).sha256_text() if record.has("buyer") else ""
	result["count"] = record.get("tiles", []).size()
	return result
