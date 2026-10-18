extends SceneTree
## 隔离真实世界/组合技能回归；不读取或写入正式存档，不调用人物模型。
const PERSON:="person_003"
const OBJECT:="water_bag/1"
var controller: Node
var sim: Node
var scene: Node3D
var ref: String
var contents: Array

func _initialize() -> void:run.call_deferred()

func reset_world() -> void:
	var bag: Dictionary=sim.world_objects.objects[OBJECT]
	# 仅重建下一离线用例的前提，与快照恢复相同；不把归位称为真实松手。
	if bag.holder!="":sim.world_objects._detach(OBJECT)
	sim.actors[PERSON].body.global_position=Vector3(3,0,6)
	sim.actors[PERSON].body.rotation.y=0
	scene.get_node("Player").global_position=Vector3(3,0,9.5)
	bag.body.global_position=Vector3(3,0.3,6.75);bag.body.rotation=Vector3.ZERO
	bag.body.linear_velocity=Vector3.ZERO;bag.body.angular_velocity=Vector3.ZERO
	for frame in 20:await physics_frame
	sim.perception.observe(PERSON)

func invoke(recipient: String="player") -> Dictionary:
	assert(controller.invoke(PERSON,"return_%d"%Time.get_ticks_usec(),{"ref":ref,"arguments":{"object":OBJECT,"recipient":recipient}}).ok)
	var outcome: Dictionary=await controller.finished
	print("RETURN_CASE ",JSON.stringify({"recipient":recipient,"success":outcome.success,"code":outcome.runtime.get("returned",{}).get("code"),"holder":sim.world_objects.objects[OBJECT].holder}))
	return outcome

func check_contents(outcome: Dictionary) -> void:
	var actual: Array=sim.water.bags["1"].contents.items
	assert(actual.size()==contents.size())
	for index in contents.size():
		assert(is_same(actual[index],contents[index]) and actual[index].material=="water")
		# 世界交接会追加递出/接收者记录；原水份身份与采集来源保持不变。
		assert(actual[index].origin.source=="fixture_original_water" and actual[index].origin.unit==index)
	assert(sim.water.drawn==0 and sim.water.consumed==0 and sim.water.spilled==0)
	assert(not outcome.runtime.trace.any(func(step):return step.operation in ["fill_container","consume_contents","consume_unit","take_unit"]))

func run() -> void:
	create_timer(75).timeout.connect(func():push_error("return object timeout");quit(1))
	scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	scene.get_node("Player").set_physics_process(false)
	var store=preload("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
	sim=preload("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	# 测试区域排除其他闲置人物的碰撞；NPC接收用例单独放回。
	for id in sim.actors:
		if id!=PERSON:sim.actors[id].body.global_position=Vector3(8,0,6+sim.actors.keys().find(id))
	controller=preload("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/return_test_%d.json"%Time.get_ticks_usec()).is_empty() and controller.library.install_builtins().is_empty())
	controller.sync_person(PERSON)
	for skill in controller.library.describe(PERSON):
		if skill.id=="return_object":ref=skill.ref
	assert(not ref.is_empty())
	var invalid: Dictionary=controller.invoke(PERSON,"bad_recipient",{"ref":ref,"arguments":{"object":OBJECT,"recipient":{"observation_id":"fixture","position":{"x":0,"y":0,"z":1}}}})
	assert(not invalid.ok and not controller.active.has(PERSON),"接收者必须是人物ID文字，不能拿取后才报坐标类型错误")
	for index in 2:assert(sim.water.bags["1"].contents.add({"material":"water","origin":{"source":"fixture_original_water","unit":index}}).ok)
	contents=sim.water.bags["1"].contents.items.duplicate()
	await reset_world()
	var result: Dictionary=await invoke()
	assert(result.success and sim.world_objects.objects[OBJECT].holder=="player")
	var operations: Array=result.runtime.trace.map(func(step):return step.operation)
	assert(operations.has("grasp") and operations.has("approach") and operations.has("handover"),"同一调用内确实完成拿取、走近和交付")
	check_contents(result)
	print("RETURN_OBJECT_GROUND_PASSED ",JSON.stringify({"elapsed_ms":result.runtime.elapsed_ms,"grasp":operations.count("grasp"),"approach":operations.count("approach"),"handover":operations.count("handover")}))
	await reset_world();assert(sim.water.pickup(PERSON,"1"))
	result=await invoke()
	assert(result.success and not result.runtime.trace.any(func(step):return step.operation=="grasp"))
	check_contents(result)
	await reset_world()
	# 持有者站在本人眼前，只检查原物持有状态，不借助隐藏位置。
	sim.actors.person_002.body.global_position=Vector3(3,0,7.2)
	assert(sim.water.pickup("person_002","1"))
	for frame in 2:await physics_frame
	sim.perception.observe(PERSON)
	result=await invoke()
	assert(not result.success and result.runtime.returned.code=="held_by_other")
	assert(sim.world_objects.objects[OBJECT].holder=="person_002" and not result.runtime.trace.any(func(step):return step.operation in ["approach","handover"]))
	check_contents(result)
	sim.actors.person_002.body.global_position=Vector3(8,0,7)
	await reset_world()
	# 接收意愿是隔离夹具；组合必须采用世界拒绝回执并保留原物。
	assert(sim.world_objects.attach_to(OBJECT,PERSON,"Hand.R",func():return sim.world_objects.carry_transform(OBJECT,sim.actors[PERSON].body,"Hand.R")).ok)
	sim.actors.person_002.body.global_position=Vector3(3,0,7.3)
	sim.actors.person_002.body.rotation.y=PI
	scene.get_node("Player").global_position=Vector3(8,0,12)
	for frame in 2:await physics_frame
	sim.perception.observe(PERSON)
	var decline:=func(event: Dictionary):sim.handover.respond(event.id,event.listeners[0],false)
	sim.handover.offered.connect(decline)
	result=await invoke("person_002")
	sim.handover.offered.disconnect(decline)
	if result.success or result.runtime.returned.code!="declined" or sim.world_objects.objects[OBJECT].holder!=PERSON:
		push_error("recipient decline condition not satisfied");quit(1);return
	check_contents(result)
	sim.actors.person_002.body.global_position=Vector3(8,0,7)
	await reset_world()
	# 以已持有原物的隔离前提测试接近期间取消；不把夹具持有当作实际拿取。
	assert(sim.world_objects.attach_to(OBJECT,PERSON,"Hand.R",func():return sim.world_objects.carry_transform(OBJECT,sim.actors[PERSON].body,"Hand.R")).ok)
	var cancelled_outcomes: Array=[]
	var capture_result:=func(outcome: Dictionary):cancelled_outcomes.append(outcome)
	controller.finished.connect(capture_result)
	assert(controller.invoke(PERSON,"cancel_return",{"ref":ref,"arguments":{"object":OBJECT,"recipient":"player"}}).ok)
	await create_timer(0.35).timeout
	assert(controller.active.has(PERSON) and sim.world_objects.objects[OBJECT].holder==PERSON)
	controller.cancel(PERSON)
	while cancelled_outcomes.is_empty():await process_frame
	result=cancelled_outcomes[0];controller.finished.disconnect(capture_result)
	assert(result.cancelled and sim.world_objects.objects[OBJECT].holder==PERSON)
	await create_timer(0.3).timeout
	assert(sim.world_objects.objects[OBJECT].holder==PERSON and sim.handover.pending.is_empty())
	check_contents(result)
	# 同一原物继续一次调用归还，不重置取消后实际持有状态。
	result=await invoke()
	assert(result.success and sim.world_objects.objects[OBJECT].holder=="player")
	check_contents(result)
	print("RETURN_OBJECT_PASSED typed_recipient_ground_and_held_same_contents_other_holder_decline_cancel_resume_single_call")
	scene.queue_free();await process_frame;await process_frame;quit()
