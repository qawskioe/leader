extends SceneTree
func _initialize() -> void:
	var client=preload("res://scripts/voice/text_gateway_client.gd")
	var attempts: Array=[{"role":"primary","elapsed_ms":12,"usage":null},{"role":"fallback","elapsed_ms":34,"usage":{"input_tokens":1}}]
	var result: Dictionary=client.decode_body({"ok":false,"error":"DeepSeek HTTP 402","model":"deepseek","fallback_from":{"model":"luna","error":"HTTP 503"},"attempts":attempts.duplicate(true)},4321)
	assert(not result.ok and result.model=="deepseek" and result.elapsed_ms==4321)
	assert(result.attempts==attempts,"客户端总时钟不能覆盖各次尝试耗时或将未知用量补零")
	assert(result.fallback_from.model=="luna" and result.fallback_from.error=="HTTP 503")
	assert(result.error.contains("503") and result.error.contains("402") and result.error.contains("luna"))
	assert(not client.decode_body({"ok":true,"text":""},1).ok)
	assert(not client.decode_body([],1).ok)
	var success: Dictionary=client.decode_body({"ok":true,"text":"{}","model":"luna","attempts":attempts.duplicate(true)},9)
	assert(success.elapsed_ms==9 and success.attempts==attempts)
	print("GATEWAY_FAILURE_PASSED primary_fallback_error_and_timing_preserved")
	quit()
