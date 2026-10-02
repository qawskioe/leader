extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var objects=preload("res://scripts/skills/world_objects.gd").new();scene.add_child(objects)
	for frame in 5: await physics_frame
	for attempt in 3:
		var body:=RigidBody3D.new();body.collision_layer=1;body.collision_mask=1
		var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3.ONE*0.12;collider.shape=shape;body.add_child(collider);scene.add_child(body)
		body.global_position=Vector3(20.18,-0.75,64.2)
		for frame in 30: await physics_frame
		body.freeze=true;body.collision_layer=0;body.collision_mask=0
		body.global_transform=Transform3D(Basis(Vector3(0.787407,-0.359602,-0.500674),Vector3(0.088464,0.869727,-0.48554),Vector3(0.61005,0.338027,0.71664)),Vector3(20.67814,-0.592227,65.99065))
		for frame in 30: await physics_frame
		# 隔离持有到自由刚体的交接；不让手部动画影响固定重现位置。
		objects.register_object("stone",body)
		objects.objects.stone.holder="person_003";objects.objects.stone.hand="Hand.L"
		var held_transform: Transform3D=body.global_transform
		objects.objects.stone.attachment=func():return held_transform
		objects.objects.stone.saved={"freeze":false,"layer":1,"mask":1}
		assert(objects.release("stone","person_003").ok)
		for frame in 90: await physics_frame
		assert(body.global_position.y> -0.8 and body.linear_velocity.length()<0.1,"释放时必须重新参与实际地面碰撞，不能穿地")
		assert(body.collision_layer==1 and body.collision_mask==1 and body.get_collision_exceptions().is_empty())
		objects.objects.erase("stone");body.queue_free();await physics_frame
	print("RELEASE_HANDOFF_PASSED 3_cycles_original_failure_position_no_collision_exemptions")
	scene.queue_free();await create_timer(0.2).timeout;quit()
