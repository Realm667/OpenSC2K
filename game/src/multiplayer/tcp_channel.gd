class_name CityTcpChannel
extends RefCounted
## Length-prefixed UTF-8 JSON. Reads and writes never wait for a complete frame.

const MAX_FRAME := 4 * 1024 * 1024
const IO_BUDGET := 256 * 1024
var socket: StreamPeerTCP
var input := PackedByteArray()
var output := PackedByteArray()
var limit := MAX_FRAME
var failed := false
var last_received := Time.get_ticks_msec()
var low_latency := false


func _init(peer: StreamPeerTCP, receive_limit := MAX_FRAME) -> void:
	socket = peer
	limit = receive_limit


func send(message: Dictionary) -> bool:
	var body := JSON.stringify(message).to_utf8_buffer()
	if body.size() > MAX_FRAME or output.size() + body.size() + 4 > MAX_FRAME * 2:
		failed = true
		return false
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, body.size())
	output.append_array(header)
	output.append_array(body)
	return true


func poll() -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	socket.poll()
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - last_received > 10000:
			failed = true
		return messages
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		failed = true
		return messages
	if not low_latency:
		socket.set_no_delay(true)
		low_latency = true
	flush()
	var available := mini(socket.get_available_bytes(), IO_BUDGET)
	if available > 0:
		var received := socket.get_partial_data(available)
		if received[0] != OK:
			failed = true
			return messages
		input.append_array(received[1])
		last_received = Time.get_ticks_msec()
	if input.size() > limit + IO_BUDGET:
		failed = true
		return messages
	for _index in 16:
		if input.size() < 4:
			break
		var size := input.decode_u32(0)
		if size < 2 or size > limit:
			failed = true
			break
		if input.size() < size + 4:
			break
		var parser := JSON.new()
		if parser.parse(input.slice(4, size + 4).get_string_from_utf8()) != OK or not parser.data is Dictionary:
			failed = true
			break
		messages.append(parser.data)
		input = input.slice(size + 4)
	if Time.get_ticks_msec() - last_received > 30000:
		failed = true
	return messages


func close() -> void:
	socket.disconnect_from_host()
	failed = true


func flush() -> void:
	if failed or output.is_empty() or socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var sent := socket.put_partial_data(output.slice(0, IO_BUDGET))
	if sent[0] != OK:
		failed = true
		return
	output = output.slice(int(sent[1]))
