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
		return {"ok":false,"code":"not_observed"}
	return sim.life_world.access_source(person,id)

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
	if sim.actors.has(person):sim.perception.observe(person)
	sim.life_world._sync(person)
	sim.life_world.fact.emit({"kind":"stored","person_id":person,"material":result.material,"source":source,"target":target,"quantity":quantity,"source_event_id":sim.life_world._event(person)})
	return result
