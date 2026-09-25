extends SceneTree
func _initialize() -> void:
	var client=preload("res://scripts/voice/text_gateway_client.gd")
	var result: Dictionary=client.decode_body({"ok":false,"error":"DeepSeek HTTP 402","model":"deepseek","fallback_from":{"model":"luna","error":"HTTP 503"}},4321)
	assert(not result.ok and result.model=="deepseek" and result.elapsed_ms==4321)
	assert(result.fallback_from.model=="luna" and result.fallback_from.error=="HTTP 503")
	assert(result.error.contains("503") and result.error.contains("402") and result.error.contains("luna"))
	assert(not client.decode_body({"ok":true,"text":""},1).ok)
	assert(not client.decode_body([],1).ok)
	assert(client.decode_body({"ok":true,"text":"{}","model":"luna"},9).elapsed_ms==9)
	print("GATEWAY_FAILURE_PASSED primary_fallback_error_and_timing_preserved")
	quit()
