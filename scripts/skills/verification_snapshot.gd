extends RefCounted
## 宿主专用隔离回放快照；不发给人物模型，不包含修改正式世界的接口。
static func vector(at: Vector3) -> Array: return [at.x,at.y,at.z]
static func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func units(items: Array) -> Array:
	var result: Array=[]
	for item in items:result.append({"material":item.get("material","food"),"origin":item.get("origin",{}).duplicate(true)})
	return result
static func transform(value: Transform3D) -> Array:
	return [vector(value.basis.x),vector(value.basis.y),vector(value.basis.z),vector(value.origin)]
static func restored_transform(value: Array) -> Transform3D:
	return Transform3D(Basis(point(value[0]),point(value[1]),point(value[2])),point(value[3]))
static func capture(sim: Node, person: String) -> Dictionary:
	var data:={"person_id":person,"clock":sim.store.memory.clock,"people":{},"objects":{},"containers":{},"hands":{},"observations":sim.store.memory.observations.duplicate(true),"records":sim.store.memory.records.duplicate(true)}
	var task: Dictionary=sim.store.working_tasks.get(person,{})
	if task.has("execution_origin"):data["host_execution_origin"]={"request_id":task.request.id,"transform":task.execution_origin.duplicate(true)}
	var player: Node3D=sim.scene.get_node("Player")
	data["player"]={"position":vector(player.global_position),"rotation":vector(player.rotation),"eyes_rotation":vector(player.get_node("Eyes").rotation)}
	for id in sim.actors:
		var actor: Dictionary=sim.actors[id]
		data.people[id]={"position":vector(actor.body.global_position),"rotation":vector(actor.body.rotation),"needs":sim.store.people[id].needs.duplicate(true),"pose":{}}
		var skeleton: Skeleton3D=actor.skeleton
		var body_state: RefCounted=actor.body.get_meta("body_state") if actor.body.has_meta("body_state") else null
		for index in skeleton.get_bone_count():
			var name:=skeleton.get_bone_name(index)
			var at: Transform3D=body_state.bone_global(name) if body_state!=null else skeleton.get_bone_global_pose(index)
			var parent:=skeleton.get_bone_parent(index)
			if parent>=0:
				var parent_at: Transform3D=body_state.bone_global(skeleton.get_bone_name(parent)) if body_state!=null else skeleton.get_bone_global_pose(parent)
				at=parent_at.affine_inverse()*at
			data.people[id].pose[name]=transform(at)
	for id in sim.world_objects.objects:
		var obj: Dictionary=sim.world_objects.objects[id]
		data.objects[id]={"position":vector(obj.body.global_position),"rotation":vector(obj.body.rotation),"holder":obj.holder,"hand":obj.hand,"grip":vector(obj.grip),"name":obj.body.get_meta("display_name",id),"linear_velocity":vector(obj.body.linear_velocity),"angular_velocity":vector(obj.body.angular_velocity)}
		if obj.holder!="" and obj.holder!="player":
			var actor: Dictionary=sim.actors[obj.holder]
			assert(obj.attachment.is_valid(),"简化回放只接受固定持有连接")
			data.objects[id]["attachment_frame"]=obj.attachment_frame
			data.objects[id]["local_offset"]=transform(actor.body.global_transform.affine_inverse()*obj.body.global_transform if obj.attachment_frame=="body" else obj.body.global_transform)
	for id in sim.content_interaction.containers:data.containers[id]=units(sim.content_interaction.containers[id].record.contents.items)
	for id in sim.gathering.hands:
		data.hands[id]=units([sim.gathering.hands[id]])[0]
		data.hands[id]["hand"]=sim.gathering.hands[id].get("hand","Hand.R")
	data["gathering"]={"elapsed":sim.gathering.elapsed,"regrow_seconds":sim.gathering.regrow_seconds,"harvested":sim.gathering.harvested,"regrown":sim.gathering.regrown}
	data["resources"]={}
	for id in sim.gathering.resources:
		var resource: Dictionary=sim.gathering.resources[id]
		data.resources[id]={"available":resource.available,"reserved":resource.reserved,"regrow_at":resource.regrow_at,"transform":transform(resource.mesh.global_transform),"collision_layer":resource.body.collision_layer}
	data["loose_food"]={}
	for id in sim.gathering.loose_food:
		var item: Dictionary=sim.gathering.loose_food[id]
		var shape: ConvexPolygonShape3D=item.body.get_child(0).shape
		var points: Array=[]
		for at in shape.points:points.append(vector(at))
		data.loose_food[id]={"transform":transform(item.body.global_transform),"visual_transform":transform(item.visual.transform),"points":points,"origin":item.origin.duplicate(true),"velocity":vector(item.body.linear_velocity),"angular_velocity":vector(item.body.angular_velocity)}
	data["counters"]={"eaten":sim.eaten,"drawn":sim.water.drawn,"consumed":sim.water.consumed,"spilled":sim.water.spilled,"player_thirst":sim.water.player_thirst}
	return data
static func restore(sim: Node, data: Dictionary) -> void:
	assert(data.has("resources") and data.has("gathering") and data.has("loose_food") and data.has("counters"),"验证快照缺少完整物资状态，必须重新捕获")
	var player: Node3D=sim.scene.get_node("Player")
	player.set_physics_process(false)
	player.global_position=point(data.player.position);player.rotation=point(data.player.rotation);player.get_node("Eyes").rotation=point(data.player.eyes_rotation)
	for id in data.people:
		sim.actors[id].body.global_position=point(data.people[id].position)
		sim.actors[id].body.rotation=point(data.people[id].rotation)
		sim.actors[id].body.velocity=Vector3.ZERO
		sim.store.people[id].needs=data.people[id].needs.duplicate(true)
		var actor: Dictionary=sim.actors[id]
		actor.animation.stop(true)
		var body_state=actor.body.get_meta("body_state") if actor.body.has_meta("body_state") else preload("res://scripts/skills/body_state.gd").new()
		if actor.body.has_meta("body_state"):actor.skeleton.reset_bone_poses()
		else:body_state.initialize(actor,id);actor.body.set_meta("body_state",body_state)
		assert(data.people[id].has("pose"),"验证快照缺少实际骨骼姿态，必须重新捕获")
		for name in data.people[id].pose:
			var index: int=actor.skeleton.find_bone(name)
			assert(index>=0,"验证骨架缺少快照骨骼")
			var local:=restored_transform(data.people[id].pose[name])
			actor.skeleton.set_bone_pose_position(index,local.origin)
			actor.skeleton.set_bone_pose_rotation(index,local.basis.orthonormalized().get_rotation_quaternion())
			actor.skeleton.set_bone_pose_scale(index,local.basis.get_scale())
	for id in data.objects:
		var saved: Dictionary=data.objects[id]
		if not sim.world_objects.objects.has(id):
			# 当前试验道具的几何由宿主保存；未知类型不能捏造近似碰撞。
			assert(false,"隔离场景不能重建物品："+id)
			return
		var obj: Dictionary=sim.world_objects.objects[id]
		if obj.holder!="":sim.world_objects._detach(id)
		obj.grip=point(saved.grip)
		obj.body.global_position=point(saved.position);obj.body.rotation=point(saved.rotation)
		obj.body.linear_velocity=Vector3.ZERO;obj.body.angular_velocity=Vector3.ZERO
		if saved.holder=="player":
			var held_transform: Transform3D=obj.body.global_transform
			sim.world_objects.attach_to(id,"player",saved.hand,func():return held_transform)
		elif saved.holder!="":
			assert(saved.get("attachment_frame") in ["body","world"],"快照不是简化连接，必须重新捕获")
			var actor: Node3D=sim.actors[saved.holder].body
			var offset:=restored_transform(saved.local_offset)
			var world_fixed: bool=saved.attachment_frame=="world"
			assert(sim.world_objects.attach_to(id,saved.holder,saved.hand,func():return offset if world_fixed else actor.global_transform*offset).ok)
			obj.attachment_frame=saved.attachment_frame

	for id in data.containers:
		assert(sim.content_interaction.containers.has(id),"验证世界缺少容器")
		var entry: Dictionary=sim.content_interaction.containers[id]
		for item in entry.record.contents.items:
			if is_instance_valid(item.get("visual")):item.visual.queue_free()
		entry.record.contents.clear()
		for item in data.containers[id]:assert(entry.record.contents.add(item.duplicate(true)).ok)
		if entry.changed.is_valid():entry.changed.call()
	for item in sim.gathering.hands.values():
		if is_instance_valid(item.get("visual")):item.visual.queue_free()
	sim.gathering.hands.clear()
	for id in data.hands:
		var item: Dictionary=data.hands[id].duplicate(true)
		item.visual=sim._fruit();sim.scene.add_child(item.visual);sim.gathering.hands[id]=item
	for field in ["elapsed","regrow_seconds","harvested","regrown"]:sim.gathering.set(field,data.gathering[field])
	for id in data.resources:
		assert(sim.gathering.resources.has(id),"验证世界缺少果实来源")
		var resource: Dictionary=sim.gathering.resources[id]
		var saved: Dictionary=data.resources[id]
		resource.available=saved.available;resource.reserved=saved.reserved;resource.regrow_at=saved.regrow_at
		resource.mesh.global_transform=restored_transform(saved.transform)
		resource.mesh.visible=saved.available;resource.body.collision_layer=int(saved.collision_layer)
	sim.store.memory.clock=data.clock;sim.perception.clock=data.clock
	# 快照记录已经属于此时刻；新场景的日序0不能触发快照前的日终整理并清空位置线索。
	sim.store.memory.consolidated_day=int(data.clock/float(sim.store.memory.policy.day_seconds))
	sim.perception.memories=data.observations.duplicate(true)
	sim.store.memory.observations=data.observations.duplicate(true)
	sim.store.memory.replace_records_owned(data.records.duplicate(true))
	for item in sim.gathering.loose_food.values():item.body.queue_free()
	sim.gathering.loose_food.clear()
	for id in data.loose_food:
		var saved: Dictionary=data.loose_food[id]
		var body:=RigidBody3D.new();body.mass=0.2;body.collision_layer=4;body.collision_mask=7;body.continuous_cd=true
		var points:=PackedVector3Array()
		for at in saved.points:points.append(point(at))
		var shape:=ConvexPolygonShape3D.new();shape.points=points
		var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
		sim.scene.add_child(body);body.global_transform=restored_transform(saved.transform)
		body.linear_velocity=point(saved.velocity);body.angular_velocity=point(saved.angular_velocity)
		var visual: MeshInstance3D=sim._fruit();body.add_child(visual);visual.transform=restored_transform(saved.visual_transform)
		sim.gathering.loose_food[id]={"body":body,"visual":visual,"origin":saved.origin.duplicate(true)}
	sim.eaten=int(data.counters.eaten)
	for field in ["drawn","consumed","spilled","player_thirst"]:sim.water.set(field,data.counters[field])
	for id in sim.actors:sim._sync(id)
static func evidence(sim: Node, person: String) -> Dictionary:
	var actor: Dictionary=sim.actors[person]
	var result:={"needs":sim.store.people[person].needs.duplicate(true),"position":vector(actor.body.global_position),"objects":{},"containers":{},"participants":{},"hand_unit":units([sim.gathering.hands[person]])[0] if sim.gathering.hands.has(person) else {}}
	for key in sim.perception.memories.get(person,{}):
		if not str(key).begins_with("person/"):continue
		var other: String=str(key).trim_prefix("person/")
		if other==person:continue
		var body: Node3D=sim.scene.get_node("Player") if other=="player" else sim.actors[other].body
		result.participants[other]={"position":vector(body.global_position)}
	for id in sim.world_objects.objects:
		var obj: Dictionary=sim.world_objects.objects[id]
		result.objects[id]={"position":vector(obj.body.global_position),"holder":obj.holder,"hand":obj.hand}
	for id in sim.content_interaction.containers:result.containers[id]=sim.content_interaction.containers[id].record.contents.describe()
	return result
