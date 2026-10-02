extends RefCounted
## 正式存档是同一时间点的世界、人物、记忆和技能包；加载前完整校验，禁止半恢复。
const Snapshot=preload("res://scripts/skills/verification_snapshot.gd")
const Memory=preload("res://scripts/voice/memory_store.gd")
const Library=preload("res://scripts/skills/library.gd")
const PERSON_FIELDS=["identity","short_term","needs","relationships","heard_events","reflections","execution_results","skill_knowledge","known_facts"]

static func capture(sim: Node, library: RefCounted) -> Dictionary:
	var people: Dictionary={}
	for id in sim.store.people:
		people[id]={}
		for field in PERSON_FIELDS:
			if sim.store.people[id].has(field):people[id][field]=sim.store.people[id][field].duplicate(true)
	return {"world":Snapshot.capture(sim,sim.actors.keys()[0]),"people":people,"memory":sim.store.memory.export_data(),"skills":library.export_data()}

static func save(path: String, sim: Node, library: RefCounted, continuity: Dictionary={}) -> String:
	if not sim.ready_for_actions:return "世界尚未就绪"
	for actor in sim.actors.values():
		if actor.stage!="idle":return "仍有行动未停止，未保存"
	var data:=capture(sim,library)
	data["continuity"]=continuity.duplicate(true)
	var body:=JSON.stringify(data)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())!=OK:return "无法创建存档目录"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "无法写入临时存档"
	file.store_string(JSON.stringify({"schema":1,"sha256":body.sha256_text(),"payload":body}));file.flush()
	var error:=file.get_error();file.close()
	if error!=OK:return "存档写入失败，原存档保留"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:return "无法替换正式存档"
	return ""

static func _vector(value: Variant) -> bool:
	if not value is Array or value.size()!=3:return false
	for n in value:
		if not (n is float or n is int) or not is_finite(n):return false
	return true

static func _transform(value: Variant) -> bool:
	if not value is Array or value.size()!=4:return false
	for v in value:
		if not _vector(v):return false
	return absf(Snapshot.restored_transform(value).basis.determinant())>0.000001

static func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	return a.size()==b.size() and a.keys().all(func(k):return b.has(k))

static func validate_world(data: Variant, sim: Node) -> String:
	if not data is Dictionary:return "世界快照缺失"
	for key in ["people","objects","containers","hands","resources","gathering","player","loose_food","counters","observations","records"]:
		if not data.get(key) is Dictionary:return "世界快照字段损坏："+key
	if not _same_keys(data.people,sim.actors) or not _same_keys(data.objects,sim.world_objects.objects) or not _same_keys(data.resources,sim.gathering.resources) or not _same_keys(data.containers,sim.content_interaction.containers):return "存档与当前场景对象不匹配"
	for field in ["position","rotation","eyes_rotation"]:
		if not _vector(data.player.get(field)):return "玩家位置损坏"
	for id in data.people:
		var actor: Variant=data.people[id]
		if not actor is Dictionary or not _vector(actor.get("position")) or not _vector(actor.get("rotation")) or not actor.get("needs") is Dictionary or not actor.get("pose") is Dictionary:return "人物状态损坏"
		if not _same_keys(actor.needs,sim.store.people[id].needs):return "人物需求字段不匹配"
		for key in actor.needs:
			var n: Variant=actor.needs[key]
			if sim.store.people[id].needs[key] is String:
				if not n is String:return "人物需求描述损坏"
			elif not (n is int or n is float) or not is_finite(n):return "人物需求数值损坏"
		for bone in actor.pose:
			if sim.actors[id].skeleton.find_bone(bone)<0 or not _transform(actor.pose[bone]):return "人物姿态损坏"
	var held: Dictionary={}
	for id in data.objects:
		var obj: Variant=data.objects[id]
		if not obj is Dictionary:return "物品数据损坏"
		for field in ["position","rotation","grip","linear_velocity","angular_velocity"]:
			if not _vector(obj.get(field)):return "物品空间数据损坏"
		if obj.get("holder") not in sim.actors.keys()+["","player"] or not obj.get("hand") is String:return "持有者数据损坏"
		if obj.holder!="":
			if obj.hand not in ["Hand.L","Hand.R"] or held.has(obj.holder+obj.hand):return "持有槽冲突"
			held[obj.holder+obj.hand]=true
			if obj.holder!="player" and (obj.get("attachment_frame") not in ["body","world"] or not _transform(obj.get("local_offset"))):return "持有连接损坏"
	for id in data.containers:
		var items: Variant=data.containers[id]
		var container=sim.content_interaction.containers[id].record.contents
		if not items is Array or items.size()>container.capacity:return "容器容量损坏"
		for item in items:
			if not item is Dictionary or item.get("material")!=container.material or not item.get("origin") is Dictionary:return "容器内容损坏"
	for id in data.hands:
		var item: Variant=data.hands[id]
		if id not in sim.actors.keys()+["player"] or not item is Dictionary or item.get("hand") not in ["Hand.L","Hand.R"] or item.get("material") not in ["food","water"] or not item.get("origin") is Dictionary:return "手中物资损坏"
		if held.has(id+item.hand):return "手中物资与持有物冲突"
	for id in data.resources:
		var item: Variant=data.resources[id]
		if not item is Dictionary or not item.get("available") is bool or not item.get("reserved") is String or not _transform(item.get("transform")):return "采集资源损坏"
		for key in ["regrow_at","collision_layer"]:
			if not (item.get(key) is int or item.get(key) is float) or not is_finite(item[key]):return "采集资源数值损坏"
	for id in data.loose_food:
		var item: Variant=data.loose_food[id]
		if not item is Dictionary or not _transform(item.get("transform")) or not _transform(item.get("visual_transform")) or not _vector(item.get("velocity")) or not _vector(item.get("angular_velocity")) or not item.get("origin") is Dictionary or not item.get("points") is Array:return "散落物资损坏"
		if item.points.size()<4 or not item.points.all(func(p):return _vector(p)):return "散落物碰撞数据损坏"
	for section in ["gathering","counters"]:
		var keys=["elapsed","regrow_seconds","harvested","regrown"] if section=="gathering" else ["eaten","drawn","consumed","spilled","player_thirst"]
		for key in keys:
			var n: Variant=data[section].get(key)
			if not (n is int or n is float) or not is_finite(n) or n<0:return "世界统计数值损坏"
	return ""

static func read(path: String, sim: Node) -> Dictionary:
	if not FileAccess.file_exists(path):return {"ok":false,"error":"尚无存档"}
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return {"ok":false,"error":"存档不是有效JSON"}
	var envelope: Variant=parser.data
	if not envelope is Dictionary or envelope.get("schema")!=1 or not envelope.get("payload") is String or envelope.get("sha256")!=envelope.payload.sha256_text():return {"ok":false,"error":"存档不完整或格式不支持"}
	if parser.parse(envelope.payload)!=OK:return {"ok":false,"error":"存档内容损坏"}
	var data: Variant=parser.data
	if not data is Dictionary or not data.get("people") is Dictionary or not _same_keys(data.people,sim.store.people):return {"ok":false,"error":"存档人物不匹配"}
	var error:=validate_world(data.get("world"),sim)
	if not error.is_empty():return {"ok":false,"error":error}
	var memory=Memory.new();error=memory.load_data(data.get("memory"),sim.store.people.keys())
	if not error.is_empty():return {"ok":false,"error":error}
	if data.world.get("clock")!=memory.clock or data.world.observations!=memory.observations or data.world.records!=memory.records:return {"ok":false,"error":"世界与记忆不在同一保存点"}
	var library=Library.new();error=library.load_data(data.get("skills"),sim.store.people)
	if not error.is_empty():return {"ok":false,"error":error}
	for id in data.people:
		if not data.people[id] is Dictionary:return {"ok":false,"error":"人物记录损坏"}
		if data.people[id].get("needs")!=data.world.people[id].needs:return {"ok":false,"error":"人物与世界需求状态不一致"}
		for field in data.people[id]:
			if field not in PERSON_FIELDS or typeof(data.people[id][field])!=typeof(sim.store.people[id].get(field)):return {"ok":false,"error":"人物记录字段损坏"}
	return {"ok":true,"data":data,"memory":memory,"library":library}

static func restore(sim: Node, library: RefCounted, checked: Dictionary) -> void:
	assert(checked.ok)
	var data: Dictionary=checked.data
	Snapshot.restore(sim,data.world)
	var store=sim.store
	var memory=checked.memory;memory.path=store.memory.path
	store.memory=memory;store.working_events=memory.short_events;store.working_tasks=memory.tasks
	for id in data.people:
		for field in data.people[id]:store.people[id][field]=data.people[id][field].duplicate(true)
	library.definitions=checked.library.definitions;library.owners=checked.library.owners
	for id in sim.actors:
		sim.actors[id].stage="idle";sim.actors[id].path=PackedVector3Array();sim._animation(sim.actors[id],"Idle");sim._sync(id)
	var player: Node3D=sim.scene.get_node("Player")
	player.velocity=Vector3.ZERO;player.set_physics_process(true)
	for id in sim.world_objects.objects:
		var obj: Dictionary=sim.world_objects.objects[id]
		if obj.holder=="player":
			var pose: Callable=sim.world_objects.player_hold_transform.bind(id,player)
			sim.world_objects._detach(id)
			assert(sim.world_objects.attach_to(id,"player",data.world.objects[id].hand,pose).ok)
		elif obj.holder=="":
			obj.body.linear_velocity=Snapshot.point(data.world.objects[id].linear_velocity)
			obj.body.angular_velocity=Snapshot.point(data.world.objects[id].angular_velocity)
