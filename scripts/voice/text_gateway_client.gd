extends Node
## 只有回环网关使用 HTTP；上游令牌由 Python 服务持有。
const KEY_PATH := "res://services/text-gateway/runtime/gateway-key.txt"
const ENDPOINT := "http://127.0.0.1:18090/game/exchange"

static func config_error() -> String:
	if not FileAccess.file_exists(KEY_PATH):
		return "未找到本机 文字网关 网关密钥，请先启动 services/text-gateway/start.cmd"
	if not FileAccess.file_exists("res://services/text-gateway/runtime/text_model.json"):
		return "缺少本机文字模型配置 runtime/text_model.json"
	return ""

func exchange(payload: Dictionary) -> Dictionary:
	var error := config_error()
	if not error.is_empty():
		return {"ok":false,"error":error}
	var key := FileAccess.get_file_as_string(KEY_PATH).strip_edges()
	if key.is_empty():
		return {"ok":false,"error":"本机 文字网关 网关密钥为空"}
	var request := HTTPRequest.new()
	request.timeout = 165.0
	request.body_size_limit = 8 * 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	var started := Time.get_ticks_msec()
	var err := request.request(ENDPOINT, PackedStringArray(["Content-Type: application/json","Authorization: Bearer " + key]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()
		return {"ok":false,"error":"无法向本地 文字网关 发起请求：%d" % err}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok":false,"error":"本地 文字网关 连接失败或超时；请确认 start.cmd 已启动，结果码 %d" % response[0]}
	if response[1]==422:
		var validation: Variant=JSON.parse_string(response[3].get_string_from_utf8())
		if validation is Dictionary and validation.get("detail") is Array:
			for issue in validation.detail:
				if issue is Dictionary and issue.get("type")=="string_too_long":
					return {"ok":false,"error":"当前文字上下文%d字，超过网关%d字限制；尚未调用模型，未丢弃记忆。"%[str(payload.get("prompt","")).length(),int(issue.get("ctx",{}).get("max_length",0))]}
		return {"ok":false,"error":"文字网关拒绝请求格式（HTTP 422），尚未调用模型"}
	if response[1] != 200:
		return {"ok":false,"error":"本地 文字网关 HTTP %d（401：密钥不符；429：服务正忙）" % response[1]}
	var body: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return decode_body(body,Time.get_ticks_msec()-started)

static func decode_body(body: Variant, elapsed_ms: int) -> Dictionary:
	if not body is Dictionary or not body.get("ok") is bool:
		return {"ok":false,"error":"文字网关 响应格式无效"}
	if body.ok and (not body.get("text") is String or body.text.strip_edges().is_empty()):
		return {"ok":false,"error":"文字网关 返回空文本"}
	if not body.ok:
		body["error"]=str(body.get("error","文字网关 请求失败"))
		var first: Variant=body.get("fallback_from",{})
		if first is Dictionary and first.has("model") and first.has("error"):
			body.error="主模型 %s 失败（%s）；备用 %s 失败（%s）"%[str(first.model),str(first.error),str(body.get("model","未知模型")),body.error]
	body["elapsed_ms"] = elapsed_ms
	return body
