extends RefCounted
## 结算资源与内容物；近距、视线、归属决定可操作性，骨骼只负责表现。
signal fact(event: Dictionary)
const INTERACTION_RANGE_M=preload("res://scripts/skills/interaction_range.gd").RADIUS_M
const EFFECTS={"food":{"hunger":45.0},"water":{"thirst":45.0}}
var sim: Node
var supplies: Dictionary={}

func register_supply(key: String, material: String, anchor: Node3D, offset: Vector3, take: Callable, flowing: bool=false) -> void:
	assert(not supplies.has(key) and take.is_valid())
	supplies[key]={"material":material,"anchor":anchor,"offset":offset,"take":take,"flowing":flowing}


func held_unit(id: String) -> Dictionary:
	return sim.gathering.hands.get(id,{})

func _known_visible(id: String, source: String, at: Vector3) -> bool:
	if sim.content_interaction.containers.has(source) and sim.content_interaction.containers[source].record.holder==id: return true
	return not sim.perception.known(id,source).is_empty() and sim.perception.sees(id,at)

func contact_point(id: String, source: String) -> Dictionary:
	var owned: bool=sim.content_interaction.containers.has(source) and sim.content_interaction.containers[source].record.holder==id
	if not owned and sim.perception.known(id,source).is_empty():return {"ok":false,"code":"not_observed"}
	var at: Vector3
	if sim.content_interaction.containers.has(source): at=sim.content_interaction.opening_position(source)
	elif supplies.has(source): at=supplies[source].anchor.to_global(supplies[source].offset)
	else: return {"ok":false,"code":"unknown_source"}
	if not _known_visible(id,source,at): return {"ok":false,"code":"not_observed"}
	return {"ok":true,"position":at}

func access_source(id: String, source: String) -> Dictionary:
	var point:=contact_point(id,source)
	if not point.ok:return point
	if sim.content_interaction.containers.has(source):
		var holder: String=sim.content_interaction.containers[source].record.holder
		if holder not in ["",id]:return {"ok":false,"code":"held_by_other"}
	var distance: float=preload("res://scripts/skills/interaction_range.gd").distance(sim.actors[id].body,point.position)
	if distance>INTERACTION_RANGE_M:return {"ok":false,"code":"out_of_reach","distance_m":distance,"interaction_range_m":INTERACTION_RANGE_M}
	return {"ok":true,"code":"source_accessible"}

func take_unit(id: String, source: String) -> Dictionary:
	var hand: String=sim.gathering.free_unit_hand(id)
	if hand.is_empty(): return {"ok":false,"code":"hand_occupied"}
	var contact:=access_source(id,source)
	if not contact.ok: return contact
	var item: Dictionary
	if sim.content_interaction.containers.has(source):
		var entry: Dictionary=sim.content_interaction.containers[source]
		if entry.record.holder not in ["",id]: return {"ok":false,"code":"held_by_other"}
		var removed: Dictionary=entry.record.contents.take()
		if not removed.ok: return removed
		item=removed.item;item["material"]=entry.record.contents.material
		if is_instance_valid(item.get("visual")) and item.visual.get_parent()!=sim.scene: item.visual.reparent(sim.scene,true)
		if entry.changed.is_valid(): entry.changed.call()
	elif supplies.has(source):
		var obtained: Dictionary=supplies[source].take.call(id)
		if not obtained.ok: return obtained
		item=obtained.item;item["material"]=supplies[source].material
	else: return {"ok":false,"code":"unsupported_source"}
	item["material"]=item.get("material","food")
	if not is_instance_valid(item.get("visual")):
		item["visual"]=sim._fruit();sim.scene.add_child(item.visual)
		if item.material=="water":
			var paint:=StandardMaterial3D.new();paint.albedo_color=Color(0.2,0.5,0.9,0.7);item.visual.material_override=paint
	elif item.visual.get_parent()!=sim.scene: item.visual.reparent(sim.scene,true)
	item["hand"]=hand
	sim.gathering.hands[id]=item
	sim._sync(id)
	fact.emit({"kind":"taken","person_id":id,"material":item.material,"source":source,"quantity":1,"source_event_id":sim.actors[id].event_id})
	return {"ok":true,"code":"unit_taken","hand":hand,"material":item.material,"source":source}

func put_unit(id: String, target: String) -> Dictionary:
	var item:=held_unit(id)
	if item.is_empty(): return {"ok":false,"code":"empty_hand"}
	var contact:=access_source(id,target)
	if not contact.ok: return contact
	var destination: RefCounted
	if sim.content_interaction.containers.has(target):
		var record: Dictionary=sim.content_interaction.containers[target].record
		if record.holder not in ["",id]: return {"ok":false,"code":"held_by_other"}
		destination=record.contents
	else: return {"ok":false,"code":"not_a_container"}
	if destination.material!=item.get("material","food"): return {"ok":false,"code":"incompatible_contents"}
	var inserted: Dictionary=destination.add(item)
	if not inserted.ok: return inserted
	sim.gathering.hands.erase(id)
	var changed: Callable=sim.content_interaction.containers[target].changed
	if changed.is_valid(): changed.call()
	sim._sync(id)
	fact.emit({"kind":"stored","person_id":id,"material":item.material,"target":target,"quantity":1,"origin":item.get("origin",{}),"source_event_id":sim.actors[id].event_id})
	return {"ok":true,"code":"unit_stored","target":target,"material":item.get("material","food")}

func consume_unit(id: String) -> Dictionary:
	var item:=held_unit(id)
	if item.is_empty(): return {"ok":false,"code":"empty_hand"}
	var material: String=item.get("material","food")
	if not EFFECTS.has(material): return {"ok":false,"code":"not_consumable"}
	sim.gathering.hands.erase(id)
	return _consume(id,item,material)

func consume_contents(id: String, object: String) -> Dictionary:
	if not sim.content_interaction.containers.has(object):return {"ok":false,"code":"unknown_container"}
	var entry: Dictionary=sim.content_interaction.containers[object]
	if entry.record.holder!=id:return {"ok":false,"code":"not_held"}
	var material: String=entry.record.contents.material
	if not EFFECTS.has(material):return {"ok":false,"code":"not_consumable"}
	var taken: Dictionary=entry.record.contents.take()
	if not taken.ok:return taken
	if entry.changed.is_valid():entry.changed.call()
	return _consume(id,taken.item,material)

func _consume(id: String, item: Dictionary, material: String) -> Dictionary:
	var origin: Dictionary=item.get("origin",{}).duplicate(true)
	if is_instance_valid(item.get("visual")):item.visual.queue_free()
	for need in EFFECTS[material]: sim.store.people[id].needs[need]=maxf(0,sim.store.people[id].needs[need]-EFFECTS[material][need])
	if material=="food": sim.eaten+=1
	else: sim.water.consumed+=1
	sim._sync(id)
	fact.emit({"kind":"consumed","person_id":id,"material":material,"quantity":1,"origin":origin,"source_event_id":sim.actors[id].event_id})
	return {"ok":true,"code":"consumed","material":material,"quantity":1}

func fill_container(id: String, source: String, target: String) -> Dictionary:
	if sim.perception.known(id,source).is_empty():return {"ok":false,"code":"not_observed"}
	if not supplies.has(source) or not supplies[source].flowing or not sim.content_interaction.containers.has(target): return {"ok":false,"code":"unsupported_source"}
	var record: Dictionary=sim.content_interaction.containers[target].record
	if record.holder!=id or record.contents.material!=supplies[source].material: return {"ok":false,"code":"incompatible_or_unheld"}
	var accessible:=access_source(id,source)
	if not accessible.ok:return accessible
	var quantity: int=record.contents.free_space
	var filled:=0
	for index in quantity:
		var obtained: Dictionary=supplies[source].take.call(id)
		if not obtained.ok: break
		obtained.item["material"]=supplies[source].material
		var added: Dictionary=record.contents.add(obtained.item)
		assert(added.ok)
		filled+=1
	if filled>0:fact.emit({"kind":"filled","person_id":id,"material":record.contents.material,"quantity":filled,"target":target,"source_event_id":sim.actors[id].event_id})
	return {"ok":filled>0 or quantity==0,"code":"filled" if filled>0 or quantity==0 else "source_empty","quantity":filled}
