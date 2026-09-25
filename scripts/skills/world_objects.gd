extends Node
## 世界拥有物体及持有关系；技能只能通过人物实际接触申请改变关系。
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
	objects[id]={"body":body,"grip":grip_local,"holder":"","hand":"","motor":null,"local_offset":Transform3D.IDENTITY,"saved":{},"attachment":Callable(),"kind":"interactable","extra":Callable()}

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
	record.holder=person;record.hand=hand;record.motor=null;record.attachment=attachment
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
	record.holder=recipient;record.hand=hand;record.motor=null;record.attachment=attachment
	held[recipient+"/"+hand]=id
	sync_held(id)
	return {"ok":true,"code":"transferred","object":id}

func grip_position(id: String) -> Vector3:
	return objects[id].body.to_global(objects[id].grip)

func hand_transform(motor: RefCounted, hand: String) -> Transform3D:
	var bone: Transform3D=motor.skeleton.global_transform*motor.skeleton.get_bone_global_pose(motor.skeleton.find_bone(hand))
	bone.origin=motor.point(hand)
	return bone

func grasp(id: String, person: String, hand: String, motor: RefCounted) -> Dictionary:
	if not objects.has(id): return {"ok":false,"code":"unavailable"}
	var record: Dictionary=objects[id]
	if record.holder!="": return {"ok":false,"code":"already_held"}
	var key:=person+"/"+hand
	if held.has(key): return {"ok":false,"code":"hand_occupied"}
	var distance: float=motor.point(hand).distance_to(grip_position(id))
	if distance>0.16: return {"ok":false,"code":"not_in_contact","distance_m":distance,"contact_limit_m":0.16}
	var body: RigidBody3D=record.body
	record.saved={"freeze":body.freeze,"layer":body.collision_layer,"mask":body.collision_mask}
	record.local_offset=hand_transform(motor,hand).affine_inverse()*body.global_transform
	record.holder=person;record.hand=hand;record.motor=motor;record.attachment=Callable();held[key]=id
	body.freeze=true;body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
	# 第一版持有连接关闭自身碰撞，释放恢复。不是完整手掌/持有物扫掠碰撞。
	body.collision_layer=0;body.collision_mask=0
	return {"ok":true,"code":"grasped","object":id}

func release(id: String, person: String) -> Dictionary:
	if not objects.has(id) or objects[id].holder!=person: return {"ok":false,"code":"not_held"}
	var record: Dictionary=objects[id]
	held.erase(person+"/"+str(record.hand))
	var body: RigidBody3D=record.body
	# 先恢复碰撞过滤再回到动态模式。反序会使 Godot Physics 在禁碰状态
	# 建立接触对，恢复掩码后小物体仍可能穿过薄地形（固定动作回放可复现）。
	body.collision_layer=record.saved.layer;body.collision_mask=record.saved.mask
	body.freeze=record.saved.freeze;body.sleeping=false
	record.holder="";record.hand="";record.motor=null;record.attachment=Callable()
	return {"ok":true,"code":"released","object":id}

func change_grip(id: String, person: String, hand: String, motor: RefCounted) -> Dictionary:
	if not objects.has(id) or objects[id].holder!=person:return {"ok":false,"code":"not_held"}
	var record: Dictionary=objects[id]
	if record.hand==hand:return {"ok":true,"code":"already_in_hand"}
	if held.has(person+"/"+hand):return {"ok":false,"code":"hand_occupied"}
	if motor.point(hand).distance_to(grip_position(id))>0.16:return {"ok":false,"code":"not_in_contact"}
	held.erase(person+"/"+str(record.hand));held[person+"/"+hand]=id
	record.hand=hand;record.motor=motor;record.attachment=Callable()
	record.local_offset=hand_transform(motor,hand).affine_inverse()*record.body.global_transform
	return {"ok":true,"code":"grip_changed"}

func release_person(person: String) -> void:
	for id in objects:
		if objects[id].holder==person: release(id,person)

func _physics_process(_delta: float) -> void:
	for id in objects:
		var record: Dictionary=objects[id]
		if record.holder!="": sync_held(id)

func _exit_tree() -> void:
	for id in objects:
		if objects[id].holder!="": release(id,objects[id].holder)

func bottom(id: String) -> Vector3:
	var body: RigidBody3D=objects[id].body
	var low:=INF
	for child in body.get_children():
		if child is CollisionShape3D and not child.disabled:
			low=minf(low,shape_bottom_y(child))
	return Vector3(body.global_position.x,low,body.global_position.z)

static func shape_bottom_y(collision: CollisionShape3D) -> float:
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
		var low:=INF
		for surface in mesh.get_surface_count():
			for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				low=minf(low,(transform*vertex).y)
		assert(is_finite(low),"碰撞形状没有可测量的表面")
		return low
	return (transform*support).y

func sync_held(id: String) -> void:
	var record: Dictionary=objects[id]
	if record.holder!="": record.body.global_transform=record.attachment.call() if record.attachment.is_valid() else hand_transform(record.motor,record.hand)*record.local_offset
