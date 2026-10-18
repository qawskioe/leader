extends RefCounted
## 仅独立回放使用；候选程序不能获得这些宿主操作。
static func apply(sim: Node, person: String, snapshot: Dictionary, conditions: Array, participants: Node=null) -> Dictionary:
	var spatial:=false
	for condition in conditions:
		if condition.kind in ["reference_distance","participant_distance","participant_occluded","restore_participant"]:spatial=true;break
	var was_processing: bool=participants!=null and participants.is_physics_processing()
	if spatial:
		if participants!=null:participants.set_physics_process(false)
		await _settle(sim)
	var result: Dictionary=await _apply(sim,person,snapshot,conditions,participants)
	if spatial and participants!=null:participants.set_physics_process(was_processing)
	return result

static func _settle(sim: Node) -> void:
	# 运动学碰撞体由物理步更新；只刷新Node变换不能保证查询得到新位置。
	await sim.get_tree().physics_frame
	await sim.get_tree().physics_frame

static func _apply(sim: Node, person: String, snapshot: Dictionary, conditions: Array, participants: Node) -> Dictionary:
	var preparation: Array=[]
	for condition in conditions:
		match condition.kind:
			"reference_distance":
				var reference: Dictionary=sim.perception.known(person,condition.reference)
				if reference.is_empty():return {"ok":false,"error":"隔离参考点不是本人已知对象","condition":condition.duplicate(true)}
				var anchor:=preload("res://scripts/skills/verification_snapshot.gd").point(reference.position)
				var original:=preload("res://scripts/skills/verification_snapshot.gd").point(snapshot.people[person].position)
				var direction:=Vector3(original.x-anchor.x,0,original.z-anchor.z)
				if direction.length()<.001:
					var yaw: float=snapshot.people[person].rotation[1]
					direction=Vector3(sin(yaw),0,cos(yaw))
				var body: CharacterBody3D=sim.scene.get_node("Player") if condition.person=="player" else sim.actors[condition.person].body
				var probe:=anchor+direction.normalized().rotated(Vector3.UP,deg_to_rad(float(condition.bearing_degrees)))*float(condition.distance_m)
				var standing: Variant=_standing_point(body,probe)
				if standing==null:return {"ok":false,"error":"指定参考方位没有真实支撑或身体净空","condition":condition.duplicate(true)}
				body.global_position=standing;body.velocity=Vector3.ZERO
				if condition.person==person:
					var facing:=Vector3(anchor.x-standing.x,0,anchor.z-standing.z)
					if facing.length()>.001:body.rotation.y=atan2(facing.x,facing.z)
				await _settle(sim)
				if participants!=null:participants.repositioned(condition.person)
				preparation.append({"operation":"reference_distance","person":condition.person,"reference":condition.reference,"position":[standing.x,standing.y,standing.z],"faces_reference":condition.person==person,"note":"仅隔离布置；受检本人朝向已知参考点，不证明目标当前存在、可见或双方已抵达"})
			"participant_handover_answer":
				if participants==null:return {"ok":false,"error":"隔离参与者接收控制器未创建"}
				participants.set_handover_answer(condition.person,condition.answer)
				preparation.append({"operation":"participant_handover_answer","person":condition.person,"answer":condition.answer,"note":"仅设置隔离接收判断，仍走真实递交结算，不是候选权限"})
			"participant_behavior":
				if participants==null:return {"ok":false,"error":"隔离参与者行为控制器未创建"}
				participants.set_behavior(condition.person,condition.behavior)
				preparation.append({"operation":"participant_behavior","person":condition.person,"behavior":condition.behavior,"note":"仅改变隔离测试参与者行为，不是候选权限"})
			"consume_to_quantity":
				var record: Dictionary=sim.content_interaction.containers[condition.object].record
				if record.holder!=person or record.contents.count<int(condition.quantity):return {"ok":false,"error":"隔离消耗前提不成立"}
				while record.contents.count>int(condition.quantity):
					var result: Dictionary=sim.life_world.consume_contents(person,condition.object)
					if not result.ok:return {"ok":false,"error":"隔离条件不能消耗该材料"}
					preparation.append({"operation":"consume_contents","object":condition.object,"result":result})
			"participant_distance","participant_occluded","restore_participant":
				var body: CharacterBody3D=sim.scene.get_node("Player") if condition.person=="player" else sim.actors[condition.person].body
				var original: Vector3=preload("res://scripts/skills/verification_snapshot.gd").point(snapshot.player.position if condition.person=="player" else snapshot.people[condition.person].position)
				var target:=original
				if condition.kind in ["participant_distance","participant_occluded"]:
					var origin: Vector3=sim.actors[person].body.global_position
					var direction:=Vector3(original.x-origin.x,0,original.z-origin.z)
					if direction.length()<.001:return {"ok":false,"error":"隔离参与者缺少距离方向"}
					# 距离条件只有水平距离，没有指定方位。按原方向优先找同距离的真实站立点。
					# 不能沿用旧高度把参与者埋进新地面，再把不能跟随误判成候选故障。
					var standing: Variant=null
					var angles: Array=[0,30,-30,60,-60,90,-90,120,-120,150,-150,180]
					if condition.kind=="participant_occluded":
						angles=[0]
						for angle in range(5,181,5):angles.append(angle);angles.append(-angle)
					# 只要求遮挡时由宿主寻找几何可实现的位置；指定距离则仍严格满足该距离。
					var distances: Array=[condition.distance_m] if condition.has("distance_m") else [1,2,3,4,5,6,7,8]
					for distance in distances:
						for degrees in angles:
							var probe:=origin+direction.normalized().rotated(Vector3.UP,deg_to_rad(float(degrees)))*float(distance)
							standing=_standing_point(body,probe)
							if standing==null:continue
							if condition.kind=="participant_occluded" and not _occluded(sim.actors[person].body,body,standing):standing=null;continue
							break
						if standing!=null:break
					if standing==null:return {"ok":false,"error":"隔离条件没有满足支撑、净空及所需遮挡的站立点","condition":condition.duplicate(true),"searched_distances_m":distances.duplicate()}
					target=standing
				body.global_position=target
				await _settle(sim)
				if participants!=null:participants.repositioned(condition.person)
				preparation.append({"operation":condition.kind,"person":condition.person,"position":[target.x,target.y,target.z],"note":"隔离位置条件；未移动正式游戏人物"})
			_:return {"ok":false,"error":"未知隔离条件"}
	return {"ok":true,"preparation":preparation}

static func _occluded(observer: CharacterBody3D, participant: CharacterBody3D, at: Vector3) -> bool:
	# 胸、头都被实际遮挡才成立；这里不检查朝向，转身不能改变遮挡前提。
	for height in preload("res://scripts/survival/perception.gd").PERSON_VISIBLE_HEIGHTS:
		var query:=PhysicsRayQueryParameters3D.create(observer.global_position+Vector3.UP*1.6,at+Vector3.UP*height,1,[observer.get_rid(),participant.get_rid()])
		if observer.get_world_3d().direct_space_state.intersect_ray(query).is_empty():return false
	return true

static func _ground(body: CharacterBody3D, at: Vector3) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at-Vector3.UP*3,1,[body.get_rid()])
	var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<preload("res://scripts/survival/ground_motion.gd").MIN_FLOOR_Y or not hit.collider is StaticBody3D:return {}
	return hit

static func _standing_point(body: CharacterBody3D, at: Vector3) -> Variant:
	var hit:=_ground(body,at)
	if hit.is_empty():return null
	var shapes: Array=[];var bottom:=INF
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		shapes.append(child)
		var bounds: AABB=(Transform3D(body.global_basis)*child.transform)*child.shape.get_debug_mesh().get_aabb()
		bottom=minf(bottom,bounds.position.y)
	assert(not shapes.is_empty(),"隔离参与者没有碰撞形状")
	var target: Vector3=hit.position+Vector3.UP*(0.04-bottom)
	for offset in [Vector3(.3,0,0),Vector3(-.3,0,0),Vector3(0,0,.3),Vector3(0,0,-.3)]:
		var support:=_ground(body,hit.position+offset)
		if support.is_empty() or absf(support.position.y-hit.position.y)>preload("res://scripts/survival/ground_motion.gd").STEP_HEIGHT:return null
	for shape in shapes:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape
		query.transform=Transform3D(body.global_basis,target)*shape.transform
		query.collision_mask=body.collision_mask;query.exclude=[body.get_rid()]
		if not body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return null
	return target
