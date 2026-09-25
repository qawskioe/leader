extends RefCounted
## 世界查询只用于判断当下能否感知；离开视线后不刷新角色知识。
var sim: Node
var world_objects: Node
var memories: Dictionary={}
var revisions: Dictionary={}
var revision_positions: Dictionary={}
const SIGNIFICANT_MOVE_M:=0.25
var clock:=0.0
func seed_arrival(ids: Array) -> void:
	clock=sim.store.memory.clock
	for id in ids:revision_positions[id]={}
	if sim.store.memory.loaded:
		for id in ids:
			memories[id]={};revisions[id]=1
			for entry in sim.store.memory.retained(id,"landmark"):
				entry.visible_now=false;memories[id][entry.id]=entry
		return
	var opening: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening_journey.json"))
	for id in ids:
		memories[id]={}
		for landmark: Dictionary in opening.landmarks:
			var entry:=landmark.duplicate(true)
			entry["visible_now"]=false
			entry["observed_at_seconds"]=-1.0
			memories[id][entry.id]=entry
			sim.store.memory.put(id,"landmark",entry.id,entry,0.6)
			sim.store.memory.note_observation(id,entry)
		revisions[id]=1

func sees(id: String, at: Vector3, target: RID=RID()) -> bool:
	var body: Node3D=sim.actors[id].body
	var eye:=body.global_position+Vector3(0,1.6,0)
	var offset:=at-eye
	if offset.length()>10 or body.global_basis.z.angle_to(offset)>deg_to_rad(80): return false
	var exclude: Array[RID]=[body.get_rid(),sim.scene.get_node("Player").get_rid()]
	if target.is_valid(): exclude.append(target)
	return sim.scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,at,1,exclude)).is_empty()

func _record(id: String, key: String, kind: String, at: Vector3, available: bool, extra: Dictionary={}) -> void:
	var previous: Dictionary=memories[id].get(key,{})
	var position: Array=[at.x,at.y,at.z]
	# 人物脚边参考点跟随移动和转身，仅更新几何；不能被当作新物资催发需求调用。
	if kind not in ["person","surface"]:
		if not revision_positions.has(id):revision_positions[id]={}
		var prior: Array=previous.get("position",position)
		var anchor: Vector3=revision_positions[id].get(key,Vector3(prior[0],prior[1],prior[2]))
		if not revision_positions[id].has(key):revision_positions[id][key]=anchor
		# 调度只关心有意义的移动；以最近一次触发点累计，不抹掉缓慢移动。
		# 下方精确位置照常更新，不能为了抑制调用而降低人物实际观察精度。
		if previous.is_empty() or anchor.distance_to(at)>=SIGNIFICANT_MOVE_M or previous.get("available")!=available or previous.get("extra")!=extra:
			revisions[id]=revisions.get(id,0)+1
			revision_positions[id][key]=at
	memories[id][key]={"id":key,"kind":kind,"position":position,"available":available,"visible_now":true,"source":"亲眼观察","observed_at_seconds":clock,"extra":extra.duplicate(true)}

	if kind!="surface": sim.store.memory.note_observation(id,memories[id][key])
	# 持久层按实际变化或30秒再观察更新，不逐物理帧写盘。
	var persisted: Dictionary=sim.store.memory.records[id].get("landmark/"+key.sha256_text(),{}).get("data",{})
	if kind!="person" and (persisted.get("position")!=position or persisted.get("available")!=available or persisted.get("extra")!=extra or clock-float(persisted.get("observed_at_seconds",-30))>=30):
		sim.store.memory.put(id,"landmark",key,memories[id][key],0.6)

func observe(id: String) -> void:
	if not memories.has(id): memories[id]={}
	for entry in memories[id].values(): entry.visible_now=false
	if sees(id,sim.STORAGE+Vector3(0,0.4,0)):
		_record(id,"storage","storage",sim.STORAGE,sim.storage_food>0,{"food_count":sim.storage_food})
	if is_instance_valid(sim.water):
		if sees(id,sim.water.SOURCE+Vector3(0,0.4,0)): _record(id,"water_source","water_source",sim.water.SOURCE,true)
	for key in sim.gathering.baskets:
		var basket: Dictionary=sim.gathering.baskets[key]
		if basket.holder==id: continue
		var at: Vector3=basket.root.global_position
		if sees(id,at+Vector3(0,0.4,0),basket.body.get_rid()):
			_record(id,"basket/"+key,"basket",at,basket.holder=="",{"food_count":basket.contents.count,"contents":basket.contents.describe()})
	for key in sim.gathering.resources:
		var fruit: Dictionary=sim.gathering.resources[key]
		var at: Vector3=fruit.mesh.global_position
		if sees(id,at): _record(id,"fruit/"+key,"fruit",at,fruit.available)
	for other in sim.actors:
		if other==id: continue
		var at: Vector3=sim.actors[other].body.global_position
		if sees(id,at+Vector3(0,1.2,0)): _record(id,"person/"+other,"person",at,true)
	var player: Node3D=sim.scene.get_node("Player")
	if sees(id,player.global_position+Vector3(0,1.2,0)): _record(id,"person/player","person",player.global_position,true)
	if is_instance_valid(world_objects):
		for key in world_objects.objects:
			var object: Dictionary=world_objects.objects[key]
			var at: Vector3=world_objects.grip_position(key)
			if object.holder==id or sees(id,at,object.body.get_rid()):
				_record(id,key,object.kind,at,object.holder=="" or object.holder==id,world_objects.observable_extra(key))
	if is_instance_valid(world_objects):
		# 空间锚点来自局部地面查询，交谈只传锚点ID，不向模型灌入全地图。
		var anchors: Dictionary={id:sim.actors[id].body}
		for other in sim.actors:
			if other!=id and memories[id].get("person/"+other,{}).get("visible_now",false): anchors[other]=sim.actors[other].body
		if memories[id].get("person/player",{}).get("visible_now",false): anchors["player"]=player
		for other in anchors:
			var body: Node3D=anchors[other]
			var at: Vector3=body.global_position+body.global_basis.z*0.28
			var exclude: Array[RID]=[player.get_rid()]
			for a in sim.actors.values(): exclude.append(a.body.get_rid())
			for obj in world_objects.objects.values(): exclude.append(obj.body.get_rid())
			var hit: Dictionary=sim.scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2,1,exclude))
			if not hit.is_empty() and hit.normal.y>0.8 and (other==id or sees(id,hit.position+Vector3.UP*0.03)):
				_record(id,"surface/person/"+other,"surface",hit.position,true,{"name":("自己" if other==id else "玩家" if other=="player" else str(sim.store.people[other].name))+"脚边地面","anchor_person":other})
	# 可以确认最后位置已空，但不因此获知物品被搬到了哪里。
	for key in memories[id]:
		var entry: Dictionary=memories[id][key]
		if entry.visible_now or entry.kind not in ["basket","person","water_bag","interactable"]: continue
		if float(entry.get("position_error_per_axis_m",0))>0: continue # 看见粗略区域中的一个空点，不能证明整个区域没人。
		var at:=Vector3(entry.position[0],entry.position[1],entry.position[2])
		if sees(id,at+Vector3(0,0.5,0)) and entry.available:
			entry.available=false
			entry["last_place_checked_at_seconds"]=clock
			if entry.kind!="person": sim.store.memory.note_observation(id,entry)
			revisions[id]=revisions.get(id,0)+1

func known(id: String, key: String) -> Dictionary:
	return memories.get(id,{}).get(key,{}).duplicate(true)

func hear_voice(id: String, speaker: String, event_id: String, source: Vector3) -> bool:
	var key:="person/"+speaker
	if memories.get(id,{}).get(key,{}).get("visible_now",false): return false
	# 只在真正听见公开台词后调用。声源给粗略线索，不能获得视觉细节或持续追踪。
	var estimate:=(source-Vector3.UP*1.6).snapped(Vector3.ONE*2.0)
	var entry:={"id":key,"kind":"person","position":[estimate.x,estimate.y,estimate.z],"available":true,"visible_now":false,"source":"听到本人说话，粗略声源位置，尚未目视核实","observed_at_seconds":clock,"heard_at_seconds":clock,"heard_from":speaker,"source_event_id":event_id,"position_error_per_axis_m":2.0,"extra":{}}
	if not memories.has(id): memories[id]={}
	memories[id][key]=entry
	sim.store.memory.note_observation(id,entry)
	sim.store.memory.put(id,"landmark",key,entry,0.6)
	# 与目视人物一样，不用每次声源更新重触发饥饿判断；实际请求由对话事件唤醒。
	return true

func hear_from(id: String, speaker: String, event_id: String, entry: Dictionary) -> bool:
	if not memories.has(id): memories[id]={}
	var key: String=entry.id
	var previous: Dictionary=memories[id].get(key,{})
	var evidence_time: float=maxf(entry.observed_at_seconds,entry.get("last_place_checked_at_seconds",-1.0))
	if not previous.is_empty():
		var previous_time: float=maxf(previous.observed_at_seconds,previous.get("last_place_checked_at_seconds",-1.0))
		if previous.get("visible_now",false) or previous_time>=evidence_time: return false
	var learned:=entry.duplicate(true)
	learned["original_source"]=entry.get("original_source",entry.source)
	learned["origin_person_id"]=entry.get("origin_person_id",speaker)
	var chain: Array=entry.get("information_chain",[]).duplicate()
	chain.append(speaker)
	if chain.size()>8: chain.pop_front()
	learned["information_chain"]=chain
	learned.source="听闻，尚未亲自核实"
	learned.visible_now=false
	learned["heard_from"]=speaker
	learned["heard_at_seconds"]=clock
	learned["source_event_id"]=event_id
	# 不把转述时间改成观察时间，避免旧情报反复传播后变成“最新”。
	memories[id][key]=learned
	sim.store.memory.note_observation(id,learned)
	sim.store.memory.put(id,"landmark",key,learned,0.6)
	revisions[id]=revisions.get(id,0)+1
	return true

func note_storage_action(id: String, amount: int) -> void:
	# amount=0仅由到场检查为空的分支调用；存取成功不推断库存总数。
	assert(amount in [-1,0,1])
	var entry: Dictionary=memories[id]["storage"]
	entry.source="本人到场确认没有食物" if amount==0 else "本人刚刚亲手存取"
	entry.observed_at_seconds=clock
	entry.visible_now=false
	entry.available=false if amount==0 else (true if amount>0 else null)
	entry.extra={"own_transfer":amount,"food_count":0 if amount==0 else null,"note":"本次到场检查为空，之后他人可能补充" if amount==0 else "只确认自己的本次存取，不推断别人未被看见的操作或当前总量"}
	# 空间上下文读取的是memory.observations，不能只更新临时perception记录。
	sim.store.memory.note_observation(id,entry)
	sim.store.memory.put(id,"landmark","storage",entry,0.6)
	revisions[id]=revisions.get(id,0)+1

func position_of(id: String, key: String) -> Variant:
	var entry:=known(id,key)
	if entry.is_empty(): return null
	var at: Array=entry.position
	return Vector3(at[0],at[1],at[2])

func nearest(id: String, kind: String, available_only: bool=true) -> Dictionary:
	var chosen: Dictionary={}
	var distance:=INF
	for entry in memories.get(id,{}).values():
		if entry.kind!=kind or (available_only and not entry.available): continue
		var at:=Vector3(entry.position[0],entry.position[1],entry.position[2])
		var d: float=sim.actors[id].body.global_position.distance_to(at)
		if d<distance: chosen=entry; distance=d
	return chosen.duplicate(true)

func reset() -> void:
	memories.clear(); revisions.clear(); revision_positions.clear(); clock=0
