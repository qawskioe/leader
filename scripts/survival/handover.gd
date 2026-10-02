extends Node
## 交接只转移同一个世界物体；NPC接收意愿经正常人物决策返回。
signal offered(event: Dictionary)
var sim: Node
var pending: Dictionary={}
var units: Dictionary={}

func _held(giver: String, object: String) -> bool:
	if units.has(object): return is_same(sim.gathering.hands.get(giver,{}),units[object])
	return sim.world_objects.objects.has(object) and sim.world_objects.objects[object].holder==giver

func give_unit(giver: String, recipient: String) -> Dictionary:
	var item: Dictionary=sim.gathering.hands.get(giver,{})
	if item.is_empty(): return {"ok":false,"code":"empty_hand"}
	var token:="unit_"+str(Time.get_ticks_usec())
	units[token]=item
	var result: Dictionary=await give(giver,token,recipient)
	units.erase(token)
	return result

func cancel_giver(giver: String) -> void:
	for offer in pending.values():
		if offer.giver==giver and offer.answer.is_empty(): offer.answer={"ok":false,"code":"cancelled","message":"递交已取消，物品保留"}

func _receiving_hand(object: String, recipient: String) -> String:
	# NPC散装物资与实体物品均可用空闲手；散装物资仍限一份。
	if units.has(object):return sim.gathering.free_unit_hand(recipient)
	var hands: Array=["Hand.R"] if recipient=="player" else ["Hand.R","Hand.L"]
	for hand in hands:
		if sim.water.free_hand(recipient,hand):return hand
	return ""

func _check(giver: String, object: String, recipient: String) -> Dictionary:
	if not _held(giver,object):return {"ok":false,"code":"not_held","message":"物品不在本人手中，未发生交付"}
	if recipient==giver or (recipient!="player" and not sim.actors.has(recipient)):
		return {"ok":false,"code":"invalid_recipient","message":"接收者无效"}
	if sim.perception.known(giver,"person/"+recipient).is_empty():return {"ok":false,"code":"unknown_recipient","message":"本人没有接收者的观察或记忆"}
	var target: Node3D=sim.water.owner(recipient)
	if not sim.gathering._reachable(giver,target.global_position+Vector3.UP,2.0):
		return {"ok":false,"code":"out_of_reach","message":"尚未到可交接的距离，物品仍在本人手中；需要先靠近接收者"}
	var receiving_hand:=_receiving_hand(object,recipient)
	if receiving_hand.is_empty():return {"ok":false,"code":"recipient_occupied","message":"接收者没有可用的接物手，需先腾出手；未发生交付"}
	if recipient!="player" and sim.actors[recipient].stage!="idle":return {"ok":false,"code":"recipient_busy","message":"对方仍在执行动作，尚未交付"}
	return {"ok":true,"hand":receiving_hand}

func give(giver: String, object: String, recipient: String) -> Dictionary:
	var checked:=_check(giver,object,recipient)
	if not checked.ok:return checked
	# 玩家先前的请求由人物判断；玩家空手时沿用现有交接规则。NPC必须另作接受决定。
	if recipient=="player":return _transfer(giver,object,recipient)
	var position: Vector3=units[object].visual.global_position if units.has(object) else sim.world_objects.grip_position(object)
	var rid: RID=RID() if units.has(object) else sim.world_objects.objects[object].body.get_rid()
	if not sim.perception.sees(recipient,position,rid):
		return {"ok":false,"code":"not_seen_by_recipient","message":"对方尚未看见递出的物品，请先取得对方注意"}
	var key:="handover_%d"%Time.get_ticks_usec()
	var name: String=("一份水" if units[object].get("material")=="water" else "一份食物") if units.has(object) else sim.world_objects.observable_extra(object).name
	var offer:={"giver":giver,"object":object,"recipient":recipient,"answer":{},"expires":Time.get_ticks_msec()+45000}
	pending[key]=offer
	offered.emit({"id":key,"kind":"item_offer","item_kind":"object","speaker":giver,"listeners":[recipient],"text":str(sim.store.people[giver].name)+"将"+name+"递给你，仍在对方手中。由你决定接受或拒绝，尚未交付。"})
	while offer.answer.is_empty():
		await get_tree().process_frame
		# 接受回调可能已完成真实转移；不能再用旧持有人校验覆盖其成功结果。
		if not offer.answer.is_empty():break
		checked=_check(giver,object,recipient)
		if not checked.ok:offer.answer=checked;break
		if Time.get_ticks_msec()>offer.expires:
			offer.answer={"ok":false,"code":"offer_expired","message":"等待接收决定超时，物品未交付"};break
	pending.erase(key)
	return offer.answer

func respond(key: String, recipient: String, accept: bool) -> Dictionary:
	if not pending.has(key) or pending[key].recipient!=recipient or not pending[key].answer.is_empty():
		return {"ok":false,"code":"offer_expired","message":"这次递交已失效，未发生交付"}
	var offer: Dictionary=pending[key]
	if Time.get_ticks_msec()>offer.expires:
		offer.answer={"ok":false,"code":"offer_expired","message":"这次递交已超时，未发生交付"}
	elif not accept:
		offer.answer={"ok":false,"code":"declined","message":"对方拒绝接收，物品仍在递出者手中"}
	else:offer.answer=_transfer(offer.giver,offer.object,recipient)
	return offer.answer

func _pose(object: String, recipient: String, hand_name: String) -> Transform3D:
	if recipient=="player":return sim.world_objects.player_hold_transform(object,sim.scene.get_node("Player"))
	return sim.world_objects.carry_transform(object,sim.actors[recipient].body,hand_name)

func _transfer(giver: String, object: String, recipient: String) -> Dictionary:
	var checked:=_check(giver,object,recipient)
	if not checked.ok:return checked
	if units.has(object):
		var item: Dictionary=units[object]
		sim.gathering.hands.erase(giver);item["hand"]=checked.hand;sim.gathering.hands[recipient]=item
		item.origin["giver_id"]=giver;item.origin["recipient_id"]=recipient
		var assistance: Dictionary=sim.actors[giver].assistance if sim.actors.has(giver) else {}
		if assistance.get("requester_id")==recipient: item.origin.merge(assistance,true)
		for id in [giver,recipient]:
			if sim.actors.has(id):sim._sync(id)
		var material: String=item.get("material","food")
		sim.life_world.fact.emit({"kind":"given","person_id":giver,"recipient_id":recipient,"material":material,"quantity":1,"origin":item.origin.duplicate(true),"source_event_id":sim.actors[giver].event_id if sim.actors.has(giver) else ""})
		return {"ok":true,"code":"transferred_unit","recipient_id":recipient,"material":material,"message":"同一份物资已交到接收者手中，尚未被食用"}
	var result: Dictionary=sim.world_objects.transfer_attachment(object,giver,recipient,checked.hand,_pose.bind(object,recipient,checked.hand))
	assert(result.ok,"校验后同步交接不应失败")
	result["message"]="同一物品已实际交到接收者手中；未取水、填充或复制物品"
	result["recipient_id"]=recipient
	if sim.content_interaction.containers.has(object):
		var contents: RefCounted=sim.content_interaction.containers[object].record.contents
		var assistance: Dictionary=sim.actors[giver].assistance if sim.actors.has(giver) else {}
		for item in contents.items:
			if not item.has("origin"):item.origin={}
			item.origin.merge({"giver_id":giver,"recipient_id":recipient},true)
			if assistance.get("requester_id")==recipient:item.origin.merge(assistance,true)
		if contents.count>0:sim.life_world.fact.emit({"kind":"given","person_id":giver,"recipient_id":recipient,"material":contents.material,"quantity":contents.count,"origin":assistance.duplicate(true),"source_event_id":sim.actors[giver].event_id if sim.actors.has(giver) else ""})
	for person in [giver,recipient]:
		if person!="player":sim.perception.observe(person);sim._sync(person)
	return result
