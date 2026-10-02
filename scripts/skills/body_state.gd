extends RefCounted
## 普通交互的只读身体参照；不包含IK、骨骼编辑或动作执行。
var actor: Dictionary
var skeleton: Skeleton3D
func initialize(value: Dictionary, _person_id: String) -> void:
 actor=value;skeleton=actor.skeleton
func point(hand: String) -> Vector3:
 assert(hand in ["Hand.L","Hand.R"])
 return actor.body.to_global(Vector3(.42 if hand=="Hand.L" else -.42,.95,.60))
func bone_global(name: String) -> Transform3D:
 return skeleton.get_bone_global_pose(skeleton.find_bone(name))
static func seconds(value: Variant) -> bool:
 return (value is float or value is int) and is_finite(value) and value>=.2 and value<=5
static func xyz(value: Vector3) -> Dictionary:
 return {"x":value.x,"y":value.y,"z":value.z}
