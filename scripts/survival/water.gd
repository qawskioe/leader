extends Node
## 玩家与人物共用水袋、接触检查及水量转移；模型不直接改水量。
const SOURCE=Vector3(20,-0.56,64)
const HOME=Vector3(3,0,7)
const CAPACITY=3
var sim: Node
var bags: Dictionary={}
var player_thirst:=35.0
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
		var mesh:=SphereMesh.new(); mesh.radius=0.22; mesh.height=0.55
		visual.mesh=mesh
		var shape:=CapsuleShape3D.new();shape.radius=0.22;shape.height=0.55
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
		bags[key].merge({"root":root,"label":label,"spawn":at,"contents":preload("res://scripts/survival/container_contents.gd").new("water",CAPACITY),"kind":"water_bag","extra":water_properties.bind(key)},true)
		sim.content_interaction.register_container("water_bag/"+key,bags[key],Vector3(0,0.28,0))

func water_properties(key: String) -> Dictionary:
	return {"water":bags[key].contents.count,"contents":bags[key].contents.describe()}

func _extract_water(_person: String) -> Dictionary:
	drawn+=1
	return {"ok":true,"item":{"material":"water","origin":{"source":"water_source"}}}

func hold_pose(id: String) -> Transform3D:
	var body:=owner(id)
	var pose:=body.global_transform*Transform3D(Basis.IDENTITY,Vector3(0.45,0.85,0.35))
	if id=="player":
		pose=body.get_node("Eyes").global_transform*Transform3D(Basis.IDENTITY,Vector3(0.48,-0.3,-1.15))
		if body.is_vr_active():pose=body.vr.hands.transform_for("water",pose,body.vr)
	return pose

func owner(id: String) -> Node3D:
	return sim.scene.get_node("Player") if id=="player" else sim.actors[id].body

func held(id: String) -> String:
	for key in bags:
		if bags[key].holder==id: return key
	return ""

func free_hand(id: String, hand: String="Hand.R") -> bool:
	return not sim.world_objects.held.has(id+"/"+hand) and (hand!="Hand.R" or not sim.gathering.hands.has(id))

func reach(id: String, at: Vector3) -> bool:
	return sim.gathering._reachable(id,at+Vector3(0,0.3,0),2.6)

func pickup(id: String, key: String) -> bool:
	if not bags.has(key) or bags[key].holder!="" or not free_hand(id) or not reach(id,bags[key].root.global_position): return false
	return sim.world_objects.attach_to("water_bag/"+key,id,"Hand.R",hold_pose.bind(id)).ok

func drop(id: String) -> bool:
	var key:=held(id)
	if key=="": return false
	sim.world_objects.sync_held("water_bag/"+key)
	var released: Dictionary=sim.world_objects.release("water_bag/"+key,id)
	if not released.ok:return false
	if id!="player":
		sim.perception._record(id,"water_bag/"+key,"water_bag",sim.world_objects.grip_position("water_bag/"+key),true,sim.world_objects.observable_extra("water_bag/"+key))
		sim.perception.memories[id]["water_bag/"+key].source="本人刚刚放下水袋"
	return true

func fill(id: String) -> bool:
	var key:=held(id)
	if key=="" or not reach(id,SOURCE): return false
	var quantity: int=bags[key].contents.free_space
	for index in quantity:
		var added: Dictionary=bags[key].contents.add({"source":"water_source"})
		assert(added.ok)
	drawn+=quantity
	return true

func drink(id: String, key: String="", use_source: bool=false) -> bool:
	if key=="" and not use_source:
		key=held(id)
		if key!="" and bags[key].contents.count==0 and reach(id,SOURCE): key=""
	if key!="":
		if not bags.has(key) or bags[key].contents.count<=0: return false
		if bags[key].holder!=id and (bags[key].holder!="" or not reach(id,bags[key].root.global_position)): return false
		var taken: Dictionary=bags[key].contents.take()
		assert(taken.ok)
	else:
		if not reach(id,SOURCE): return false
		drawn+=1
	consumed+=1
	if id=="player": player_thirst=maxf(0,player_thirst-45)
	else: sim.store.people[id].needs.thirst=maxf(0,sim.store.people[id].needs.thirst-45)
	return true

func give(id: String, recipient: String) -> Dictionary:
	var key:=held(id)
	if key=="": return {"success":false,"category":"no_held_water_bag","message":"自己没有持有水袋，未发生交付"}
	if recipient==id or (recipient!="player" and not sim.actors.has(recipient)):
		return {"success":false,"category":"invalid_recipient","message":"交付对象无效，水袋仍在自己手中"}
	# 先验证接触范围；不能通过远程尝试交付窥知接收者持物状态。
	if not reach(id,owner(recipient).global_position):
		return {"success":false,"category":"out_of_reach","message":"尚未到接收者可交接的距离，水袋仍在自己手中"}
	if not free_hand(recipient):
		return {"success":false,"category":"recipient_occupied","message":"接收者双手被物品占用，无法接下水袋；水袋仍在自己手中，需对方腾出手后才能交付"}
	var transferred: Dictionary=sim.world_objects.transfer_attachment("water_bag/"+key,id,recipient,"Hand.R",hold_pose.bind(recipient))
	assert(transferred.ok,"接触与空手检查后同步转移不应失败")
	return {"success":true,"category":"","message":"把水袋实际交给对方"}

func player_hint() -> String:
	var camera: Camera3D=sim.scene.get_node("Player/Eyes")
	if aimed(camera,SOURCE): return "F · 装满水袋" if held("player")!="" else "F · 在水源喝水"
	for bag in bags.values():
		if bag.holder=="" and aimed(camera,bag.root.global_position): return "F · 拿起水袋（%d 份水）"%bag.contents.count
	if held("player")!="":
		for id in sim.actors:
			if aimed(camera,owner(id).global_position+Vector3(0,1,0)): return "F · 递水袋给"+sim.store.people[id].name+"（等待对方决定）"
	return ""

func _physics_process(delta: float) -> void:
	if not sim.ready_for_actions or not sim.enabled: return
	player_thirst=minf(100,player_thirst+0.035*delta)
	for bag in bags.values():
		var desktop_held: bool=bag.holder=="player" and not sim.scene.get_node("Player").is_vr_active()
		bag.label.pixel_size=0.0015 if desktop_held else 0.005
		bag.label.position.y=0.32 if desktop_held else 0.45
		bag.label.text="水袋 · %d / %d"%[bag.contents.count,CAPACITY]

func player_interact() -> bool:
	var camera: Camera3D=sim.scene.get_node("Player/Eyes")
	if aimed(camera,SOURCE):
		var ok:=fill("player") if held("player")!="" else drink("player")
		sim.gathering.interaction_result.emit({"action":"取水／饮水","ok":ok}); return true
	for key in bags:
		if bags[key].holder=="" and aimed(camera,bags[key].root.global_position):
			sim.gathering.interaction_result.emit({"action":"拿水袋","ok":pickup("player",key)}); return true
	if held("player")!="":
		for id in sim.actors:
			if aimed(camera,owner(id).global_position+Vector3(0,1,0)):
				var offered: String=sim.gathering.offer_item(id,"water")
				sim.gathering.interaction_result.emit({"action":"递出水袋","ok":offered!="","pending":offered!=""})
				return true
	return false

func aimed(camera: Camera3D, at: Vector3) -> bool:
	var delta:=at-camera.global_position
	return delta.length()<2.6 and (-camera.global_basis.z).dot(delta.normalized())>0.65

func reset() -> void:
	for key in bags:
		var bag: Dictionary=bags[key]
		if bag.holder!="":sim.world_objects.release("water_bag/"+key,bag.holder)
		bag.contents.clear();bag.root.global_position=bag.spawn
		bag.root.linear_velocity=Vector3.ZERO;bag.root.angular_velocity=Vector3.ZERO
	drawn=0; consumed=0; spilled=0; player_thirst=35
