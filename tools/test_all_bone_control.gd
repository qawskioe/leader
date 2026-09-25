extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions: await physics_frame
 var api=load("res://scripts/skills/world_adapter.gd").new();api.sim=sim;api.person_id="person_003";scene.add_child(api)
 assert(api.acquire().ok)
 var info=await api.operate("inspect_body",[])
 var skeleton: Skeleton3D=sim.actors.person_003.skeleton
 assert(info.body.bones.size()==skeleton.get_bone_count())
 var pose: Dictionary={}
 for bone in info.body.bones: pose[bone]={"rotation":{"x":5,"y":10,"z":-5}}
 pose["Hand.R"].rotation={"x":120,"y":0,"z":0}
 pose["Root"]["position"]={"x":0.03,"y":0.05,"z":0}
 assert((await api.operate("pose_bones",[pose,0.2])).ok)
 for bone in pose:
  var index=skeleton.find_bone(bone)
  var v=pose[bone].rotation
  var expected=skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion.from_euler(Vector3(deg_to_rad(v.x),deg_to_rad(v.y),deg_to_rad(v.z)))
  assert(skeleton.get_bone_pose_rotation(index).is_equal_approx(expected),"骨骼被覆盖: "+bone)
 var head=skeleton.get_bone_pose_rotation(skeleton.find_bone("Head"))
 assert((await api.operate("pose_bones",[{"Hand.R":{"rotation":{"x":-100,"y":20,"z":0}}},0.2])).ok)
 assert(skeleton.get_bone_pose_rotation(skeleton.find_bone("Head")).is_equal_approx(head),"未指定骨骼必须保持")
 var held_pose: Dictionary=api.motor.bone_snapshot()
 var started:=Time.get_ticks_msec()
 var held: Dictionary=await api.operate("pose_bones",[{},0.2])
 assert(held.ok and held.code=="pose_held" and Time.get_ticks_msec()-started>=180)
 assert(api.motor.bone_snapshot()==held_pose,"保持姿态不能复位或改变已有骨骼")
 assert(not (await api.operate("pose_bones",[{},-1])).ok)
 assert(not (await api.operate("pose_bones",[{"ImaginaryFinger":{"rotation":{"x":0,"y":0,"z":0}}},0.2])).ok)
 create_timer(0.05).timeout.connect(api.cancel)
 var cancelled=await api.operate("pose_bones",[pose,1.0])
 assert(cancelled.code=="cancelled")
 for index in skeleton.get_bone_count():
  assert(skeleton.get_bone_pose_position(index).is_equal_approx(skeleton.get_bone_rest(index).origin))
 var file=FileAccess.open("res://services/text-gateway/runtime/body_control_inventory.json",FileAccess.WRITE);file.store_string(JSON.stringify(info.body,"  "));file.close()
 print("ALL_BONES_PASSED count=",skeleton.get_bone_count()," names=",info.body.bones.keys()," raw_rotation, translation, partial_preservation, invalid_name, cancellation")
 scene.queue_free();await create_timer(0.2).timeout;quit()
