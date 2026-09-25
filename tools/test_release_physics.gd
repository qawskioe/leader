extends SceneTree
class AuditObjects extends "res://scripts/skills/world_objects.gd":
	var samples: Array=[]
	var watching:=""
	var remaining:=0
	func snapshot(id: String, phase: String) -> void:
		var body: RigidBody3D=objects[id].body
		var server: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var velocity: Vector3=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var floor_hit:=body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(body.global_position+Vector3.UP,body.global_position-Vector3.UP*5,1,[body.get_rid()]))
		var support: Dictionary={}
		if not floor_hit.is_empty(): support={"position":str(floor_hit.position),"normal":str(floor_hit.normal),"collider":str(floor_hit.collider.get_path())}
		var overlaps: Array=[]
		for child in body.get_children():
			if child is CollisionShape3D:
				var query:=PhysicsShapeQueryParameters3D.new();query.shape=child.shape;query.transform=child.global_transform;query.exclude=[body.get_rid()];query.collision_mask=1
				for hit in body.get_world_3d().direct_space_state.intersect_shape(query): overlaps.append(str(hit.collider.get_path()))
		samples.append({"support":support,"overlaps":overlaps,"phase":phase,"frame":Engine.get_physics_frames(),"node":str(body.global_position),"server":str(server.origin),"velocity":str(velocity),"bottom":str(bottom(id)),"freeze":body.freeze,"layer":body.collision_layer,"mask":body.collision_mask,"basis":str(body.global_basis)})
	func release(id: String, person: String) -> Dictionary:
		snapshot(id,"before_release")
		var result: Dictionary=super.release(id,person)
		snapshot(id,"after_release")
		watching=id;remaining=50
		return result
	func _physics_process(delta: float) -> void:
		super._physics_process(delta)
		if remaining>0:
			snapshot(watching,"physics");remaining-=1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var trials: Array=[]
	for attempt in 5:
		var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
		var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
		var objects:=AuditObjects.new();voice.skills.add_child(objects);voice.skills.world_objects=objects
		await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/release_audit_%d.json"%Time.get_ticks_usec())
		var refs: Dictionary={}
		for entry in voice.skills.library.describe("person_003"): refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
		var results: Array=[]
		for goal in ["take_object","place_object"]:
			var args: Dictionary={"object":"wood_block"}
			if goal=="place_object": args.target=ground_target(voice.survival,"person_003")
			var submitted: Dictionary=voice.skills.invoke("person_003","audit_"+goal,{"ref":refs[goal],"arguments":args})
			if not submitted.ok: results.append(submitted);break
			var result: Dictionary=await voice.skills.finished
			results.append(result)
			if not result.success: break
		trials.append({"attempt":attempt,"results":results,"samples":objects.samples.duplicate(true)})
		print("RELEASE_AUDIT ",attempt," success=",results[-1].get("success",false))
		scene.queue_free();await create_timer(0.2).timeout
	var file:=FileAccess.open("res://services/luau-runtime/runtime/release_audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(trials,"  "));file.close()
	quit()

func ground_target(sim: Node, id: String) -> Dictionary:
	var observation: Dictionary=sim.space.capture(id)
	return {"observation_id":observation.id,"position":observation.near_field.landmarks["surface/person/"+id].position}
