extends RefCounted
## 简化操作范围以躯干附近为中心，不能从脚底测球距误拒绝眼前的果实。
const RADIUS_M:=1.6
const HEIGHT_M:=.9
static func distance(actor: Node3D, target: Vector3) -> float:
 return (actor.global_position+Vector3.UP*HEIGHT_M).distance_to(target)
static func reachable(actor: Node3D, target: Vector3) -> bool:
 return distance(actor,target)<=RADIUS_M
