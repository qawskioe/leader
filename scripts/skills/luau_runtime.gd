extends Node
## 代码始终在服务中；Godot只执行世界请求，主体由本次调用绑定而非脚本自报。
signal finished(result: Dictionary)
signal operations_drained
var _pending_operations:=0
var service: Node
var api: Node
var invocation:=""
var running:=false
var trace: Array=[]
var _generation:=0
var _sequence:=0
var _started_ms:=0

func is_starting() -> bool:
	return running and _sequence==0

func run(source: String, arguments: Dictionary, context: Dictionary, adapter: Node, capabilities: Array) -> Dictionary:
	assert(not running and _pending_operations==0)
	api=adapter
	var acquired: Dictionary=api.acquire()
	if not acquired.ok: return {"status":"error","code":acquired.code}
	var error: String=service.start()
	if error!="": await api.finish();return {"status":"error","code":error}
	running=true;trace.clear();_generation+=1;_sequence=0;_started_ms=Time.get_ticks_msec()
	invocation="call_%d_%d"%[get_instance_id(),Time.get_ticks_usec()]
	service.message_received.connect(_message)
	error=service.send({"op":"start","id":invocation,"source":source,"arguments":arguments,"context":context,"capabilities":capabilities})
	# 未发送的start可能同步失败；直接返回清理结果，不能先emit再等待同一个信号。
	if error!="":return await _complete({"status":"error","code":error,"trace":trace.duplicate(true)})
	return await finished

func _message(event: Dictionary) -> void:
	if not running or event.get("id")!=invocation: return
	if event.type=="world_request":
		if event.sequence!=_sequence+1: _complete({"status":"error","code":"invalid_sequence"});return
		_sequence=event.sequence
		_execute(event,_generation)
	elif event.type=="completed": _complete({"status":"completed","returned":event.get("result"),"trace":trace.duplicate(true)})
	elif event.type in ["failed","cancelled"]: _complete({"status":"error","code":event.get("error",event.type),"trace":trace.duplicate(true)})

func _execute(event: Dictionary, generation: int) -> void:
	_pending_operations+=1
	var started:=Time.get_ticks_msec()
	var result: Dictionary=await api.request(event.request.operation,event.request.arguments)
	# 取消/失败只结束Lua续跑；正在排空的世界请求仍可能返回已结算的真实结果。
	# drained会同步唤醒_complete，必须先存回执，不能让下一次调用丢失实际进展。
	if generation==_generation or (not running and generation+1==_generation):
		trace.append({"operation":event.request.operation,"arguments":event.request.arguments,"result":result,"elapsed_ms":Time.get_ticks_msec()-started})
	_pending_operations-=1
	if _pending_operations==0: operations_drained.emit()
	if not running or generation!=_generation: return
	var error: String=service.send({"op":"resume","id":invocation,"sequence":event.sequence,"result":result})
	if error!="":
		# 世界操作已经发生；结束原生等待协程并保留真实轨迹，不回滚或重放，也不中止其他调用。
		service.send({"op":"cancel","id":invocation})
		_complete({"status":"error","code":error,"trace":trace.duplicate(true)})

func _complete(result: Dictionary) -> Dictionary:
	if not running: return {}
	running=false;_generation+=1
	service.message_received.disconnect(_message)
	if result.get("status")!="completed":
		api.cancel()
		# 取消先让世界协程退出；否则控制器释放adapter时仍有伸手/移动协程挂起。
		if _pending_operations>0: await operations_drained
		result["trace"]=trace.duplicate(true)
	else:
		var cleanup: Variant=await api.finish()
		if cleanup is Dictionary and cleanup.get("restored",false):
			trace.append({"operation":"host_restore_idle","arguments":{},"result":cleanup,"elapsed_ms":cleanup.get("elapsed_ms",0)})
			result["trace"]=trace.duplicate(true)
	result["elapsed_ms"]=Time.get_ticks_msec()-_started_ms
	result["operation_elapsed_ms"]={}
	for step in trace:
		result.operation_elapsed_ms[step.operation]=result.operation_elapsed_ms.get(step.operation,0)+step.get("elapsed_ms",0)
	finished.emit(result)
	return result

func cancel() -> void:
	if not running: return
	if service.process_id>0: service.send({"op":"cancel","id":invocation})
	_complete({"status":"cancelled","trace":trace.duplicate(true)})

func _exit_tree() -> void: cancel()
