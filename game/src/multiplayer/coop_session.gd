class_name CoopSession
extends Node
## One authoritative host, up to eight simultaneous participants, no client simulation.

signal state_received(state: Dictionary)
signal feedback(message: String)
signal connection_changed
signal choice_requested(result: Dictionary)
signal environment_received(state: Dictionary)

const PROTOCOL := 1
const BUILD := "opensc2k-coop-1"
const NETWORK_BUILD := "opensc2k-coop-2"
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


func host(document: Sc2File, port: int, join_code: String, player_name: String) -> String:
	var candidate := CoopWorld.new()
	if not candidate.open(document):
		return candidate.error
	var listener := TCPServer.new()
	var result := listener.listen(port)
	if result != OK:
		return "Cannot listen on TCP port %d: %s" % [port, error_string(result)]
	stop()
	world = candidate
	server = listener
	code = join_code
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	members[token] = {"name": player_name.left(32), "sequence": 0}
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
		"token": token, "name": player_name.left(32), "session": session_id})
	connection_changed.emit()
	return ""


func stop() -> void:
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
		identities[id] = message.token
		if not members.has(message.token):
			members[message.token] = {"name": message.name, "sequence": 0}
		requested_speed[message.token] = 2
		channels[id].send({"type": "welcome", "session": session_id, "next": int(members[message.token].sequence) + 1})
		channels[id].send(make_state())
		feedback.emit("%s joined Koop." % message.name)
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
		"ping":
			pass
		_:
			channels[0].failed = true


func make_state() -> Dictionary:
	var state := world.snapshot()
	var players: Array[String] = []
	for actor: String in requested_speed:
		players.append("%s (%s)" % [members[actor].name, "paused" if requested_speed[actor] == 1 else "playing"])
	state["players"] = players
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
			channels[id].send(state)


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
			identities.erase(id)
			disconnected_pause = true
			world.controller.set_speed(1)
			feedback.emit("%s disconnected. The host can release the disconnect pause." % members[actor].name)
	else:
		connected = false
		feedback.emit("Connection lost or refused. Check host, port and code, then reconnect. The view is frozen.")
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
		"dispatch": Array(world.dispatch_cycles), "dispatch_initialized": world.dispatch_initialized}
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
	publish()
	return ""
