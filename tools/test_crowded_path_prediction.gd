extends SceneTree
## 无云端物理回归：暂时靠近/重叠的成员不得堵死真实可用的退路。
const Motion=preload("res://scripts/survival/ground_motion.gd")
func _initialize() -> void:run.call_deferred()
func person(world: Node3D, at: Vector3) -> CharacterBody3D:
	var body:=CharacterBody3D.new();body.collision_layer=2;body.collision_mask=3;body.floor_snap_length=.3
	var collision:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.3;shape.height=1.7
	collision.shape=shape;collision.position.y=.85;body.add_child(collision);world.add_child(body);body.position=at
	return body
func run() -> void:
	create_timer(35).timeout.connect(func():push_error("成员退路回归超时");quit(1))
	var failures:=0
	for setup in [{"separation":.75},{"separation":.61},{"separation":.58},{"separation":.50},{"separation":.50,"back_wall":true}]:
		var separation: float=setup.separation
		for direction in [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK]:
			var world:=Node3D.new();root.add_child(world)
			var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(12,1,12)
			collision.shape=box;floor.add_child(collision);world.add_child(floor);floor.position.y=-.5
			if setup.get("back_wall",false):
				var wall:=StaticBody3D.new();var wall_collision:=CollisionShape3D.new();var wall_shape:=BoxShape3D.new()
				wall_shape.size=Vector3(3,2,.2);wall_collision.shape=wall_shape;wall.add_child(wall_collision);world.add_child(wall);wall.position=Vector3(0,1,-.6)
			var body:=person(world,Vector3(0,.02,0))
			for frame in 5:
				await physics_frame;body.velocity=Vector3.DOWN*2;Motion.move(body,1.0/60)
			var initial: Vector3=body.position
			person(world,Vector3(0,initial.y,separation))
			await physics_frame
			var before: Transform3D=body.global_transform
			var predicted:=Motion.path_clear(body,initial+direction*.8)
			assert(body.global_transform==before,"路径预判不能挪动真实身体")
			for frame in 45:
				await physics_frame;body.velocity=direction*1.5+Vector3.DOWN*2;Motion.move(body,1.0/60)
			var progress: float=(body.position-initial).dot(direction)
			var actual:=progress>.7
			print("CROWDED_PATH_CASE separation=",separation," back_wall=",setup.get("back_wall",false)," direction=",direction," predicted=",predicted," actual=",actual," progress=",progress)
			if predicted!=actual:failures+=1
			world.queue_free();await physics_frame
	print("CROWDED_PATH_FAILURES ",failures)
	quit(0 if failures==0 else 1)
