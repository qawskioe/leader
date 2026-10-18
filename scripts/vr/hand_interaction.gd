extends RefCounted
## 握键调用真实资源接口；与 NPC 共用占用、距离、数量及来源检查。
var sim: Node
var held: Dictionary = {}
var last_release_result: Dictionary = {}

func candidate(at: Vector3) -> Array:
	# 内部果实先独立命中，篮子抓握点只在外沿，开口不作为提篮目标。
	var closest: Array=[]
	var distance:=0.22
	for key in sim.gathering.baskets:
		var basket: Dictionary=sim.gathering.baskets[key]
		if basket.holder not in ["","player"]: continue
		for index in basket.contents.items.size():
			var position: Vector3=basket.contents.items[index].visual.global_position
			var d:=at.distance_to(position)
			if d<distance:
				distance=d; closest=["contained",key,index,position]
	if not closest.is_empty(): return closest
	var options: Array=[]
	for key in sim.gathering.baskets:
		var basket: Dictionary=sim.gathering.baskets[key]
		if basket.holder!="": continue
		for offset in [Vector3(-0.34,0.4,0),Vector3(0.34,0.4,0)]:
			options.append(["basket",key,-1,basket.root.to_global(offset)])
	for key in sim.gathering.resources:
		var fruit: Dictionary=sim.gathering.resources[key]
		if fruit.available: options.append(["fruit",key,-1,fruit.mesh.global_position])
	for key in sim.gathering.loose_food:
		options.append(["loose",key,-1,sim.gathering.loose_food[key].visual.global_position])
	for key in sim.water.bags:
		var bag: Dictionary=sim.water.bags[key]
		if bag.holder=="": options.append(["water",key,-1,bag.root.global_position])
	distance=0.23
	for item in options:
		var d: float=at.distance_to(item[3])
		if d<distance: closest=item; distance=d
	return closest

func grab(side: String, at: Vector3) -> String:
	assert(side in ["left","right"])
	if held.has(side): return "这只手已有物品"
	var best:=candidate(at)
	if best.is_empty(): return "手靠近篮子外沿、果实或水袋，再按握键"
	var ok := false
	var hand:="Hand.L" if side=="left" else "Hand.R"
	match best[0]:
		"contained": ok=sim.gathering.take_from_basket("player",best[1],best[2],hand)
		"basket": ok = sim.gathering.pickup("player",best[1],hand)
		"fruit": ok = sim.gathering.harvest("player",best[1],hand)
		"loose": ok = sim.gathering.take_loose_food("player",best[1],hand)
		"water": ok = sim.water.pickup("player",best[1],hand)
	if not ok: return "无法拿取：检查篮子、空手、容量和遮挡"
	held[side] = {"kind":"fruit" if best[0] in ["contained","loose"] else best[0],"key":best[1]}
	return "已拿起 · 果实移到篮内再松开" if held[side].kind=="fruit" else "已拿起 · 松开握键放下"

func release(side: String, at: Vector3) -> String:
	last_release_result.clear()
	if not held.has(side): return ""
	var item: Dictionary = held[side]
	var ok := false
	var stored:=false
	match item.kind:
		"fruit":
			for key in sim.gathering.baskets:
				var basket: Dictionary=sim.gathering.baskets[key]
				if basket.holder in ["","player"] and at.distance_to(basket.root.to_global(Vector3(0,0.25,0)))<0.4:
					ok=sim.gathering.load_hand("player",key)
					if ok:stored=true;break
			if not ok:
				for target in sim.actors:
					if at.distance_to(sim.actors[target].body.global_position+Vector3(0,1.1,0))<0.75:
						var offer: String=sim.gathering.offer_food(target)
						if offer!="": return "正在递给"+sim.store.people[target].name+"，等待对方决定；移开手可撤回"
			# 松开到空处与PC共用真实落地结算；不是强制装篮或递交。
			if not ok:ok=sim.gathering.drop_food("player")

		"basket":
			last_release_result=sim.gathering.drop_result("player")
			ok=last_release_result.ok
		"water":
			for target in sim.actors:
				if at.distance_to(sim.actors[target].body.global_position+Vector3(0,1.1,0))<0.75:
					var offer: String=sim.gathering.offer_item(target,"water")
					if offer!="": return "正在递水袋，等待对方决定；移开手可撤回"
			last_release_result=sim.water.drop_result("player")
			ok=last_release_result.ok
	if ok:
		held.erase(side)
		return "已装篮" if stored else "已放下"
	if not last_release_result.is_empty():return release_failure(item.kind,last_release_result)
	return "未放下：检查手中果实和周围阻挡，再握住并松开"

static func release_failure(kind: String, result: Dictionary) -> String:
	var name:="水袋" if kind=="water" else "篮子"
	if result.code=="not_held":return "手中已经没有"+name
	assert(result.code=="release_overlapping",str(result))
	var obstacles: PackedStringArray=[]
	if result.contacts.has("person"):obstacles.append("人物身体")
	if result.contacts.has("environment"):obstacles.append("地面或墙壁")
	if result.contacts.has("movable_object"):obstacles.append("其他物品")
	return name+"与"+"、".join(obstacles)+"重叠；把手移到空处，再握住并松开"

func transform_for(kind: String, fallback: Transform3D, rig: Node) -> Transform3D:
	for side in held:
		var item: Dictionary = held[side]
		if item.kind != kind: continue
		var hand: XRController3D = rig.left if side == "left" else rig.right
		var pose := hand.global_transform
		if kind == "basket": pose.origin -= Vector3(0,0.4,0)
		return pose
	return fallback

func reconcile() -> void:
	for side in held.keys():
		var kind: String=held[side].kind
		if (kind=="fruit" and not sim.gathering.hands.has("player")) or (kind=="basket" and sim.gathering.basket_for("player")=="") or (kind=="water" and sim.water.held("player")==""):
			held.erase(side)
	# 手柄绑定是世界持有关系的视图；读档或 NPC 递交不能留下只能看见、不能松手的物品。
	for id in sim.world_objects.objects:
		var item: Dictionary=sim.world_objects.objects[id]
		if item.holder!="player" or item.xr_kind not in ["basket","water"]:continue
		var present: bool=held.values().any(func(value):return value.kind==item.xr_kind)
		if present:continue
		var side:="left" if item.hand=="Hand.L" else "right"
		assert(not held.has(side),"世界持物槽与手柄持物视图冲突")
		held[side]={"kind":item.xr_kind,"key":id.get_slice("/",1)}
	# 散装物资也由世界持有关系恢复；别人递来或读档时不经过控制器grab。
	if sim.gathering.hands.has("player") and not held.values().any(func(value):return value.kind=="fruit"):
		var unit: Dictionary=sim.gathering.hands.player
		assert(unit.hand in ["Hand.L","Hand.R"])
		var side:="left" if unit.hand=="Hand.L" else "right"
		assert(not held.has(side),"世界散装物资槽与手柄持物视图冲突")
		held[side]={"kind":"fruit","key":""}
