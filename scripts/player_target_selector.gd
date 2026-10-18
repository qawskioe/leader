extends RefCounted
## 输入适配只选准星目标；合法性和实际效果仍由对应世界操作检查。
var camera: Camera3D
var target:=""
var best_score:=INF
func _init(view: Camera3D) -> void:camera=view
func consider(key: String, at: Vector3, range_m: float, alignment_min: float, ray_radius: float=INF) -> void:
	var offset:=at-camera.global_position
	var distance:=offset.length()
	if distance<=0 or distance>=range_m:return
	var forward: Vector3=-camera.global_basis.z
	var alignment:=forward.dot(offset/distance)
	if alignment<=alignment_min:return
	if (offset-forward*forward.dot(offset)).length()>=ray_radius:return
	var score:=(1.0-alignment)*100.0+distance*.01
	if score<best_score:
		best_score=score;target=key
