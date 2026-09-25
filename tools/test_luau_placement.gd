extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/test_placement_%d.json"%Time.get_ticks_usec())
	var refs: Dictionary={}
	for entry in voice.skills.library.describe("person_003"): refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	voice.survival.perception.observe("person_003")
	var snapshot: Dictionary=voice.survival.space.capture("person_003")
	var target: Dictionary={"observation_id":snapshot.id,"position":snapshot.near_field.landmarks["surface/person/person_003"].position}
	print("SURFACE ",target)
	var original_position: Vector3=voice.survival.actors.person_003.body.global_position
	var rejected: Dictionary=voice.skills.invoke("person_003","without_object",{"ref":refs.place_object,"arguments":{"object":"wood_block","target":{"observation_id":snapshot.id,"position":{"x":0,"y":0,"z":2}}}})
	assert(rejected.ok)
	var missing: Dictionary=await voice.skills.finished
	assert(not missing.success and missing.runtime.returned.code=="not_held")
	assert(voice.survival.actors.person_003.body.global_position.distance_to(original_position)<0.01,"未持有时不得先走开")
	for id in ["wood_block","stone_tool"]:
		var taken: Dictionary=voice.skills.invoke("person_003","take_"+id,{"ref":refs.take_object,"arguments":{"object":id}})
		if not taken.ok: print("FAIL ",taken);quit(1);return
		var result: Dictionary=await voice.skills.finished
		if not result.success: print("FAIL TAKE ",result);quit(1);return
		if id=="stone_tool":
			snapshot=voice.survival.space.capture("person_003")
			target={"observation_id":snapshot.id,"position":snapshot.near_field.landmarks["surface/person/person_003"].position}
		voice.survival.perception.observe("person_003")
		var call: Dictionary={"ref":refs.place_object,"arguments":{"object":id,"target":target}}
		if OS.get_cmdline_user_args().has("--cloud") and id=="wood_block":
			voice.survival._sync("person_003")
			var gateway=preload("res://scripts/voice/text_gateway_client.gd").new();scene.add_child(gateway)
			var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=voice.store;pipeline.space=voice.survival.space;pipeline.gateway=gateway;scene.add_child(pipeline)
			var reports: Array=[];pipeline.report_ready.connect(func(report): reports.append(report))
			var text:="大山，把木块放在你的脚下。"
			pipeline.run({"id":"placement_model_test","kind":"speech_intent","speaker":"player","text":text,"listeners":["person_003"],"spatial_segments":[{"text":text,"focus_hint":"person_003","audience":{"person_003":{"angle_degrees":0,"distance_m":1.2}}}]},{})
			await pipeline.completed
			if reports.size()!=1 or reports[0].has("error"):
				print("FAIL MODEL ",reports);quit(1);return
			call=reports[0].decision.get("skill_call",{})
			if call.get("ref")!=refs.place_object or call.get("arguments",{}).get("object")!=id or not call.arguments.get("target") is Dictionary:
				print("FAIL MODEL TARGET ",reports[0].decision);quit(1);return
			print("LUAU_PLACEMENT_MODEL_PASSED ",call)
			pipeline.queue_free();gateway.queue_free()
		var submitted: Dictionary=voice.skills.invoke("person_003","place_"+id,call)
		if not submitted.ok: print("FAIL ",submitted);quit(1);return
		result=await voice.skills.finished
		if not result.success or not result.goal_verified: print("FAIL PLACE ",result);quit(1);return
		# 避免第二次的真实障碍干扰目标达成测试。
		voice.skills.world_objects.objects[id].body.global_position+=Vector3(3,0,0)
		await physics_frame;await physics_frame
		assert(voice.skills.world_objects.objects[id].body.get_collision_exceptions().is_empty(),"分离后必须恢复人物碰撞")
	# 普通松手单独验证：不指定落点，保留重力与碰撞，不追求原地静止。
	var motor=preload("res://scripts/skills/body_motor.gd").new();motor.initialize(voice.survival.actors.person_003,"person_003")
	var stone: RigidBody3D=voice.skills.world_objects.objects.stone_tool.body
	stone.global_position=motor.point("Hand.R")-Vector3.UP*0.06
	assert(voice.skills.world_objects.grasp("stone_tool","person_003","Hand.R",motor).ok)
	assert(voice.skills.world_objects.release("stone_tool","person_003").ok)
	var released_y:=stone.global_position.y
	for frame in 15: await physics_frame
	assert(not stone.freeze and stone.global_position.y<released_y-0.05,"松手后须自然下落")
	assert(stone.collision_layer==1 and stone.collision_mask==1 and stone.get_collision_exceptions().is_empty(),"松手不能豁免碰撞")
	# 未观察到的目标不能凭空放置，更不能松手后宣称完成。
	var api=preload("res://scripts/skills/luau_world_adapter.gd").new();api.sim=voice.survival;api.person_id="person_003";api.objects=voice.skills.world_objects;scene.add_child(api)
	assert(not api.resolve_surface("surface/unknown").ok)
	voice.survival.perception.observe("person_003")
	snapshot=voice.survival.space.capture("person_003")
	var chosen={"observation_id":snapshot.id,"position":{"x":0.1,"y":0,"z":0.6}}
	var located: Dictionary=api.resolve_surface(chosen)
	assert(located.ok,"模型所选的可见相对地面坐标可被查询")
	assert(absf(located.position.x-0.1)<0.001 and absf(located.position.z-0.6)<0.001,"程序不得改写模型选定的水平位置")
	assert(not api.resolve_surface({"observation_id":snapshot.id,"position":{"x":0,"y":0,"z":-4}}).ok,"背后不可见目标不能凭空确认为可用")
	# 结果查询接受有效观察坐标，不依赖调用者曾缓存同一浮点文本键。
	assert(api.acquire().ok)
	var object_state: Dictionary=await api.request("observe",{"object":"stone_tool"})
	assert(object_state.ok and object_state.has("bottom_position") and object_state.has("speed_mps"))
	var bottom_world: Dictionary=voice.survival.space.resolve("person_003",{"observation_id":object_state.observation_id,"position":object_state.bottom_position})
	assert(bottom_world.position.distance_to(api.objects.bottom("stone_tool"))<0.001)
	var chest: Dictionary=await api.request("body_point",{"point":"Chest"})
	assert(chest.ok)
	var located_chest: Dictionary=voice.survival.space.resolve("person_003",chest.target)
	assert(located_chest.position.distance_to(api.motor.point("Chest"))<0.001)
	assert(not (await api.request("body_point",{"point":"other_person/Chest"})).ok)
	api.placement_targets.clear()
	var corrected:={"observation_id":located.observation_id,"position":located.position}
	var measured: Dictionary=await api.request("check_placement",{"object":"stone_tool","target":corrected})
	assert(measured.code in ["placed","not_at_destination"],"有效支撑点应得到真实测量，而非placement_not_attempted")
	var denied: Dictionary=await api.request("check_placement",{"object":"stone_tool","target":{"observation_id":"unknown_frame","position":{"x":0,"y":0,"z":1}}})
	assert(not denied.ok and denied.code=="unknown_observation","新查询也不能绕过观察权限")
	await api.finish()
	print("LUAU_PLACEMENT_PASSED ground_pickup_and_placement_natural_drop_no_exceptions")
	scene.queue_free();await create_timer(0.2).timeout;quit()
