extends SceneTree
const Motion=preload("res://scripts/survival/ground_motion.gd")
func _initialize() -> void: _run.call_deferred()
func _box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var solid:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size; collision.shape=shape
	solid.add_child(collision); parent.add_child(solid); solid.position=at
	return solid
func _run() -> void:
	var world:=Node3D.new()
	root.add_child(world)
	_box(world,Vector3(0,-0.5,0),Vector3(12,1,12))
	var body:=CharacterBody3D.new()
	var collision:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=0.3; capsule.height=1.7
	collision.shape=capsule; collision.position.y=0.85
	body.add_child(collision); world.add_child(body)
	body.floor_snap_length=0.3
	var failures:=0
	for case in [{"height":0.12,"ceiling":false,"pass":true},{"height":0.28,"ceiling":false,"pass":true},{"height":0.5,"ceiling":false,"pass":false},{"height":0.28,"ceiling":true,"pass":false}]:
		var obstacle:=_box(world,Vector3(1,case.height/2,0),Vector3(2,case.height,3))
		var ceiling: StaticBody3D
		if case.ceiling: ceiling=_box(world,Vector3(0,1.85,0),Vector3(4,0.1,3))
		body.position=Vector3(-1,0.01,0); body.velocity=Vector3.ZERO
		for frame in 160:
			await physics_frame
			body.velocity=Vector3(1.5,-2,0)
			Motion.move(body,1.0/60)
		var crossed:=body.position.x>0.4
		print("STEP_CASE ",case," position=",body.position," crossed=",crossed)
		if crossed!=case.pass: failures+=1
		obstacle.queue_free()
		if ceiling!=null: ceiling.queue_free()
		await physics_frame
	world.queue_free()
	await create_timer(0.15).timeout
	print("GROUND_MOTION_FAILURES ",failures)
	quit(0 if failures==0 else 1)
