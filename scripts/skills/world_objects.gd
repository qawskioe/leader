extends Node
## 世界拥有物体及持有关系；普通拿取使用近距与视线检查，不依赖骨骼接触。
var objects: Dictionary={}
var held: Dictionary={}

func has_held(person: String) -> bool:
	return held.keys().any(func(key):return str(key).begins_with(person+"/"))

func drop_held(person: String) -> Dictionary:
	for id in objects:
		if objects[id].holder==person:
			sync_held(id)
			return release(id,person)
	return {"ok":false,"code":"not_held"}

func register_object(id: String, body: RigidBody3D, grip_local: Vector3=Vector3.ZERO) -> void:
	assert(not id.is_empty() and not objects.has(id))
	objects[id]={"body":body,"grip":grip_local,"holder":"","hand":"","saved":{},"attachment":Callable(),"attachment_frame":"body","kind":"interactable","extra":Callable(),"player_frame":NodePath("Eyes"),"player_offset":Vector3(0.48,-0.3,-1.15),"xr_kind":""}

func player_hold_transform(id: String, player: Node3D) -> Transform3D:
	# PC拿取、他人递交和读档共用同一持物槽；物品配置只决定高度/前后与参考节点。
	var record: Dictionary=objects[id]
	assert(record.holder=="player" and record.hand in ["Hand.L","Hand.R"])
	var offset: Vector3=record.player_offset
	offset.x=absf(offset.x)*(-1 if record.hand=="Hand.L" else 1)
	var frame: Node3D=player.get_node(record.player_frame)
	var pose:=frame.global_transform*Transform3D(Basis.IDENTITY,offset)
	if player.is_vr_active() and not record.xr_kind.is_empty():
		pose=player.vr.hands.transform_for(record.xr_kind,pose,player.vr)
	return pose

func observable_extra(id: String) -> Dictionary:
	var record: Dictionary=objects[id]
	var extra: Dictionary=record.extra.call() if record.extra.is_valid() else {}
	extra.merge({"name":record.body.get_meta("display_name",id),"graspable":true,"holder":record.holder,"hand":record.hand},true)
	return extra

func attach_to(id: String, person: String, hand: String, attachment: Callable) -> Dictionary:
	if not objects.has(id):return {"ok":false,"code":"unavailable"}
	var record: Dictionary=objects[id]
	if record.holder!="":return {"ok":false,"code":"already_held"}
	if held.has(person+"/"+hand):return {"ok":false,"code":"hand_occupied"}
	assert(attachment.is_valid())
	var body: RigidBody3D=record.body
	record.saved={"freeze":body.freeze,"layer":body.collision_layer,"mask":body.collision_mask}
	record.holder=person;record.hand=hand;record.attachment=attachment;record.attachment_frame="body"
	held[person+"/"+hand]=id
	body.freeze=true;body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
	body.collision_layer=0;body.collision_mask=0
	sync_held(id)
	return {"ok":true,"code":"attached","object":id}

func transfer_attachment(id: String, giver: String, recipient: String, hand: String, attachment: Callable) -> Dictionary:
	if not objects.has(id) or objects[id].holder!=giver:return {"ok":false,"code":"not_held"}
	if held.has(recipient+"/"+hand):return {"ok":false,"code":"hand_occupied"}
	assert(attachment.is_valid())
	var record: Dictionary=objects[id]
	held.erase(giver+"/"+str(record.hand))
	record.holder=recipient;record.hand=hand;record.attachment=attachment;record.attachment_frame="body"
	held[recipient+"/"+hand]=id
	sync_held(id)
	return {"ok":true,"code":"transferred","object":id}

func grip_position(id: String) -> Vector3:
	return objects[id].body.to_global(objects[id].grip)

const PICKUP_RANGE_M=preload("res://scripts/skills/interaction_range.gd").RADIUS_M

func carry_transform(id: String, actor: Node3D, hand: String) -> Transform3D:
	# 只用碰撞外框确定固定槽的前后间距，不求解骨骼或移动路径。
	var rear:=0.0
	for child in objects[id].body.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var bounds: AABB=child.shape.get_debug_mesh().get_aabb()
		for i in 8:rear=minf(rear,(child.transform*bounds.get_endpoint(i)).z-objects[id].grip.z)
	var actor_front:=0.0
	for child in actor.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var bounds: AABB=child.shape.get_debug_mesh().get_aabb()
		for i in 8:actor_front=maxf(actor_front,(child.transform*bounds.get_endpoint(i)).z)
	var forward:=maxf(.60,actor_front-rear+.08)
	var socket:=Transform3D(actor.global_basis,actor.to_global(Vector3(.42 if hand=="Hand.L" else -.42,.95,forward)))
	socket.origin-=socket.basis*objects[id].grip
	return socket

func grasp(id: String, person: String, hand: String, body_state: RefCounted) -> Dictionary:
	if hand not in ["Hand.L","Hand.R"]:return {"ok":false,"code":"invalid_hand"}
	if not objects.has(id):return {"ok":false,"code":"unavailable"}
	var record: Dictionary=objects[id]
	if record.holder!="":return {"ok":false,"code":"already_held"}
	if held.has(person+"/"+hand):return {"ok":false,"code":"hand_occupied"}
	var actor: CharacterBody3D=body_state.actor.body
	var at:=grip_position(id)
	var distance:=preload("res://scripts/skills/interaction_range.gd").distance(actor,at)
	if distance>PICKUP_RANGE_M:return {"ok":false,"code":"out_of_reach","distance_m":distance,"interaction_range_m":PICKUP_RANGE_M}
	var query:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*1.4,at,1,[actor.get_rid(),record.body.get_rid()])
	if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():return {"ok":false,"code":"occluded"}
	var offset: Transform3D=actor.global_transform.affine_inverse()*carry_transform(id,actor,hand)
	var result:=attach_to(id,person,hand,func():return actor.global_transform*offset)
	if result.ok:result.code="grasped"
	return result

func release(id: String, person: String) -> Dictionary:
	if not objects.has(id) or objects[id].holder!=person: return {"ok":false,"code":"not_held"}
	sync_held(id)
	# 禁碰持有物不能在穿入实体的状态下直接转为动态刚体，否则解穿透会弹飞双方。
	# 只报告当前实际重叠，保留持有关系；移动到何处仍由人物技能决定。
	var contacts: Array=release_contacts(id)
	if not contacts.is_empty():
		return {"ok":false,"code":"release_overlapping","object":id,"contacts":contact_kinds(contacts),"message":"持有物当前与实体重叠，尚未松手；先将物品移到无重叠位置再释放。"}
	_detach(id)
	return {"ok":true,"code":"released","object":id}

func _detach(id: String) -> void:
	var record: Dictionary=objects[id]
	var body: RigidBody3D=record.body
	held.erase(str(record.holder)+"/"+str(record.hand))
	# 先恢复碰撞过滤再回到动态模式。反序会使 Godot Physics 在禁碰状态
	# 建立接触对，恢复掩码后小物体仍可能穿过薄地形（固定动作回放可复现）。
	body.collision_layer=record.saved.layer;body.collision_mask=record.saved.mask
	body.freeze=record.saved.freeze;body.sleeping=false
	record.holder="";record.hand="";record.attachment=Callable()

static func contact_kinds(contacts: Array) -> Dictionary:
	var kinds: Dictionary={}
	for kind in contacts:kinds[str(kind)]=true
	return kinds

func release_contacts(id: String) -> Array:
	return pose_contacts(id,objects[id].body.global_transform)

func pose_contacts(id: String, at: Transform3D) -> Array:
	# 只查询指定刚体姿态；不移动实体，也不豁免持有者碰撞。
	var record: Dictionary=objects[id]
	var body: RigidBody3D=record.body
	var contacts: Array=[]
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape;query.transform=at*child.transform
		query.collision_mask=record.saved.mask;query.exclude=[body.get_rid()]
		# 零额外裕量，不把接近地面误作穿透，也不关闭与人物或环境的碰撞。
		query.margin=0.0
		for hit in body.get_world_3d().direct_space_state.intersect_shape(query):
			var collider: CollisionObject3D=hit.collider
			var kind: String="person" if collider is CharacterBody3D else ("movable_object" if collider is RigidBody3D else "environment")
			if kind not in contacts:contacts.append(kind)
	return contacts

func change_grip(id: String, person: String, hand: String, body_state: RefCounted) -> Dictionary:
	if hand not in ["Hand.L","Hand.R"]:return {"ok":false,"code":"invalid_hand"}
	if not objects.has(id) or objects[id].holder!=person:return {"ok":false,"code":"not_held"}
	var record: Dictionary=objects[id]
	if record.hand==hand:return {"ok":true,"code":"already_in_hand"}
	if held.has(person+"/"+hand):return {"ok":false,"code":"hand_occupied"}
	var actor: Node3D=body_state.actor.body
	var offset: Transform3D=actor.global_transform.affine_inverse()*carry_transform(id,actor,hand)
	var result:=transfer_attachment(id,person,person,hand,func():return actor.global_transform*offset)
	if result.ok:result.code="grip_changed"
	return result

func release_person(person: String) -> void:
	for id in objects:
		if objects[id].holder==person: release(id,person)

func _physics_process(_delta: float) -> void:
	for id in objects:
		var record: Dictionary=objects[id]
		if record.holder!="": sync_held(id)

func _exit_tree() -> void:
	for id in objects:
		if objects[id].holder!="": _detach(id)

func bottom(id: String) -> Vector3:
	var body: RigidBody3D=objects[id].body
	var low:=INF
	for child in body.get_children():
		if child is CollisionShape3D and not child.disabled:
			low=minf(low,shape_bottom_y(child))
	return Vector3(body.global_position.x,low,body.global_position.z)

func bottom_support_point(id: String) -> Vector3:
	var result:=Vector3(0,INF,0)
	for child in objects[id].body.get_children():
		if child is CollisionShape3D and not child.disabled:
			var point:=shape_bottom_point(child)
			if point.y<result.y:result=point
	assert(result.is_finite(),"物品没有可测量的底部")
	return result

static func shape_bottom_y(collision: CollisionShape3D) -> float:
	return shape_bottom_point(collision).y

static func shape_bottom_point(collision: CollisionShape3D) -> Vector3:
	# 支撑方向变换到碰撞形状局部空间；旋转包围盒角点不在圆形物体表面上。
	var transform: Transform3D=collision.global_transform
	var direction: Vector3=transform.basis.transposed()*Vector3.DOWN
	var shape: Shape3D=collision.shape
	var support:=Vector3.ZERO
	if shape is SphereShape3D:
		support=direction.normalized()*shape.radius
	elif shape is CapsuleShape3D:
		support=direction.normalized()*shape.radius
		support.y+=signf(direction.y)*maxf(0,shape.height*0.5-shape.radius)
	elif shape is CylinderShape3D:
		support=Vector3(direction.x,0,direction.z).normalized()*shape.radius
		support.y=signf(direction.y)*shape.height*0.5
	elif shape is BoxShape3D:
		support=Vector3(signf(direction.x),signf(direction.y),signf(direction.z))*shape.size*0.5
	else:
		# 其他形状使用实际调试网格顶点，不能再用包围盒替代形状。
		var mesh: ArrayMesh=shape.get_debug_mesh()
		var lowest:=Vector3(0,INF,0)
		for surface in mesh.get_surface_count():
			for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point:=transform*vertex
				if point.y<lowest.y:lowest=point
		assert(lowest.is_finite(),"碰撞形状没有可测量的表面")
		return lowest
	return transform*support

func sync_held(id: String) -> void:
	var record: Dictionary=objects[id]
	if record.holder!="":
		assert(record.attachment.is_valid(),"持有物必须具有固定连接")
		record.body.global_transform=record.attachment.call()
