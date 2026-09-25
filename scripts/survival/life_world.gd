extends RefCounted
## 只结算一次资源/内容物/身体接触，不选择路线或组织生活流程。
signal fact(event: Dictionary)
const CONTACT:=0.20
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

func _hand_contact(id: String, source: String, motor: RefCounted) -> Dictionary:
	var point:=contact_point(id,source)
	if not point.ok:
		# 记得旧位置可以伸手试探；只有实际触到才证实，不提供未接触的实时位置。
		if point.code!="not_observed" or sim.perception.known(id,source).is_empty():return point
		var at: Vector3=sim.content_interaction.opening_position(source) if sim.content_interaction.containers.has(source) else supplies[source].anchor.to_global(supplies[source].offset)
		if motor.point("Hand.R").distance_to(at)>CONTACT:return point
		return {"ok":true,"position":at,"sense":"touch"}
	var distance: float=motor.point("Hand.R").distance_to(point.position)
	if distance>CONTACT: return {"ok":false,"code":"hand_not_in_contact","distance_m":distance,"contact_limit_m":CONTACT}
	return point

func take_unit(id: String, source: String, motor: RefCounted) -> Dictionary:
	if not held_unit(id).is_empty() or sim.world_objects.held.has(id+"/Hand.R"): return {"ok":false,"code":"hand_occupied"}
	var contact:=_hand_contact(id,source,motor)
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
	sim.gathering.hands[id]=item
	sim._sync(id)
	fact.emit({"kind":"taken","person_id":id,"material":item.material,"source":source,"quantity":1,"source_event_id":sim.actors[id].event_id})
	return {"ok":true,"code":"unit_taken","material":item.material,"source":source}

func put_unit(id: String, target: String, motor: RefCounted) -> Dictionary:
	var item:=held_unit(id)
	if item.is_empty(): return {"ok":false,"code":"empty_hand"}
	var contact:=_hand_contact(id,target,motor)
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

func consume_unit(id: String, motor: RefCounted) -> Dictionary:
	var item:=held_unit(id)
	if item.is_empty(): return {"ok":false,"code":"empty_hand"}
	var material: String=item.get("material","food")
	if not EFFECTS.has(material): return {"ok":false,"code":"not_consumable"}
	var distance: float=motor.point("Hand.R").distance_to(motor.mouth())
	if distance>CONTACT: return {"ok":false,"code":"hand_not_at_mouth","distance_m":distance}
	sim.gathering.hands.erase(id)
	return _consume(id,item,material)

func consume_contents(id: String, object: String, motor: RefCounted) -> Dictionary:
	if not sim.content_interaction.containers.has(object):return {"ok":false,"code":"unknown_container"}
	var entry: Dictionary=sim.content_interaction.containers[object]
	if entry.record.holder!=id:return {"ok":false,"code":"not_held"}
	var material: String=entry.record.contents.material
	if not EFFECTS.has(material):return {"ok":false,"code":"not_consumable"}
	if sim.content_interaction.opening_position(object).distance_to(motor.mouth())>CONTACT:return {"ok":false,"code":"opening_not_at_mouth"}
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
	if sim.content_interaction.opening_position(target).distance_to(supplies[source].anchor.to_global(supplies[source].offset))>0.35: return {"ok":false,"code":"opening_not_at_source"}
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
