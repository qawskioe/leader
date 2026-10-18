extends SceneTree
## 离线感知夹具：姓名随本人目击/真实听闻保留，不注入全人物名单。
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("person identity memory timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	var sim: Node=voice.survival
	sim.enabled=false
	var person:="person_001";var seen:="person_002";var unheard:="person_004"
	var body: Node3D=sim.actors[person].body
	var target: Node3D=sim.actors[seen].body
	var at: Vector3=sim.water.SOURCE+Vector3(0,0.6,-2)
	body.global_position=at;body.rotation.y=0;target.global_position=at+Vector3(0,0,2)
	for other in ["person_003",unheard]:sim.actors[other].body.global_position=at+Vector3(30,0,30)
	sim.perception.memories[person]={};sim.store.memory.observations[person]={}
	sim.perception.clock=20
	sim.perception.observe(person)
	var observed: Dictionary=sim.perception.known(person,"person/"+seen)
	assert(observed.get("visible_now",false),"夹具必须先证明本人实际看到目标")
	assert(observed.extra.get("name")==sim.store.people[seen].name,"目视人物缺少已识别的姓名")
	var old_position: Array=observed.position.duplicate()
	target.global_position+=Vector3(25,0,0);body.rotation.y=PI
	sim.perception.observe(person)
	var remembered: Dictionary=sim.perception.known(person,"person/"+seen)
	assert(not remembered.visible_now and remembered.position==old_position,"名字保留不得暗中刷新离开视野者的位置")
	assert(remembered.extra.name==sim.store.people[seen].name)
	# 听闻已识别声音可以建立姓名对照，但不能把旧目视细节一并复制成听闻事实。
	sim.perception.memories[person]["person/"+seen].extra["visible_item"]="不可听见的物品"
	assert(sim.perception.hear_voice(person,seen,"heard_known_voice",at+Vector3(-1,1.6,-2),21))
	var heard: Dictionary=sim.perception.known(person,"person/"+seen)
	assert(not heard.visible_now and heard.extra=={"name":sim.store.people[seen].name})
	assert(heard.observed_at_seconds==21 and heard.position_error_per_axis_m>0)
	assert(not sim.perception.hear_voice(person,seen,"older_voice",Vector3.ZERO,19,"错误旧名字"))
	assert(sim.perception.known(person,"person/"+seen).extra.name==sim.store.people[seen].name,"迟到声音不能覆盖较新名字")
	sim.actors.person_003.body.global_position=at+Vector3(2,0,-1)
	sim.perception.clock=22
	voice._deliver_public("person_003","heard_first_voice","我是大山",10)
	assert(sim.store.people[person].heard_events.any(func(e):return e.id=="heard_first_voice_spoken" and e.speaker_name==sim.store.people.person_003.name),"真实受众联动必须先记录听见的姓名")
	assert(sim.perception.known(person,"person/person_003").extra.name==sim.store.people.person_003.name,"已识别的声音初次听到也须保留姓名")
	assert(not sim.store.people[unheard].heard_events.any(func(e):return e.id=="heard_first_voice_spoken"),"范围外人物不能因公开讲话获得听闻事件")
	var memory=preload("res://scripts/voice/memory_store.gd").new()
	assert(memory.load_data(sim.store.memory._snapshot_for_save(),sim.store.people.keys()).is_empty())
	assert(memory.observations[person]["person/"+seen].extra.name==sim.store.people[seen].name,"保存恢复不得丢失本人观察的名字")
	assert(memory.observations[person]["person/person_003"].extra.name==sim.store.people.person_003.name)
	var frame: Dictionary=sim.space.capture(person)
	var context: Dictionary=sim.space.prepare_context(person,sim.store.context_for(person),frame)
	context.visible_people=[]
	var event:={"id":"identity_wire","kind":"speech_intent","speaker":"player","text":"找小花和大山","listeners":[person]}
	var wire: Dictionary=JSON.parse_string(Pipeline.request_for(context,event).prompt)
	for other in [seen,"person_003"]:
		var key: String="person/"+other
		assert(wire.self.working_context.last_known_locations[key].extra.name==sim.store.people[other].name,"完整模型输入丢失本人已知名字")
		assert(wire.self.survival_observation.known_objects[key].extra.name==sim.store.people[other].name)
	assert(not wire.self.working_context.last_known_locations.has("person/"+unheard),"未见未听者不得因全人物名单而获得身份/位置")
	assert(not wire.self.survival_observation.known_objects.has("person/"+unheard))
	assert(sim.perception.hear_voice(person,unheard,"unidentified_voice",at+Vector3(1,1.6,-2),23))
	assert(sim.perception.known(person,"person/"+unheard).extra.is_empty(),"未识别声音不能从全局人物表补名")
	# 远场回忆及结构压缩同样只能保留自己的旧线索和名字。
	body.global_position+=Vector3(30,0,0)
	frame=sim.space.capture(person);context=sim.space.prepare_context(person,sim.store.context_for(person),frame)
	var far: Dictionary=context.working_context.last_known_locations["person/"+seen]
	assert(far.spatial_layer=="far_field" and far.extra.name==sim.store.people[seen].name)
	assert(Pipeline.request_for(context,event).prompt.contains(sim.store.people[seen].name))
	print("PERSON_IDENTITY_MEMORY_PASSED observed_heard_names_retained_full_wire_unseen_position_stale_no_visual_details_no_roster; cloud_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
