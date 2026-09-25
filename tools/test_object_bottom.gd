extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	var objects=preload("res://scripts/skills/world_objects.gd").new();root.add_child(objects)
	var capsule:=CapsuleShape3D.new();capsule.radius=0.22;capsule.height=0.55
	var sphere:=SphereShape3D.new();sphere.radius=0.22
	var box:=BoxShape3D.new();box.size=Vector3(0.4,0.6,0.8)
	var cylinder:=CylinderShape3D.new();cylinder.radius=0.22;cylinder.height=0.6
	for kind in ["capsule","sphere","box","cylinder"]:
		var body:=RigidBody3D.new();body.freeze=true
		var collision:=CollisionShape3D.new();collision.shape={"capsule":capsule,"sphere":sphere,"box":box,"cylinder":cylinder}[kind];body.add_child(collision);root.add_child(body)
		body.rotation.z=PI/4
		body.position.y=0.22+0.055/sqrt(2.0) if kind=="capsule" else 0.22 if kind=="sphere" else 0.52/sqrt(2.0) if kind=="cylinder" else 0.5/sqrt(2.0)
		objects.register_object(kind,body)
		var bottom: Vector3=objects.bottom(kind)
		assert(absf(bottom.y)<0.006,"倾斜%s真实底部应在地面，不能使用包围盒角点：%f"%[kind,bottom.y])
		body.queue_free()
	objects.queue_free();await process_frame
	print("OBJECT_BOTTOM_PASSED rotated_capsule_sphere_box_cylinder")
	quit()
