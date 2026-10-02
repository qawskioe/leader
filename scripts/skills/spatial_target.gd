extends RefCounted
## 物品用ID；空间目标只接受绑定观察时刻的人物相对坐标，不解释旧世界偏移。
static func valid(value: Variant, max_component: float=10.0) -> bool:
	if value is String: return not value.is_empty() and value.length()<=150
	if not value is Dictionary or value.size()!=2 or not value.get("observation_id") is String or not valid(value.observation_id): return false
	var at: Variant=value.get("position")
	if not at is Dictionary or at.size()!=3: return false
	for axis in ["x","y","z"]:
		if not (at.get(axis) is float or at.get(axis) is int) or not is_finite(at[axis]) or absf(at[axis])>max_component: return false
	return true
static func position(value: Dictionary) -> Vector3:
	return Vector3(value.position.x,value.position.y,value.position.z)
static func key(value: Dictionary) -> String:
	return value.observation_id+"/"+JSON.stringify(value.position)
