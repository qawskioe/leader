extends "res://scripts/skills/world_adapter.gd"
## 角色权限绑定实例；Lua不能通过传入person_id选择另一个身体。
var objects: Node
var placement_targets: Dictionary={}
var observation_id:=""
var _frame_leases: Dictionary={}
var recalled_entries: Dictionary={}
var world_facts: Array=[]
var starting_frame: Transform3D
const Spatial=preload("res://scripts/skills/spatial_target.gd")

func retain_observation(token: String) -> void:
	if _frame_leases.has(token):return
	assert(sim.space.retain_frame(person_id,token),"技能只能保留本人已有的观察")
	_frame_leases[token]=true

func _exit_tree() -> void:
	if not is_instance_valid(sim):return
	for token in _frame_leases:sim.space.release_frame(token)
	_frame_leases.clear()

func acquire() -> Dictionary:
	var result: Dictionary=super.acquire()
	if result.ok:
		world_facts.clear();sim.life_world.fact.connect(_record_fact)
		if observation_id.is_empty(): observation_id=sim.space.capture(person_id).id
		retain_observation(observation_id)
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
	if operation not in preload("res://scripts/skills/luau_contract.gd").OPERATIONS:return _result(false,"unsupported_operation")
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
				sample["path_blocker"]="body" if wall else ""
			seen["path_meaning"]="仅检查本人身体直达可见采样点的路径；固定携带不做逐帧外形绕障。受阻不代表其他路线不存在。"
			return seen
		"consume_contents":
			if not args.get("object") is String:return _result(false,"invalid_arguments")
			if not await _life_action_time(1.0):return _result(false,"cancelled")
			return sim.life_world.consume_contents(person_id,args.object)
		"change_grip":
			if not args.get("object") is String or args.get("hand") not in ["Hand.L","Hand.R"]:return _result(false,"invalid_arguments")
			if not sim.water.free_hand(person_id,args.hand):return _result(false,"hand_occupied")
			return objects.change_grip(args.object,person_id,args.hand,body_state)
		"give_unit":
			if not args.get("recipient") is String:return _result(false,"invalid_arguments")
			return await sim.handover.give_unit(person_id,args.recipient)
		"perceive":
			sim.perception.observe(person_id)
			var seen: Dictionary=sim.space.capture(person_id)
			observation_id=seen.id
			retain_observation(observation_id)
			var known: Dictionary={}
			for key in sim.store.memory.observations[person_id]:
				known[key]=sim.space.recalled_landmark(person_id,sim.store.memory.observations[person_id][key],observation_id)
			for key in recalled_entries:
				if not known.has(key):known[key]=sim.space.recalled_landmark(person_id,recalled_entries[key],observation_id)
			var unit: Dictionary=sim.life_world.held_unit(person_id)
			var current: Transform3D=starting_frame.affine_inverse()*sim.space.frames[observation_id].transform
			return {"ok":true,"odometry":{"meaning":"本次技能开始时本人脚底坐标系内的自身移动与朝向；不是世界坐标","position":sim.space.xyz(current.origin),"right":sim.space.xyz(current.basis.x),"forward":sim.space.xyz(current.basis.z)},"observation_id":observation_id,"near":seen.near_field,"known":known,"available_hands":{"Hand.L":sim.water.free_hand(person_id,"Hand.L"),"Hand.R":sim.water.free_hand(person_id,"Hand.R")},"held_unit":{} if unit.is_empty() else {"material":unit.get("material","food"),"hand":unit.get("hand","Hand.R")},"needs":sim.store.people[person_id].needs.duplicate(true)}
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
		"access_source":
			if not args.get("source") is String:return _result(false,"invalid_arguments")
			return sim.life_world.access_source(person_id,args.source)
		"take_unit":
			if not args.get("source") is String:return _result(false,"invalid_arguments")
			if not await _life_action_time(0.3):return _result(false,"cancelled")
			return sim.life_world.take_unit(person_id,args.source)
		"put_unit":
			if not args.get("target") is String:return _result(false,"invalid_arguments")
			if not await _life_action_time(0.3):return _result(false,"cancelled")
			return sim.life_world.put_unit(person_id,args.target)
		"consume_unit":
			if not await _life_action_time(1.0):return _result(false,"cancelled")
			return sim.life_world.consume_unit(person_id)
		"fill_container":
			if not args.get("source") is String or not args.get("target") is String:return _result(false,"invalid_arguments")
			if not await _life_action_time(1.0):return _result(false,"cancelled")
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
		"check_settled": return await check_settled(args)
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
		"approach":
			return await approach_segment(args)

		"observe","grasp","release":
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
					released["release_location"]=sim.space.release_location(id,objects.grip_position(id),sim.space.frames[observation_id].transform,observation_id,sim.perception.memories[person_id],sim.space.near_range_m)
				return released
			if not _visible_object(id): return _result(false,"not_observed")
			if operation=="observe": return {"ok":true,"observation_id":observation_id,"object":id,"grip_position":local_point(objects.grip_position(id)),"body_position":local_point(objects.objects[id].body.global_position),"bottom_position":local_point(objects.bottom(id)),"speed_mps":objects.objects[id].body.linear_velocity.length(),"reference_meaning":"grip_position是手接触点；bottom_position是物体底部参考点，落稳检查以其水平位置和真实最低高度为准，二者不等同。","held":objects.objects[id].holder!="","held_by_self":objects.objects[id].holder==person_id,"hand":objects.objects[id].hand,"nearest_free_hand":_nearest_free_hand(id),"nearest_hand":"Hand.R" if body_state.point("Hand.R").distance_squared_to(objects.grip_position(id))<=body_state.point("Hand.L").distance_squared_to(objects.grip_position(id)) else "Hand.L"}
			var hand: Variant=args.get("hand","Hand.R")
			if hand not in ["Hand.L","Hand.R"]: return _result(false,"invalid_hand")
			if operation=="grasp":
				if not sim.water.free_hand(person_id,hand): return _result(false,"hands_occupied")
				var grasped: Dictionary=objects.grasp(id,person_id,hand,body_state)
				sim.perception.observe(person_id)
				return grasped
	return _result(false,"unsupported_operation")

func cancel() -> void:
	_disconnect_facts()
	sim.handover.cancel_giver(person_id)
	# 停止执行权和未完成交接；已持有物保持原归属，松手必须通过明确的世界操作。
	super.cancel()

func _nearest_free_hand(id: String) -> String:
	var best:=""
	var distance:=INF
	for hand in ["Hand.L","Hand.R"]:
		if not sim.water.free_hand(person_id,hand):continue
		var value: float=body_state.point(hand).distance_squared_to(objects.grip_position(id))
		if value<distance:distance=value;best=hand
	return best

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
	# 远处记忆可以用来转身；它不授权向远处直接行走或操作物品。
	var resolved: Dictionary=sim.space.resolve(person_id,target,INF)
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

func approach_segment(args: Dictionary, keep_heading: bool=false) -> Dictionary:
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
	actor["keep_motion_heading"]=keep_heading
	_motion={};sim._animation(actor,"Walk")
	var deadline:=Time.get_ticks_msec()+int(actor.walk_limit*1000)+1000
	while _owned and _motion.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
	if not _owned: return _result(false,"cancelled")
	if _motion.is_empty(): sim._finish_skill_motion(person_id,false,"选定的一段移动未能完成，请重新观察并选择下一段")
	if keep_heading and _motion.get("ok",false):
		# 局部接触规划按双脚落稳计算，不能在Walk→Idle混合未结束时锁住抬起的脚。
		var settled:=0.0
		while settled<sim.MOTION_STOP_BLEND_SECONDS:
			await get_tree().process_frame
			if not _owned:return _result(false,"cancelled")
			if sim.enabled:settled+=get_process_delta_time()
		await get_tree().process_frame
		if not _owned:return _result(false,"cancelled")
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

func check_settled(args: Dictionary) -> Dictionary:
	if not args.get("object") is String or args.has("target"):return _result(false,"invalid_arguments")
	var id: String=args.object
	if not _visible_object(id):return _result(false,"not_observed")
	var record: Dictionary=objects.objects[id]
	var body: RigidBody3D=record.body
	var elapsed:=0.0
	var stable:=0.0
	var anchor:=body.global_position
	var last: Dictionary={}
	while elapsed<2.0:
		await get_tree().physics_frame
		if not _owned:return _result(false,"cancelled")
		if not sim.enabled:continue
		if not _visible_object(id):return _result(false,"target_lost")
		var delta:=get_physics_process_delta_time();elapsed+=delta
		if record.holder!="":return _result(false,"still_held")
		if body.freeze:return _result(false,"immobilized","固定物体不能据此确认自然落稳")
		# 仅确认可见物体的局部支撑，不公开被它遮住的支撑面坐标。
		# 几何最低点采样是保守检查；没有命中不等于任何部位都没有支撑。
		var bottom: Vector3=objects.bottom_support_point(id)
		var hit: Dictionary=body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(bottom+Vector3.UP*.08,bottom-Vector3.UP*.03,body.collision_mask,[body.get_rid()]))
		var supported: bool=not hit.is_empty() and hit.normal.y>.8 and absf(bottom.y-hit.position.y)<=.02
		var quiet: bool=body.linear_velocity.length()<.15 and body.angular_velocity.length()<.25
		if supported and quiet and body.global_position.distance_to(anchor)<.015:stable+=delta
		else:stable=0.0;anchor=body.global_position
		last={"ok":false,"code":"not_settled","support_confirmed":supported,"speed_mps":body.linear_velocity.length(),"angular_speed_rad_s":body.angular_velocity.length(),"stable_seconds":stable,"observed_seconds":elapsed,"scope":"visible_object_bottom_support_probe","meaning":"仅确认当前位置稳定，不证明已到达指定地点；未确认支撑不等于周围没有支撑面。"}
		if stable>=.3:
			last.ok=true;last.code="settled";return last
	return last

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
	if not args.get("object") is String or not args.get("target") is Dictionary or not Spatial.valid(args.target) or not BodyState.seconds(args.get("seconds")):return _result(false,"invalid_arguments")
	var id: String=args.object
	if not objects.objects.has(id) or objects.objects[id].holder!=person_id:return _result(false,"not_held")
	if not await _life_action_time(float(args.seconds)):return _result(false,"cancelled")
	if objects.objects[id].holder!=person_id:return _result(false,"not_held")
	# 结束时重新核对表面、视线和距离；动画轨迹不作为普通放置的成败条件。
	var target: Dictionary=resolve_surface(args.target)
	if not target.ok:return target
	var at: Vector3=placement_targets[Spatial.key(args.target)]
	if not preload("res://scripts/skills/interaction_range.gd").reachable(sim.actors[person_id].body,at):return _result(false,"out_of_reach")
	objects.sync_held(id)
	var record: Dictionary=objects.objects[id]
	var destination: Transform3D=record.body.global_transform
	destination.origin+=at+Vector3.UP*.015-objects.bottom(id)
	var contacts: Array=objects.pose_contacts(id,destination)
	if not contacts.is_empty():return {"ok":false,"code":"placement_blocked","contacts":objects.contact_kinds(contacts)}
	record.attachment_frame="world"
	record.attachment=func():return destination
	objects.sync_held(id)
	return {"ok":true,"code":"moved_to_surface","observation_id":observation_id,"bottom":local_point(objects.bottom(id)),"target":local_point(at)}

func _life_action_time(seconds: float) -> bool:
	# 时间属于世界规则；暂停不推进，取消不消耗。等待后重新校验物资和目标。
	var elapsed:=0.0
	while elapsed<seconds:
		await get_tree().process_frame
		if not _owned:return false
		if sim.enabled:elapsed+=get_process_delta_time()
	return true
