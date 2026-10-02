extends SceneTree
class WaitingGateway extends Node:
	var space: RefCounted
	func exchange(_payload: Dictionary) -> Dictionary:
		var token: String=space.retained_frames.keys()[0]
		for index in 70:space.capture("person_002")
		assert(space.frames.has(token),"模型等待期间其他人物观察不能淘汰本轮坐标")
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify({"capability_gap":null,"intent":"none","public_reply":"","speech_style":"","private_interpretation":"当前没有待办","routing_reason":"等待","speech_act":"statement","addressed_person":"","task_status":"none","task_handling":{"state":"none","scope":"independent","reason":"无待办"},"conversation":{"participation":"listen","addressees":[],"reason":"身体通知"}})}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("space test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/frame_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var space: RefCounted=voice.survival.space
	var actor: Node3D=voice.survival.actors.person_003.body
	actor.rotation.y=0
	var original:=actor.global_position
	voice.survival.perception._record("person_003","known_far_tree","landmark",original+Vector3(31,2,43),true,{"name":"以前见过的大树"})
	voice.survival.perception.memories.person_003.known_far_tree.visible_now=false
	var snapshot: Dictionary=space.capture("person_003")
	assert(not snapshot.far_field.has("landmarks") and not snapshot.near_field.landmarks.has("known_far_tree"),"不自动倾倒远处地标记忆")
	var recalled: Dictionary=space.recalled_landmark("person_003",voice.survival.perception.known("person_003","known_far_tree"),snapshot.id)
	assert(recalled.approx_position=={"x":-30.0,"y":0.0,"z":40.0} and not recalled.has("position") and recalled.position_error_per_axis_m==5)
	assert(snapshot.near_field.landmarks.has("wood_block"))
	assert(snapshot.near_field.held_objects.is_empty())
	var underwater: Array=snapshot.near_field.ground_samples.filter(func(s):return s.get("surface_kind")=="submerged_ground")
	var dry: Array=snapshot.near_field.ground_samples.filter(func(s):return s.get("surface_kind")=="dry_ground")
	assert(not underwater.is_empty() and not dry.is_empty(),"初始视野应区别水底和露出水面的岸边地面")
	for sample in underwater: assert(sample.water_surface.y>=sample.position.y)
	for region in snapshot.near_field.regions:
		for p in region.visible_boundary_points:
			var at: Vector3=space.frames[snapshot.id].transform*Vector3(p.x,p.y,p.z)
			assert(voice.survival.perception.sees("person_003",at+Vector3.UP*0.03),"不能泄露被遮挡的边界")
	var adapter=preload("res://scripts/skills/luau_world_adapter.gd").new()
	adapter.sim=voice.survival;adapter.person_id="person_003";adapter.objects=voice.skills.world_objects;root.add_child(adapter)
	var invalid: Dictionary=adapter.resolve_surface({"observation_id":snapshot.id,"position":{"x":0,"y":8,"z":1}})
	assert(not invalid.ok and invalid.scope=="selected_point_only" and invalid.target.position.y==8)
	var far_target={"observation_id":snapshot.id,"position":{"x":-30.0,"y":0.0,"z":-10.0}}
	var start_position: Vector3=actor.global_position
	voice.survival.enabled=true
	adapter._owned=true
	var turned: Dictionary=await adapter.look_toward(far_target)
	assert(turned.ok,"远处记忆方向必须可以转身")
	var heading: Vector3=Vector3(sin(actor.rotation.y),0,cos(actor.rotation.y))
	assert(heading.dot(Vector3(30,0,-10).normalized())>0.999)
	assert(actor.global_position.distance_to(start_position)<0.05,"转身不能移动人物")
	var distant_move: Dictionary=await adapter.approach_segment({"object":far_target})
	assert(not distant_move.ok and distant_move.code=="invalid_target","近距离移动接口不能因此接受远处坐标")
	assert(not space.resolve("person_002",far_target,INF).ok,"远处朝向仍验证观察归属")
	assert(not space.resolve("person_003",{"observation_id":snapshot.id,"position":{"x":INF,"y":0,"z":1}},INF).ok)
	actor.rotation.y=0
	voice.survival.enabled=false
	adapter.queue_free()
	var target={"observation_id":snapshot.id,"position":{"x":1.0,"y":0.0,"z":2.0}}
	var resolved: Dictionary=space.resolve("person_003",target)
	assert(resolved.ok and resolved.position.distance_to(original+Vector3(-1,0,2))<0.0001,"本人右方必须与身体朝向一致，不误用世界+X")
	actor.global_position+=Vector3(4,0,1);actor.rotation.y=PI/2
	assert(space.resolve("person_003",target).position==resolved.position,"等待期间移动转身不能改变旧观察的落点")
	assert(not space.resolve("person_002",target).ok,"其他人物不能使用此观察")
	assert(not space.resolve("person_003",{"anchor":"old","offset":{"x":0,"y":0,"z":1}}).ok,"不保留旧坐标兼容")
	var second: Dictionary=space.capture("person_003")
	var next: Dictionary=space.resolve("person_003",{"observation_id":second.id,"position":{"x":1,"y":0,"z":2}})
	assert(next.position.distance_to(actor.global_position+Vector3(2,0,1))<0.0001)
	var context: Dictionary=space.prepare_context("person_003",voice.store.context_for("person_003"),second)
	assert(not context.survival_observation.has("body_position") and not context.survival_observation.has("body_forward"))
	assert(context.space_observation.near_field.ground_samples.size()==54)
	assert(not context.survival_observation.known_objects.has("known_far_tree"),"事实列表不能绕过主动回忆")
	assert(not context.space_observation.far_field.has("landmarks"),"不得自动提供远场地图记忆")
	assert(space.retain_frame("person_003",snapshot.id))
	assert(space.retain_frame("person_003",snapshot.id))
	assert(not space.retain_frame("person_002",snapshot.id))
	for index in 70:space.capture("person_002")
	assert(space.frames.has(snapshot.id),"其他人物观察不能淘汰活动坐标系")
	assert(space.resolve("person_003",target).ok)
	space.release_frame(snapshot.id)
	assert(space.frames.has(snapshot.id),"多个活动调用共同使用时仍须保留")
	space.frames[snapshot.id].created_ms=Time.get_ticks_msec()-300001
	assert(space.resolve("person_003",target).code=="observation_expired")
	assert(space.resolve("person_003",far_target,INF).code=="observation_expired")
	space.release_frame(snapshot.id)
	assert(not space.frames.has(snapshot.id) and space.frames.size()<=64,"最后调用结束后恢复有界缓存")
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();scene.add_child(pipeline)
	var gateway:=WaitingGateway.new();gateway.space=space;scene.add_child(gateway)
	pipeline.store=voice.store;pipeline.space=space;pipeline.gateway=gateway
	var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
	pipeline.run({"id":"frame_wait","kind":"body_state","speaker":"body","text":"测试通知","listeners":["person_003"]},{})
	await pipeline.completed
	assert(reports.size()==1 and not reports[0].has("error"))
	assert(space.retained_frames.is_empty(),"模型返回后释放本轮坐标")
	print("EGOCENTRIC_SPACE_PASSED rotation_translation_snapshot_owner_expiry_local_context_near_far_precision")
	scene.queue_free();await create_timer(0.2).timeout;quit()
