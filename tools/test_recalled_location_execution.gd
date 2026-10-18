extends SceneTree
## 离线回归：真实日终/快照恢复、记忆检索和技能入口；不调用云端或改正式存档。
func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(40).timeout.connect(func():push_error("回忆地标执行回归超时");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var prefix:="user://recalled_location_%d"%Time.get_ticks_usec()
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json",prefix+"/memory.json",true).is_empty())
	var sim=preload("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.enabled=false;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var person:="person_004"
	var point: Vector3=sim.actors[person].body.global_position+Vector3(0,0,.5)
	var remembered:={"id":"remembered_route","kind":"route","position":[point.x,point.y,point.z],"available":true,"visible_now":false,"observed_at_seconds":0.0,"source":"过去亲眼走过的路线","extra":{}}
	store.memory.put(person,"landmark",remembered.id,remembered,.6)
	store.memory.note_observation(person,remembered)
	var unread: Dictionary=remembered.duplicate(true);unread.id="unread_route"
	store.memory.put(person,"landmark",unread.id,unread,.6)
	store.memory.put("person_002","landmark","other_route",unread,.6)
	store.memory.advance(store.memory.policy.day_seconds+1)
	var snapshot=preload("res://scripts/skills/verification_snapshot.gd")
	snapshot.restore(sim,snapshot.capture(sim,person))
	assert(sim.perception.known(person,remembered.id).is_empty(),"恢复现场不能自动展开全部长期地标")
	var observation: Dictionary=sim.space.capture(person)
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=store;pipeline.space=sim.space;scene.add_child(pipeline)
	var answer: Dictionary=pipeline._memory_operation(person,{"recall":{"kind":"landmark","keywords":[remembered.id],"limit":1}},{"space_observation":observation},{})
	assert(answer.ok and answer.records.size()==1 and not answer.records[0].data.visible_now)
	assert(not sim.perception.known(person,remembered.id).is_empty(),"模型实际回忆出的地标须进入本人的执行知识")
	assert(sim.perception.known(person,unread.id).is_empty(),"未选择回忆的其他地标不能全部注入")
	assert(sim.perception.known("person_002",remembered.id).is_empty(),"回忆不能流向其他人物")
	var skills=preload("res://scripts/skills/controller.gd").new();skills.sim=sim;skills.store=store;scene.add_child(skills)
	assert(skills.initialize_current(prefix+"/skills.json").is_empty())
	var ref:=""
	for entry in skills.library.describe(person):
		if entry.id=="go_to_known":ref=entry.ref;break
	assert(not ref.is_empty());sim.enabled=true
	assert(skills.invoke(person,"remembered_route_action",{"ref":ref,"arguments":{"object":remembered.id,"distance":1.0}}).ok,"已回忆的合法参照物不能被技能参数边界拒绝")
	var finished: Dictionary=await skills.finished
	assert(finished.success and finished.runtime.returned.code=="at_remembered_location")
	# 新的亲眼核实优先；回忆旧坐标不能把空地点重新标为存在。
	sim.perception._record(person,remembered.id,"route",point+Vector3.RIGHT,false)
	var current: Dictionary=sim.perception.known(person,remembered.id)
	sim.perception.recall_location(person,remembered)
	assert(sim.perception.known(person,remembered.id)==current)
	print("RECALLED_LOCATION_EXECUTION_PASSED selected_recall_actual_skill_no_bulk_or_cross_person_current_evidence_priority; model_calls=0")
	scene.queue_free();await process_frame;quit()
