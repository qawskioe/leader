extends SceneTree
## 同一世界入口验证两种主体和两类资源，不启动日常模型或修改正式存档。
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("通用资源主体验证超时");quit(1))
	for id in ["person_003","player"]:
		for material in ["food","water"]:
			if await run_case(id,material)!=true:quit(1);return
	for winner in ["person_003","player"]:
		if await run_competing_case(winner)!=true:quit(1);return
	print("RESOURCE_SUBJECTS_PASSED shared_sources_ownership_origin_facts_capacity_consumption_current_needs_last_unit_once")
	quit()

func run_competing_case(winner: String):
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var file:="user://resource_competing_%d.json"%Time.get_ticks_usec()
	var store:=Store.new();assert(store.initialize("res://data/people.json",file,true).is_empty())
	var sim:=Sim.new();sim.store=store;sim.scene=scene;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false);player.set_process(false)
	var npc: Node3D=sim.life_world.subjects.person_003.body
	var source:=""
	# 两主体在同一隔离世界、同一真实果实前；只建立可达前提，不补造取得结果。
	for key in sim.gathering.resources:
		var at: Vector3=sim.gathering.resources[key].mesh.global_position
		npc.global_position=at+Vector3(0,-1,-.7);npc.rotation.y=0
		player.global_position=npc.global_position;player.rotation.y=0
		sim.perception.observe("person_003")
		if sim.life_world.access_source("person_003","fruit/"+key).ok and sim.life_world.access_source("player","fruit/"+key).ok:
			source="fruit/"+key;break
	assert(not source.is_empty(),"须找到两主体都可见可达的同一份真实果实")
	for holder in ["person_003","player"]:
		var key:="1" if holder=="person_003" else "2"
		sim.gathering.baskets[key].root.global_position=sim.life_world.subjects[holder].body.global_position+Vector3(.4,.4,.6)
		assert(sim.gathering.pickup(holder,key),"两位采摘主体均须持有当前规则要求的篮子")
		sim.world_objects.sync_held("basket/"+key)
	var events: Array=[];sim.life_world.fact.connect(func(value: Dictionary):events.append(value.duplicate(true)))
	var loser:="player" if winner=="person_003" else "person_003"
	assert(sim.life_world.take_unit(winner,source).ok)
	assert(not sim.life_world.take_unit(loser,source).ok,"同一份有限资源不能被两个主体重复取走")
	assert(sim.gathering.harvested==1 and not sim.gathering.resources[source.trim_prefix("fruit/")].available)
	assert(sim.life_world.held_unit(winner).origin.collector_id==winner and sim.life_world.held_unit(loser).is_empty())
	assert(events.size()==1 and events[0].person_id==winner and events[0].source==source and events[0].quantity==1)
	print("RESOURCE_COMPETING_CASE winner=",winner," harvested=1 loser_empty=true facts=1")
	scene.queue_free();await create_timer(.2).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return true

func run_case(id: String, material: String):
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var file:="user://resource_subjects_%d.json"%Time.get_ticks_usec()
	var store:=Store.new();assert(store.initialize("res://data/people.json",file,true).is_empty())
	var sim:=Sim.new();sim.store=store;sim.scene=scene;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false);player.set_process(false)
	var body: Node3D=sim.life_world.subjects[id].body
	var events: Array=[];sim.life_world.fact.connect(func(value: Dictionary):events.append(value.duplicate(true)))
	assert(sim.life_world.take_unit("absent","water_source").code=="invalid_subject")
	if material=="food":
		var selected:=""
		for key in sim.gathering.resources:
			var at: Vector3=sim.gathering.resources[key].mesh.global_position
			body.global_position=at+Vector3(0,-1,-.7);body.rotation.y=0
			if id!="player":sim.perception.observe(id)
			if sim.life_world.access_source(id,"fruit/"+key).ok:selected=key;break
		assert(not selected.is_empty(),"夹具须先找到实际可见可达的果实")
		var basket: Dictionary=sim.gathering.baskets["1"]
		basket.root.global_position=body.global_position+Vector3(.4,.4,.6)
		assert(sim.gathering.pickup(id,"1"));sim.world_objects.sync_held("basket/1")
		assert(sim.life_world.take_unit(id,"fruit/"+selected).ok)
		var item: Dictionary=sim.life_world.held_unit(id)
		assert(item.material=="food" and item.origin.collector_id==id and item.origin.resource_id==selected)
		assert(sim.gathering.harvested==1 and not sim.gathering.resources[selected].available)
		if id=="player":
			# 当前玩家只建模口渴；未建模饥饿时拒绝消费，且保留原食物。
			assert(sim.life_world.consume_unit(id).code=="not_consumable")
		else:
			# 存档会替换NPC字典；注册主体必须读取新字典，不修改旧引用。
			var old: Dictionary=store.people[id].needs
			store.people[id].needs={"hunger":72.0,"thirst":72.0,"food":"很饿","water":"很渴"}
			assert(sim.life_world.put_unit(id,"basket/1").ok)
			assert(sim.life_world.consume_contents(id,"basket/1").ok)
			assert(store.people[id].needs.hunger==27 and old.hunger!=27)
			assert(events[-1].origin.resource_id==selected)
		if id=="player":
			assert(sim.life_world.put_unit(id,"basket/1").ok)
			assert(basket.contents.count==1 and is_same(basket.contents.items[0],item))
	else:
		body.global_position=sim.water.SOURCE+Vector3(0,.1,-1);body.rotation.y=0
		if id!="player":sim.perception.observe(id)
		var bag: Dictionary=sim.water.bags["1"]
		bag.root.global_position=body.global_position+Vector3(.4,.5,.5)
		assert(sim.water.pickup(id,"1"));sim.world_objects.sync_held("water_bag/1")
		assert(sim.water.fill(id))
		assert(bag.contents.count==3 and sim.water.drawn==3 and events.size()==1 and events[0].kind=="filled")
		for item in bag.contents.items:assert(item.material=="water" and item.origin.source=="water_source")
		var needs: Dictionary=sim.life_world.subjects[id].needs.call();needs.thirst=72
		assert(sim.water.drink(id) and needs.thirst==27 and sim.water.consumed==1 and bag.contents.count==2)
		assert(events[-1].kind=="consumed" and events[-1].origin.source=="water_source")
		assert(sim.life_world.take_unit(id,"water_source").ok)
		assert(sim.life_world.put_unit(id,"water_bag/1").ok)
		assert(bag.contents.count==3 and sim.water.drawn==4)
		assert(sim.life_world.take_unit(id,"water_source").ok)
		assert(sim.life_world.put_unit(id,"water_bag/1").code=="container_full")
		assert(sim.life_world.held_unit(id).material=="water" and bag.contents.count==3)
	for event in events:
		assert(event.person_id==id)
		if id=="player":assert(not event.source_event_id.is_empty())
	print("RESOURCE_SUBJECT_CASE ",id," ",material," facts=",events.size())
	scene.queue_free();await create_timer(.2).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return true
