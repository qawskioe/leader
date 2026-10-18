extends SceneTree
## Real Luau transport/runtime; a deterministic world double settles 0.50m,
## cancels before returning its receipt, and checks that no resume was sent.
const Runtime=preload("res://scripts/skills/luau_runtime.gd")
const SOURCE='return function() local result=world.request("approach",{object={observation_id="receipt_frame",position={x=0,y=0,z=1}},distance=0.45}) error("cancelled request resumed Luau") return result end'

class RecordedService extends "res://scripts/skills/luau_service.gd":
	var sent: Array=[]
	func send(value: Dictionary) -> String:
		sent.append(value.duplicate(true))
		return super.send(value)

class SettledWorld extends Node:
	var runtime: Node
	var owned:=false
	var calls:=0
	var moved_m:=0.0
	var settled: Dictionary={}
	func acquire() -> Dictionary:
		owned=true
		return {"ok":true}
	func cancel() -> void:
		owned=false
	func finish() -> Dictionary:
		owned=false
		return {"ok":true,"restored":false}
	func request(operation: String, arguments: Dictionary) -> Dictionary:
		assert(operation=="approach" and owned)
		calls+=1
		await get_tree().process_frame
		# This is the already-settled result, not a cancellation result fabricated
		# afterward. Match the real adapter's result-before-cancel checkpoint.
		moved_m=0.50
		settled={"ok":true,"code":"arrived","scope":"selected_ground_point_only","selected_target":arguments.object.duplicate(true),"standing_position":{"observation_id":"receipt_frame","position":{"x":0.0,"y":0.0,"z":0.5}},"distance_to_selected_point_m":0.5,"touch_contacts":{},"message":"fixture actually settled 0.50m before runtime cancellation"}
		runtime.cancel()
		assert(not owned and runtime._pending_operations==1)
		await get_tree().process_frame
		return settled

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(15).timeout.connect(func():push_error("CANCELLED_APPROACH_RECEIPT_TIMEOUT");quit(1))
	var service:=RecordedService.new();root.add_child(service)
	var runtime:=Runtime.new();runtime.service=service;root.add_child(runtime)
	var api:=SettledWorld.new();api.runtime=runtime;root.add_child(api)
	var observations:={"finished":0,"pending_at_finish":-1}
	runtime.finished.connect(func(_result: Dictionary):
		observations.finished+=1
		observations.pending_at_finish=runtime._pending_operations)
	var result: Dictionary=await runtime.run(SOURCE,{},{},api,["approach"])
	assert(result.status=="cancelled" and api.calls==1 and api.moved_m==0.50)
	assert(observations.finished==1 and observations.pending_at_finish==0 and runtime._pending_operations==0)
	var resumes:=0
	for message in service.sent:
		if message.op=="resume":resumes+=1
	assert(resumes==0,"cancelled world result must never resume Luau")
	var trace: Array=result.get("trace",[])
	if trace.is_empty() or trace[-1].get("operation")!="approach":
		push_error("CANCELLED_APPROACH_RECEIPT_MISSING: actual_moved_m=0.50; trace_entries=%d; resumes=%d"%[trace.size(),resumes])
		quit(1)
		return
	var actual: Dictionary=trace[-1].result
	assert(JSON.stringify(actual)==JSON.stringify(api.settled),"the settled world receipt must survive cancellation byte for byte")
	assert(trace[-1].arguments.object==api.settled.selected_target and trace[-1].get("elapsed_ms",-1)>=0)
	assert(result.operation_elapsed_ms.has("approach"),"operation timing must include the drained step")
	for frame in 3:await process_frame
	for message in service.sent:
		assert(message.op!="resume","late cancellation cleanup must not send resume")
	assert(observations.finished==1,"late service cancellation must not finish twice")
	print("CANCELLED_APPROACH_RECEIPT_PASSED ",JSON.stringify({"status":result.status,"actual_moved_m":api.moved_m,"trace_entries":trace.size(),"receipt_equal":true,"resumes":resumes,"pending_at_finish":observations.pending_at_finish,"model_calls":0}))
	runtime.queue_free();api.queue_free();service.queue_free();await process_frame
	quit()
