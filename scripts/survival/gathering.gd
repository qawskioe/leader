extends Node
## 玩家与 NPC 共用实体篮子、手持物和果实来源；没有资源背包 UI。
signal interaction_result(result: Dictionary)
signal item_offered(event: Dictionary)
var offers: Dictionary={}
const CAPACITY:=4
const GROVE:=Vector3(-9,0.4,48)
var sim: Node
var baskets: Dictionary={}
var resources: Dictionary={}
var hands: Dictionary={}
var loose_food: Dictionary={}
var elapsed:=0.0
var regrow_seconds:=600.0
var harvested:=0
var regrown:=0
var _hold:=0.0
var _target:=""
var _used:=false
var interaction_hint: Label
var _feedback:=0.0

func _ready() -> void:
	if not sim.scene.has_node("Outdoor"): return
	var canvas:=CanvasLayer.new(); add_child(canvas)
	interaction_hint=Label.new(); canvas.add_child(interaction_hint)
	interaction_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_hint.offset_left=-280; interaction_hint.offset_right=280
	interaction_hint.offset_top=-90; interaction_hint.offset_bottom=-20
	interaction_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	interaction_hint.add_theme_font_size_override("font_size",20)
	interaction_result.connect(func(result: Dictionary):
		_feedback=2.0
		interaction_hint.text=str(result.get("message",str(result.action)+( " · 已递出，等待对方决定" if result.get("pending",false) else " · 完成" if result.ok else " · 未完成：检查距离、占用及手中物品"))))
	var outdoor: Node3D=sim.scene.get_node("Outdoor")
	for index in [1,2]:
		var prefix:="Basket_%d_"%index
		var parts:=outdoor.find_children(prefix+"*","MeshInstance3D",true,false)
		assert(not parts.is_empty())
		var base: Node3D=outdoor.find_child(prefix+"Base",true,false)
		var root:=RigidBody3D.new()
		root.mass=0.8;root.continuous_cd=true;root.collision_mask=7
		root.name="CarryBasket%d"%index
		root.set_meta("display_name","篮子")
		sim.scene.add_child(root)
		root.global_position=base.global_position
		for part in parts: part.reparent(root,true)
		var body: RigidBody3D=root
		body.collision_layer=5
		body.set_meta("basket",str(index))
		var shape:=CollisionShape3D.new()
		var cylinder:=CylinderShape3D.new()
		cylinder.radius=0.40
		cylinder.height=0.54
		shape.shape=cylinder
		shape.position.y=0.25
		body.add_child(shape)
		sim.world_objects.register_object("basket/"+str(index),body,Vector3(0,0.55,0))
		baskets[str(index)]=sim.world_objects.objects["basket/"+str(index)]
		baskets[str(index)].merge({"root":root,"spawn":root.global_transform,"reserved":"","kind":"basket","contents":preload("res://scripts/survival/container_contents.gd").new("food",CAPACITY)},true)
		baskets[str(index)]["extra"]=_basket_properties.bind(str(index))
		sim.content_interaction.register_container("basket/"+str(index),baskets[str(index)],Vector3(0,0.55,0),_layout.bind(str(index)))
	for mesh in outdoor.find_children("HarvestFruit_*","MeshInstance3D",true,false):
		var id:=str(mesh.name)
		var body:=StaticBody3D.new()
		body.collision_layer=4
		mesh.add_child(body)
		body.set_meta("resource",id)
		var shape:=CollisionShape3D.new()
		var sphere:=SphereShape3D.new()
		sphere.radius=0.18
		shape.shape=sphere
		body.add_child(shape)
		resources[id]={"mesh":mesh,"body":body,"spawn":mesh.global_transform,"available":true,"reserved":"","regrow_at":0.0}
		sim.life_world.register_supply("fruit/"+id,"food",mesh,Vector3.ZERO,_extract_resource.bind(id))

func _extract_resource(person: String, key: String) -> Dictionary:
	if not harvest(person,key,sim.actors[person].assistance): return {"ok":false,"code":"source_unavailable"}
	return {"ok":true,"item":hands[person]}

func _basket_properties(key: String) -> Dictionary:
	return {"food_count":baskets[key].contents.count,"contents":baskets[key].contents.describe()}

func basket_for(id: String) -> String:
	for key in baskets:
		if baskets[key].holder==id: return key
	return ""

func reserve_basket(id: String) -> String:
	var held:=basket_for(id)
	if not held.is_empty(): return held
	for key in baskets:
		if baskets[key].holder=="" and baskets[key].reserved in ["",id]:
			baskets[key].reserved=id
			return key
	return ""

func _position(id: String) -> Vector3:
	return sim.scene.get_node("Player").global_position if id=="player" else sim.actors[id].body.global_position

func _reachable(id: String, target: Vector3, distance: float=2.5) -> bool:
	var source:=_position(id)+Vector3(0,1.2,0)
	if source.distance_to(target)>distance: return false
	var query:=PhysicsRayQueryParameters3D.create(source,target,1,[sim.scene.get_node("Player").get_rid()])
	# 篮子自身不应遮住其提手；地形和树干仍会挡住伸手。
	var excluded: Array[RID]=query.exclude
	for basket in baskets.values(): excluded.append(basket.body.get_rid())
	query.exclude=excluded
	return sim.scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func hold_pose(id: String) -> Transform3D:
	var owner: Node3D=sim.scene.get_node("Player") if id=="player" else sim.actors[id].body
	var pose: Transform3D=owner.global_transform*Transform3D(Basis.IDENTITY,Vector3(-0.44,0.65,-0.75) if id=="player" else Vector3(-0.52,0.6,0.35))
	if id=="player" and owner.is_vr_active(): pose=owner.vr.hands.transform_for("basket",pose,owner.vr)
	return pose

func pickup(id: String, key: String) -> bool:
	if sim.world_objects.held.has(id+"/Hand.L") or not baskets.has(key): return false
	var basket: Dictionary=baskets[key]
	if basket.holder!="" or (id!="player" and basket.reserved not in ["",id]): return false
	if not _reachable(id,basket.root.global_position+Vector3(0,0.4,0)): return false
	var result: Dictionary=sim.world_objects.attach_to("basket/"+key,id,"Hand.L",hold_pose.bind(id))
	if result.ok: basket.reserved=id
	return result.ok

func drop(id: String) -> bool:
	var key:=basket_for(id)
	if key.is_empty(): return false
	sim.world_objects.sync_held("basket/"+key)
	var released: Dictionary=sim.world_objects.release("basket/"+key,id)
	if released.ok: baskets[key].reserved=""
	return released.ok

func reserve_fruit(id: String, excluded: Array=[]) -> String:
	var closest:=""
	var distance:=8.0
	for key in resources:
		if key in excluded: continue
		var resource: Dictionary=resources[key]
		if resource.reserved not in ["",id]: continue
		var known: Dictionary=sim.perception.known(id,"fruit/"+key)
		if known.is_empty() or not known.available: continue
		var at:=Vector3(known.position[0],known.position[1],known.position[2])
		var d:=_position(id).distance_to(at)
		if d<distance:
			distance=d
			closest=key
	if closest!="": resources[closest].reserved=id
	return closest

func harvest(id: String, key: String, assistance: Dictionary={}) -> bool:
	if is_instance_valid(sim.water) and sim.world_objects.held.has(id+"/Hand.R"): return false
	if not resources.has(key) or hands.has(id): return false
	var basket:=basket_for(id)
	if basket.is_empty() or baskets[basket].contents.items.size()>=CAPACITY: return false
	var resource: Dictionary=resources[key]
	if not resource.available or (id!="player" and resource.reserved not in ["",id]): return false
	if not _reachable(id,resource.mesh.global_position): return false
	resource.available=false
	resource.reserved=""
	resource.body.collision_layer=0
	resource.mesh.hide()
	if id!="player":
		sim.perception._record(id,"fruit/"+key,"fruit",resource.mesh.global_position,false)
		sim.perception.memories[id]["fruit/"+key].source="本人刚刚采摘，知道该处这颗果实已取走"
	resource.regrow_at=elapsed+regrow_seconds
	var origin:=assistance.duplicate(true)
	origin["collector_id"]=id
	origin["resource_id"]=key
	var visual: MeshInstance3D=resource.mesh.duplicate()
	for child in visual.get_children(): child.free()
	sim.scene.add_child(visual)
	visual.show()
	hands[id]={"visual":visual,"origin":origin}
	harvested+=1
	return true

func take_from_basket(id: String, key: String, index: int) -> bool:
	if not baskets.has(key) or hands.has(id) or sim.world_objects.held.has(id+"/Hand.R"): return false
	var basket: Dictionary=baskets[key]
	if basket.holder not in ["",id] or index<0 or index>=basket.contents.items.size(): return false
	if not _reachable(id,basket.root.global_position+Vector3(0,0.3,0)): return false
	if id!="player" and sim.actors[id].carried>0: return false
	var removed: Dictionary=basket.contents.take(index)
	assert(removed.ok)
	var item: Dictionary=removed.item
	item.visual.reparent(sim.scene,true)
	hands[id]=item
	_layout(key)
	return true

func load_hand(id: String, key: String="") -> bool:
	if key=="": key=basket_for(id)
	if not baskets.has(key) or not hands.has(id) or baskets[key].contents.items.size()>=CAPACITY: return false
	if baskets[key].holder not in ["",id] or not _reachable(id,baskets[key].root.global_position+Vector3(0,0.3,0)): return false
	var item: Dictionary=hands[id]
	var inserted: Dictionary=baskets[key].contents.add(item)
	if not inserted.ok: return false
	hands.erase(id)
	item.visual.reparent(baskets[key].root,true)
	_layout(key)
	return true

func load_player_hand() -> bool:
	var target:=aimed_target()
	var key: String=target.get_slice("/",1) if target.begins_with("basket/") else basket_for("player")
	return load_hand("player",key)

func drop_food(id: String) -> bool:
	if not hands.has(id): return false
	var item: Dictionary=hands[id]
	if item.get("material","food")=="water":
		sim.water.spilled+=1;item.visual.queue_free();hands.erase(id);return true
	var visual: MeshInstance3D=item.visual
	var bounds:=visual.get_aabb()
	# 用网格凸包构造实际碰撞体；把视觉缩放/旋转烘进顶点，刚体保持单位缩放。
	var shape:=visual.mesh.create_convex_shape()
	var points:=shape.points
	for index in points.size():
		points[index]=visual.global_basis*(points[index]-bounds.get_center())
	shape.points=points
	var at:=Transform3D(Basis.IDENTITY,visual.to_global(bounds.get_center()))
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=at;query.collision_mask=7
	if not sim.scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var body:=RigidBody3D.new()
	body.mass=0.2;body.collision_layer=4;body.collision_mask=7
	body.continuous_cd=true
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	sim.scene.add_child(body);body.global_transform=at
	visual.reparent(body,true)
	var key:=str(body.get_instance_id())
	loose_food[key]={"body":body,"visual":visual,"origin":item.origin}
	hands.erase(id)
	return true

func take_loose_food(id: String, key: String) -> bool:
	if not loose_food.has(key) or hands.has(id) or sim.world_objects.held.has(id+"/Hand.R"): return false
	if id!="player" and sim.actors[id].carried>0: return false
	var item: Dictionary=loose_food[key]
	if not _reachable(id,item.body.global_position): return false
	item.visual.reparent(sim.scene,true)
	item.body.collision_layer=0;item.body.collision_mask=0;item.body.queue_free()
	hands[id]={"visual":item.visual,"origin":item.origin}
	loose_food.erase(key)
	return true

func _offered_visual(kind: String) -> Node3D:
	if kind=="food": return hands.player.visual if hands.has("player") else null
	var key: String=sim.water.held("player")
	return sim.water.bags[key].root if key!="" else null

func offer_food(target: String) -> String:
	return offer_item(target,"food")

func offer_item(target: String, kind: String) -> String:
	assert(kind in ["food","water"])
	if not sim.actors.has(target): return ""
	var visual:=_offered_visual(kind)
	if visual==null:return ""
	var at: Vector3=sim.actors[target].body.global_position+Vector3(0,1.1,0)
	if visual.global_position.distance_to(at)>0.75 or not _reachable("player",at): return ""
	if not sim.perception.sees(target,visual.global_position): return ""
	for key in offers:
		if offers[key].visual==visual.get_instance_id() and Time.get_ticks_msec()<offers[key].expires: return ""
	var key:="offer_%d"%Time.get_ticks_usec()
	var label: String="一份食物" if kind=="food" else "水袋（%d份水）"%sim.water.bags[sim.water.held("player")].contents.count
	offers[key]={"target":target,"kind":kind,"visual":visual.get_instance_id(),"expires":Time.get_ticks_msec()+45000}
	item_offered.emit({"id":key,"kind":"item_offer","item_kind":kind,"speaker":"player","listeners":[target],"text":"玩家将%s递到你面前，仍在玩家手中。结合自己的状态决定接受或拒绝，尚未发生交付。"%label})
	return key

func resolve_offer(key: String, target: String, accept: bool) -> Dictionary:
	var result:={"success":false,"source_event_id":key,"recipient_id":target,"message":"递物已失效，未转移物品"}
	if not offers.has(key) or offers[key].target!=target: return result
	var offer: Dictionary=offers[key]; offers.erase(key)
	result["item_kind"]=offer.kind
	if not accept:
		result.message="对方拒绝，物品仍在玩家手中"; return result
	var visual:=_offered_visual(offer.kind)
	if Time.get_ticks_msec()>offer.expires or visual==null or visual.get_instance_id()!=offer.visual: return result
	if offer.kind=="water":
		var at: Vector3=sim.actors[target].body.global_position+Vector3(0,1.1,0)
		if visual.global_position.distance_to(at)>0.85 or not _reachable("player",at):return result
		if sim.actors[target].stage!="idle":
			result.message="对方仍在行动，水袋仍在玩家手中";result["category"]="busy";return result
		var outcome: Dictionary=sim.water.give("player",target)
		if not outcome.success:
			result.message=outcome.message;result["category"]=outcome.category;return result
		sim._sync(target)
		result.success=true;result.message="玩家实际交给你水袋，现在在你手中；是否喝水由你决定"
		return result
	var actor: Dictionary=sim.actors[target]
	var at: Vector3=actor.body.global_position+Vector3(0,1.1,0)
	if hands.player.visual.global_position.distance_to(at)>0.85 or not _reachable("player",at): return result
	if actor.stage!="idle" or actor.carried>0 or hands.has(target) or sim.world_objects.held.has(target+"/Hand.R"):
		result.message="对方双手占用，未转移食物"; return result
	var item: Dictionary=hands.player
	var origin: Dictionary=item.origin.duplicate(true)
	origin.merge({"giver_id":"player","recipient_id":target,"helper_id":"player","requester_id":target,"request_id":key},true)
	hands.erase("player")
	item.origin=origin;item["material"]="food"
	hands[target]=item
	sim._sync(target)
	result.success=true; result.message="玩家实际交给你一份食物，现在在你手中"; result.food_origin=origin
	return result

func unload_one(id: String) -> bool:
	var key:=basket_for(id)
	if key.is_empty() or baskets[key].contents.items.is_empty() or hands.has(id): return false
	if not _reachable(id,sim.STORAGE+Vector3(0,0.4,0),2.4): return false
	var transferred: Dictionary=baskets[key].contents.transfer_to(sim.storage_contents,1)
	if not transferred.ok: return false
	if id!="player": sim.perception.note_storage_action(id,1)
	sim._refresh_visuals()
	_layout(key)
	return true

func _layout(key: String) -> void:
	for index in baskets[key].contents.items.size():
		var item: Dictionary=baskets[key].contents.items[index]
		if not is_instance_valid(item.get("visual")):
			item.visual=sim._fruit();sim.scene.add_child(item.visual)
		if item.visual.get_parent()!=baskets[key].root: item.visual.reparent(baskets[key].root,true)
		item.visual.transform=Transform3D(Basis.IDENTITY,Vector3((index%2-0.5)*0.28,0.22,(index/2-0.5)*0.28))

func release_reservations(id: String) -> void:
	for resource in resources.values():
		if resource.reserved==id: resource.reserved=""
	for basket in baskets.values():
		if basket.reserved==id and basket.holder!=id: basket.reserved=""

func _cancel_offer(key: String, message: String) -> void:
	# 在交接失效的当帧反馈；排队或迟到的模型答复不能恢复已取消的物品转移。
	offers.erase(key)
	interaction_result.emit({"action":"递物","ok":false,"pending":false,"offer_id":key,"message":message})

func _physics_process(delta: float) -> void:
	if not sim.enabled: return
	for key in offers.keys():
		var offer: Dictionary=offers[key]
		var visual:=_offered_visual(offer.kind)
		if visual==null or visual.get_instance_id()!=offer.visual:
			_cancel_offer(key,"递物已取消：原来的物品已不在手中")
		elif visual.global_position.distance_to(sim.actors[offer.target].body.global_position+Vector3(0,1.1,0))>0.85:
			_cancel_offer(key,"递物已撤回：距离已拉开，物品仍在你手中")
		elif Time.get_ticks_msec()>offer.expires:
			_cancel_offer(key,"递物等待已超时：物品仍在你手中，可重新递出")
	elapsed+=delta
	for resource in resources.values():
		if not resource.available and elapsed>=resource.regrow_at:
			resource.available=true
			resource.mesh.show()
			resource.body.collision_layer=4
			regrown+=1
	for id in hands:
		if id=="player":
			hands[id].visual.global_transform=sim.scene.get_node("Player/Eyes").global_transform*Transform3D(Basis.IDENTITY,Vector3(0.32,-0.24,-0.65))
			var player: Node3D=sim.scene.get_node("Player")
			if player.is_vr_active(): hands[id].visual.global_transform=player.vr.hands.transform_for("fruit",hands[id].visual.global_transform,player.vr)
		else:
			var skeleton: Skeleton3D=sim.actors[id].skeleton
			hands[id].visual.global_position=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hand.R")).origin)
	_player_input(delta)

func aimed_target() -> String:
	var camera: Camera3D=sim.scene.get_node("Player/Eyes")
	var nearest:=INF
	var target:=""
	if hands.has("player"):
		for id in sim.actors:
			var at: Vector3=sim.actors[id].body.global_position+Vector3(0,1.1,0)
			var offset:=at-camera.global_position
			if hands.player.visual.global_position.distance_to(at)<=0.75 and (-camera.global_basis.z).dot(offset.normalized())>0.85 and _reachable("player",at) and sim.perception.sees(id,hands.player.visual.global_position):
				if offset.length()<nearest:nearest=offset.length();target="offer/"+id
		if target!="":return target
	if not hands.has("player"):
		# 看进开口、对准实际果实才取内容物；篮沿仍保留提篮入口。
		for key in baskets:
			var basket: Dictionary=baskets[key]
			if basket.holder not in ["","player"] or basket.root.to_local(camera.global_position).y<0.52: continue
			for index in basket.contents.items.size():
				var at: Vector3=basket.contents.items[index].visual.global_position
				var offset:=at-camera.global_position
				var forward: Vector3=-camera.global_basis.z
				var depth:=forward.dot(offset)
				var aim_distance: float=(offset-forward*depth).length()
				if depth>0 and offset.length()<2.6 and aim_distance<0.16 and _reachable("player",at):
					if aim_distance<nearest: nearest=aim_distance;target="contained/"+key+"/"+str(index)
		if target!="": return target
		for key in loose_food:
			var at: Vector3=loose_food[key].body.global_position
			var offset:=at-camera.global_position
			if offset.length()<2.6 and (-camera.global_basis.z).dot(offset.normalized())>0.94 and _reachable("player",at):
				if offset.length()<nearest: nearest=offset.length();target="loose/"+key
		if target!="": return target
	# 小果实使用有限角度选择，不要求像射击一样命中 18cm 碰撞球；仍检查遮挡和伸手距离。
	for key in baskets:
		if baskets[key].holder!="": continue
		var at: Vector3=baskets[key].root.global_position+Vector3(0,0.35,0)
		var offset:=at-camera.global_position
		if offset.length()<2.6 and (-camera.global_basis.z).dot(offset.normalized())>0.94 and _reachable("player",at):
			var score: float=(1.0-(-camera.global_basis.z).dot(offset.normalized()))*100+offset.length()*0.01
			if score<nearest: nearest=score; target="basket/"+key
	for key in resources:
		if not resources[key].available: continue
		var at: Vector3=resources[key].mesh.global_position
		var offset:=at-camera.global_position
		if offset.length()<2.6 and (-camera.global_basis.z).dot(offset.normalized())>0.97 and _reachable("player",at):
			var score: float=(1.0-(-camera.global_basis.z).dot(offset.normalized()))*100+offset.length()*0.01
			if score<nearest: nearest=score; target="fruit/"+key
	var to_storage: Vector3=sim.STORAGE+Vector3(0,0.4,0)-camera.global_position
	if to_storage.length()<2.4 and (-camera.global_basis.z).dot(to_storage.normalized())>0.65 and basket_for("player")!="": target="unload"
	return target

func _player_input(delta: float) -> void:
	if interaction_hint==null: return
	interaction_hint.visible=Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
	if not interaction_hint.visible:
		_hold=0; _used=false; return
	_feedback=maxf(0,_feedback-delta)
	var pressed:=Input.is_action_pressed("player_interact")
	var target:=aimed_target()
	if target=="" and pressed and not _used and sim.water.player_interact(): _used=true; return
	var description:=""
	var blocked:=""
	if target.begins_with("offer/"):
		description="递给"+str(sim.store.people[target.get_slice("/",1)].name)+"（等待对方决定）"
	elif target.begins_with("contained/"):
		description="从篮中取出一颗果实"
		if sim.water.held("player")!="": blocked="先按 G 放下水袋"
	elif target.begins_with("loose/"):
		description="拿起地上的食物"
	elif target.begins_with("basket/"):
		description="拿起篮子（右键可放入果实）" if hands.has("player") else "拿起篮子"
		if basket_for("player")!="" or sim.water.held("player")!="": blocked="先按 G 放下携带物"
	elif target.begins_with("fruit/"):
		description="摘取果实"
		if basket_for("player")=="": blocked="先拿一只篮子"
		elif hands.has("player"): blocked="先按右键把手中果实装篮"
		elif baskets[basket_for("player")].contents.items.size()>=CAPACITY: blocked="篮子已满，带回储食处卸下"
	elif target=="unload": description="卸下一份食物"
	if not pressed: _hold=0; _used=false
	if target!=_target: _target=target; _hold=0
	if _feedback<=0:
		interaction_hint.text=blocked if blocked!="" else ("按住 F · "+description+"  %d%%"%int(_hold/0.8*100) if target!="" else "T 说话 · F 取物／取水 · 右键装篮 · G 放下手中物品 · Q 喝水")
	if _feedback<=0 and target=="" and sim.water.player_hint()!="": interaction_hint.text=sim.water.player_hint()
	if not pressed or _used or target=="" or blocked!="": return
	_hold+=delta
	if _hold<0.8: return
	_used=true
	var ok:=false
	if target.begins_with("offer/"): ok=not offer_food(target.get_slice("/",1)).is_empty()
	elif target.begins_with("contained/"): ok=take_from_basket("player",target.get_slice("/",1),int(target.get_slice("/",2)))
	elif target.begins_with("loose/"): ok=take_loose_food("player",target.get_slice("/",1))
	elif target.begins_with("basket/"): ok=pickup("player",target.get_slice("/",1))
	elif target.begins_with("fruit/"): ok=harvest("player",target.get_slice("/",1))
	elif target=="unload": ok=unload_one("player")
	interaction_result.emit({"action":description,"ok":ok,"pending":ok and target.begins_with("offer/")})

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_Q:
		interaction_result.emit({"action":"喝水","ok":sim.water.drink("player")})
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		interaction_result.emit({"action":"装篮","ok":load_player_hand()})
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_G:
		if hands.has("player"):
			var ok:=drop_food("player")
			interaction_result.emit({"action":"松开食物","ok":ok,"message":"已松手，食物自然落下" if ok else "当前位置与物体重叠，请移开手中食物再松手"})
			get_viewport().set_input_as_handled();return
		if sim.world_objects.has_held("player"):
			var released: Dictionary=sim.world_objects.drop_held("player")
			interaction_result.emit({"action":"放下携带物","ok":released.ok})
		else:interaction_result.emit({"action":"放下携带物","ok":drop("player")})
		get_viewport().set_input_as_handled()

func reset() -> void:
	offers.clear()
	for item in loose_food.values(): item.body.queue_free()
	loose_food.clear()
	for item in hands.values(): item.visual.queue_free()
	hands.clear()
	for basket in baskets.values():
		for item in basket.contents.items: item.visual.queue_free()
		basket.contents.clear()
		if basket.holder!="":sim.world_objects.release("basket/"+str(basket.root.get_meta("basket")),basket.holder)
		basket.reserved=""
		basket.root.global_transform=basket.spawn
		basket.body.collision_layer=5;basket.body.linear_velocity=Vector3.ZERO;basket.body.angular_velocity=Vector3.ZERO
	for resource in resources.values():
		resource.available=true; resource.reserved=""
		resource.mesh.show(); resource.body.collision_layer=4
	elapsed=0; harvested=0; regrown=0

func carried_count() -> int:
	var count:=hands.size()
	for basket in baskets.values(): count+=basket.contents.items.size()
	return count
