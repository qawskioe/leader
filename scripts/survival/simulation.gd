extends Node
const MOTION_STOP_BLEND_SECONDS:=0.2
## 世界模拟：技能提出操作，程序处理实际移动、库存、物品转移、消费和需求。
signal action_result(result: Dictionary)
signal state_changed
signal skill_motion_result(person_id: String, result: Dictionary)
const Gathering=preload("res://scripts/survival/gathering.gd")
const GroundMotion=preload("res://scripts/survival/ground_motion.gd")
const Water=preload("res://scripts/survival/water.gd")
var water: Node
var world_objects: Node
var content_interaction:=preload("res://scripts/survival/content_interaction.gd").new()
var handover: Node
var gathering: Node
var move_speed:=1.5
const Catalog=preload("res://scripts/survival/action_catalog.gd")
const Perception=preload("res://scripts/survival/perception.gd")
var perception:=Perception.new()
var space:=preload("res://scripts/skills/egocentric_space.gd").new()
var _memory_clock:=0.0
var _sense_clock:=0.0
const STORAGE := Vector3(5.4,0,4.2)
const INTENTS = Catalog.IDS
var store: RefCounted
var scene: Node3D
var ready_for_actions := false
var enabled := true
var hunger_rate := 0.025
var storage_contents=preload("res://scripts/survival/container_contents.gd").new("food",1000)
var life_world=preload("res://scripts/survival/life_world.gd").new()
var storage_food: int:
	get: return storage_contents.count
var storage_origins: Array[Dictionary]:
	get:
		var origins: Array[Dictionary]=[]
		for item in storage_contents.items: origins.append(item.get("origin",{}))
		return origins
var eaten := 0
var actors: Dictionary = {}
var supplies: Node3D
var storage_visual: Node3D
var _clock := 0.0

func _ready() -> void:
	content_interaction.sim=self
	life_world.sim=self
	world_objects=preload("res://scripts/skills/world_objects.gd").new();add_child(world_objects)
	perception.world_objects=world_objects
	perception.sim=self
	space.sim=self
	for id in store.people:
		var body: CharacterBody3D = scene.get_node("People/"+store.people[id].node)
		var animation: AnimationPlayer = body.find_children("*","AnimationPlayer",true,false)[0]
		var skeleton: Skeleton3D = body.find_children("*","Skeleton3D",true,false)[0]
		assert(skeleton.find_bone("Hand.R")>=0,"人物缺少右手骨骼")
		actors[id]={"body":body,"animation":animation,"skeleton":skeleton,"spawn":body.transform,"food_origin":{},"assistance":{},
			"stage":"idle","skill_name":"","event_id":"","carried":0,"path":PackedVector3Array(),"step":0,"elapsed":0.0,"stalled":0.0}
	supplies=Node3D.new()
	supplies.name="SurvivalFood"
	scene.add_child(supplies)
	storage_visual=_station(STORAGE,Color(0.36,0.23,0.12),"Storage")
	var storage_body:=StaticBody3D.new();storage_visual.add_child(storage_body)
	content_interaction.register_container("storage",{"root":storage_visual,"body":storage_body,"holder":"","contents":storage_contents},Vector3(0,0.4,0),_refresh_visuals)
	for index in 3:
		var added: Dictionary=storage_contents.add({"material":"food","origin":{}})
		assert(added.ok)
	_refresh_visuals()
	gathering=Gathering.new()
	gathering.sim=self
	add_child(gathering)
	water=Water.new(); water.sim=self; add_child(water)
	handover=preload("res://scripts/survival/handover.gd").new();handover.sim=self;add_child(handover)
	for id in actors: store.people[id].needs["thirst"]=35.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	ready_for_actions=true
	perception.seed_arrival(actors.keys())
	for id in actors: _sync(id)

func observation(id: String) -> Dictionary:
	var storage:=perception.known(id,"storage")
	var seen: Variant=storage.get("extra",{}).get("food_count") if storage.get("visible_now",false) else null
	var allowed:=INTENTS.duplicate()
	var catalog:=Catalog.DESCRIPTIONS.duplicate()
	return {"control_level":"skill","allowed_intents":allowed,"action_catalog":catalog,
		"holding_water_bag":water.held(id)!="", "personal_water":water.bags[water.held(id)].contents.count if water.held(id)!="" else 0,
		"carried_food":actors[id].carried,"holding_basket":gathering.basket_for(id)!="",
		"personal_basket_food":gathering.baskets[gathering.basket_for(id)].contents.items.size() if gathering.basket_for(id)!="" else 0,
		"hand_harvested_food":gathering.hands.has(id),"storage_food_seen":seen,
		"known_objects":perception.memories.get(id,{}).duplicate(true),"knowledge_revision":perception.revisions.get(id,0),
		"rules":"known_objects 是本人观察或记住的信息。visible_now=false 时位置和数量可能过时；未知不等于没有。不要用缺材料、路线失败或未知位置冒充缺少接口。先探索确认，或选择已存在的行为。技能参数中的recipient是物品接收者，与addressed_person说话对象独立。"}

func _physics_process(delta: float) -> void:
	if not ready_for_actions or not enabled: return
	_clock+=delta
	store.memory.advance(delta)
	perception.clock=store.memory.clock
	_memory_clock+=delta
	if _memory_clock>=5:
		_memory_clock=0
		store.refresh_memory_views()
		for id in actors:
			var retained: Dictionary={}
			for entry in store.memory.retained(id,"landmark"): retained[entry.id]=true
			for key in perception.memories.get(id,{}).keys():
				if not perception.memories[id][key].visible_now and not retained.has(key) and not store.memory.observations[id].has(key): perception.memories[id].erase(key)
		var memory_error: String=store.memory.save()
		if memory_error!="": push_error(memory_error)
	_sense_clock+=delta
	if _sense_clock>=0.2:
		_sense_clock=0
		for id in actors: perception.observe(id)
	for id in actors:
		var actor: Dictionary=actors[id]
		var body: CharacterBody3D=actor.body
		store.people[id].needs.thirst=clampf(store.people[id].needs.thirst+0.035*delta,0,100)
		store.people[id].needs.hunger=clampf(store.people[id].needs.hunger+hunger_rate*delta,0,100)
		var before_motion: Transform3D=body.global_transform
		if actor.stage=="skill_moving": _walk(id,delta)
		else:
			body.velocity.x=0
			body.velocity.z=0
		if not body.is_on_floor(): body.velocity.y-=9.8*delta
		else: body.velocity.y=0
		if actor.has("motion_guard"):
			var proposed:=body.global_transform;proposed.origin+=body.velocity*delta
			var checked: Dictionary=actor.motion_guard.call(before_motion,proposed)
			if not checked.ok:
				body.global_transform=before_motion;body.velocity=Vector3.ZERO
				_finish_skill_motion(id,false,"持物移动受阻",checked)
		GroundMotion.move(body,delta)
		if actor.has("motion_guard"):
			var checked: Dictionary=actor.motion_guard.call(before_motion,body.global_transform)
			if not checked.ok:
				body.global_transform=before_motion;body.velocity=Vector3.ZERO
				_finish_skill_motion(id,false,"持物移动受阻",checked)
		_sync(id)
	if _clock>=1.0:
		_clock=0
		state_changed.emit()

func _walk(id: String, delta: float) -> void:
	var actor: Dictionary=actors[id]
	var body: CharacterBody3D=actor.body
	actor.elapsed+=delta
	if actor.elapsed>actor.walk_limit:
		_finish_skill_motion(id,false,"当前一段移动超时，未能到达所选目标")
		return
	if actor.path.is_empty(): return
	var target: Vector3=actor.path[actor.step]
	var direction:=target-body.global_position
	direction.y=0
	# 技能已在目的地预留站位距离；再提前0.2米结束会使近距离抓握够不到。
	var arrival_tolerance:=0.01 if actor.get("keep_motion_heading",false) else (0.04 if actor.stage=="skill_moving" else 0.20)
	if direction.length()<arrival_tolerance:
		actor.step+=1
		if actor.step>=actor.path.size():
			_finish_skill_motion(id,true,"已到达本次选择的地面点附近")
		return
	if body.get_real_velocity().length()<0.08: actor.stalled+=delta
	else: actor.stalled=0
	if actor.stalled>5:
		_finish_skill_motion(id,false,"路线被挡住，未能到达所选目标")
		return
	# 精细站位必须真正到点；末帧减速避免固定步长越过目标后反复折返。
	var speed:=minf(move_speed,direction.length()/maxf(delta,.0001))
	direction=direction.normalized()
	body.velocity.x=direction.x*speed
	body.velocity.z=direction.z*speed
	if not actor.get("keep_motion_heading",false):body.rotation.y=lerp_angle(body.rotation.y,atan2(direction.x,direction.z),minf(delta*8,1))

func _finish_skill_motion(id: String, success: bool, message: String, details: Dictionary={}) -> void:
	var actor: Dictionary=actors[id]
	var contacts: Array=[]
	if not success:
		for index in actor.body.get_slide_collision_count():
			var collision: KinematicCollision3D=actor.body.get_slide_collision(index)
			if absf(collision.get_normal().y)>=GroundMotion.MIN_FLOOR_Y: continue
			contacts.append({"position":collision.get_position(),"normal":collision.get_normal()})
			if contacts.size()==4: break
	actor.erase("motion_guard");actor.erase("keep_motion_heading")
	actor.stage="skill_wait";actor.path=PackedVector3Array();actor.body.velocity=Vector3.ZERO
	# 行走停下不应先reset_bone_poses；让动画混合保留当前身体姿态。
	# 下一段技能可以接管此过渡中的姿态，整项技能结束仍由宿主连续回位。
	actor.animation.get_animation("Idle").loop_mode=Animation.LOOP_LINEAR
	actor.animation.play("Idle",MOTION_STOP_BLEND_SECONDS)
	# 世界坐标仅在宿主信号中流转，由技能适配器换算到本次观察坐标系再交付。
	var result: Dictionary={"ok":success,"code":"arrived" if success else "movement_failed","message":message,"world_contacts":contacts}
	result.merge(details,true)
	skill_motion_result.emit(id,result)

func _sync(id: String) -> void:
	var person: Dictionary=store.people[id]
	var unit: Dictionary=gathering.hands.get(id,{})
	actors[id].carried=1 if not unit.is_empty() and unit.get("material","food")=="food" else 0
	actors[id].food_origin=unit.get("origin",{})
	person.needs["water"]="目前不渴" if person.needs.thirst<25 else ("有些渴" if person.needs.thirst<60 else "很渴")
	person.needs.food="目前不饿" if person.needs.hunger<25 else ("有些饿" if person.needs.hunger<60 else "很饿")
	var actor: Dictionary=actors[id]
	var action_name: String={"idle":"休息","skill_learning":"正在学习","skill_teaching":"正在教导","skill_studying":"正在学习"}.get(actor.stage,actor.get("skill_name",actor.stage))
	person.current_action={"name":action_name,"status":"休息" if actor.stage=="idle" else "执行中",
		"intent":"none","source_event_id":actor.event_id if actor.stage!="idle" else ""}
	person["survival_observation"]=observation(id)

func _animation(actor: Dictionary, name: String) -> void:
	actor.skeleton.reset_bone_poses()
	actor.animation.get_animation(name).loop_mode=Animation.LOOP_LINEAR
	actor.animation.play(name)

func _fruit() -> MeshInstance3D:
	var fruit:=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=0.14
	mesh.height=0.25
	fruit.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(0.78,0.29,0.08)
	fruit.material_override=material
	return fruit

func _station(at: Vector3, color: Color, label: String) -> Node3D:
	var root:=Node3D.new()
	root.name=label
	root.position=at
	supplies.add_child(root)
	var base:=MeshInstance3D.new()
	var mesh:=CylinderMesh.new()
	mesh.top_radius=0.65
	mesh.bottom_radius=0.55
	mesh.height=0.2
	base.mesh=mesh
	base.position.y=0.13
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	base.material_override=material
	root.add_child(base)
	var food:=Node3D.new()
	food.name="Food"
	root.add_child(food)
	return food

func _refresh_visuals() -> void:
	for index in storage_contents.items.size():
		var item: Dictionary=storage_contents.items[index]
		if not is_instance_valid(item.get("visual")):
			item["visual"]=_fruit();storage_visual.add_child(item.visual)
		elif item.visual.get_parent()!=storage_visual: item.visual.reparent(storage_visual,true)
		item.visual.position=Vector3((index%3-1)*0.3,0.36,(index/3)*0.28)
	state_changed.emit()

func reset() -> void:
	for id in actors:
		if actors[id].has("skill_owner"):
			_finish_skill_motion(id,false,"场景重置取消技能动作")
			actors[id].erase("skill_owner")
	perception.reset()
	perception.seed_arrival(actors.keys())
	for item in storage_contents.items:
		if is_instance_valid(item.get("visual")): item.visual.queue_free()
	storage_contents.clear()
	for index in 3:
		var added: Dictionary=storage_contents.add({"material":"food","origin":{}})
		assert(added.ok)
	if is_instance_valid(gathering): gathering.reset()
	if is_instance_valid(water): water.reset()
	for id in actors: store.people[id].needs["thirst"]=35.0
	eaten=0
	for id in actors:
		var actor: Dictionary=actors[id]
		actor.stage="idle"
		actor.carried=0
		actor.food_origin={}
		actor.assistance={}
		actor.path=PackedVector3Array()
		actor.body.transform=actor.spawn
		actor.body.velocity=Vector3.ZERO
		_animation(actor,"Idle")
		_sync(id)
	_refresh_visuals()

func debug_summary() -> String:
	return "储食处 %d 份；已食用 %d 份"%[storage_food,eaten]

func add_stored_food(origin: Dictionary) -> void:
	var added: Dictionary=storage_contents.add({"material":"food","origin":origin.duplicate(true)})
	assert(added.ok)
	_refresh_visuals()

func stop(id: String) -> void:
	if actors[id].stage=="skill_moving": _finish_skill_motion(id,false,"动作已取消")
	actors[id].body.velocity=Vector3.ZERO
