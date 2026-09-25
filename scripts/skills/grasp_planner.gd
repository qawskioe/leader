extends RefCounted
## 只规划本人当前可见物品周围的站位；不移动身体、物品或渲染骨架。
var api: Node
var posture=preload("res://scripts/rig/posture_planner.gd").new()

func initialize(adapter: Node) -> void:
 api=adapter;posture.initialize(api.motor.skeleton)

func plan(id: String, hand: String, seen: Dictionary, exclude_current: bool=false) -> Dictionary:
 var started:=Time.get_ticks_usec()
 var slice_started:=started
 var compute_us:=0
 var max_slice_us:=0
 var actor: CharacterBody3D=api.sim.actors[api.person_id].body
 var center: Vector3=api.objects.objects[id].body.global_position
 var grip: Vector3=api.objects.grip_position(id)
 if Vector2(center.x-actor.global_position.x,center.z-actor.global_position.z).length()>2.5:return {"ok":false,"code":"grasp_target_far"}
 var skeleton: Skeleton3D=api.motor.skeleton
 var relative:=actor.global_transform.affine_inverse()*skeleton.global_transform
 var radial:=actor.global_position-center;radial.y=0
 if radial.length()<.05:radial=-actor.global_basis.z
 radial=radial.normalized()
 var candidates: Array[Vector3]=[]
 if not exclude_current:candidates.append(actor.global_position)
 for radius in [.4,.45,.5,.55,.6,.7,.8,1.0]:
  for angle in [0,-35,35,-70,70]:candidates.append(center+radial.rotated(Vector3.UP,deg_to_rad(angle))*radius)
 var frame: Transform3D=api.sim.space.frames[seen.observation_id].transform
 var best: Dictionary={};var best_cost:=INF;var checked:=0
 for candidate in candidates:
  # 姿态与碰撞候选分帧计算；不会为缩短总时间而阻塞输入/渲染。
  if Time.get_ticks_usec()-slice_started>=2000:
   var duration:=Time.get_ticks_usec()-slice_started;compute_us+=duration;max_slice_us=maxi(max_slice_us,duration)
   await api.get_tree().process_frame
   while api._owned and not api.sim.enabled:await api.get_tree().process_frame
   if not api._owned:return {"ok":false,"code":"cancelled"}
   if not api._visible_object(id) or api.objects.objects[id].holder!="" or api.objects.grip_position(id).distance_to(grip)>.02:return {"ok":false,"code":"target_changed"}
   slice_started=Time.get_ticks_usec()
  var move_distance:=Vector2(candidate.x-actor.global_position.x,candidate.z-actor.global_position.z).length()
  if exclude_current and move_distance<.08:continue
  var local:=frame.affine_inverse()*candidate
  var nearest: Dictionary={};var distance:=INF
  for sample in seen.near.ground_samples:
   if sample.state!="visible_surface" or sample.slope_degrees>=35:continue
   var p: Dictionary=sample.position
   var value:=Vector2(p.x-local.x,p.z-local.z).length_squared()
   if value<distance:distance=value;nearest=sample
  if nearest.is_empty() or distance>1.0:continue
  var target:={"observation_id":seen.observation_id,"position":{"x":local.x,"y":nearest.position.y,"z":local.z}}
  var support: Dictionary=api.resolve_surface(target)
  if not support.ok:continue
  candidate=frame*Vector3(support.position.x,support.position.y,support.position.z)
  var heading:=atan2(grip.x-candidate.x,grip.z-candidate.z)
  var transform:=Transform3D(Basis(Vector3.UP,heading).scaled(actor.global_basis.get_scale()),candidate)
  if not _clear(actor,transform,Vector3.ZERO):continue
  var from:=actor.global_transform
  if move_distance>.04 and not _clear(actor,from,candidate-actor.global_position):continue
  var model:=transform*relative
  var wrist: Vector3=model.affine_inverse()*grip-skeleton.get_bone_global_rest(skeleton.find_bone(hand)).basis*api.motor.contacts.get(hand,Vector3.ZERO)
  var feet: Dictionary={}
  for foot in ["Foot.L","Foot.R"]:feet[foot]=posture.rest_positions[foot]
  var pose: Dictionary=posture.choose(posture.rest_positions.Hips,{hand:wrist},feet)
  checked+=1
  if pose.is_empty() or pose.error_m>.005:continue
  var cost:=move_distance+float(pose.cost)*10
  if cost<best_cost:
   best_cost=cost
   best={"ok":true,"code":"grasp_plan","stance":{"observation_id":seen.observation_id,"position":support.position},"look_target":{"observation_id":seen.observation_id,"position":api.local_point(grip)},"needs_move":move_distance>.04,"predicted_error_m":pose.error_m}
 if best.is_empty():best={"ok":false,"code":"no_feasible_grasp_stance","message":"当前可见且路径无阻挡的站位中，没有满足身体范围的抓取姿态"}
 var duration:=Time.get_ticks_usec()-slice_started;compute_us+=duration;max_slice_us=maxi(max_slice_us,duration)
 best["compute_ms"]=compute_us/1000.0;best["max_slice_ms"]=max_slice_us/1000.0
 best["planning_ms"]=(Time.get_ticks_usec()-started)/1000.0;best["poses_checked"]=checked
 return best

func _clear(body: CharacterBody3D, from: Transform3D, motion: Vector3) -> bool:
 var parameters:=PhysicsTestMotionParameters3D.new()
 parameters.from=from;parameters.from.origin+=Vector3.UP*.04;parameters.motion=motion;parameters.margin=.005;parameters.recovery_as_collision=true
 var result:=PhysicsTestMotionResult3D.new()
 if PhysicsServer3D.body_test_motion(body.get_rid(),parameters,result):
  for index in result.get_collision_count():
   if result.get_collision_normal(index).y<.7:return false
 return true
