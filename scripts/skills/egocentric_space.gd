extends RefCounted
## 观察快照的世界变换仅由宿主持有，模型只读取人物局部坐标。
const Target=preload("res://scripts/skills/spatial_target.gd")
var sim: Node
var frames: Dictionary={}
var retained_frames: Dictionary={}
var serial:=0
var near_range_m:=10.0
var far_resolution_m:=10.0

func retain_frame(person: String, token: String) -> bool:
	if not frames.has(token) or frames[token].person!=person:return false
	retained_frames[token]=int(retained_frames.get(token,0))+1
	return true

func release_frame(token: String) -> void:
	assert(retained_frames.has(token),"观察租约必须成对释放")
	retained_frames[token]-=1
	if retained_frames[token]==0:retained_frames.erase(token)
	_trim_frames()

func _trim_frames() -> void:
	for token in frames.keys():
		if frames.size()-retained_frames.size()<=64:break
		if not retained_frames.has(token):frames.erase(token)

static func xyz(at: Vector3) -> Dictionary:
	return {"x":at.x,"y":at.y,"z":at.z}

func capture(id: String) -> Dictionary:
	serial+=1
	var token:="observation_%s_%d_%d"%[id,Time.get_ticks_usec(),serial]
	var body: Node3D=sim.actors[id].body
	var forward:=Vector3(sin(body.rotation.y),0,cos(body.rotation.y))
	var transform:=Transform3D(Basis(forward.cross(Vector3.UP),Vector3.UP,forward),body.global_position)
	frames[token]={"person":id,"transform":transform,"created_ms":Time.get_ticks_msec()}
	_trim_frames()
	var observation:={"id":token,"unit":"metre","origin":"本人脚底中心，观察瞬间固定","axes":{"x":"右","y":"上","z":"前"},"self_position":xyz(Vector3.ZERO),"self_forward":xyz(Vector3(0,0,1)),"view":{"eye":xyz(Vector3(0,1.6,0)),"range":10.0,"half_angle_degrees":80.0},"landmarks":{},"ground_samples":[],"occlusion_samples":[],"sample_spacing":0.75,"unknown_rule":"仅描述本次可见采样；未知不是空地。点间未采样部分不保证通行。路线与下一步目标由人物选择。"}
	observation["body_bounds"]=bounds(body,transform)
	var body_state: RefCounted=body.get_meta("body_state") if body.has_meta("body_state") else null
	if body_state==null:
		body_state=preload("res://scripts/skills/body_state.gd").new();body_state.initialize(sim.actors[id],id)
	observation["hands"]={"right":xyz(transform.affine_inverse()*body_state.point("Hand.R")),"left":xyz(transform.affine_inverse()*body_state.point("Hand.L"))}
	observation["hands_meaning"]="固定交互槽，用于选择左右手；不代表动画骨骼的实时手掌位置"
	for key in sim.perception.memories.get(id,{}):
		var entry: Dictionary=sim.perception.known(id,key)
		var p: Array=entry.position
		entry.position=xyz(transform.affine_inverse()*Vector3(p[0],p[1],p[2]))
		if entry.visible_now and is_instance_valid(sim.perception.world_objects) and sim.perception.world_objects.objects.has(key):
			entry["bounds"]=bounds(sim.perception.world_objects.objects[key].body,transform)
		observation.landmarks[key]=entry
	var exclusions: Array[RID]=[body.get_rid()]
	if is_instance_valid(sim.perception.world_objects):
		for object in sim.perception.world_objects.objects.values():
			if object.holder==id: exclusions.append(object.body.get_rid())
	var physics: PhysicsDirectSpaceState3D=sim.scene.get_world_3d().direct_space_state
	var eye:=transform*Vector3(0,1.6,0)
	for z in range(1,7):
		for x in range(-4,5):
			var local:=Vector3(x*0.75,0,z*0.75)
			var at:=transform*local
			var floor_hit:=physics.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.5,at-Vector3.UP*2,1,exclusions))
			var sample:={"probe":xyz(local),"state":"unknown"}
			if not floor_hit.is_empty():
				var point: Vector3=floor_hit.position+Vector3.UP*0.03
				var direction:=point-eye
				if direction.length()<=10 and transform.basis.z.angle_to(direction)<=deg_to_rad(80):
					var obstruction:=physics.intersect_ray(PhysicsRayQueryParameters3D.create(eye,point,1,exclusions))
					if obstruction.is_empty():
						sample={"probe":xyz(local),"position":xyz(transform.affine_inverse()*floor_hit.position),"normal":xyz(transform.basis.inverse()*floor_hit.normal),"state":"visible_surface","slope_degrees":rad_to_deg(floor_hit.normal.angle_to(Vector3.UP))}
						# 首个可见命中可能是物品/人物顶部，不能标成地面或继续穿透查找地面。
						if floor_hit.collider is RigidBody3D or floor_hit.collider is CharacterBody3D:
							sample["state"]="visible_object_surface"
							sample["surface_kind"]="person" if floor_hit.collider is CharacterBody3D else "movable_object"
						else:
							var covering_water:=visible_water_above(id,floor_hit.position)
							sample["surface_kind"]="dry_ground" if covering_water.is_empty() else "submerged_ground"
							if not covering_water.is_empty(): sample["water_surface"]=xyz(transform.affine_inverse()*covering_water.position)
					else:
						observation.occlusion_samples.append({"position":xyz(transform.affine_inverse()*obstruction.position),"normal":xyz(transform.basis.inverse()*obstruction.normal)})
			observation.ground_samples.append(sample)
	var near:={"range_m":near_range_m,"landmarks":{},"ground_samples":observation.ground_samples,"occlusion_samples":observation.occlusion_samples,"sample_spacing_m":observation.sample_spacing,"body_bounds":observation.body_bounds,"hands":observation.hands,"view":observation.view,"unknown_rule":observation.unknown_rule}
	near["regions"]=visible_regions(id,transform)
	near["held_objects"]=[]
	if is_instance_valid(sim.perception.world_objects):
		for key in sim.perception.world_objects.objects:
			var record: Dictionary=sim.perception.world_objects.objects[key]
			if record.holder==id: near.held_objects.append({"id":key,"hand":record.hand})
	near["held_objects_meaning"]="本人当前实际握持的物体；空数组表示双手没有握持这些物体，优先于旧任务与记忆。"
	var far:={"coordinate_resolution_m":far_resolution_m,"landmarks":{},"purpose":"已知地标的粗略方位与距离，用于分段行进；不是全地图真实状态，不能直接作为精确放置位置"}
	for key in observation.landmarks:
		var entry: Dictionary=observation.landmarks[key]
		var relative:=Vector3(entry.position.x,entry.position.y,entry.position.z)
		if relative.length()<=near_range_m:
			if entry.visible_now: near.landmarks[key]=entry
	for key in ["landmarks","ground_samples","occlusion_samples","sample_spacing","body_bounds","hands","view","unknown_rule"]: observation.erase(key)
	far.erase("landmarks")
	far["access"]="通过recall(kind=landmark)主动回忆本人已知地标；不会自动输入全部地图记忆"
	observation["near_field"]=near;observation["far_field"]=far
	return observation

func resolve(id: String, target: Variant, max_component: float=10.0) -> Dictionary:
	if not target is Dictionary or not Target.valid(target,max_component): return {"ok":false,"code":"invalid_spatial_target"}
	var frame: Dictionary=frames.get(target.observation_id,{})
	if frame.is_empty() or frame.person!=id: return {"ok":false,"code":"unknown_observation"}
	if Time.get_ticks_msec()-int(frame.created_ms)>300000: return {"ok":false,"code":"observation_expired"}
	return {"ok":true,"position":frame.transform*Target.position(target),"transform":frame.transform}

func local_point(id: String, token: String, at: Vector3) -> Dictionary:
	assert(frames.has(token) and frames[token].person==id)
	return xyz(frames[token].transform.affine_inverse()*at)

func prepare_context(id: String, context: Dictionary, observation: Dictionary) -> Dictionary:
	var result:=context.duplicate(true)
	var survival: Dictionary=result.get("survival_observation",{})
	survival.erase("body_position");survival.erase("body_forward");survival.erase("spatial_rules")
	survival["known_objects"]={}
	for key in observation.near_field.landmarks:
		var fact: Dictionary=observation.near_field.landmarks[key].duplicate(true)
		fact.erase("position");fact.erase("bounds");fact["spatial_layer"]="near_field"
		survival.known_objects[key]=fact
	result["survival_observation"]=survival
	result["space_observation"]=observation.duplicate(true)
	var working: Dictionary=result.get("working_context",{})
	working["last_known_locations"]={}
	for key in sim.store.memory.observations[id]:
		working.last_known_locations[key]=recalled_landmark(id,sim.store.memory.observations[id][key],observation.id)
		# 当天已见的近处物品仍可作为行动对象；当前不可见只降低信息新鲜度，不抹去身份。
		# 不扩展远场目录，也不读取物品的实时位置或库存。
		var remembered: Dictionary=working.last_known_locations[key]
		if remembered.spatial_layer=="near_field" and not survival.known_objects.has(key):
			var fact:=remembered.duplicate(true)
			fact.erase("position");fact.erase("bounds")
			fact["location_ref"]="self.working_context.last_known_locations/"+str(key)
			survival.known_objects[key]=fact
	if not working.get("task",{}).is_empty():
		working.task["initial_locations"]={}
		for key in sim.store.working_tasks[id].get("observations",{}):
			working.task.initial_locations[key]=recalled_landmark(id,sim.store.working_tasks[id].observations[key],observation.id)
	result["working_context"]=working
	for field in ["heard_events","reflections","execution_results","skill_knowledge","known_facts"]: result.erase(field)
	result["memory_access"]={"kinds":["heard","reflection","action","landmark","skill","fact","relationship"],"usage":"需要过去信息时先请求recall；空keywords表示该类最近记录。不是所有记忆都在当前输入里。"}
	return result

static func release_location(object_id: String, grip: Vector3, frame: Transform3D, token: String, known: Dictionary, near_range: float) -> Dictionary:
	# 只使用本人记住的参考点；不能查询物体当前真值来更新离开视野后的情报。
	var references: Dictionary={}
	for key in known:
		if key==object_id: continue
		var entry: Dictionary=known[key]
		var p: Array=entry.position
		var remembered:=Vector3(p[0],p[1],p[2])
		if frame.origin.distance_to(remembered)>near_range: continue
		var offset: Vector3=frame.basis.inverse()*(grip-remembered)
		references[key]={"offset_from_reference":xyz(offset),"horizontal_distance_m":Vector2(offset.x,offset.z).length(),"reference_visible_at_release":entry.get("visible_now",false),"source":entry.get("source",""),"observed_at_seconds":entry.get("observed_at_seconds",0),"position_error_per_axis_m":entry.get("position_error_per_axis_m",0)}
	return {"observation_id":token,"grip_position":xyz(frame.affine_inverse()*grip),"unit":"metre","axes":{"x":"右","y":"上","z":"前"},"known_references":references,"meaning":"松手瞬间物体抓握点的位置，不是落稳后的位置；参考点不可见时使用最后已知位置，不证明它现在仍在那里。坐标系固定在observation_id对应的本人观察瞬间；不能当作当前站位坐标。"}

static func execution_phases(trace: Array) -> Array:
	var phases: Array=[]
	for step in trace:
		if not step is Dictionary or not step.get("result") is Dictionary or step.get("operation","") in ["perceive","recall_locations","walk_options"]:continue
		var phase:={"operation":step.get("operation",""),"ok":step.result.get("ok"),"code":step.result.get("code","")}
		for key in ["object","holder","hand","recipient","material","source","target","quantity","source_count","destination_count","distance_m","contact_limit_m","horizontal_error","height_error","supported","speed"]:
			if step.result.has(key):phase[key]=step.result[key]
		if step.result.get("release_location") is Dictionary:phase["release_location"]=step.result.release_location.duplicate(true)
		if step.has("elapsed_ms"):phase["elapsed_ms"]=step.elapsed_ms
		if step.result.get("timing") is Dictionary:phase["timing"]=step.result.timing.duplicate(true)
		if step.get("arguments") is Dictionary and step.arguments.has("seconds"):phase["requested_seconds"]=step.arguments.seconds
		phases.append(phase)
	return phases

static func sanitize_event(event: Dictionary) -> void:
	# 听闻已有方向/距离，不再附带玩家世界坐标；内部事件保留原命令但移除原始轨迹。
	event.erase("source_position");event.erase("positions");event.erase("player_voice_sources")
	if event.get("original_event") is Dictionary: sanitize_event(event.original_event)
	if event.get("result") is Dictionary: event.result.erase("world_position")
	if event.get("result") is Dictionary and event.result.get("runtime") is Dictionary:
		var runtime: Dictionary=event.result.runtime
		var returned: Dictionary=runtime.get("returned",{}) if runtime.get("returned") is Dictionary else {}
		var message: String=str(event.result.get("skill_name","动作"))+"："+str(runtime.get("code",returned.get("code","")))
		if event.get("text") is String and event.result.get("message") is String: event.text=event.text.replace(event.result.message,message)
		var phases: Array=runtime.get("phase_summary",execution_phases(runtime.get("trace",[])))
		event.result["execution_summary"]={"complete_action_history":runtime.has("phase_summary"),"status":runtime.get("status",""),"elapsed_ms":runtime.get("elapsed_ms",0),"phases":phases,"meaning":"phases按顺序记录实际世界操作及回执，省略纯感知采样；complete_action_history表示是否覆盖全程。feedback是方法返回值。requested_seconds是请求时长，实际耗时看elapsed_ms/timing。success表示代码正常结束且方法返回ok；原请求完成到哪一步，由本人结合各阶段回执与world_facts判断。"}
		var failures: Array=[]
		for step in runtime.get("trace",[]):
			if not step is Dictionary or not step.get("result") is Dictionary or step.result.get("ok",true):continue
			var failure:={"operation":step.get("operation",""),"code":step.result.get("code","")}
			# 只给本人的操作与测得距离，不泄露回放路径或世界绝对坐标。
			for key in ["distance_m","contact_limit_m"]:
				if step.result.has(key):failure[key]=step.result[key]
			failures.append(failure)
		if not failures.is_empty():event.result["failed_attempts"]=failures.slice(-8)
		event.result["feedback"]=returned.duplicate(true)
		event.result.message=message+"；"+str(returned.get("message",""))
		event.result.erase("runtime")

static func bounds(body: Node3D, frame: Transform3D) -> Dictionary:
	var minimum:=Vector3(INF,INF,INF)
	var maximum:=Vector3(-INF,-INF,-INF)
	for node in body.get_children():
		if node is CollisionShape3D and not node.disabled:
			var shape_bounds: AABB=node.shape.get_debug_mesh().get_aabb()
			for corner in 8:
				var point: Vector3=frame.affine_inverse()*node.global_transform*shape_bounds.get_endpoint(corner)
				minimum=minimum.min(point);maximum=maximum.max(point)
	if not minimum.is_finite(): return {}
	return {"min":xyz(minimum),"max":xyz(maximum),"approximation":"轴对齐包围盒，不等同于完整碰撞形状"}

func recalled_landmark(person: String, entry: Dictionary, token: String) -> Dictionary:
	assert(frames.has(token) and frames[token].person==person)
	var result:=entry.duplicate(true)
	var p: Array=entry.position
	var relative: Vector3=frames[token].transform.affine_inverse()*Vector3(p[0],p[1],p[2])
	result.erase("position");result["visible_now"]=false;result["observation_id"]=token
	if relative.length()<=near_range_m:
		result["spatial_layer"]="near_field";result["position"]=xyz(relative)
	else:
		result["spatial_layer"]="far_field"
		result["approx_position"]=xyz(relative.snapped(Vector3.ONE*far_resolution_m))
		result["position_error_per_axis_m"]=far_resolution_m/2+float(entry.get("position_error_per_axis_m",0))
		result["distance_range_m"]=[floorf(relative.length()/far_resolution_m)*far_resolution_m,(floorf(relative.length()/far_resolution_m)+1)*far_resolution_m]
	return result

func visible_regions(id: String, frame: Transform3D) -> Array:
	var regions: Array=[]
	for label in ["WaterPool", "Cenote_water"]:
		var surface:=sim.scene.find_child(label,true,false) as MeshInstance3D
		if surface==null or surface.mesh==null: continue
		# 从渲染网格提取外围顶点，再逐点检查人物的可见性；被遮挡的边界不泄露。
		var vertices: PackedVector3Array=surface.mesh.get_faces()
		var footprint: PackedVector2Array=[]
		for vertex in vertices: footprint.append(Vector2(vertex.x,vertex.z))
		if footprint.size()<3: continue
		var outline:=Geometry2D.convex_hull(footprint)
		var visible: Array=[]
		var height:=surface.mesh.get_aabb().get_center().y
		for point in outline:
			var world_point: Vector3=surface.global_transform*Vector3(point.x,height,point.y)
			if sim.perception.sees(id,world_point+Vector3.UP*0.03): visible.append(xyz(frame.affine_inverse()*world_point))
		if not visible.is_empty(): regions.append({"kind":"water_surface","name":str(surface.name),"visible_boundary_points":visible,"complete":visible.size()==outline.size(),"approximation":"可见水面凸包边界，非实体支撑面；未看见的边界不提供"})
	return regions

func visible_water_above(id: String, floor_point: Vector3) -> Dictionary:
	# 水面是透明渲染网格，没有实体碰撞；只读脚下同一可见采样柱的真实网格。
	# 物理地面可见并不意味着干地，水底不能当作“水池外”。
	for label in ["WaterPool", "Cenote_water"]:
		var surface:=sim.scene.find_child(label,true,false) as MeshInstance3D
		if surface==null or surface.mesh==null: continue
		var start: Vector3=surface.to_local(floor_point+Vector3.UP*2)
		var finish: Vector3=surface.to_local(floor_point)
		if not surface.mesh.get_aabb().grow(0.001).intersects_segment(start,finish): continue
		var triangles: PackedVector3Array=surface.mesh.get_faces()
		for index in range(0,triangles.size(),3):
			var hit: Variant=Geometry3D.segment_intersects_triangle(start,finish,triangles[index],triangles[index+1],triangles[index+2])
			if hit==null: continue
			var point: Vector3=surface.to_global(hit)
			if sim.perception.sees(id,point+Vector3.UP*0.03): return {"position":point}
	return {}
