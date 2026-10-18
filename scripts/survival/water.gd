extends Node
## 玩家与人物共用水袋、接触检查及水量转移；模型不直接改水量。
const SOURCE=Vector3(20,-0.56,64)
const HOME=Vector3(3,0,7)
const CAPACITY=3
var sim: Node
var bags: Dictionary={}
var player_needs: Dictionary={"thirst":35.0}
var player_thirst: float:
	get:return player_needs.thirst
	set(value):player_needs.thirst=value
var drawn:=0
var consumed:=0
var spilled:=0

func _ready() -> void:
	var source:=Marker3D.new();sim.scene.add_child(source);source.global_position=SOURCE
	sim.life_world.register_supply("water_source","water",source,Vector3(0,0.03,0),_extract_water,true)
	for key in ["1","2"]:
		var root:=RigidBody3D.new()
		root.mass=0.4;root.collision_layer=4;root.collision_mask=7;root.continuous_cd=true
		root.set_meta("display_name","水袋")
		var visual:=MeshInstance3D.new();root.add_child(visual)
		var mesh:=CylinderMesh.new();mesh.top_radius=0.16;mesh.bottom_radius=0.22;mesh.height=0.55
		visual.mesh=mesh
		# 软水袋近似为有平底的容器；圆弧底在轻微坡面会倾倒滚走，导致放置后的地点校验失败。
		var shape:=CylinderShape3D.new();shape.radius=0.22;shape.height=0.55
		var collision:=CollisionShape3D.new();collision.shape=shape;root.add_child(collision)
		var material:=StandardMaterial3D.new(); material.albedo_color=Color(0.48,0.27,0.10)
		visual.material_override=material
		sim.supplies.add_child(root)
		var at:=HOME+Vector3(float(key)*0.6,0.3,0)
		root.global_position=at
		var label:=Label3D.new(); label.text="水袋 · 空"; label.position.y=0.45; label.font_size=32; label.pixel_size=0.005
		root.add_child(label)
		sim.world_objects.register_object("water_bag/"+key,root,Vector3(0,0.18,0))
		# 同一字典就是世界物体记录，水系统不维护第二份持有关系。
		bags[key]=sim.world_objects.objects["water_bag/"+key]
		bags[key]["xr_kind"]="water"
		bags[key].merge({"root":root,"label":label,"spawn":at,"contents":preload("res://scripts/survival/container_contents.gd").new("water",CAPACITY),"kind":"water_bag","extra":water_properties.bind(key)},true)
		sim.content_interaction.register_container("water_bag/"+key,bags[key],Vector3(0,0.28,0),_contents_changed.bind(key))

func _contents_changed(key: String) -> void:
	# 流体在袋内由水量显示；手中临时水团不能留在存入前的位置。
	for item in bags[key].contents.items:
		if is_instance_valid(item.get("visual")):item.visual.queue_free()
		item.erase("visual")

func water_properties(key: String) -> Dictionary:
	return {"water":bags[key].contents.count,"contents":bags[key].contents.describe()}

func _extract_water(_person: String) -> Dictionary:
	drawn+=1
	return {"ok":true,"item":{"material":"water","origin":{"source":"water_source"}}}

func hold_pose(id: String) -> Transform3D:
	var body:=owner(id)
	if id=="player":return sim.world_objects.player_hold_transform("water_bag/"+held(id),body)
	return body.global_transform*Transform3D(Basis.IDENTITY,Vector3(0.45,0.85,0.35))

func owner(id: String) -> Node3D:
	return sim.scene.get_node("Player") if id=="player" else sim.actors[id].body

func held(id: String) -> String:
	for key in bags:
		if bags[key].holder==id: return key
	return ""

func free_hand(id: String, hand: String="Hand.R") -> bool:
	return not sim.world_objects.held.has(id+"/"+hand) and (not sim.gathering.hands.has(id) or sim.gathering.hands[id].get("hand","Hand.R")!=hand)

func reach(id: String, at: Vector3) -> bool:
	return sim.gathering._reachable(id,at+Vector3(0,0.3,0),2.6)

func pickup(id: String, key: String, hand: String="Hand.R") -> bool:
	assert(hand in ["Hand.L","Hand.R"])
	if not bags.has(key) or bags[key].holder!="" or not free_hand(id,hand) or not reach(id,bags[key].root.global_position): return false
	return sim.world_objects.attach_to("water_bag/"+key,id,hand,hold_pose.bind(id)).ok

func drop(id: String) -> bool:
	return drop_result(id).ok

func drop_result(id: String) -> Dictionary:
	var key:=held(id)
	if key=="": return {"ok":false,"code":"not_held"}
	sim.world_objects.sync_held("water_bag/"+key)
	var released: Dictionary=sim.world_objects.release("water_bag/"+key,id)
	if not released.ok:return released
	if id!="player":
		sim.perception._record(id,"water_bag/"+key,"water_bag",sim.world_objects.grip_position("water_bag/"+key),true,sim.world_objects.observable_extra("water_bag/"+key))
		sim.perception.memories[id]["water_bag/"+key].source="本人刚刚放下水袋"
	return released

func fill(id: String) -> bool:
	var key:=held(id)
	if key=="":return false
	return sim.life_world.fill_container(id,"water_source","water_bag/"+key).ok

func drink(id: String, key: String="", use_source: bool=false) -> bool:
	if key=="" and not use_source:
		key=held(id)
		if key!="" and bags[key].contents.count==0 and reach(id,SOURCE): key=""
	if key!="":
		if not bags.has(key):return false
		return sim.life_world.consume_contents(id,"water_bag/"+key).ok
	return sim.life_world.consume_source(id,"water_source").ok

func give(id: String, recipient: String) -> Dictionary:
	var key:=held(id)
	if key=="": return {"success":false,"category":"no_held_water_bag","message":"自己没有持有水袋，未发生交付"}
	if recipient==id or (recipient!="player" and not sim.actors.has(recipient)):
		return {"success":false,"category":"invalid_recipient","message":"交付对象无效，水袋仍在自己手中"}
	# 先验证接触范围；不能通过远程尝试交付窥知接收者持物状态。
	if not reach(id,owner(recipient).global_position):
		return {"success":false,"category":"out_of_reach","message":"尚未到接收者可交接的距离，水袋仍在自己手中"}
	var hand:=""
	for candidate in (["Hand.R"] if recipient=="player" else ["Hand.R","Hand.L"]):
		if free_hand(recipient,candidate):hand=candidate;break
	if hand.is_empty():return {"success":false,"category":"recipient_occupied","message":"接收者没有空手，水袋仍在自己手中"}
	var attachment: Callable=hold_pose.bind(recipient)
	if recipient!="player":
		var actor: Node3D=owner(recipient)
		var offset: Transform3D=actor.global_transform.affine_inverse()*sim.world_objects.carry_transform("water_bag/"+key,actor,hand)
		attachment=func():return actor.global_transform*offset
	var transferred: Dictionary=sim.world_objects.transfer_attachment("water_bag/"+key,id,recipient,hand,attachment)
	assert(transferred.ok,"接触与空手检查后同步转移不应失败")
	return {"success":true,"category":"","message":"把水袋实际交给对方"}

func player_hint() -> String:
	var target:=player_target()
	if target.is_empty():return ""
	var blocked:=player_blocked(target)
	return blocked if not blocked.is_empty() else "F · "+player_description(target)

func player_target(drink_only: bool=false) -> String:
	var carried:=held("player")
	if drink_only:
		if not carried.is_empty() and bags[carried].contents.count>0:return "water/drink/"+carried
		return "water/drink/source" if sim.life_world.access_source("player","water_source").ok else ""
	var camera: Camera3D=sim.scene.get_node("Player/Eyes")
	var selector:=preload("res://scripts/player_target_selector.gd").new(camera)
	add_player_targets(selector)
	return selector.target

func add_player_targets(selector: RefCounted) -> void:
	var carried:=held("player")
	selector.consider("water/fill/"+carried if not carried.is_empty() else "water/drink/source",SOURCE,2.6,.65)
	for key in bags:
		var bag: Dictionary=bags[key]
		if free_hand("player") and bag.holder=="":selector.consider("water/pickup/"+key,bag.root.global_position,2.6,.65)
	if not carried.is_empty():
		for id in sim.actors:
			selector.consider("water/offer/"+id,owner(id).global_position+Vector3(0,1,0),2.6,.65)

func player_description(target: String) -> String:
	var key:=target.get_slice("/",2)
	match target.get_slice("/",1):
		"fill":return "装满水袋"
		"drink":return "在水源喝水" if key=="source" else "喝水袋里的水"
		"pickup":return "拿起水袋（%d 份水）"%bags[key].contents.count
		"offer":return "递水袋给"+sim.store.people[key].name+"（等待对方决定）"
	assert(false,"未知玩家水交互目标")
	return ""

func player_blocked(target: String) -> String:
	var key:=target.get_slice("/",2)
	match target.get_slice("/",1):
		"fill":
			if bags[key].contents.free_space==0:return "水袋已满"
			if not sim.life_world.access_source("player","water_source").ok:return "再靠近水源，或移开取水路线上的阻挡"
		"drink":
			if key=="source" and not sim.life_world.access_source("player","water_source").ok:return "再靠近水源，或移开取水路线上的阻挡"
		"offer":return sim.gathering.offer_availability(key,"water").get("message","")
	return ""

func _physics_process(delta: float) -> void:
	if not sim.ready_for_actions:return
	_update_labels()
	if not sim.enabled:return
	player_thirst=minf(100,player_thirst+0.035*delta)

func _update_labels() -> void:
	var vr_active: bool=sim.scene.get_node("Player").is_vr_active()
	for bag in bags.values():
		var desktop_held: bool=bag.holder=="player" and not vr_active
		# VR 手中物品的数量进入手柄提示，避免大号物品标签盖住操作说明。
		bag.label.visible=not (bag.holder=="player" and vr_active)
		bag.label.pixel_size=0.0015 if desktop_held else 0.005
		bag.label.position.y=0.32 if desktop_held else 0.45
		bag.label.text="水袋 · %d / %d"%[bag.contents.count,CAPACITY]

func player_interact(target: String) -> Dictionary:
	var kind:=target.get_slice("/",1)
	var key:=target.get_slice("/",2)
	# 计时结束时再次核实原目标；不能给换手后的袋子结算旧动作。
	if target!=player_target(kind=="drink") or not player_blocked(target).is_empty():return {"ok":false}
	match kind:
		"fill":return {"ok":fill("player")}
		"drink":return {"ok":drink("player","" if key=="source" else key,key=="source")}
		"pickup":return {"ok":pickup("player",key)}
		"offer":
			var offered: String=sim.gathering.offer_item(key,"water")
			return {"ok":not offered.is_empty(),"pending":not offered.is_empty()}
	assert(false,"未知玩家水交互目标")
	return {"ok":false}

func reset() -> void:
	for key in bags:
		var bag: Dictionary=bags[key]
		if bag.holder!="":sim.world_objects.release("water_bag/"+key,bag.holder)
		bag.contents.clear();bag.root.global_position=bag.spawn
		bag.root.linear_velocity=Vector3.ZERO;bag.root.angular_velocity=Vector3.ZERO
	drawn=0; consumed=0; spilled=0; player_thirst=35
