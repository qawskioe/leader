extends RefCounted
## 宿主专用隔离回放快照；不发给人物模型，不包含修改正式世界的接口。
static func vector(at: Vector3) -> Array: return [at.x,at.y,at.z]
static func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func units(items: Array) -> Array:
	var result: Array=[]
	for item in items:result.append({"material":item.get("material","food"),"origin":item.get("origin",{}).duplicate(true)})
	return result
static func capture(sim: Node, person: String) -> Dictionary:
	var data:={"person_id":person,"clock":sim.store.memory.clock,"people":{},"objects":{},"containers":{},"hands":{},"observations":sim.store.memory.observations.duplicate(true),"records":sim.store.memory.records.duplicate(true)}
	var player: Node3D=sim.scene.get_node("Player")
	data["player"]={"position":vector(player.global_position),"rotation":vector(player.rotation),"eyes_rotation":vector(player.get_node("Eyes").rotation)}
	for id in sim.actors:
		var actor: Dictionary=sim.actors[id]
		data.people[id]={"position":vector(actor.body.global_position),"rotation":vector(actor.body.rotation),"needs":sim.store.people[id].needs.duplicate(true)}
	for id in sim.world_objects.objects:
		var obj: Dictionary=sim.world_objects.objects[id]
		data.objects[id]={"position":vector(obj.body.global_position),"rotation":vector(obj.body.rotation),"holder":obj.holder,"hand":obj.hand,"grip":vector(obj.grip),"name":obj.body.get_meta("display_name",id)}
	for id in sim.content_interaction.containers:data.containers[id]=units(sim.content_interaction.containers[id].record.contents.items)
	for id in sim.gathering.hands:data.hands[id]=units([sim.gathering.hands[id]])[0]
	return data
static func restore(sim: Node, data: Dictionary) -> void:
	var player: Node3D=sim.scene.get_node("Player")
	player.set_physics_process(false)
	player.global_position=point(data.player.position);player.rotation=point(data.player.rotation);player.get_node("Eyes").rotation=point(data.player.eyes_rotation)
	for id in data.people:
		sim.actors[id].body.global_position=point(data.people[id].position)
		sim.actors[id].body.rotation=point(data.people[id].rotation)
		sim.actors[id].body.velocity=Vector3.ZERO
		sim.store.people[id].needs=data.people[id].needs.duplicate(true)
	for id in data.objects:
		var saved: Dictionary=data.objects[id]
		if not sim.world_objects.objects.has(id):
			# 当前试验道具的几何由宿主保存；未知类型不能捏造近似碰撞。
			assert(false,"隔离场景不能重建物品："+id)
			return
		var obj: Dictionary=sim.world_objects.objects[id]
		obj.body.global_position=point(saved.position);obj.body.rotation=point(saved.rotation)
		obj.body.linear_velocity=Vector3.ZERO;obj.body.angular_velocity=Vector3.ZERO
		if saved.holder=="player":
			var held_transform: Transform3D=obj.body.global_transform
			sim.world_objects.attach_to(id,"player",saved.hand,func():return held_transform)
		elif saved.holder!="":
			var motor=preload("res://scripts/skills/body_motor.gd").new();motor.initialize(sim.actors[saved.holder],saved.holder)
			var frame: Transform3D=sim.world_objects.hand_transform(motor,saved.hand)
			var offset: Transform3D=frame.affine_inverse()*obj.body.global_transform
			sim.world_objects.attach_to(id,saved.holder,saved.hand,func():return sim.world_objects.hand_transform(motor,saved.hand)*offset)
	for id in data.containers:
		assert(sim.content_interaction.containers.has(id),"验证世界缺少容器")
		var entry: Dictionary=sim.content_interaction.containers[id]
		for item in entry.record.contents.items:
			if is_instance_valid(item.get("visual")):item.visual.queue_free()
		entry.record.contents.clear()
		for item in data.containers[id]:assert(entry.record.contents.add(item.duplicate(true)).ok)
		if entry.changed.is_valid():entry.changed.call()
	sim.gathering.hands.clear()
	for id in data.hands:
		var item: Dictionary=data.hands[id].duplicate(true)
		item.visual=sim._fruit();sim.scene.add_child(item.visual);sim.gathering.hands[id]=item
	sim.store.memory.clock=data.clock;sim.perception.clock=data.clock
	sim.perception.memories=data.observations.duplicate(true)
	sim.store.memory.observations=data.observations.duplicate(true)
	sim.store.memory.records=data.records.duplicate(true)
	for id in sim.actors:sim._sync(id)
static func evidence(sim: Node, person: String) -> Dictionary:
	var actor: Dictionary=sim.actors[person]
	var result:={"needs":sim.store.people[person].needs.duplicate(true),"position":vector(actor.body.global_position),"objects":{},"containers":{},"hand_unit":units([sim.gathering.hands[person]])[0] if sim.gathering.hands.has(person) else {}}
	for id in sim.world_objects.objects:
		var obj: Dictionary=sim.world_objects.objects[id]
		result.objects[id]={"position":vector(obj.body.global_position),"holder":obj.holder,"hand":obj.hand}
	for id in sim.content_interaction.containers:result.containers[id]=sim.content_interaction.containers[id].record.contents.describe()
	return result
