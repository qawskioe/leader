extends RefCounted
## 世界注册容器能力，所有内容物仍在原实体的同一个组件中。
const Contents=preload("res://scripts/survival/container_contents.gd")

var sim: Node
var containers: Dictionary={}

func register_container(id: String, record: Dictionary, opening: Vector3, changed: Callable=Callable()) -> void:
	assert(not containers.has(id) and record.contents.get_script()==Contents)
	assert(record.root is Node3D and record.body is CollisionObject3D and record.has("holder"))
	containers[id]={"record":record,"opening":opening,"changed":changed}

func opening_position(id: String) -> Vector3:
	var entry: Dictionary=containers[id]
	return entry.record.root.to_global(entry.opening)

func _access(person: String, id: String) -> Dictionary:
	if not containers.has(id):
		return {"ok":false,"code":"not_observed" if sim.perception.known(person,id).is_empty() else "unsupported_container"}
	var record: Dictionary=containers[id].record
	var held_by_self: bool=record.holder==person
	if not held_by_self:
		if sim.perception.known(person,id).is_empty(): return {"ok":false,"code":"not_observed"}
		if not sim.perception.sees(person,opening_position(id),record.body.get_rid()): return {"ok":false,"code":"not_visible"}
	if not preload("res://scripts/skills/interaction_range.gd").reachable(sim.actors[person].body,opening_position(id)): return {"ok":false,"code":"out_of_reach"}
	# 距离和可见性通过后才能获知容器当前状态。
	if record.holder not in ["",person]: return {"ok":false,"code":"held_by_other"}
	return {"ok":true}

func inspect(person: String, id: String) -> Dictionary:
	var accessible:=_access(person,id)
	if not accessible.ok: return accessible
	var contents: RefCounted=containers[id].record.contents
	return {"ok":true,"material":contents.material,"quantity":contents.count,"capacity":contents.capacity}

func transfer(person: String, source: String, target: String, quantity: int) -> Dictionary:
	if quantity<=0: return {"ok":false,"code":"invalid_quantity"}
	for id in [source,target]:
		var accessible:=_access(person,id)
		if not accessible.ok: return accessible
	if source==target: return {"ok":false,"code":"same_container"}
	if containers[source].record.holder!=person: return {"ok":false,"code":"source_not_held"}
	var result: Dictionary=containers[source].record.contents.transfer_to(containers[target].record.contents,quantity)
	if not result.ok: return result
	for id in [source,target]:
		var changed: Callable=containers[id].changed
		if changed.is_valid(): changed.call()
	sim.perception.observe(person)
	sim._sync(person)
	return result
