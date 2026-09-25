extends RefCounted
## 人物局部的骨骼执行器；技能指定姿态和接触目标，本地逐帧插值。
var actor: Dictionary
var skeleton: Skeleton3D
var held_water: MeshInstance3D
var changed:=false
var target_rig: Node3D
var contacts: Dictionary={}
var hand_frames: Dictionary={}
const LIMITS={"Hips":80.0,"Spine":65.0,"Chest":65.0,"Neck":50.0,"Head":60.0,"UpperArm.L":155.0,"UpperArm.R":155.0,"Forearm.L":145.0,"Forearm.R":145.0,"Hand.L":75.0,"Hand.R":75.0,"Thigh.L":110.0,"Thigh.R":110.0,"Shin.L":140.0,"Shin.R":140.0,"Foot.L":60.0,"Foot.R":60.0}

func initialize(value: Dictionary, person_id: String) -> void:
	actor=value;skeleton=actor.skeleton
	var landmarks: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_landmarks.json"))[person_id]
	for name in landmarks:
		var bone: String="Head" if name=="mouth" else name
		var p: Array=landmarks[name]
		contacts[name]=skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse()*Vector3(p[0],p[1],p[2])
	var frames: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/hand_frames.json"))[person_id]
	for hand in frames:
		var f: Dictionary=frames[hand]
		var wrist:=Vector3(f.wrist[0],f.wrist[1],f.wrist[2])
		var palm:=Vector3(f.palm[0],f.palm[1],f.palm[2])
		var edge:=Vector3(f.side[0],f.side[1],f.side[2])
		var forward:=(palm-wrist).normalized()
		var normal:=forward.cross(edge-palm).normalized()
		# 静止姿态掌面朝向身体；由同一网格定位点推导，不假设导入骨骼轴。
		if normal.dot(Vector3.LEFT if hand=="Hand.L" else Vector3.RIGHT)<0: normal=-normal
		var frame:=Basis(forward.cross(normal).normalized(),forward,normal).orthonormalized()
		hand_frames[hand]=skeleton.get_bone_global_rest(skeleton.find_bone(hand)).basis.inverse()*frame

static func seconds(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value>=0.2 and value<=5.0

func start() -> void:
	stop_target_rig()
	# stop() 默认会恢复动画初始姿态；多步骤技能必须保留上一阶段的骨骼状态。
	if actor.animation.is_playing(): actor.animation.stop(true)
	actor.stage="skill_body"

func point(bone: String) -> Vector3:
	var index:=skeleton.find_bone(bone)
	var pose: Transform3D=target_rig.final_poses[index].global if is_instance_valid(target_rig) and target_rig.final_poses.has(index) else skeleton.get_bone_global_pose(index)
	return skeleton.to_global(pose*contacts.get(bone,Vector3.ZERO))

func begin_target_reach(host: Node, hand: String) -> void:
	start()
	target_rig=preload("res://scripts/rig/target_rig.gd").new();host.add_child(target_rig)
	target_rig.initialize(skeleton);target_rig.controlled_hands=[hand]
	changed=true

func target_contact(hand: String, at: Vector3) -> void:
	# IK目标是手腕，交互目标是掌心；由程序换算，不让模型猜偏移。
	var target: Node3D=target_rig.targets[hand]
	target.global_position=at-target.global_basis*contacts.get(hand,Vector3.ZERO)

func stop_target_rig() -> void:
	if is_instance_valid(target_rig):
		target_rig.detach();target_rig.free()
	target_rig=null

func mouth() -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Head"))*contacts.mouth)

func mouth_forward() -> Vector3:
	var head:=skeleton.find_bone("Head")
	return (skeleton.global_basis*skeleton.get_bone_global_pose(head).basis*skeleton.get_bone_global_rest(head).basis.inverse()*Vector3.FORWARD*-1.0).normalized()

func drinking_target() -> Vector3:
	# 掌心是盛水位置，不应塞到嘴的内部定位点；留出掌指体积。
	return mouth()+mouth_forward()*0.09-Vector3.UP*0.025

func cup_alignment(hand: String) -> float:
	var frame: Basis=skeleton.global_basis*skeleton.get_bone_global_pose(skeleton.find_bone(hand)).basis*hand_frames[hand]
	return frame.z.normalized().dot(Vector3.UP)

func head_clearance(hand: String) -> float:
	# 保守头部代理体，仅用于拒绝明显穿头，不能声称是完整网格碰撞。
	var center:=mouth()+Vector3.UP*0.065-mouth_forward()*0.035
	var elbow:=point("Forearm."+hand.trim_prefix("Hand."))
	var wrist:=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(hand)).origin)
	var nearest:=Geometry3D.get_closest_point_to_segment(center,elbow,wrist)
	return nearest.distance_to(center)-0.085

func validate_pose(pose: Variant) -> bool:
	if not pose is Dictionary or pose.is_empty() or pose.size()>19: return false
	for bone in pose:
		if bone=="lower_hips":
			if not (pose[bone] is float or pose[bone] is int) or not is_finite(pose[bone]) or pose[bone]<0 or pose[bone]>0.55: return false
			continue
		if not LIMITS.has(bone) or not pose[bone] is Dictionary or pose[bone].size()!=3: return false
		for axis in ["x","y","z"]:
			var value: Variant=pose[bone].get(axis)
			if not (value is float or value is int) or not is_finite(value) or absf(value)>LIMITS[bone]: return false
	return true

func snapshot() -> Dictionary:
	var result: Dictionary={}
	for bone in LIMITS:
		result[bone]=skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
	result["hips_position"]=skeleton.get_bone_pose_position(skeleton.find_bone("Hips"))
	result["feet"]={"L":point("Foot.L"),"R":point("Foot.R")}
	return result

func apply_pose(pose: Dictionary, initial: Dictionary, weight: float) -> void:
	for bone in pose:
		if bone=="lower_hips": continue
		var index:=skeleton.find_bone(bone)
		var v: Dictionary=pose[bone]
		var target:=skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion.from_euler(Vector3(deg_to_rad(v.x),deg_to_rad(v.y),deg_to_rad(v.z)))
		skeleton.set_bone_pose_rotation(index,initial[bone].slerp(target,weight))
	if pose.has("lower_hips"):
		var hips:=skeleton.find_bone("Hips")
		var parent:=skeleton.get_bone_parent(hips)
		var down:=skeleton.get_bone_global_pose(parent).basis.inverse()*Vector3(0,-float(pose.lower_hips),0)
		skeleton.set_bone_pose_position(hips,initial.hips_position.lerp(skeleton.get_bone_rest(hips).origin+down,weight))
		for side in ["L","R"]: solve("Foot."+side,["Shin."+side,"Thigh."+side],initial.feet[side])
	changed=true

func solve(end: String, joints: Array, at: Vector3) -> void:
	var target:=skeleton.to_local(at)
	var tip:=skeleton.find_bone(end)
	for iteration in 12:
		for bone: String in joints:
			var joint:=skeleton.find_bone(bone)
			var origin:=skeleton.get_bone_global_pose(joint).origin
			var a: Vector3=skeleton.get_bone_global_pose(tip)*contacts.get(end,Vector3.ZERO)-origin
			var b:=target-origin
			if a.length()<0.001 or b.length()<0.001: continue
			var rotation:=Quaternion(a.normalized(),b.normalized())
			var parent:=skeleton.get_bone_global_pose(skeleton.get_bone_parent(joint)).basis.get_rotation_quaternion()
			var next: Quaternion=(parent.inverse()*rotation*parent*skeleton.get_bone_pose_rotation(joint)).normalized()
			var rest:=skeleton.get_bone_rest(joint).basis.get_rotation_quaternion()
			var angle:=rest.angle_to(next)
			var limit:=deg_to_rad(float(LIMITS[bone]))
			if angle>limit: next=rest.slerp(next,limit/angle)
			skeleton.set_bone_pose_rotation(joint,next)
	changed=true

func reach(hand: String, at: Vector3, _upper_body: bool) -> void:
	var side:=hand.trim_prefix("Hand.")
	var joints: Array=["Forearm."+side,"UpperArm."+side]
	# 伸手不能偷偷改写模型已指定的胸腰姿态。够不到时返回失败，由技能调整身体。
	solve(hand,joints,at)
	update_water(hand)

func show_water(hand: String) -> void:
	held_water=MeshInstance3D.new()
	var mesh:=SphereMesh.new();mesh.radius=0.055;mesh.height=0.035
	held_water.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.15,0.65,0.95)
	held_water.material_override=material
	skeleton.add_child(held_water)
	update_water(hand)

func update_water(hand: String) -> void:
	if is_instance_valid(held_water): held_water.global_position=point(hand)

func clear_water() -> void:
	if is_instance_valid(held_water): held_water.queue_free()
	held_water=null

func reset() -> void:
	stop_target_rig()
	clear_water()
	skeleton.reset_bone_poses()

static func xyz(value: Vector3) -> Dictionary:
	return {"x":value.x,"y":value.y,"z":value.z}

static func describe(s: Skeleton3D) -> Dictionary:
	var bones: Dictionary={}
	for index in s.get_bone_count():
		var parent:=s.get_bone_parent(index)
		var rest:=s.get_bone_rest(index)
		bones[s.get_bone_name(index)]={"parent":s.get_bone_name(parent) if parent>=0 else "","rest_position":xyz(rest.origin),"rest_rotation_degrees":xyz(rest.basis.get_euler()*180.0/PI),"current_position":xyz(s.get_bone_pose_position(index)),"current_rotation_degrees":xyz(s.get_bone_pose_rotation(index).get_euler()*180.0/PI)}
	return {"bones":bones,"coordinate_rule":"pose_bones 的 rotation 是相对 rest 的父骨骼局部欧拉角（度，Godot YXZ 顺序）；position 是相对 rest 的父骨骼局部位移（米）。未指定字段与骨骼保持当前值。骨架前方+Z，上方+Y；关节局部轴按rest旋转，不能当世界轴。","limitations":"只控制此骨架已有骨骼，不创建骨骼或修改蒙皮；位移会改变骨段长度，需自行保持身体形状。不会自动锁脚或修正手腕。骨架内位移不移动角色物理碰撞体；角色位移仍用世界移动接口。"}

func valid_vector(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3: return false
	for axis in ["x","y","z"]:
		if not (value.get(axis) is float or value.get(axis) is int) or not is_finite(value[axis]): return false
	return true

func validate_bones(pose: Variant) -> bool:
	if not pose is Dictionary or pose.size()>skeleton.get_bone_count(): return false
	for bone in pose:
		if skeleton.find_bone(bone)<0 or not pose[bone] is Dictionary or pose[bone].is_empty(): return false
		for field in pose[bone]:
			if field not in ["rotation","position"] or not valid_vector(pose[bone][field]): return false
	return true

func bone_snapshot() -> Dictionary:
	var values: Dictionary={}
	for index in skeleton.get_bone_count():
		values[skeleton.get_bone_name(index)]={"rotation":skeleton.get_bone_pose_rotation(index),"position":skeleton.get_bone_pose_position(index)}
	return values

func apply_bones(pose: Dictionary, initial: Dictionary, weight: float) -> void:
	for bone in pose:
		var index:=skeleton.find_bone(bone)
		var rest:=skeleton.get_bone_rest(index)
		if pose[bone].has("rotation"):
			var v: Dictionary=pose[bone].rotation
			var target:=rest.basis.get_rotation_quaternion()*Quaternion.from_euler(Vector3(deg_to_rad(v.x),deg_to_rad(v.y),deg_to_rad(v.z)))
			skeleton.set_bone_pose_rotation(index,initial[bone].rotation.slerp(target,weight))
		if pose[bone].has("position"):
			var v: Dictionary=pose[bone].position
			skeleton.set_bone_pose_position(index,initial[bone].position.lerp(rest.origin+Vector3(v.x,v.y,v.z),weight))
	changed=true
