extends SceneTree
class OfflineGateway extends "res://scripts/voice/text_gateway_client.gd":
	var endpoint: String
	func exchange(payload: Dictionary) -> Dictionary:
		return await _request(endpoint,"fixture",payload)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var port:=int(OS.get_cmdline_user_args()[0])
	assert(port>0 and port<=65535)
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	var gateway:=OfflineGateway.new();gateway.endpoint="http://127.0.0.1:%d/pending"%port;root.add_child(gateway)
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new()
	pipeline.store=store;pipeline.gateway=gateway;root.add_child(pipeline)
	var reports: Array=[];pipeline.report_ready.connect(func(report):reports.append(report))
	pipeline.run({"id":"pending_network","speaker":"player","kind":"speech_intent","text":"请先听我说","listeners":["person_001","person_003"]},{})
	await create_timer(.2).timeout
	var before:=gateway.get_child_count()
	pipeline.cancel()
	await process_frame;await process_frame
	var pending:=gateway.get_child_count()
	print("GATEWAY_CANCELLATION_RESULT ",JSON.stringify({"before":before,"pending_after_cancel":pending,"reports_after_cancel":reports.size()}))
	if before!=2 or pending!=0 or not reports.is_empty():
		push_error("取消人物判断后不得保留在途HTTP等待或发布迟到决定")
		quit(1);return
	pipeline.queue_free();gateway.queue_free();await process_frame
	print("GATEWAY_CANCELLATION_PASSED native_requests_cancelled_await_released_no_late_report")
	quit()
