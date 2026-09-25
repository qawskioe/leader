extends SceneTree
class WorldDouble extends Node:
	var changed:=0
	var owned:=false
	func acquire() -> Dictionary: owned=true;return {"ok":true}
	func finish() -> void: owned=false
	func cancel() -> void: owned=false
	func request(operation: String, args: Dictionary) -> Dictionary:
		await get_tree().create_timer(0.01).timeout
		if not owned: return {"ok":false,"code":"cancelled"}
		if operation=="count": changed+=int(args.amount)
		return {"ok":true,"changed":changed}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var service=load("res://scripts/skills/luau_service.gd").new();root.add_child(service)
	var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;root.add_child(runtime)
	var api:=WorldDouble.new();root.add_child(api)
	var result: Dictionary=await runtime.run('return function(args, context) local function twice(x) return x*2 end local r=world.request("count",{amount=twice(args.amount)}) return {ok=r.ok,total=r.changed} end',{"amount":3},{},api,["count"])
	assert(result.status=="completed" and result.returned.total==6 and api.changed==6)
	# 大消息持续收到分块确认时不应触发两秒无响应超时。
	result=await runtime.run('return function(args, context) return {ok=true,size=#context.payload} end',{},{"payload":"x".repeat(131072)},api,[])
	assert(result.status=="completed" and result.returned.size==131072,"完整传输大上下文，不能把传输中误报为服务失联")
	create_timer(0.005).timeout.connect(runtime.cancel)
	result=await runtime.run('return function() return world.request("count",{amount=100}) end',{},{},api,["count"])
	assert(result.status=="cancelled")
	await create_timer(0.1).timeout
	assert(api.changed==6,"取消后的世界请求不得继续生效")
	# 服务退出发生在世界操作之前，不能通过重试偷偷产生一次动作。
	create_timer(0.005).timeout.connect(func():
		if service.process_id>0: OS.kill(service.process_id))
	result=await runtime.run('return function() while true do end end',{},{},api,[])
	assert(result.status=="error" and not api.owned)
	assert(api.changed==6)
	print("LUAU_BRIDGE_PASSED async_world_response, functions, cancellation; main_dispatch_max_ms=",service.max_dispatch_ms)
	runtime.queue_free();api.queue_free();service.queue_free();await process_frame;quit()
