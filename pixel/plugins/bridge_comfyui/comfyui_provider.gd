class_name PFComfyUIProvider
extends PFProvider

## Local/LAN ComfyUI adapter using official /prompt, /ws, /history, /view and /interrupt routes.

const TaskScript := preload("res://services/pf_task.gd")
const HttpClientScript := preload("res://infra/http_client.gd")
const Templates := preload("res://plugins/bridge_comfyui/workflow_template.gd")
const IdUtil := preload("res://core/util/id_util.gd")

const PROVIDER_ID := "comfyui"
const DEFAULT_ENDPOINT := "http://127.0.0.1:8188"
const POLL_INTERVAL_SECONDS := 0.15
const MAX_POLLS := 1200

var _request_host: Node = null
var _http: Node = null
var _endpoint := DEFAULT_ENDPOINT
var _default_template := "sdxl_pixel_txt2img"
var _template_dir := "user://comfyui_templates"
var _templates := {}
var _active_requests := {}
var _prompt_ids := {}


func get_id() -> String:
	return PROVIDER_ID


func get_display_name() -> String:
	return "ComfyUI (Local / LAN)"


func get_api_version() -> int:
	return 1


func get_capabilities() -> Dictionary:
	var has_inpaint := false
	for template in _templates.values():
		has_inpaint = has_inpaint or String(Dictionary(template).get("mode", "")) == "inpaint"
	return {
		"txt2img": true,
		"img2img": true,
		"inpaint": has_inpaint,
		"transparent_bg": false,
		"native_pixel": false,
		"max_batch": 1,
		"sizes": [[64, 64], [2048, 2048]],
		"animation": false,
		"cost_estimate": false,
	}


func get_config_schema() -> Array[Dictionary]:
	return [
		{
			"key": "endpoint",
			"label": "ComfyUI endpoint",
			"kind": "text",
			"default": DEFAULT_ENDPOINT,
		},
		{
			"key": "default_template",
			"label": "Default workflow template id",
			"kind": "text",
			"default": "sdxl_pixel_txt2img",
		},
		{
			"key": "template_dir",
			"label": "Imported API workflow template directory",
			"kind": "text",
			"default": "user://comfyui_templates",
		},
	]


func attach_request_host(host: Node) -> void:
	_request_host = host
	if _http == null:
		_http = HttpClientScript.new()
		_http.name = "ComfyUIHttpClient"
		host.add_child(_http)


func configure(config: Dictionary) -> Variant:
	_endpoint = String(config.get("endpoint", DEFAULT_ENDPOINT)).strip_edges().trim_suffix("/")
	if not _endpoint.begins_with("http://") and not _endpoint.begins_with("https://"):
		return _error("invalid_request", "ComfyUI endpoint must use http:// or https://")
	_default_template = String(config.get("default_template", "sdxl_pixel_txt2img"))
	_template_dir = String(config.get("template_dir", "user://comfyui_templates"))
	_reload_templates()
	if not _templates.has(_default_template):
		_default_template = "sdxl_pixel_txt2img"
	return null


func validate_credentials() -> Variant:
	if _http == null:
		return null
	return _http.request_json(
		HTTPClient.METHOD_GET,
		_endpoint + "/system_stats",
		PackedStringArray(),
		null,
		{"timeout": 10.0, "transform": _decode_validation}
	)


func generate(request: Dictionary) -> Variant:
	if _request_host == null:
		return null
	var task := TaskScript.new("comfyui_generate", {"endpoint": _endpoint})
	task.configure_external(_start_generation.bind(request), _cancel_task)
	return task


func estimate_cost(_request: Dictionary) -> float:
	return 0.0


func cancel(task_id: String) -> void:
	if _active_requests.has(task_id):
		_cancel_task(_active_requests[task_id].get("task"))


func clear_session_config() -> void:
	if _http != null:
		_http.cancel_all()
	for task_id in _active_requests.keys():
		var task: Variant = _active_requests[task_id].get("task")
		if task != null:
			task.cancel()


func has_session_credentials() -> bool:
	return true


func get_template_ids() -> Array:
	var ids: Array = _templates.keys()
	ids.sort()
	return ids


func import_template_file(path: String) -> Dictionary:
	var source := Templates.load_from_path(path)
	if source.is_empty():
		return _error("invalid_request", "Workflow template JSON could not be read")
	var template := source
	if not source.has("workflow"):
		var slots := Templates.discover_slots(source)
		var bindings := {}
		for slot in slots:
			var field := String(slot.get("field", ""))
			if not bindings.has(field):
				bindings[field] = String(slot.get("path", ""))
		template = Templates.import_api_workflow(
			source, path.get_file().get_basename(), path.get_file().get_basename(), bindings
		)
	return save_template(template)


func save_template(template: Dictionary) -> Dictionary:
	if not template.has("id") or not template.has("workflow"):
		return _error("invalid_request", "Template requires id and workflow")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_template_dir))
	var destination := _template_dir.path_join("%s.json" % String(template.get("id", "workflow")))
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return _error("provider_internal", "Workflow template could not be saved")
	file.store_string(JSON.stringify(template, "  "))
	_reload_templates()
	return {"ok": true, "template": template, "path": destination}


func build_workflow(request: Dictionary, upload_name: String = "") -> Dictionary:
	var extra: Dictionary = request.get("extra", {})
	var template_id := String(extra.get("template_id", _default_template))
	var template: Dictionary = _templates.get(template_id, {})
	return Templates.fill(template, request, upload_name) if not template.is_empty() else {}


func parse_ws_message(message: Dictionary, prompt_id: String) -> Dictionary:
	var data: Dictionary = message.get("data", {})
	if String(data.get("prompt_id", "")) != prompt_id:
		return {}
	match String(message.get("type", "")):
		"progress":
			var maximum := maxf(1.0, float(data.get("max", 1.0)))
			return {"progress": clampf(float(data.get("value", 0.0)) / maximum, 0.0, 1.0)}
		"executing":
			return {"done": data.get("node", "sentinel") == null}
		"execution_error":
			return {"error": String(data.get("exception_message", "ComfyUI execution failed"))}
	return {}


func _start_generation(task: Variant, request: Dictionary) -> void:
	_active_requests[task.id] = {"task": task, "request": null}
	_run_generation(task, request)


func _run_generation(task: Variant, request: Dictionary) -> void:
	var upload_name := ""
	if request.get("ref_image") is Image:
		upload_name = "%s-input.png" % IdUtil.uuid_v4()
		var upload := await _upload_image(task, request["ref_image"], upload_name)
		if not bool(upload.get("ok", false)):
			_finish_rejected(task, upload.get("error", _error("network", "Image upload failed")))
			return
	var workflow := build_workflow(request, upload_name)
	if workflow.is_empty():
		_finish_rejected(task, _error("invalid_request", "ComfyUI workflow template is missing"))
		return
	var client_id := IdUtil.uuid_v4()
	var queued := await _request_json(
		task,
		HTTPClient.METHOD_POST,
		_endpoint + "/prompt",
		{"prompt": workflow, "client_id": client_id}
	)
	if not bool(queued.get("ok", false)):
		_finish_rejected(task, queued.get("error", _error("network", "ComfyUI queue failed")))
		return
	var prompt_id := String(Dictionary(queued.get("body", {})).get("prompt_id", ""))
	if prompt_id.is_empty():
		_finish_rejected(task, _error("provider_internal", "ComfyUI returned no prompt id"))
		return
	_prompt_ids[task.id] = prompt_id
	var socket := WebSocketPeer.new()
	socket.connect_to_url(_ws_url(client_id))
	for poll_index in range(MAX_POLLS):
		if task.cancel_requested:
			return
		_poll_socket(socket, task, prompt_id)
		var history := await _request_json(
			task, HTTPClient.METHOD_GET, _endpoint + "/history/%s" % prompt_id
		)
		if bool(history.get("ok", false)):
			var entry := _history_entry(Dictionary(history.get("body", {})), prompt_id)
			if not entry.is_empty() and Dictionary(entry).has("outputs"):
				var result := await _download_history_images(task, entry, prompt_id, request)
				if bool(result.get("ok", false)):
					_finish_resolved(task, result)
				else:
					_finish_rejected(
						task,
						result.get("error", _error("provider_internal", "Output download failed"))
					)
				return
		task.report_progress(minf(0.95, 0.05 + poll_index * 0.01), "Waiting for ComfyUI")
		await _request_host.get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
	_finish_rejected(task, _error("timeout", "ComfyUI did not finish before the local timeout"))


func _poll_socket(socket: WebSocketPeer, task: Variant, prompt_id: String) -> void:
	socket.poll()
	while socket.get_available_packet_count() > 0:
		if not socket.was_string_packet():
			socket.get_packet()
			continue
		var parsed: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if not (parsed is Dictionary):
			continue
		var event: Dictionary = parse_ws_message(parsed, prompt_id)
		if event.has("progress"):
			task.report_progress(float(event["progress"]), "ComfyUI sampling")


func _download_history_images(
	task: Variant, entry: Dictionary, prompt_id: String, request: Dictionary
) -> Dictionary:
	var images := []
	for output_value in Dictionary(entry.get("outputs", {})).values():
		for image_info_value in Dictionary(output_value).get("images", []):
			var image_info: Dictionary = image_info_value
			var url := (
				_endpoint
				+ (
					"/view?filename=%s&subfolder=%s&type=%s"
					% [
						String(image_info.get("filename", "")).uri_encode(),
						String(image_info.get("subfolder", "")).uri_encode(),
						String(image_info.get("type", "output")).uri_encode(),
					]
				)
			)
			var downloaded := await _request_raw(task, HTTPClient.METHOD_GET, url)
			if not bool(downloaded.get("ok", false)):
				continue
			var image := Image.new()
			if image.load_png_from_buffer(downloaded["body"]) == OK:
				if image.get_format() != Image.FORMAT_RGBA8:
					image.convert(Image.FORMAT_RGBA8)
				images.append(image)
	if images.is_empty():
		return {"ok": false, "error": _history_error(entry)}
	var seeds := []
	for index in range(images.size()):
		seeds.append(int(request.get("seed", -1)) + index)
	return {
		"ok": true,
		"images": images,
		"raw_pixel": false,
		"seeds": seeds,
		"cost": 0.0,
		"provider_meta":
		{
			"prompt_id": prompt_id,
			"template_id": request.get("extra", {}).get("template_id", _default_template)
		},
	}


func _upload_image(task: Variant, image: Image, file_name: String) -> Dictionary:
	var boundary := "----PixelForge%s" % IdUtil.uuid_v4().replace("-", "")
	var prefix := (
		(
			(
				'--%s\r\nContent-Disposition: form-data; name="image"; filename="%s"\r\n'
				% [boundary, file_name]
			)
			+ "Content-Type: image/png\r\n\r\n"
		)
		. to_utf8_buffer()
	)
	var suffix := (
		(
			'\r\n--%s\r\nContent-Disposition: form-data; name="type"\r\n\r\ninput\r\n--%s--\r\n'
			% [boundary, boundary]
		)
		. to_utf8_buffer()
	)
	var body := prefix
	body.append_array(image.save_png_to_buffer())
	body.append_array(suffix)
	return await _request_raw(
		task,
		HTTPClient.METHOD_POST,
		_endpoint + "/upload/image",
		PackedStringArray(["Content-Type: multipart/form-data; boundary=%s" % boundary]),
		body
	)


func _request_json(task: Variant, method: int, url: String, body: Variant = null) -> Dictionary:
	var bytes := PackedByteArray()
	var headers := PackedStringArray()
	if body != null:
		bytes = JSON.stringify(body).to_utf8_buffer()
		headers.append("Content-Type: application/json")
	var response := await _request_raw(task, method, url, headers, bytes)
	if not bool(response.get("ok", false)):
		return response
	var parsed: Variant = JSON.parse_string(
		PackedByteArray(response["body"]).get_string_from_utf8()
	)
	if not (parsed is Dictionary):
		return {
			"ok": false, "error": _error("provider_internal", "ComfyUI returned malformed JSON")
		}
	response["body"] = parsed
	return response


func _request_raw(
	task: Variant,
	method: int,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: PackedByteArray = PackedByteArray()
) -> Dictionary:
	if not _active_requests.has(task.id) or task.cancel_requested:
		return {"ok": false, "error": _error("cancelled", "ComfyUI task was canceled")}
	var request := HTTPRequest.new()
	request.timeout = 30.0
	_request_host.add_child(request)
	_active_requests[task.id]["request"] = request
	var error := request.request_raw(url, headers, method, body)
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": _error("network", "ComfyUI request could not start")}
	var completed: Array = await request.request_completed
	request.queue_free()
	if not _active_requests.has(task.id) or task.cancel_requested:
		return {"ok": false, "error": _error("cancelled", "ComfyUI task was canceled")}
	_active_requests[task.id]["request"] = null
	var result := int(completed[0])
	var status := int(completed[1])
	if result != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {"ok": false, "error": map_error(result, status, completed[3])}
	return {"ok": true, "status_code": status, "body": completed[3]}


func map_error(result: int, status: int, body: Variant = null) -> Dictionary:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return _error("timeout", "ComfyUI request timed out; confirm the local server is running")
	if result != HTTPRequest.RESULT_SUCCESS:
		return _error("network", "Could not reach ComfyUI; check endpoint, firewall, and server")
	var detail := ""
	if body is PackedByteArray:
		detail = body.get_string_from_utf8().left(500)
	return _error(
		"invalid_request" if status < 500 else "provider_internal",
		"ComfyUI rejected the workflow%s" % (": %s" % detail if not detail.is_empty() else "")
	)


func _cancel_task(task: Variant) -> void:
	if task == null or not _active_requests.has(task.id):
		return
	var request: HTTPRequest = _active_requests.get(task.id, {}).get("request")
	if request != null:
		request.cancel_request()
	_fire_interrupt()
	_active_requests.erase(task.id)
	_prompt_ids.erase(task.id)
	# External async tasks must settle so TaskQueue can emit its canceled terminal state.
	task.resolve(null)


func _fire_interrupt() -> void:
	if _request_host == null:
		return
	var request := HTTPRequest.new()
	_request_host.add_child(request)
	request.request_completed.connect(
		func(_a: int, _b: int, _c: PackedStringArray, _d: PackedByteArray) -> void:
			request.queue_free()
	)
	request.request_raw(
		_endpoint + "/interrupt",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		"{}".to_utf8_buffer()
	)


func _finish_resolved(task: Variant, result: Dictionary) -> void:
	if not _active_requests.has(task.id):
		return
	_active_requests.erase(task.id)
	_prompt_ids.erase(task.id)
	task.resolve(result)


func _finish_rejected(task: Variant, error: Dictionary) -> void:
	if not _active_requests.has(task.id):
		return
	_active_requests.erase(task.id)
	_prompt_ids.erase(task.id)
	task.reject(error)


func _history_entry(history: Dictionary, prompt_id: String) -> Dictionary:
	if history.has(prompt_id) and history[prompt_id] is Dictionary:
		return history[prompt_id]
	return history if history.has("outputs") else {}


func _history_error(entry: Dictionary) -> Dictionary:
	var messages: Array = Dictionary(entry.get("status", {})).get("messages", [])
	for message_value in messages:
		var message: Array = message_value
		if message.size() >= 2 and String(message[0]) == "execution_error":
			return _error(
				"provider_internal",
				String(Dictionary(message[1]).get("exception_message", "ComfyUI execution failed"))
			)
	return _error("provider_internal", "ComfyUI history contains no output image")


func _reload_templates() -> void:
	_templates.clear()
	for template_id in Templates.builtin_ids():
		_templates[template_id] = Templates.load_builtin(String(template_id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_template_dir))
	var directory := DirAccess.open(_template_dir)
	if directory != null:
		for file_name in directory.get_files():
			if file_name.ends_with(".json"):
				var template := Templates.load_from_path(_template_dir.path_join(file_name))
				if template.has("id") and template.has("workflow"):
					_templates[String(template["id"])] = template


func _ws_url(client_id: String) -> String:
	var base := _endpoint.replace("https://", "wss://").replace("http://", "ws://")
	return "%s/ws?clientId=%s" % [base, client_id.uri_encode()]


func _decode_validation(response: Dictionary) -> Dictionary:
	return {"ok": true, "result": response.get("body", {})}


func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}
