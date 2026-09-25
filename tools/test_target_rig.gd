extends SceneTree
func _initialize():call_deferred("run")
func run():
 for person in range(1,5):
  var model=load("res://assets/characters/person_v2_%02d.glb"%person).instantiate();root.add_child(model)
  var skeleton: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
  var rig=load("res://scripts/rig/target_rig.gd").new();root.add_child(rig);rig.initialize(skeleton)
  rig.auto_posture=false
  for i in 5:await process_frame
  var lengths: Dictionary={}
  for name in rig.sample:lengths[name]=rig.sample[name].lengths
  rig.targets["Hand.L"].global_position=Vector3(.3,1.2,.35)
  for i in 5:await process_frame
  assert(rig.sample["Hand.L"].error_m<.015,"可达手腕目标误差")
  rig.targets["Hand.L"].rotate_object_local(Vector3.UP,.3)
  for i in 5:await process_frame
  # 修改器结束后骨架会恢复输入姿态，所以读取求解时保存的测量，不读恢复后的姿态。
  assert(rig.sample["Hand.L"].orientation_error<.001,"末端朝向跟随")
  rig.pelvis.global_position.y-=.4
  await create_timer(.8).timeout
  for side in ["L","R"]:
   var foot: Dictionary=rig.sample["Foot."+side]
   assert(foot.error_m<.015,"下蹲时锁脚")
   assert(foot.bend_degrees<146)
   assert(foot.joint.z>foot.root.z,"膝盖向前而非反折")
  rig.auto_posture=true;rig.reset_targets()
  for side in ["L","R"]:rig.targets["Hand."+side].global_position=Vector3(.22 if side=="L" else -.22,.28,.3)
  await create_timer(1.6).timeout
  for name in rig.sample:
   assert(rig.sample[name].error_m<.02,"低处目标协同求解: "+name+str(rig.sample[name].error_m))
   assert(rig.sample[name].lengths.distance_to(lengths[name])<.0001,"骨段不得拉伸")
  if person==2:
   var previous: Dictionary=rig.sample.duplicate(true)
   var max_step:=0.0
   for step in 90:
    var weight:=float(step+1)/90
    for side in ["L","R"]:
     var x:=.22 if side=="L" else -.22
     rig.targets["Hand."+side].global_position=Vector3(x,.28,.3).lerp(Vector3(x,1.25,.38),weight)
    await create_timer(.016).timeout
    for name in rig.sample:
     max_step=maxf(max_step,rig.sample[name].joint.distance_to(previous[name].joint))
     if name.begins_with("Foot"):assert(rig.sample[name].error_m<.02,"抬手起身过程中锁脚")
    previous=rig.sample.duplicate(true)
   assert(max_step<.12,"连续目标移动时关节跳变")
   print("RIG_SWEEP_MAX_JOINT_STEP_M ",max_step)
  rig.auto_posture=false;rig.reset_targets()
  await create_timer(1.6).timeout
  rig.targets["Hand.L"].global_position=Vector3(3,1.2,0)
  for i in 5:await process_frame
  assert(rig.sample["Hand.L"].limited and rig.sample["Hand.L"].error_m>1.0)
  assert(rig.sample["Hand.L"].bend_degrees>=4.0)
  rig.targets["Hand.L"].global_position=rig.sample["Hand.L"].root
  for i in 5:await process_frame
  assert(rig.sample["Hand.L"].end.is_finite())
  assert(rig.sample["Hand.L"].bend_degrees<=146)
  print("TARGET_RIG_PERSON_PASSED ",person)
  rig.free();model.free()
 print("TARGET_RIG_PASSED 4 skeletons, reachable_target, orientation, planted_feet, squat, no_stretch, bend_limits, singular_target")
 quit()
