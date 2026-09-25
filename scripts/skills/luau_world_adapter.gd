extends "res://scripts/skills/world_adapter.gd"
## 角色权限绑定实例；Lua不能通过传入person_id选择另一个身体。
var objects: Node
var placement_targets: Dictionary={}
var observation_id:=""
var recalled_entries: Dictionary={}
var world_facts: Array=[]
var starting_frame: Transform3D
var grasp_planner: RefCounted
const Spatial=preload("res://scripts/skills/spatial_target.gd")

func acquire() -> Dictionary:
	var result: Dictionary=super.acquire()
	if result.ok:
		world_facts.clear();sim.life_world.fact.connect(_record_fact)
		if observation_id.is_empty(): observation_id=sim.space.capture(person_id).id
		starting_frame=sim.space.frames[observation_id].transform
	return result

func _record_fact(event: Dictionary) -> void:
	if event.person_id==person_id:world_facts.append(event.duplicate(true))

func _disconnect_facts() -> void:
	if sim.life_world.fact.is_connected(_record_fact):sim.life_world.fact.disconnect(_record_fact)

func finish() -> Dictionary:
	var result: Dictionary=await super.finish()
	_disconnect_facts()
	return result

func local_point(at: Vector3) -> Dictionary:
	return sim.space.local_point(person_id,observation_id,at)

func _visible_object(id: String) -> bool:
	if not objects.objects.has(id): return false
	if objects.objects[id].holder==person_id: return true
	if sim.perception.known(person_id,id).is_empty(): return false
	return sim.perception.sees(person_id,objects.grip_position(id),objects.objects[id].body.get_rid())

func request(operation: String, args: Dictionary) -> Dictionary:
	if not _owned: return _result(false,"cancelled")
	if args.has("person_id") or args.has("actor"): return _result(false,"actor_override_denied")
	match operation:
		"walk_options":
			var seen: Dictionary=await request("perceive",{})
			var body: CharacterBody3D=sim.actors[person_id].body
			var frame: Transform3D=sim.space.frames[seen.observation_id].transform
			for sample in seen.near.ground_samples:
				if sample.state!="visible_surface":continue
				var p: Dictionary=sample.position
				var target: Vector3=frame*Vector3(p.x,p.y,p.z)
				var parameters:=PhysicsTestMotionParameters3D.new()
				parameters.from=body.global_transform;parameters.from.origin+=Vector3.UP*0.04
				parameters.motion=target-body.global_position
				parameters.margin=0.005
				var collision:=PhysicsTestMotionResult3D.new()
				var hit:=PhysicsServer3D.body_test_motion(body.get_rid(),parameters,collision)
				var wall:=false
				if hit:
					for index in collision.get_collision_count():
						if collision.get_collision_normal(index).y<0.7:wall=true
				sample["path_clear"]=not wall
			seen["path_meaning"]="只预测当前身体到本次可见采样点的一段通行；不提供地图路线，动态物体仍可能在行动时改变。"
			return seen
		"consume_contents":
			if not args.get("object") is String:return _result(false,"invalid_arguments")
			return sim.life_world.consume_contents(person_id,args.object,motor)
		"change_grip":
			if not args.get("object") is String or args.get("hand") not in ["Hand.L","Hand.R"]:return _result(false,"invalid_arguments")
			if not sim.water.free_hand(person_id,args.hand):return _result(false,"hand_occupied")
			return objects.change_grip(args.object,person_id,args.hand,motor)
		"give_unit":
			if not args.get("recipient") is String:return _result(false,"invalid_arguments")
			return await sim.handover.give_unit(person_id,args.recipient)
		"perceive":
			sim.perception.observe(person_id)
			var seen: Dictionary=sim.space.capture(person_id)
			observation_id=seen.id
			var known: Dictionary={}
			for key in sim.store.memory.observations[person_id]:
				known[key]=sim.space.recalled_landmark(person_id,sim.store.memory.observations[person_id][key],observation_id)
			for key in recalled_entries:
				if not known.has(key):known[key]=sim.space.recalled_landmark(person_id,recalled_entries[key],observation_id)
			var unit: Dictionary=sim.life_world.held_unit(person_id)
			var current: Transform3D=starting_frame.affine_inverse()*sim.space.frames[observation_id].transform
			return {"ok":true,"odometry":{"meaning":"本次技能开始时本人脚底坐标系内的自身移动与朝向；不是世界坐标","position":sim.space.xyz(current.origin),"right":sim.space.xyz(current.basis.x),"forward":sim.space.xyz(current.basis.z)},"observation_id":observation_id,"near":seen.near_field,"known":known,"available_hands":{"Hand.L":sim.water.free_hand(person_id,"Hand.L"),"Hand.R":sim.water.free_hand(person_id,"Hand.R")},"held_unit":{} if unit.is_empty() else {"material":unit.get("material","food")},"needs":sim.store.people[person_id].needs.duplicate(true)}
		"recall_locations":
			if not args.get("kind") is String:return _result(false,"invalid_arguments")
			var recalled: Dictionary={}
			for record in sim.store.memory.retained(person_id,"landmark"):
				if record.get("kind")!=args.kind:continue
				var answer: Dictionary=sim.store.memory.recall(person_id,{"kind":"landmark","keywords":[str(record.id)],"limit":1})
				if answer.ok:
					recalled[record.id]=sim.space.recalled_landmark(person_id,record,observation_id)
					recalled_entries[record.id]=record.duplicate(true)
				if recalled.size()>=4:break
			return {"ok":true,"locations":recalled}
		"contact_point":
			if not args.get("source") is String:return _result(false,"invalid_arguments")
			var contact: Dictionary=sim.life_world.contact_point(person_id,args.source)
			if contact.ok: contact.position={"observation_id":observation_id,"position":local_point(contact.position)}
			return contact
		"plan_grasp":
			if not args.get("object") is String or args.get("hand") not in ["Hand.L","Hand.R"] or not args.get("exclude_current",false) is bool:return _result(false,"invalid_arguments")
			if not _visible_object(args.object):return _result(false,"not_observed")
			if objects.objects[args.object].holder!="":return _result(false,"already_held")
			if not sim.water.free_hand(person_id,args.hand):return _result(false,"hand_occupied")
			if grasp_planner==null:
				grasp_planner=preload("res://scripts/skills/grasp_planner.gd").new();grasp_planner.initialize(self)
			var seen: Dictionary=await request("perceive",{})
			return await grasp_planner.plan(args.object,args.hand,seen,args.get("exclude_current",false))
		"reach_with_body":
			return await reach_with_body(args)
		"reach_point":
			return await reach_point(args)
		"body_point":
			if not args.get("point") is String or (args.point!="mouth" and motor.skeleton.find_bone(args.point)<0):return _result(false,"invalid_body_point")
			return {"ok":true,"target":{"observation_id":observation_id,"position":local_point(motor.drinking_target() if args.point=="mouth" else motor.point(args.point))}}
		"take_unit":
			if not args.get("source") is String:return _result(false,"invalid_arguments")
			return sim.life_world.take_unit(person_id,args.source,motor)
		"put_unit":
			if not args.get("target") is String:return _result(false,"invalid_arguments")
			return sim.life_world.put_unit(person_id,args.target,motor)
		"consume_unit": return sim.life_world.consume_unit(person_id,motor)
		"fill_container":
			if not args.get("source") is String or not args.get("target") is String:return _result(false,"invalid_arguments")
			return sim.life_world.fill_container(person_id,args.source,args.target)
		"inspect_contents":
			if not args.get("object") is String: return _result(false,"invalid_arguments")
			var inspected: Dictionary=sim.content_interaction.inspect(person_id,args.object)
			if inspected.ok:
				inspected["opening"]={"observation_id":observation_id,"position":local_point(sim.content_interaction.opening_position(args.object))}
			return inspected
		"transfer_contents":
			if not args.get("source") is String or not args.get("target") is String: return _result(false,"invalid_arguments")
			var quantity: Variant=args.get("quantity")
			if not (quantity is int or quantity is float) or not is_finite(quantity) or quantity<1 or quantity>1000 or floorf(quantity)!=quantity: return _result(false,"invalid_quantity")
			return sim.content_interaction.transfer(person_id,args.source,args.target,int(quantity))
		"handover":
			if not args.get("object") is String or not args.get("recipient") is String:return _result(false,"invalid_arguments")
			return await sim.handover.give(person_id,args.object,args.recipient)
		"look_toward": return await look_toward(args.get("target"))
		"surface": return resolve_surface(args.get("target",""))
		"move_held": return await move_held(args)
		"check_placement":
			if not args.get("object") is String or (not args.get("target") is Dictionary or not Spatial.valid(args.target)): return _result(false,"invalid_arguments")
			# 查询结果不要求先执行放置；surface返回的校正坐标也必须能重新验证。
			if not placement_targets.has(Spatial.key(args.target)):
				var support:=resolve_surface(args.target)
				if not support.ok:return support
			for frame in 45:
				await get_tree().physics_frame
				if not _owned: return _result(false,"cancelled")
			return placement_result(args.object,args.target)
		"pose":
			if not args.has("pose") or not args.has("seconds"): return _result(false,"invalid_arguments")
			return await operate("pose",[args.pose,args.seconds])
		"inspect_body": return await operate("inspect_body",[])
		"pose_bones":
			if not args.has("pose") or not args.has("seconds"): return _result(false,"invalid_arguments")
			return await operate("pose_bones",[args.pose,args.seconds])
		"relax":
			if not args.has("seconds"): return _result(false,"invalid_arguments")
			return await operate("relax",[args.seconds])
		"approach":
			return await approach_segment(args)

		"observe","grasp","release","reach":
			var id: Variant=args.get("object")
			if not id is String: return _result(false,"invalid_arguments","object必须是本人已知的物品ID")
			if not objects.objects.has(id):
				if sim.perception.known(person_id,id).is_empty(): return _result(false,"not_observed","本人没有这件物品的观察或记忆")
				return _result(false,"unsupported_interaction","这件已知物品尚未接入身体抓握交互，不能用此技能观察抓取点、伸手抓握或释放；不是物品消失，也不是再找一次就能解决。请核对已有行为目录，或报告缺少该交互能力。")
			if operation=="release":
				var released: Dictionary=objects.release(id,person_id)
				sim.perception.observe(person_id)
				if released.ok:
					var record: Dictionary=objects.objects[id]
					sim.perception._record(person_id,id,record.kind,objects.grip_position(id),true,objects.observable_extra(id))
					var memory: Dictionary=sim.perception.memories[person_id][id]
					memory.source="本人刚刚松手，位置为松手时所知"
					memory.visible_now=_visible_object(id)
				return released
			if not _visible_object(id): return _result(false,"not_observed")
			if operation=="observe": return {"ok":true,"observation_id":observation_id,"object":id,"grip_position":local_point(objects.grip_position(id)),"body_position":local_point(objects.objects[id].body.global_position),"bottom_position":local_point(objects.bottom(id)),"speed_mps":objects.objects[id].body.linear_velocity.length(),"reference_meaning":"grip_position是手接触点；bottom_position是物体底部参考点，落稳检查以其水平位置和真实最低高度为准，二者不等同。","held":objects.objects[id].holder!="","held_by_self":objects.objects[id].holder==person_id,"hand":objects.objects[id].hand,"nearest_free_hand":_nearest_free_hand(id),"nearest_hand":"Hand.R" if motor.point("Hand.R").distance_squared_to(objects.grip_position(id))<=motor.point("Hand.L").distance_squared_to(objects.grip_position(id)) else "Hand.L"}
			var hand: Variant=args.get("hand","Hand.R")
			if hand not in ["Hand.L","Hand.R"]: return _result(false,"invalid_hand")
			if operation=="grasp":
				if not sim.water.free_hand(person_id,hand): return _result(false,"hands_occupied")
				var grasped: Dictionary=objects.grasp(id,person_id,hand,motor)
				sim.perception.observe(person_id)
				return grasped
			if not BodyMotor.seconds(args.get("seconds")): return _result(false,"invalid_duration")
			motor.start()
			var origin: Vector3=motor.point(hand)
			var elapsed:=0.0
			while elapsed<float(args.seconds):
				await get_tree().process_frame
				if not _owned: return _result(false,"cancelled")
				if not sim.enabled: continue
				if not _visible_object(id): return _result(false,"target_lost")
				elapsed+=get_process_delta_time()
				motor.reach(hand,origin.lerp(objects.grip_position(id),smoothstep(0,1,minf(1,elapsed/float(args.seconds)))),true)
			var distance: float=motor.point(hand).distance_to(objects.grip_position(id))
			return {"ok":distance<=0.16,"code":"reach_finished","message":"手已接近抓取点" if distance<=0.16 else "原地伸手后仍未接触物品，手距抓取点%.2f米（接触要求不超过0.16米）。本次伸手没有移动脚步；请结合本人相对坐标判断需要走近、转身还是调整姿势。"%distance,"distance_m":distance,"contact_limit_m":0.16,"observation_id":observation_id,"hand":local_point(motor.point(hand)),"target":local_point(objects.grip_position(id))}
	return _result(false,"unsupported_operation")

func cancel() -> void:
	_disconnect_facts()
	sim.handover.cancel_giver(person_id)
	if is_instance_valid(objects): objects.release_person(person_id)
	super.cancel()

func _nearest_free_hand(id: String) -> String:
	var best:=""
	var distance:=INF
	for hand in ["Hand.L","Hand.R"]:
		if not sim.water.free_hand(person_id,hand):continue
		var value: float=motor.point(hand).distance_squared_to(objects.grip_position(id))
		if value<distance:distance=value;best=hand
	return best

func reach_with_body(args: Dictionary) -> Dictionary:
	if not args.get("object") is String or args.get("hand") not in ["Hand.L","Hand.R"] or not BodyMotor.seconds(args.get("seconds")):return _result(false,"invalid_arguments")
	var id: String=args.object;var hand: String=args.hand
	if not _visible_object(id):return _result(false,"not_observed")
	if objects.objects[id].holder!="":return _result(false,"already_held")
	if not sim.water.free_hand(person_id,hand):return _result(false,"hand_occupied")
	motor.begin_target_reach(self,hand)
	var elapsed:=0.0
	while elapsed<float(args.seconds):
		if not _owned:return _result(false,"cancelled")
		if not _visible_object(id) or objects.objects[id].holder!="":
			motor.stop_target_rig();return _result(false,"target_changed")
		motor.target_rig.set_process(sim.enabled)
		motor.target_contact(hand,objects.grip_position(id))
		await get_tree().process_frame
		if sim.enabled:elapsed+=get_process_delta_time()
	if not _owned:return _result(false,"cancelled")
	var distance: float=motor.point(hand).distance_to(objects.grip_position(id))
	var diagnostics: Dictionary=motor.target_rig.sample.get(hand,{}).duplicate(true)
	diagnostics.erase("root");diagnostics.erase("joint");diagnostics.erase("end");diagnostics.erase("lengths")
	motor.stop_target_rig()
	return {"body_diagnostics":diagnostics,"ok":distance<=0.06,"code":"body_reached" if distance<=0.06 else "body_out_of_reach","distance_m":distance,"contact_limit_m":0.06,"message":"身体已配合接触目标" if distance<=0.06 else "本次站位的身体活动范围不足，拿取程序可调整站位后重试"}

func reach_point(args: Dictionary) -> Dictionary:
	if args.get("hand") not in ["Hand.R","Hand.L"] or not BodyMotor.seconds(args.get("seconds")):return _result(false,"invalid_arguments")
	var resolved: Dictionary=sim.space.resolve(person_id,args.get("target"))
	if not resolved.ok:return resolved
	if sim.actors[person_id].body.global_position.distance_to(resolved.position)>2.5:return _result(false,"out_of_reach")
	var start: Vector3=motor.point(args.hand)
	var elapsed:=0.0
	motor.start()
	while elapsed<float(args.seconds):
		await get_tree().physics_frame
		if not _owned:return _result(false,"cancelled")
		if not sim.enabled:continue
		elapsed+=get_physics_process_delta_time()
		motor.reach(args.hand,start.lerp(resolved.position,minf(1,elapsed/float(args.seconds))),true)
	var distance: float=motor.point(args.hand).distance_to(resolved.position)
	return {"ok":distance<=0.20,"code":"reached" if distance<=0.20 else "hand_not_in_contact","distance_m":distance}

func resolve_surface(target: Variant) -> Dictionary:
	if not target is Dictionary or not Spatial.valid(target): return _result(false,"invalid_target")
	var key: String=Spatial.key(target)
	var resolved: Dictionary=sim.space.resolve(person_id,target)
	if not resolved.ok: return resolved
	var at: Vector3=placement_targets.get(key,resolved.position)
	var exclude: Array[RID]=[sim.actors[person_id].body.get_rid()]
	for object in objects.objects.values():
		if object.holder==person_id: exclude.append(object.body.get_rid())
	var hit: Dictionary=sim.scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.15,at-Vector3.UP*0.15,1,exclude))
	if hit.is_empty() or hit.normal.y<0.8: return {"ok":false,"code":"no_support","message":"仅指定坐标上下0.15米未找到平缓支撑面，不代表周围或整个区域没有地面；请根据新观察中的可见地面高度重新选择。","target":target.duplicate(true),"scope":"selected_point_only","vertical_tolerance_m":0.15}
	if not sim.perception.sees(person_id,hit.position+Vector3.UP*0.03): return _result(false,"target_not_visible")
	placement_targets[key]=hit.position
	var corrected:={"observation_id":target.observation_id,"position":sim.space.local_point(person_id,target.observation_id,hit.position)}
	# 原请求点与接口返回的实际表面点指向同一份已验证证据。
	placement_targets[Spatial.key(corrected)]=hit.position
	return {"ok":true,"observation_id":target.observation_id,"position":corrected.position,"distance":Vector2(hit.position.x-sim.actors[person_id].body.global_position.x,hit.position.z-sim.actors[person_id].body.global_position.z).length()}

func look_toward(target: Variant) -> Dictionary:
	var resolved: Dictionary=sim.space.resolve(person_id,target)
	if not resolved.ok: return resolved
	var body: CharacterBody3D=sim.actors[person_id].body
	var direction: Vector3=resolved.position-body.global_position
	direction.y=0
	if direction.length()<0.05: return _result(false,"direction_too_close")
	var origin:=body.rotation.y
	var heading:=atan2(direction.x,direction.z)
	if absf(angle_difference(origin,heading))<deg_to_rad(2):return _result(true,"already_facing")
	var elapsed:=0.0
	# 仅朝角色给出的记忆/观察坐标转身，不按物品ID追踪真实位置。
	while elapsed<0.6:
		await get_tree().physics_frame
		if not _owned: return _result(false,"cancelled")
		if not sim.enabled: continue
		elapsed+=get_physics_process_delta_time()
		body.rotation.y=lerp_angle(origin,heading,minf(elapsed/0.6,1.0))
	sim.perception.observe(person_id)
	return _result(true,"looked_toward")

func approach_segment(args: Dictionary) -> Dictionary:
	var value: Variant=args.get("object")
	if not value is Dictionary or not Spatial.valid(value): return _result(false,"invalid_target")
	var distance: Variant=args.get("distance",0.45)
	if not (distance is float or distance is int) or not is_finite(distance) or distance<0 or distance>2: return _result(false,"invalid_distance")
	var surface:=resolve_surface(value)
	if not surface.ok: return surface
	var target: Vector3=placement_targets[Spatial.key(value)]
	var actor: Dictionary=sim.actors[person_id]
	var body: CharacterBody3D=actor.body
	var direction:=Vector3(target.x-body.global_position.x,0,target.z-body.global_position.z)
	if direction.length()<=float(distance): return _segment_feedback(_result(true,"arrived"),value,target,body)
	# 一段直行是运动执行；不查询全地图、不替人物选择绕行点。
	var destination:=target-direction.normalized()*float(distance)
	actor.stage="skill_moving";actor.path=PackedVector3Array([destination]);actor.step=0;actor.elapsed=0.0;actor.stalled=0.0
	actor.walk_limit=direction.length()/maxf(sim.move_speed,0.1)+5.0
	_motion={};sim._animation(actor,"Walk")
	var deadline:=Time.get_ticks_msec()+int(actor.walk_limit*1000)+1000
	while _owned and _motion.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
	if not _owned: return _result(false,"cancelled")
	if _motion.is_empty(): sim._finish_skill_motion(person_id,false,"选定的一段移动未能完成，请重新观察并选择下一段")
	return _segment_feedback(_motion,value,target,body)

func _segment_feedback(outcome: Dictionary, selected: Dictionary, target: Vector3, body: Node3D) -> Dictionary:
	var result:=outcome.duplicate(true)
	result["scope"]="selected_ground_point_only"
	result["selected_target"]=selected.duplicate(true)
	result["standing_position"]={"observation_id":selected.observation_id,"position":sim.space.local_point(person_id,selected.observation_id,body.global_position)}
	result["distance_to_selected_point_m"]=Vector2(body.global_position.x-target.x,body.global_position.z-target.z).length()
	# Luau输出合同使用字符串键对象，不能把非空数组直接原样返回。
	result["touch_contacts"]={}
	var frame: Transform3D=sim.space.frames[selected.observation_id].transform
	for contact in result.get("world_contacts",[]):
		result.touch_contacts["contact_%d"%(result.touch_contacts.size()+1)]={"position":sim.space.local_point(person_id,selected.observation_id,contact.position),"normal":sim.space.xyz(frame.basis.inverse()*contact.normal)}
	result.erase("world_contacts")
	if not result.touch_contacts.is_empty(): result["contact_meaning"]="本次移动实际碰到的阻挡面，位置与法线使用selected_target同一观察坐标系；法线朝向阻挡面外侧，不代表该方向整条路都可通行。"
	if result.ok: result["message"]="仅到达本次选择的地面点附近；不证明已经到达原任务中的人物或物品旁边，需要重新观察确认"
	return result

func placement_result(id: String, target: Variant) -> Dictionary:
	if not target is Dictionary or not Spatial.valid(target) or not objects.objects.has(id) or not placement_targets.has(Spatial.key(target)): return _result(false,"placement_not_attempted")
	var record: Dictionary=objects.objects[id]
	var at: Vector3=placement_targets[Spatial.key(target)]
	var bottom: Vector3=objects.bottom(id)
	var horizontal:=Vector2(bottom.x-at.x,bottom.z-at.z).length()
	var hit: Dictionary=sim.scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(bottom+Vector3.UP*0.08,bottom-Vector3.UP*0.05,1,[record.body.get_rid(),sim.actors[person_id].body.get_rid()]))
	var ok: bool=record.holder=="" and not record.body.freeze and horizontal<=0.12 and absf(bottom.y-at.y)<0.06 and not hit.is_empty() and hit.normal.y>0.8 and record.body.linear_velocity.length()<0.15
	return {"ok":ok,"code":"placed" if ok else "not_at_destination","horizontal_error":horizontal,"height_error":bottom.y-at.y,"supported":not hit.is_empty(),"speed":record.body.linear_velocity.length()}

func move_held(args: Dictionary) -> Dictionary:
	if not args.get("object") is String or (not args.get("target") is Dictionary or not Spatial.valid(args.target)) or not BodyMotor.seconds(args.get("seconds")): return _result(false,"invalid_arguments")
	var id: String=args.object
	if not objects.objects.has(id) or objects.objects[id].holder!=person_id: return _result(false,"not_held")
	var target: Dictionary=resolve_surface(args.target)
	if not target.ok: return target
	var at: Vector3=placement_targets[Spatial.key(args.target)]
	if sim.actors[person_id].body.global_position.distance_to(at)>1.4: return _result(false,"out_of_reach")
	var record: Dictionary=objects.objects[id]
	var hand: String=record.hand
	motor.start()
	var origin: Vector3=objects.bottom(id)
	var elapsed:=0.0
	while elapsed<float(args.seconds):
		await get_tree().physics_frame
		if not _owned: return _result(false,"cancelled")
		if not sim.enabled: continue
		elapsed+=get_physics_process_delta_time()
		objects.sync_held(id)
		var before: Transform3D=record.body.global_transform
		# 在物体底部的同一参照空间规划轨迹，再反馈到手；不能把动态手目标与初始手位置混合插值。
		var desired_bottom: Vector3=origin.lerp(at+Vector3.UP*0.015,minf(1,elapsed/float(args.seconds)))
		var desired: Vector3=motor.point(hand)+(desired_bottom-objects.bottom(id))
		motor.reach(hand,desired,false)
		objects.sync_held(id)
		var motion: Vector3=record.body.global_position-before.origin
		for child in record.body.get_children():
			if child is CollisionShape3D and not child.disabled and motion.length()>0.0001:
				var query:=PhysicsShapeQueryParameters3D.new();query.shape=child.shape;query.transform=before*child.transform;query.motion=motion;query.collision_mask=1;query.exclude=[record.body.get_rid(),sim.actors[person_id].body.get_rid()];query.margin=0.001
				var fractions: PackedFloat32Array=sim.scene.get_world_3d().direct_space_state.cast_motion(query)
				if fractions[0]<0.99:
					# 不能穿越障碍；保留最后有效物体位置并终止此动作。
					record.body.global_transform=before
					record.local_offset=objects.hand_transform(record.motor,hand).affine_inverse()*before
					return {"ok":false,"code":"path_blocked","operation":"move_held","scope":"held_object_motion","message":"人物已接近目标，但手持物体的移动轨迹遇到碰撞；这不是人物走路受阻，也不能据此断言目标地面不可用。"}
	return {"ok":objects.bottom(id).distance_to(at+Vector3.UP*0.015)<0.045,"code":"moved_to_surface","observation_id":observation_id,"bottom":local_point(objects.bottom(id)),"target":local_point(at),"hand":local_point(motor.point(hand))}
