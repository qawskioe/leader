extends SceneTree
## 隔离物理夹具：拒绝穿透释放，不改位置、碰撞关系或伪造自由落体。
func _initialize():run.call_deferred()
func run():
 create_timer(15).timeout.connect(func():push_error("release overlap timeout");quit(1))
 var scene:=Node3D.new();root.add_child(scene)
 var floor_body:=StaticBody3D.new();scene.add_child(floor_body)
 var floor_shape:=CollisionShape3D.new();var floor_box:=BoxShape3D.new();floor_box.size=Vector3(10,.2,10);floor_shape.shape=floor_box;floor_body.add_child(floor_shape);floor_body.position.y=-.1
 var actor:=CharacterBody3D.new();actor.collision_layer=2;actor.collision_mask=1;scene.add_child(actor)
 var actor_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.7;actor_shape.shape=capsule;actor.add_child(actor_shape);actor_shape.position.y=.85
 var item:=RigidBody3D.new();item.collision_layer=4;item.collision_mask=3;scene.add_child(item)
 var item_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.4,.4,.4);item_shape.shape=box;item.add_child(item_shape)
 var objects=load("res://scripts/skills/world_objects.gd").new();scene.add_child(objects);objects.register_object("held_item",item)
 var anchor:=Node3D.new();scene.add_child(anchor);anchor.position=Vector3(0,.8,0)
 assert(objects.attach_to("held_item","fixture","Hand.L",func():return anchor.global_transform).ok)
 for n in 3:await physics_frame
 var blocked: Dictionary=objects.release("held_item","fixture")
 assert(not blocked.ok and blocked.code=="release_overlapping" and "person" in blocked.contacts,str(blocked))
 assert(objects.held["fixture/Hand.L"]=="held_item" and item.freeze and item.collision_layer==0)
 anchor.position=Vector3(2,.1,0);objects.sync_held("held_item")
 blocked=objects.release("held_item","fixture")
 assert(not blocked.ok and "environment" in blocked.contacts,str(blocked))
 anchor.position=Vector3(2,1.2,0);objects.sync_held("held_item")
 var before:=item.global_position
 var released: Dictionary=objects.release("held_item","fixture")
 assert(released.ok and item.global_position.is_equal_approx(before))
 assert(not item.freeze and item.collision_layer==4 and item.collision_mask==3 and objects.held.is_empty())
 for n in 90:await physics_frame
 assert(item.global_position.y<before.y-.5 and item.global_position.y>.15,str(item.global_position))
 # 场景销毁仅解除连接，不对已经退树的节点进行空间查询。
 assert(objects.attach_to("held_item","fixture","Hand.L",func():return anchor.global_transform).ok)
 scene.queue_free();await create_timer(.1).timeout
 print("RELEASE_OVERLAP_PASSED retain_hold_person_ground_valid_drop_teardown")
 quit()
