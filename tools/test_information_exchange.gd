extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var voice:=Voice.new(); scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=true; voice.survival.enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	var sender: CharacterBody3D=sim.actors.person_002.body
	var at: Vector3=sim.gathering.baskets["1"].root.global_position
	sender.position=at+Vector3(0,0.1,2); sender.rotation.y=PI
	await physics_frame
	sim.perception.clock=20; sim.perception.observe("person_002")
	var decision:={"intent":"none","recipient_id":"","speech_act":"reply","addressed_person":"person_001","private_interpretation":"告诉她我知道的位置","public_reply":"我最后在洞口看见篮子，你去那里确认一下。","speech_style":"平静清楚","routing_reason":"回答位置","capability_gap":null,"shared_knowledge":["basket/1"],"request_kind":"information"}
	assert(Cloud.validate_decision(JSON.stringify(decision),true).ok)
	var offer:=Cloud.knowledge_offer(decision,{"survival_observation":sim.observation("person_002")},sim.perception.memories.person_002)
	assert(offer.entries.has("basket/1"))
	var original: Array=offer.entries["basket/1"].position.duplicate()
	# 仅存在于短期记忆中的位置同样可以转述；使用生成决策之前的宿主记录。
	var snapshot: Dictionary=sim.store.memory.observations.person_002.duplicate(true)
	var memory_context:={"survival_observation":{"known_objects":{}},"working_context":{"last_known_locations":{"basket/1":{"spatial_layer":"far_field","approx_position":{"x":10,"y":0,"z":20}}}}}
	var remembered_offer: Dictionary=Cloud.knowledge_offer(decision,memory_context,snapshot)
	assert(remembered_offer.entries["basket/1"].position==original,"相对坐标与粗略坐标不能被误当作接收者的世界坐标")
	assert(remembered_offer.entries["basket/1"].observed_at_seconds==20)
	var hidden:=decision.duplicate(true);hidden.shared_knowledge=["storage"]
	assert(Cloud.knowledge_offer(hidden,memory_context,snapshot).rejected==["storage"],"不能分享未在本次输入提供的物品记录")
	sim.perception.memories.person_002["basket/1"].position=[50,0,50]
	sim.store.memory.observations.person_002["basket/1"].position=[60,0,60]
	assert(remembered_offer.entries["basket/1"].position==original and snapshot["basket/1"].position==original,"等待模型和朗读期间的新观察不能改写旧台词所引用的情报")
	offer=remembered_offer
	sim.perception.memories.person_001.clear(); sim.perception.memories.person_003.clear()
	sim.actors.person_001.body.position=Vector3(1,0.2,6)
	sender.position=Vector3(4,0.2,6)
	sim.actors.person_003.body.position=Vector3(80,0.2,80)
	await physics_frame
	assert(sim.perception.known("person_001","basket/1").is_empty(),"生成答案尚不传播情报")
	voice.store.hear("person_001",{"id":"question","kind":"need_changed","speaker":"body","text":"需要篮子位置"})
	voice._deliver_public("person_001","question","小花，篮子在哪里？",12,{"speech_act":"request","request_kind":"information","addressed_person":"person_002"})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="information_request")
	assert(voice.help_tasks.tasks.is_empty(),"问路不是请求搬运食物")
	voice.autonomy.requests.clear()
	sim.perception.clock=40
	voice._deliver_public("person_002","answer",decision.public_reply,12,decision,offer)
	var learned: Dictionary=sim.perception.known("person_001","basket/1")
	assert(learned.position==original and learned.heard_from=="person_002" and not learned.visible_now)
	assert(learned.observed_at_seconds==20 and learned.heard_at_seconds==40)
	assert(sim.perception.known("person_003","basket/1").is_empty(),"范围外人物没有共享知识")
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="information_received")
	sim.perception.clock=50
	voice._deliver_public("person_002","repeat",decision.public_reply,12,decision,offer)
	assert(voice.autonomy.requests.size()==1 and sim.perception.known("person_001","basket/1").heard_at_seconds==40,"重复情报不刷新时效或触发循环")
	var receiver: CharacterBody3D=sim.actors.person_001.body
	receiver.position=at+Vector3(0,0.1,2); receiver.rotation.y=PI
	await physics_frame
	sim.perception.clock=60; sim.perception.observe("person_001")
	receiver.rotation.y=0; sim.perception.observe("person_001")
	assert(not sim.perception.hear_from("person_001","person_002","old",offer.entries["basket/1"]),"旧转述不覆盖新观察")
	decision.shared_knowledge=["invented"]
	var rejected:=Cloud.knowledge_offer(decision,{"survival_observation":sim.observation("person_002")},sim.perception.memories.person_002)
	assert(rejected.entries.is_empty() and rejected.rejected==["invented"])
	decision.public_reply=""
	assert(not Cloud.validate_decision(JSON.stringify(decision),true).ok)
	print("INFORMATION_EXCHANGE_PASSED: query_kind, frozen_offer, hearing_range, provenance, freshness, no_echo_loop, unknown_reference_rejected")
	scene.queue_free(); await create_timer(0.2).timeout; quit()
