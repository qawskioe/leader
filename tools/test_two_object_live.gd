extends SceneTree
class RecordedGateway extends "res://scripts/voice/text_gateway_client.gd":
	var requests: Array=[]
	func exchange(payload: Dictionary) -> Dictionary:
		requests.append(payload.duplicate(true))
		return await super.exchange(payload)
var reports: Array=[]
var executions: Array=[]
var one_at_time:=OS.get_cmdline_user_args().has("--one-at-time")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/conversation_%d.json"%Time.get_ticks_usec())
	voice.config.tts_enabled=false
	var recorded:=RecordedGateway.new();voice.add_child(recorded);voice.pipeline.gateway=recorded
	voice.pipeline.report_ready.connect(func(r): reports.append(r))
	voice.skills.finished.connect(func(r): executions.append(r))
	# 重放玩家澄清后用省略句启动两件物品搬运的失败现场。
	voice.store.hear("person_003",{"id":"clarification","speaker":"player","text":"分两趟搬，先把石块放到池塘外干地，再回来拿木块放到干地。不要同时拿两件。" if one_at_time else "我是说把石头和木块一起放到池塘的外面。"})
	voice.store.remember("person_003","clarification",{"private_interpretation":"理解两件物品的目标","public_reply":"明白，先搬石块，放好后回来取木块，分两趟。" if one_at_time else "明白，把这块石头和木块一起放到池塘外的干地上。"})
	voice.store.mark_reply("person_003","clarification","已播放完成；附近成员听闻另行记录")
	await say(voice,"start_both","没错，开始动手。")
	var placed: Array=[]
	for result in executions:
		if result.success and result.get("runtime",{}).get("returned",{}).get("code")=="placed": placed.append(result.object_id)
	var objects: Dictionary={}
	var passed:=true
	for id in ["stone_tool","wood_block"]:
		var object: Dictionary=voice.skills.world_objects.objects[id]
		var dry:=on_dry_ground(scene,object.body)
		objects[id]={"held":object.holder,"dry":dry,"placed":id in placed}
		passed=passed and object.holder.is_empty() and dry and id in placed
	passed=passed and not reports.is_empty() and reports[-1].get("decision",{}).get("task_status")=="completed"
	if one_at_time:
		var stone_placed:=false
		var returned_for_wood:=false
		for result in executions:
			if result.success and result.get("runtime",{}).get("returned",{}).get("code")=="placed" and result.object_id=="stone_tool":stone_placed=true
			if result.success and result.get("runtime",{}).get("returned",{}).get("code")=="grasped" and result.object_id=="wood_block":returned_for_wood=stone_placed
		passed=passed and returned_for_wood
	var report_path:="res://services/luau-runtime/runtime/two_object_return_live.json" if one_at_time else "res://services/luau-runtime/runtime/two_object_live.json"
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"objects":objects,"reports":reports,"executions":executions,"requests":recorded.requests},"  "));file.close()
	print("TWO_OBJECT_LIVE_", "PASSED" if passed else "FAILED")
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
func say(voice: Node, id: String, text: String) -> void:
	voice.busy=true;voice._allow_execution=true;voice._decisions_done=false;voice._event_started=Time.get_ticks_msec();voice._job_config=voice.config.duplicate(true)
	voice._start_pipeline({"id":id,"kind":"speech_intent","speaker":"player","text":text,"listeners":["person_003"],"spatial_segments":[{"text":text,"focus_hint":"person_003","audience":{"person_003":{"angle_degrees":0,"distance_m":1.2}}}]},voice._job_config)
	var deadline:=Time.get_ticks_msec()+240000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not voice.busy and voice.skills.active.is_empty() and voice.autonomy.requests.is_empty():return
	assert(false,"真实模型任务超时")

func on_dry_ground(scene: Node3D, body: RigidBody3D) -> bool:
	var at:=body.global_position
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2,1,[body.get_rid()]))
	if hit.is_empty(): return false
	for label in ["WaterPool","Cenote_water"]:
		var mesh:=scene.find_child(label,true,false) as MeshInstance3D
		var start: Vector3=mesh.to_local(hit.position+Vector3.UP*2)
		var finish: Vector3=mesh.to_local(hit.position)
		var triangles:=mesh.mesh.get_faces()
		for index in range(0,triangles.size(),3):
			if Geometry3D.segment_intersects_triangle(start,finish,triangles[index],triangles[index+1],triangles[index+2])!=null: return false
	return true
