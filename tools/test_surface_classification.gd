extends SceneTree
## 隔离几何：首个可见命中是箱顶时，不能伪称地面或透露其下地面。
func _initialize():run.call_deferred()
func shape(parent: Node3D, size: Vector3) -> void:
 var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;collision.shape=box;parent.add_child(collision)
func sample_at(samples: Array, x: float, z: float) -> Dictionary:
 for sample in samples:
  if is_equal_approx(sample.probe.x,x) and is_equal_approx(sample.probe.z,z):return sample
 return {}
func run() -> void:
 create_timer(10).timeout.connect(func():push_error("surface test timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://surface_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 sim.set_physics_process(false)
 var actor: Node3D=sim.actors.person_003.body
 actor.global_position=Vector3(100,2,100);actor.rotation.y=0
 var floor:=StaticBody3D.new();scene.add_child(floor);floor.position=Vector3(100,1.9,101);shape(floor,Vector3(5,.2,5))
 var item:=RigidBody3D.new();scene.add_child(item);item.freeze=true;item.position=Vector3(100,2.25,100.75);shape(item,Vector3(.5,.5,.5))
 await physics_frame;await physics_frame
 var observed: Dictionary=sim.space.capture("person_003")
 var top:=sample_at(observed.near_field.ground_samples,0,.75)
 var ground:=sample_at(observed.near_field.ground_samples,.75,.75)
 print("SURFACE_SAMPLES top=",top," ground=",ground)
 if top.get("state")!="visible_object_surface" or top.get("surface_kind")!="movable_object":push_error("物品顶部被错误标为地面");quit(1);return
 assert(top.position.y>.45,"保留真实可见顶部高度，不穿透读取隐藏地面")
 assert(ground.state=="visible_surface" and ground.surface_kind=="dry_ground" and absf(ground.position.y)<.01)
 print("SURFACE_CLASSIFICATION_PASSED object_top_not_ground_no_xray")
 scene.queue_free();await create_timer(.1).timeout;quit()
