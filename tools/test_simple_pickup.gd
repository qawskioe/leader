extends SceneTree
## 简化拿取的世界规则回归；不读取人物记忆、不调用真实模型。
class BodyStub extends RefCounted:
 var actor: Dictionary
 func point(_hand: String) -> Vector3:
  assert(false,"简化拿取不得查询手掌接触点")
  return Vector3.ZERO
func _initialize():run.call_deferred()
func object_at(parent: Node3D, at: Vector3) -> RigidBody3D:
 var body:=RigidBody3D.new();body.position=at;body.collision_layer=4;body.collision_mask=1
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*.2;shape.shape=box;body.add_child(shape);parent.add_child(body)
 return body
func run():
 create_timer(15).timeout.connect(func():push_error("simple pickup timeout");quit(1))
 var scene:=Node3D.new();root.add_child(scene)
 var actor:=CharacterBody3D.new();scene.add_child(actor)
 var body_state:=BodyStub.new();body_state.actor={"body":actor}
 var distance_rule=load("res://scripts/skills/interaction_range.gd")
 assert(distance_rule.reachable(actor,Vector3(0,1.53,1.0)),"面前正常高度的物品属于操作范围")
 assert(not distance_rule.reachable(actor,Vector3(0,4,0)))
 assert(not distance_rule.reachable(actor,Vector3(0,.9,3)))
 var objects=load("res://scripts/skills/world_objects.gd").new();scene.add_child(objects)
 var item:=object_at(scene,Vector3(0,.4,1));item.gravity_scale=0;objects.register_object("test_item",item)
 var other:=object_at(scene,Vector3(.2,.4,1));other.gravity_scale=0;objects.register_object("other",other)
 await physics_frame;await physics_frame
 item.position=Vector3(0,.4,4)
 assert(objects.grasp("test_item","person","Hand.R",body_state).code=="out_of_reach")
 item.position=Vector3(0,.4,1)
 var wall:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,3,.1);collision.shape=box;wall.add_child(collision);scene.add_child(wall);wall.position=Vector3(0,1,.5)
 await physics_frame;await physics_frame
 assert(objects.grasp("test_item","person","Hand.R",body_state).code=="occluded")
 wall.position.x=10
 await physics_frame;await physics_frame
 var grabbed: Dictionary=objects.grasp("test_item","person","Hand.R",body_state)
 assert(grabbed.ok)
 assert(objects.objects.test_item.holder=="person" and item.freeze and item.collision_layer==0)
 assert(objects.grasp("test_item","someone","Hand.L",body_state).code=="already_held")
 assert(objects.grasp("other","person","Hand.R",body_state).code=="hand_occupied")
 var offset: Transform3D=actor.global_transform.affine_inverse()*item.global_transform
 actor.position=Vector3(2,0,0);actor.rotation.y=.7;objects.sync_held("test_item")
 assert(item.global_transform.is_equal_approx(actor.global_transform*offset))
 assert(objects.change_grip("test_item","person","Hand.L",body_state).ok)
 assert(not objects.held.has("person/Hand.R") and objects.held["person/Hand.L"]=="test_item")
 item.gravity_scale=1
 assert(objects.release("test_item","someone").code=="not_held")
 assert(objects.release("test_item","person").ok)
 assert(not item.freeze and item.collision_layer==4 and item.collision_mask==1)
 var before: float=item.position.y
 for i in 12:await physics_frame
 assert(item.position.y<before-.05,"松手后必须真实落下")
 assert(objects.held.is_empty() and objects.objects.test_item.holder=="")
 print("SIMPLE_PICKUP_PASSED distance_occlusion_ownership_occupied_fixed_carry_swap_release_gravity_no_bones")
 scene.queue_free();await process_frame;quit()
