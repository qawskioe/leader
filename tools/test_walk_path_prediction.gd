extends SceneTree
## 路径预判与真实人物移动比较：前方地面接触不能掩盖后续阻挡。
const Motion=preload("res://scripts/survival/ground_motion.gd")
class ProbeSpace extends Node:
	var frames: Dictionary={}
class ProbeSim extends Node:
	var actors: Dictionary={}
	var space: Node
class ProbeAPI extends "res://scripts/skills/luau_world_adapter.gd":
	var seen: Dictionary={}
	func request(operation: String,args: Dictionary) -> Dictionary:
		if operation=="perceive":return seen.duplicate(true)
		return await super.request(operation,args)
func _initialize() -> void: _run.call_deferred()
func _box(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var solid:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new()
	shape.size=size;collision.shape=shape;solid.add_child(collision);parent.add_child(solid);solid.position=at
func _ramp(parent: Node3D) -> void:
	var solid:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=ConvexPolygonShape3D.new()
	var points:=PackedVector3Array()
	for x in [-3.0,5.0]:
		for z in [-3.0,3.0]:
			points.append(Vector3(x,-1,z));points.append(Vector3(x,(x+3)*.2,z))
	shape.points=points;collision.shape=shape;solid.add_child(collision);parent.add_child(solid)
func _crest(parent: Node3D) -> void:
	var solid:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=ConvexPolygonShape3D.new()
	var points:=PackedVector3Array()
	for x in [-3.0,0.0]:
		for z in [-3.0,3.0]:
			points.append(Vector3(x,-1,z));points.append(Vector3(x,(x+1)*.3,z))
	shape.points=points;collision.shape=shape;solid.add_child(collision);parent.add_child(solid)
	_box(parent,Vector3(3,-.35,0),Vector3(6,1.3,6))
func _rounded_edge(parent: Node3D) -> void:
	var solid:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=CapsuleShape3D.new()
	shape.radius=.3;shape.height=1.6;collision.shape=shape;solid.add_child(collision);parent.add_child(solid)
	solid.position=Vector3(.25,.8,-.48)
func _run() -> void:
	var failures:=0
	for case in [{"name":"small_step","height":.12,"pass":true},{"name":"max_step","height":.28,"pass":true},{"name":"tall_step","height":.5,"pass":false},{"name":"low_ceiling","height":.28,"ceiling":true,"pass":false},{"name":"continuous_ramp","ramp":true,"pass":true},{"name":"floor_before_wall","ramp":true,"wall":true,"pass":false},{"name":"rounded_edge_slide","rounded":true,"pass":true},{"name":"unsupported_gap","gap":true,"pass":false}]:
		var world:=Node3D.new();root.add_child(world)
		if case.get("ramp",false):
			if case.get("wall",false):_crest(world)
			else:_ramp(world)
			if case.get("wall",false):_box(world,Vector3(1,1.7,0),Vector3(.2,2,3))
		elif case.get("gap",false):
			_box(world,Vector3(-3.125,-.5,0),Vector3(5.75,1,6))
			_box(world,Vector3(3.4,-.5,0),Vector3(5.2,1,6))
		else:
			_box(world,Vector3(0,-.5,0),Vector3(12,1,12))
			if case.get("rounded",false):_rounded_edge(world)
			else:_box(world,Vector3(1,case.height/2,0),Vector3(2,case.height,3))
			if case.get("ceiling",false):_box(world,Vector3(0,1.85,0),Vector3(5,.1,3))
		var body:=CharacterBody3D.new();var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new()
		capsule.radius=.3;capsule.height=1.7;collision.shape=capsule;collision.position.y=.85
		body.add_child(collision);world.add_child(body);body.floor_snap_length=.3
		body.position=Vector3(-1,.42 if case.get("ramp",false) and not case.get("wall",false) else .02,0)
		for frame in 5:
			await physics_frame;body.velocity=Vector3(0,-2,0);Motion.move(body,1.0/60)
		var api:=ProbeAPI.new();var sim:=ProbeSim.new();var space:=ProbeSpace.new()
		world.add_child(api);world.add_child(sim);world.add_child(space);sim.space=space;sim.actors.probe={"body":body}
		var target:=Vector3(2,.3 if case.get("wall",false) else (1.0 if case.get("ramp",false) else float(case.get("height",0))),0)
		if case.get("wall",false):
			var first:=PhysicsTestMotionParameters3D.new();first.from=body.global_transform;first.from.origin+=Vector3.UP*.04
			first.motion=target-body.position;first.margin=.005
			var contact:=PhysicsTestMotionResult3D.new()
			assert(PhysicsServer3D.body_test_motion(body.get_rid(),first,contact))
			assert(contact.get_collision_normal(0).y>.85,"必须先遇到地面，才能重现长扫掠漏掉后续墙体")
		space.frames.probe={"transform":Transform3D.IDENTITY}
		api.sim=sim;api.person_id="probe";api._owned=true
		api.seen={"observation_id":"probe","near":{"ground_samples":[{"state":"visible_surface","position":{"x":target.x,"y":target.y,"z":target.z}}]}}
		var before:=body.global_transform
		var preview: Dictionary=await api.request("walk_options",{})
		assert(body.global_transform==before,"路径查询不能移动实际身体")
		var predicted: bool=preview.near.ground_samples[0].path_clear
		for frame in 160:
			await physics_frame;body.velocity=Vector3(1.5,-2,0);Motion.move(body,1.0/60)
		var crossed:=body.position.x>1.6 and body.position.y>-.35
		print("PATH_CASE ",case.name," predicted=",predicted," actual=",crossed," expected=",case.pass)
		if predicted!=case.pass or crossed!=case.pass:failures+=1
		if case.get("wall",false):
			var samples: Array=api.seen.near.ground_samples
			var sample: Dictionary=samples[0]
			for index in 300:samples.append(sample.duplicate(true))
			physics_frame.connect(func():api._owned=false,CONNECT_ONE_SHOT)
			var cancelled: Dictionary=await api.request("walk_options",{})
			assert(not cancelled.ok and cancelled.code=="cancelled","分帧查询必须允许下一帧取消")
			print("PATH_QUERY_YIELD_CANCEL_PASSED")
		api.sim=null;world.queue_free();await physics_frame
	print("WALK_PATH_FAILURES ",failures);quit(0 if failures==0 else 1)
