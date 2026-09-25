extends Node3D
## 目标控制层：引擎TwoBoneIK求解四肢；目标、关节弯曲方向、末端朝向分别控制。
const LIMBS={"Hand.L":["UpperArm.L","Forearm.L"],"Hand.R":["UpperArm.R","Forearm.R"],"Foot.L":["Thigh.L","Shin.L"],"Foot.R":["Thigh.R","Shin.R"]}
var skeleton: Skeleton3D
var targets: Dictionary={}
var poles: Dictionary={}
var defaults: Dictionary={}
var solved: Dictionary={}
var constraints: Dictionary={}
var sample: Dictionary={}
var auto_posture:=true
var controlled_hands: Array=["Hand.L","Hand.R"]
var final_poses: Dictionary={}
var modifiers: Array[Node]=[]
var pelvis: Node3D
var _ends: SkeletonModifier3D
var _hip: Vector3
var _lean:=0.0
var planner=preload("res://scripts/rig/posture_planner.gd").new()

class EndFrames extends SkeletonModifier3D:
 var rig: Node3D
 func _process_modification() -> void:
  var s:=get_skeleton()
  for name in rig.targets:
   var index:=s.find_bone(name)
   var parent:=s.get_bone_global_pose(s.get_bone_parent(index)).basis.orthonormalized()
   var desired: Basis=s.global_basis.orthonormalized().inverse()*rig.targets[name].global_basis.orthonormalized()
   s.set_bone_pose_rotation(index,(parent.inverse()*desired).get_rotation_quaternion())
  rig.measure()
  rig.final_poses.clear()
  for index in s.get_bone_count():
   rig.final_poses[index]={"rotation":s.get_bone_pose_rotation(index),"position":s.get_bone_pose_position(index),"global":s.get_bone_global_pose(index)}

func initialize(s: Skeleton3D) -> void:
 skeleton=s;planner.initialize(s)
 process_priority=-10
 for name in LIMBS:
  var index:=skeleton.find_bone(name)
  assert(index>=0)
  var goal:=Node3D.new();goal.name=name.replace(".","_")+"Target";add_child(goal)
  goal.global_transform=skeleton.global_transform*skeleton.get_bone_global_rest(index)
  targets[name]=goal;defaults[name]=goal.global_transform
  var pole:=Node3D.new();pole.name=name.replace(".","_")+"Pole";add_child(pole)
  var root:=skeleton.get_bone_global_rest(skeleton.find_bone(LIMBS[name][0])).origin
  var side:=1.0 if name.ends_with(".L") else -1.0
  pole.global_position=skeleton.to_global(root+Vector3(side*0.5,-0.15,-0.6) if name.begins_with("Hand") else root+Vector3(0,0,1.0))
  poles[name]=pole
  var actual:=Node3D.new();actual.name=name.replace(".","_")+"Reachable";add_child(actual);actual.global_transform=goal.global_transform;solved[name]=actual
  var ik:=TwoBoneIK3D.new();ik.name=name.replace(".","_")+"IK";skeleton.add_child(ik);modifiers.append(ik)
  ik.setting_count=1
  ik.set_root_bone_name(0,LIMBS[name][0]);ik.set_middle_bone_name(0,LIMBS[name][1]);ik.set_end_bone_name(0,name)
  ik.set_target_node(0,ik.get_path_to(actual));ik.set_pole_node(0,ik.get_path_to(pole))
  ik.set_extend_end_bone(0,false)
 pelvis=Node3D.new();pelvis.name="PelvisTarget";add_child(pelvis)
 pelvis.global_position=skeleton.to_global(skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin)
 defaults["Hips"]=pelvis.global_position;_hip=skeleton.to_local(pelvis.global_position)
 _ends=EndFrames.new();_ends.rig=self;skeleton.add_child(_ends);modifiers.append(_ends)

func _process(delta: float) -> void:
 if skeleton==null:return
 skeleton.reset_bone_poses()
 var desired:=skeleton.to_local(pelvis.global_position)
 var wanted_lean:=0.0
 desired.y=clampf(desired.y,0.36,float(skeleton.to_local(defaults.Hips).y)+0.06)
 desired.x=clampf(desired.x,-0.18,0.18);desired.z=clampf(desired.z,-0.20,0.20)
 if auto_posture:
  var hands: Dictionary={};var feet: Dictionary={}
  for hand in controlled_hands:hands[hand]=skeleton.to_local(targets[hand].global_position)
  for foot in ["Foot.L","Foot.R"]:feet[foot]=skeleton.to_local(targets[foot].global_position)
  var plan: Dictionary=planner.choose(desired,hands,feet)
  if not plan.is_empty():desired=plan.hip;wanted_lean=plan.lean
 _hip=_hip.move_toward(desired,delta*0.65);_lean=move_toward(_lean,wanted_lean,delta*0.8)
 _apply_base(_hip,_lean)
 for hand in ["Hand.L","Hand.R"]:
  if hand not in controlled_hands:
   targets[hand].global_transform=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(hand))
 for name in LIMBS:
  var upper:=skeleton.find_bone(LIMBS[name][0]);var mid:=skeleton.find_bone(LIMBS[name][1]);var tip:=skeleton.find_bone(name)
  var root:=skeleton.get_bone_global_pose(upper).origin
  var middle:=skeleton.get_bone_global_pose(mid).origin
  var end:=skeleton.get_bone_global_pose(tip).origin
  var a:=root.distance_to(middle);var b:=middle.distance_to(end)
  var offset:=skeleton.to_local(targets[name].global_position)-root
  var length:=offset.length()
  var minimum:=sqrt(a*a+b*b+2*a*b*cos(deg_to_rad(145)))
  var maximum:=sqrt(a*a+b*b+2*a*b*cos(deg_to_rad(5)))
  var direction:=offset.normalized() if length>0.00001 else (end-root).normalized()
  var distance:=clampf(length,minimum,maximum)
  solved[name].global_position=skeleton.to_global(root+direction*distance)
  constraints[name]={"requested_distance":length,"minimum":minimum,"maximum":maximum,"limited":absf(distance-length)>0.002}

func _apply_base(hip: Vector3, lean: float) -> void:
 var hips:=skeleton.find_bone("Hips")
 var parent:=skeleton.get_bone_global_pose(skeleton.get_bone_parent(hips))
 skeleton.set_bone_pose_position(hips,parent.affine_inverse()*hip)
 for name in ["Spine","Chest"]:
  var i:=skeleton.find_bone(name)
  skeleton.set_bone_pose_rotation(i,skeleton.get_bone_rest(i).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,lean*(0.7 if name=="Spine" else 0.3)))

func measure() -> void:
 sample={}
 for name in LIMBS:
  var a:=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(LIMBS[name][0])).origin)
  var b:=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(LIMBS[name][1])).origin)
  var c:=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)
  var angle:=rad_to_deg((b-a).normalized().angle_to((c-b).normalized()))
  sample[name]={"root":a,"joint":b,"end":c,"error_m":c.distance_to(targets[name].global_position),"bend_degrees":angle,"lengths":Vector2(a.distance_to(b),b.distance_to(c)),"limited":constraints.get(name,{}).get("limited",false),"orientation_error":(skeleton.global_basis*skeleton.get_bone_global_pose(skeleton.find_bone(name)).basis).get_rotation_quaternion().angle_to(targets[name].global_basis.get_rotation_quaternion())}

func reset_targets() -> void:
 for name in targets:targets[name].global_transform=defaults[name]
 pelvis.global_position=defaults.Hips

func detach() -> void:
 set_process(false)
 for modifier in modifiers:
  modifier.active=false
  skeleton.remove_child(modifier);modifier.free()
 modifiers.clear()
 # 将渲染时的最终姿态交还常规动作，避免SkeletonModifier帧末恢复导致回跳。
 for index in final_poses:
  skeleton.set_bone_pose_rotation(index,final_poses[index].rotation)
  skeleton.set_bone_pose_position(index,final_poses[index].position)

func _exit_tree() -> void:
 if is_instance_valid(skeleton) and not modifiers.is_empty():detach()
