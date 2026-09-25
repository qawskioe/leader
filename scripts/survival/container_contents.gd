extends RefCounted
## 简化世界中的离散“份”；每份携带原始来源/外观，不另外维护数量副本。
var material: String
var capacity: int
var items: Array[Dictionary]=[]
var count: int:
	get: return items.size()
var free_space: int:
	get: return capacity-items.size()

func _init(kind: String, limit: int) -> void:
	assert(not kind.is_empty() and limit>0)
	material=kind;capacity=limit

func add(item: Dictionary) -> Dictionary:
	if free_space<=0: return {"ok":false,"code":"container_full"}
	items.append(item)
	return {"ok":true,"code":"inserted"}

func take(index: int=0) -> Dictionary:
	if index<0 or index>=count: return {"ok":false,"code":"content_missing"}
	return {"ok":true,"code":"removed","item":items.pop_at(index)}

func transfer_to(destination: RefCounted, quantity: int) -> Dictionary:
	if destination==self: return {"ok":false,"code":"same_container"}
	if destination==null or destination.get_script()!=get_script(): return {"ok":false,"code":"invalid_container"}
	if quantity<=0: return {"ok":false,"code":"invalid_quantity"}
	if material!=destination.material: return {"ok":false,"code":"incompatible_contents"}
	if quantity>count: return {"ok":false,"code":"insufficient_contents"}
	if quantity>destination.free_space: return {"ok":false,"code":"container_full"}
	# 一次同步结算；所有检查通过后才修改两端，失败不能先取走一部分。
	for index in quantity: destination.items.append(items.pop_front())
	return {"ok":true,"code":"contents_transferred","material":material,"quantity":quantity,"source_count":count,"destination_count":destination.count}

func clear() -> void:
	items.clear()

func describe() -> Dictionary:
	return {"material":material,"quantity":count,"capacity":capacity}
