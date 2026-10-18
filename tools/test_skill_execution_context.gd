extends SceneTree
## 离线夹具：真实Luau与世界消费；不调用人物模型、不授予正式存档技能。
const Session=preload("res://scripts/survival/session_store.gd")
const Snapshot=preload("res://scripts/skills/verification_snapshot.gd")
func _initialize() -> void: run.call_deferred()
func choose(store: RefCounted, person: String, event: Dictionary, ref: String, scope: String) -> void:
	store.hear(person,event)
	store.remember(person,event.id,{"intent":"none","private_interpretation":"按真实进展执行","public_reply":"","skill_call":{"ref":ref,"arguments":{"object":"water_bag/1"}},"task_status":"active","task_handling":{"state":"execute","scope":scope}})
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("执行记录夹具超时");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var prefix:="user://journal_probe_%d"%Time.get_ticks_usec()
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json",prefix+"/memory.json",true).is_empty())
	var sim=preload("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var person:="person_003";var actor: Dictionary=sim.actors[person]
	actor.body.global_position=sim.water.SOURCE+Vector3(0,.06,-.5);actor.body.rotation.y=0
	for frame in 12:await physics_frame
	assert(sim.world_objects.attach_to("water_bag/1",person,"Hand.R",sim.water.hold_pose.bind(person)).ok)
	sim.perception.observe(person)
	assert(sim.life_world.fill_container(person,"water_source","water_bag/1").ok)
	var bag: Dictionary=sim.content_interaction.containers["water_bag/1"].record
	assert(bag.contents.count==3)
	var skills=preload("res://scripts/skills/controller.gd").new();skills.sim=sim;skills.store=store;scene.add_child(skills)
	assert(skills.initialize_current(prefix+"/library.json").is_empty())
	skills.finished.connect(store.record_execution)
	var source:="""return function(args,context)
  local seen=world.request('perceive',{})
  for _,call in ipairs(context.task_execution.calls) do
    for _,fact in ipairs(call.facts) do
      if fact.kind == 'consumed' and fact.source == args.object then
        return {ok=true,code='already_consumed',request_id=context.task_execution.request_id,request_odometry=seen.request_odometry,odometry=seen.odometry}
      end
    end
  end
  local receipt=world.request('consume_contents',{object=args.object})
  return {ok=false,code='stopped_after_consumption',receipt=receipt,request_id=context.task_execution.request_id,request_odometry=seen.request_odometry,odometry=seen.odometry}
end"""
	var definition:={"id":"journal_probe","name":"实际回执续办夹具","description":"测试来源绑定和存取","parameters":{"object":"本人持有容器"},"program_json":JSON.stringify(preload("res://scripts/skills/luau_contract.gd").make_program(source,["consume_contents","perceive"]))}
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=skills.library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and skills.library.grant(person,registered.ref,"仅离线夹具").is_empty())
	var original:={"id":"request_A","speaker":"player","kind":"speech_intent","text":"消费一份后继续其他步骤"}
	# 真实控制器接收超过通信上限的开发审查原件，仍只能将人物相关状态送进Luau。
	store.people[person]["learning"]={"state":"failed","goal":"修订带路","message":"没有通过验收","review":{"issues":[{"runtime":{"trace":["host_only_"+"x".repeat(1048576)]}}]}}
	assert(not store.context_for(person).learning.has("review"),"审查轨迹不属于人物的世界事实")
	choose(store,person,original,registered.ref,"current_request")
	assert(skills.invoke(person,original.id,{"ref":registered.ref,"arguments":{"object":"water_bag/1"}}).ok)
	var first: Dictionary=await skills.finished
	assert(not first.success and bag.contents.count==2)
	assert(first.world_facts[0].source=="water_bag/1" and first.world_facts[0].source_event_id==original.id)
	var original_origin: Array=store.working_tasks[person].execution_origin.duplicate(true)
	assert(first.runtime.returned.request_odometry.request_id==original.id)
	assert(absf(first.runtime.returned.request_odometry.position.x)<.01 and absf(first.runtime.returned.request_odometry.position.z)<.01)
	assert(Snapshot.capture(sim,person).host_execution_origin=={"request_id":original.id,"transform":original_origin},"只有宿主快照携带请求世界原点")
	var prepared: Dictionary=sim.space.prepare_context(person,store.context_for(person),sim.space.capture(person))
	assert(not JSON.stringify(prepared).contains('"execution_origin"'),"世界原点不得进入人物完整输入")
	assert(not preload("res://scripts/voice/decision_pipeline.gd").request_for(prepared,original).prompt.contains('"execution_origin"'),"最终发送模型输入也不能含宿主原点")
	var path:=prefix+"/session.json"
	assert((await Session.save(path,sim,skills.library,self)).is_empty())
	store.working_tasks.clear()
	var saved:=Session.read(path,sim);assert(saved.ok)
	Session.restore(sim,skills.library,saved)
	assert(Snapshot.restored_transform(store.working_tasks[person].execution_origin).is_equal_approx(Snapshot.restored_transform(original_origin)),"存取后必须保留原请求坐标系")
	# 明确隔离布置：移动和转身后重新调用，不冒充正常游玩。
	actor.body.global_position+=Vector3(1,0,.5);actor.body.rotation.y+=PI/2
	var continued:={"id":"continue_A","speaker":"body","kind":"need_changed","text":"需要继续"}
	choose(store,person,continued,registered.ref,"existing_request")
	assert(Snapshot.restored_transform(store.working_tasks[person].execution_origin).is_equal_approx(Snapshot.restored_transform(original_origin)),"remember重建任务不能丢失同请求原点")
	var context: Dictionary=store.skill_execution_context(person,continued.id)
	assert(context.request_id==original.id and context.calls.size()==1 and context.calls[0].facts[0].quantity==1)
	assert(context.calls[0].arguments.object=="water_bag/1" and context.calls[0].movements.is_empty() and context.calls[0].movements_complete,"正式控制器的已验证调用参数和运动完整性须随任务恢复")
	context.calls[0].facts[0].quantity=999
	assert(store.skill_execution_context(person,continued.id).calls[0].facts[0].quantity==1,"上下文修改不能回写真实进度")
	assert(skills.invoke(person,continued.id,{"ref":registered.ref,"arguments":{"object":"water_bag/1"}}).ok)
	var second: Dictionary=await skills.finished
	assert(second.success and second.runtime.returned.code=="already_consumed" and second.runtime.returned.request_id==original.id)
	assert(second.world_facts.is_empty() and bag.contents.count==2,"恢复后的续办读取已消费记录，不能重复消费")
	var ongoing: Dictionary=second.runtime.returned.request_odometry
	var local_motion: Dictionary=second.runtime.returned.odometry
	assert(ongoing.request_id==original.id and Vector2(ongoing.position.x,ongoing.position.z).length()>.8,"旧原点须体现跨调用真实移动")
	assert(Vector2(local_motion.position.x,local_motion.position.z).length()<.1,"本次调用odometry原点仍独立")
	var frame:=Snapshot.restored_transform(original_origin)
	var expected: Vector3=frame.affine_inverse()*actor.body.global_position
	assert(Vector2(expected.x-ongoing.position.x,expected.z-ongoing.position.z).length()<.03)
	var expected_forward: Vector3=frame.basis.inverse()*actor.body.global_basis.z
	assert(expected_forward.distance_to(Vector3(ongoing.forward.x,ongoing.forward.y,ongoing.forward.z))<.001,"转身后方向仍须在原请求坐标系")
	var fresh:={"id":"request_B","speaker":"player","kind":"speech_intent","text":"现在再消费一份"}
	choose(store,person,fresh,registered.ref,"current_request")
	assert(store.skill_execution_context(person,fresh.id).calls.is_empty())
	assert(skills.invoke(person,fresh.id,{"ref":registered.ref,"arguments":{"object":"water_bag/1"}}).ok)
	var third: Dictionary=await skills.finished
	assert(third.runtime.returned.request_id==fresh.id and bag.contents.count==1,"新请求不能读取旧请求的已消费标记")
	assert(Vector2(third.runtime.returned.request_odometry.position.x,third.runtime.returned.request_odometry.position.z).length()<.1,"新请求须在本人当前站位重建原点")
	var fresh_origin: Array=store.working_tasks[person].execution_origin.duplicate(true)
	assert(fresh_origin!=original_origin)
	var independent:={"id":"body_independent","speaker":"body","kind":"need_changed","text":"自身需要"}
	choose(store,person,independent,registered.ref,"independent")
	assert(store.skill_execution_context(person,independent.id).calls.is_empty())
	assert(store.skill_execution_context("person_002","other_request").calls.is_empty())
	assert(skills.invoke(person,independent.id,{"ref":registered.ref,"arguments":{"object":"water_bag/1"}}).ok)
	var fourth: Dictionary=await skills.finished
	assert(fourth.runtime.returned.request_id==independent.id and bag.contents.count==0)
	assert(fourth.runtime.returned.request_odometry.request_id==independent.id and store.working_tasks[person].execution_origin==fresh_origin,"独立行动不得读写明确任务原点")
	assert(store.working_tasks[person].progress.size()==1,"自主行为不能追加到别人的明确请求进度")
	var broken: Dictionary=store.memory.export_data();broken.short_term.tasks[person].execution_origin[3][0]=NAN
	assert(not preload("res://scripts/voice/memory_store.gd").new().load_data(broken,store.people.keys()).is_empty(),"非有限原点必须在存档入口拒绝")
	# 日常模型可直接选择当前观察里的地面；该技能内部没有再次perceive。
	# 独立物理夹具：此前消费位于水边，不能让本测试依赖那里的干燥落脚点。
	var floor_body:=StaticBody3D.new();scene.add_child(floor_body)
	floor_body.global_position=Vector3(0,20,0)
	var floor_collision:=CollisionShape3D.new();var floor_shape:=BoxShape3D.new()
	floor_shape.size=Vector3(10,.5,10);floor_collision.shape=floor_shape;floor_body.add_child(floor_collision)
	actor.body.global_position=Vector3(0,20.31,-2);actor.body.rotation.y=0;actor.body.velocity=Vector3.ZERO
	for frame_index in 12:await physics_frame
	var observation: Dictionary=sim.space.capture(person)
	var selected: Dictionary={}
	var selected_frame: Transform3D=sim.space.frames[observation.id].transform
	for sample in observation.near_field.ground_samples:
		if sample.state!="visible_surface" or sample.surface_kind!="dry_ground" or sample.slope_degrees>=35:continue
		var at: Vector3=Vector3(sample.position.x,sample.position.y,sample.position.z)
		if at.length()<1.3 or at.length()>2.5:continue
		if preload("res://scripts/survival/ground_motion.gd").path_clear(actor.body,selected_frame*at):
			selected={"observation_id":observation.id,"position":sample.position.duplicate(true)};break
	assert(not selected.is_empty(),"夹具需有真实可见、可达的干燥地面")
	var direct_definition:={"id":"direct_point_probe","name":"直接选点夹具","description":"只移动，不重新观察","parameters":{"target":"本人观察的地面"},"program_json":JSON.stringify(preload("res://scripts/skills/luau_contract.gd").make_program("return function(args) return world.request('approach',{object=args.target,distance=0.25,keep_heading=true}) end",["approach"]))}
	var direct_raw:=JSON.stringify(direct_definition)
	var direct_ref: Dictionary=skills.library.register_verified(direct_definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":direct_raw,"definition_sha256":direct_raw.sha256_text()})
	assert(direct_ref.ok and skills.library.grant(person,direct_ref.ref,"仅离线夹具").is_empty())
	var point_event:={"id":"direct_point_request","speaker":"player","kind":"speech_intent","text":"走到我选的地面"}
	store.hear(person,point_event)
	store.remember(person,point_event.id,{"intent":"none","private_interpretation":"按选点移动","public_reply":"","skill_call":{"ref":direct_ref.ref,"arguments":{"target":selected}},"task_status":"active","task_handling":{"state":"execute","scope":"current_request"}})
	actor.body.rotation.y+=PI/2
	assert(skills.invoke(person,point_event.id,{"ref":direct_ref.ref,"arguments":{"target":selected}}).ok)
	var direct_result: Dictionary=await skills.finished
	assert(direct_result.success and direct_result.runtime.trace.size()==1 and direct_result.runtime.trace[0].operation=="approach")
	var movement: Dictionary=direct_result.movement_history.entries[0]
	assert(direct_result.movement_history.complete and movement.evidence_complete and movement.observation_source=="retained_argument_frame")
	assert(not movement.observation_immediately_preceded and movement.references.is_empty())
	var reference: Transform3D=Snapshot.restored_transform(store.working_tasks[person].execution_origin)
	var point: Dictionary=movement.standing_position.position
	var odometry: Dictionary=movement.request_odometry
	var observed_end: Vector3=Vector3(odometry.position.x,odometry.position.y,odometry.position.z)+Vector3(odometry.right.x,odometry.right.y,odometry.right.z)*point.x+Vector3.UP*point.y+Vector3(odometry.forward.x,odometry.forward.y,odometry.forward.z)*point.z
	assert(observed_end.distance_to(reference.affine_inverse()*actor.body.global_position)<.03,"旧参数帧与转身后的真实终点须在同请求坐标系一致")
	assert(not direct_result.runtime.has("argument_frames"),"参数帧表不重复进入日常运行摘要")
	var raw_execution: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(direct_result.runtime.full_evidence_path))
	assert(raw_execution.argument_frames.has(observation.id),"原始证据保留合法参数帧来源")
	var missing_frame:=raw_execution.duplicate(true);missing_frame.erase("argument_frames")
	assert(not preload("res://scripts/skills/execution_journal.gd").execution_evidence({},{},missing_frame).movement_history.complete,"同一次实际移动缺少参数帧时应重现证据不完整")
	assert(store.skill_execution_context(person,point_event.id).calls[0].movements[0].evidence_complete)
	print("SKILL_EXECUTION_CONTEXT_PASSED actual_receipts, save_restore, no_repeat, new_request, independent, person_isolation, request_odometry_continuity_rotation_private_origin_validation; model_calls=0")
	scene.queue_free();await process_frame;quit()
