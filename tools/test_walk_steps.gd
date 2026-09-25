extends SceneTree
const WalkMap=preload("res://scripts/survival/walk_map.gd")
func _initialize() -> void: _run.call_deferred()
func _floor(parent: Node3D, at: Vector3, size: Vector3) -> Node3D:
	var holder:=Node3D.new()
	holder.name="Solid_CaveFloor"
	var body:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=size; collision.shape=box
	body.add_child(collision); holder.add_child(body); parent.add_child(holder)
	holder.position=at
	return holder
func _run() -> void:
	var failures:=0
	for height in [0.12,0.28,0.5]:
		var scene:=Node3D.new()
		root.add_child(scene)
		_floor(scene,Vector3(-3,-0.5,0),Vector3(6,1,12))
		var upper:=Node3D.new()
		scene.add_child(upper)
		_floor(upper,Vector3(3,height-0.5,0),Vector3(6,1,12))
		await physics_frame
		await physics_frame
		var map:=WalkMap.new()
		map.build(scene.get_world_3d(),[],true)
		var route:=map.path(Vector3(-2.4,0,0),Vector3(2.4,height,0))
		var reached:=not route.is_empty()
		var right_exists:=map.heights.has(Vector2i(4,0))
		print("WALK_STEP height=",height," route=",reached," upper_floor_sampled=",right_exists)
		if reached!=(height<0.3) or not right_exists: failures+=1
		scene.queue_free()
		await physics_frame
	print("WALK_STEPS_FAILURES ",failures)
	quit(0 if failures==0 else 1)
