extends RefCounted
## 握键调用真实资源接口；与 NPC 共用占用、距离、数量及来源检查。
var sim: Node
var held: Dictionary = {}

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
	for key in sim.water.bags:
		var bag: Dictionary=sim.water.bags[key]
		if bag.holder=="": options.append(["water",key,-1,bag.root.global_position])
	distance=0.23
	for item in options:
		var d: float=at.distance_to(item[3])
		if d<distance: closest=item; distance=d
	return closest

func grab(side: String, at: Vector3) -> String:
	if held.has(side): return "这只手已有物品"
	var best:=candidate(at)
	if best.is_empty(): return "手靠近篮子外沿、果实或水袋，再按握键"
	var ok := false
	match best[0]:
		"contained": ok=sim.gathering.take_from_basket("player",best[1],best[2])
		"basket": ok = sim.gathering.pickup("player",best[1])
		"fruit": ok = sim.gathering.harvest("player",best[1])
		"water": ok = sim.water.pickup("player",best[1])
	if not ok: return "无法拿取：检查篮子、空手、容量和遮挡"
	held[side] = {"kind":"fruit" if best[0]=="contained" else best[0],"key":best[1]}
	return "已拿起 · 松开握键放下；果实移到篮内再松开"

func release(side: String, at: Vector3) -> String:
	if not held.has(side): return ""
	var item: Dictionary = held[side]
	var ok := false
	match item.kind:
		"fruit":
			for key in sim.gathering.baskets:
				var basket: Dictionary=sim.gathering.baskets[key]
				if basket.holder in ["","player"] and at.distance_to(basket.root.to_global(Vector3(0,0.25,0)))<0.4:
					ok=sim.gathering.load_hand("player",key)
					if ok: break
			if not ok:
				for target in sim.actors:
					if at.distance_to(sim.actors[target].body.global_position+Vector3(0,1.1,0))<0.75:
						var offer: String=sim.gathering.offer_food(target)
						if offer!="": return "正在递给"+sim.store.people[target].name+"，等待对方决定；移开手可撤回"

		"basket": ok = sim.gathering.drop("player")
		"water":
			for target in sim.actors:
				if at.distance_to(sim.actors[target].body.global_position+Vector3(0,1.1,0))<0.75:
					var offer: String=sim.gathering.offer_item(target,"water")
					if offer!="": return "正在递水袋，等待对方决定；移开手可撤回"
			ok=sim.water.drop("player")
	if ok:
		held.erase(side)
		return "已装篮" if item.kind == "fruit" else "已放下"
	return "未放下：果实需放入篮内，篮子下方需有空地；可再次握住再松开"

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
