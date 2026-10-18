extends SceneTree
## 隔离测试回复通过真实递交结算；拒绝保留原物与内容，接受后只转移一次。
const Conditions=preload("res://scripts/skills/verification_conditions.gd")
const Participants=preload("res://scripts/skills/verification_participants.gd")

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(20).timeout.connect(func():push_error("verification consent timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var person:="person_003"
	var recipient:="person_002"
	var actor: CharacterBody3D=sim.actors[person].body
	actor.global_position=Vector3(0,.1,3);actor.rotation.y=0
	var player: CharacterBody3D=scene.get_node("Player")
	player.global_position=Vector3(8,.1,4.3);player.set_physics_process(false)
	sim.actors[recipient].body.global_position=Vector3(0,.1,4.3);sim.actors[recipient].body.rotation.y=PI
	for other in sim.actors:
		if other not in [person,recipient]:sim.actors[other].body.global_position+=Vector3(8,0,0)
	for frame in 20:await physics_frame
	sim.perception.observe(person)
	var object_id:="water_bag/1"
	var record: Dictionary=sim.world_objects.objects[object_id]
	# 夹具构造两份现有水；这不是正式玩家装水证据。
	for index in 2:assert(record.contents.add({"material":"water","origin":{"fixture":"consent"}}).ok)
	assert(sim.world_objects.attach_to(object_id,person,"Hand.R",func():return sim.world_objects.carry_transform(object_id,actor,"Hand.R")).ok)
	var helper:=Participants.new();scene.add_child(helper)
	var policies: Array=[]
	helper.configure(sim,person,[],func(event):policies.append(event))
	var answers: Array=[];var facts: Array=[]
	sim.life_world.fact.connect(func(event):facts.append(event.duplicate(true)))
	sim.handover.offered.connect(func(event):
		var answer: String=helper.handover_answer(event.listeners[0]);answers.append(answer)
		sim.handover.respond.call_deferred(event.id,event.listeners[0],answer=="accept"))
	var api=preload("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id=person;api.objects=sim.world_objects;scene.add_child(api)
	assert(api.acquire().ok)
	var original_position: Vector3=record.body.global_position
	var configured: Dictionary=await Conditions.apply(sim,person,{},[{"kind":"participant_handover_answer","person":recipient,"answer":"decline"}],helper)
	assert(configured.ok)
	var declined: Dictionary=await api.request("handover",{"object":object_id,"recipient":recipient})
	assert(not declined.ok and declined.code=="declined",str(declined))
	assert(record.holder==person and record.contents.count==2)
	assert(not facts.any(func(event):return event.kind=="given"))
	assert(record.body.global_position.distance_to(original_position)<.01)
	assert(helper.handover_answer(recipient)=="decline")
	configured=await Conditions.apply(sim,person,{},[{"kind":"participant_handover_answer","person":recipient,"answer":"accept"}],helper)
	assert(configured.ok)
	var accepted: Dictionary=await api.request("handover",{"object":object_id,"recipient":recipient})
	assert(accepted.ok and record.holder==recipient and record.contents.count==2,str(accepted))
	assert(answers==["decline","accept"])
	var delivered: Array=facts.filter(func(event):return event.kind=="given")
	assert(delivered.size()==1 and delivered[0].recipient_id==recipient and delivered[0].quantity==2)
	var repeated: Dictionary=await api.request("handover",{"object":object_id,"recipient":recipient})
	assert(not repeated.ok and record.contents.count==2 and facts.size()==1)
	assert(helper.evidence().handover_answers[recipient]=="accept")
	helper.set_handover_answer(recipient,"decline");helper.reset([])
	assert(helper.handover_answer(recipient)=="accept" and helper.evidence().handover_answers.is_empty())
	assert(policies.any(func(event):return event.type=="participant_fixture_consent_policy"))
	# 当前玩家接收是实际世界规则；隔离替身不能给玩家伪造拒绝。
	sim.actors[recipient].body.global_position.x+=8
	player.global_position=Vector3(0,.1,4.3)
	await physics_frame
	sim.perception.observe(person)
	var other_object:="water_bag/2"
	assert(sim.world_objects.attach_to(other_object,person,"Hand.R",func():return sim.world_objects.carry_transform(other_object,actor,"Hand.R")).ok)
	var to_player: Dictionary=await api.request("handover",{"object":other_object,"recipient":"player"})
	assert(to_player.ok and sim.world_objects.objects[other_object].holder=="player",str(to_player))
	assert(answers==["decline","accept"],"玩家直接接收不产生NPC决策事件")
	await api.finish()
	scene.queue_free();await create_timer(.1).timeout
	print("VERIFICATION_CONSENT_PASSED npc_decline_retains_object_contents_accept_once_policy_reset_player_auto; real_model_calls=0")
	quit()
