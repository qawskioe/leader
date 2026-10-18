extends SceneTree
## 真实原生服务：越界消息必须完成失败并释放占用，已发生的世界变化不能重放。
const Service=preload("res://scripts/skills/luau_service.gd")
const Runtime=preload("res://scripts/skills/luau_runtime.gd")
class WorldDouble extends Node:
	var owned:=false
	var changed:=0
	var large_reply:=false
	func acquire() -> Dictionary:owned=true;return {"ok":true}
	func finish() -> void:owned=false
	func cancel() -> void:owned=false
	func request(_operation: String,_arguments: Dictionary) -> Dictionary:
		await get_tree().process_frame
		changed+=1
		return {"ok":true,"padding":"x".repeat(1048576)} if large_reply else {"ok":true}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(10).timeout.connect(func():push_error("oversize message must finish instead of hanging");quit(1))
	var service:=Service.new();root.add_child(service)
	var runtime:=Runtime.new();runtime.service=service;root.add_child(runtime)
	var api:=WorldDouble.new();root.add_child(api)
	var finished: Array=[];runtime.finished.connect(func(result: Dictionary):finished.append(result))
	var result: Dictionary=await runtime.run('return function() return world.request("change",{}) end',{},{"payload":"x".repeat(1048576)},api,["change"])
	assert(result.status=="error" and result.code=="transport_message_too_large")
	assert(not runtime.running and not api.owned and api.changed==0 and finished.size()==1,"未发送的start必须释放占用且无世界动作")
	assert(service.active.is_empty() and service.expected.is_empty(),"拒绝发送不能留下等待回执")
	api.large_reply=true
	result=await runtime.run('return function() return world.request("change",{}) end',{},{},api,["change"])
	assert(result.status=="error" and result.code=="transport_message_too_large")
	assert(not runtime.running and not api.owned and api.changed==1 and finished.size()==2,"超限resume保留一次真实变化，不重放、不重复结束")
	assert(result.trace.size()==1 and result.trace[0].operation=="change")
	var deadline:=Time.get_ticks_msec()+2000
	while not service.active.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	assert(service.active.is_empty() and service.expected.is_empty(),"失效调用应取消原生协程，不中止共享服务")
	assert(service.process_id>0 and OS.is_process_running(service.process_id))
	api.large_reply=false
	result=await runtime.run('return function() local r=world.request("change",{}) return {ok=r.ok} end',{},{},api,["change"])
	assert(result.status=="completed" and result.returned.ok and api.changed==2 and finished.size()==3)
	assert(not api.owned and not runtime.running)
	print("LUAU_MESSAGE_BOUNDS_PASSED oversized_start_no_world_action_resume_preserves_fact_no_replay_released_native_coroutine_service_reusable; cloud_calls=0")
	runtime.queue_free();api.queue_free();service.queue_free();await process_frame;quit()
