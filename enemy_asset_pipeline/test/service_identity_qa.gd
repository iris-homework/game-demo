extends Node
## Exercise the real workbench handshake without launching an editor or touching drafts.
class Probe extends "res://enemy_asset_pipeline/workbench.gd":
	var origin: String
	func _editor_url() -> String:
		return origin

var server := TCPServer.new()
var clients: Array[StreamPeerTCP] = []
var payload: Variant
var status := 200
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _process(_delta: float) -> void:
	while server.is_connection_available(): clients.append(server.take_connection())
	for client in clients.duplicate():
		client.poll()
		if client.get_available_bytes() == 0: continue
		client.get_data(client.get_available_bytes())
		var body := JSON.stringify(payload).to_utf8_buffer()
		client.put_data(("HTTP/1.1 %d Result\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]).to_utf8_buffer())
		client.put_data(body)
		clients.erase(client)

func _ready() -> void:
	check(server.listen(0, "127.0.0.1") == OK, "isolated HTTP listener")
	var probe := Probe.new()
	probe.origin = "http://127.0.0.1:%d" % server.get_local_port()
	probe.editor_request = HTTPRequest.new()
	probe.editor_request.timeout = 2.0
	add_child(probe.editor_request)
	probe.pipeline_label = Label.new()
	var identity := {"service":"midnight-enemy-pipeline", "test":false,
		"projectRoot":ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")}
	payload = identity.duplicate()
	check(await probe._server_alive(), "same project and formal mode can reuse service")
	check(not probe.server_conflict, "matching service is not a conflict")
	probe.test_mode = true
	check(not await probe._server_alive() and probe.server_conflict, "mode mismatch is refused")
	payload.test = true
	check(await probe._server_alive(), "same project and test mode can reuse service")
	probe.test_mode = false
	for invalid in [
		{"service":"midnight-enemy-pipeline", "test":false},
		{"service":"midnight-enemy-pipeline", "test":false, "projectRoot":identity.projectRoot+"-other"},
		{"service":"other-service", "test":false, "projectRoot":identity.projectRoot},
		[], null]:
		payload = invalid
		await probe.open_editor()
		check(probe.server_conflict, "foreign/old/invalid service is refused")
		check(probe.owned_server == -1, "refusal does not launch or kill a service")
		check(not probe.editor_opening and probe.pipeline_label.text.contains("占用"), "refusal gives an actionable message and permits retry")
	payload = identity
	status = 503
	check(not await probe._server_alive() and probe.server_conflict, "unhealthy occupied port is refused")
	server.stop()
	check(not await probe._server_alive() and not probe.server_conflict, "connection refused permits starting this project's service")
	probe.pipeline_label.free()
	probe.free()
	print("SERVICE_IDENTITY_QA checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
