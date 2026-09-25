extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/frame_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var space: RefCounted=voice.survival.space
	var actor: Node3D=voice.survival.actors.person_003.body
	actor.rotation.y=0
	var original:=actor.global_position
	voice.survival.perception._record("person_003","known_far_tree","landmark",original+Vector3(31,2,43),true,{"name":"以前见过的大树"})
	voice.survival.perception.memories.person_003.known_far_tree.visible_now=false
	var snapshot: Dictionary=space.capture("person_003")
	assert(not snapshot.far_field.has("landmarks") and not snapshot.near_field.landmarks.has("known_far_tree"),"不自动倾倒远处地标记忆")
	var recalled: Dictionary=space.recalled_landmark("person_003",voice.survival.perception.known("person_003","known_far_tree"),snapshot.id)
	assert(recalled.approx_position=={"x":-30.0,"y":0.0,"z":40.0} and not recalled.has("position") and recalled.position_error_per_axis_m==5)
	assert(snapshot.near_field.landmarks.has("wood_block"))
	assert(snapshot.near_field.held_objects.is_empty())
	var underwater: Array=snapshot.near_field.ground_samples.filter(func(s):return s.get("surface_kind")=="submerged_ground")
	var dry: Array=snapshot.near_field.ground_samples.filter(func(s):return s.get("surface_kind")=="dry_ground")
	assert(not underwater.is_empty() and not dry.is_empty(),"初始视野应区别水底和露出水面的岸边地面")
	for sample in underwater: assert(sample.water_surface.y>=sample.position.y)
	for region in snapshot.near_field.regions:
		for p in region.visible_boundary_points:
			var at: Vector3=space.frames[snapshot.id].transform*Vector3(p.x,p.y,p.z)
			assert(voice.survival.perception.sees("person_003",at+Vector3.UP*0.03),"不能泄露被遮挡的边界")
	var adapter=preload("res://scripts/skills/luau_world_adapter.gd").new()
	adapter.sim=voice.survival;adapter.person_id="person_003";adapter.objects=voice.skills.world_objects;root.add_child(adapter)
	var invalid: Dictionary=adapter.resolve_surface({"observation_id":snapshot.id,"position":{"x":0,"y":8,"z":1}})
	assert(not invalid.ok and invalid.scope=="selected_point_only" and invalid.target.position.y==8)
	adapter.queue_free()
	var target={"observation_id":snapshot.id,"position":{"x":1.0,"y":0.0,"z":2.0}}
	var resolved: Dictionary=space.resolve("person_003",target)
	assert(resolved.ok and resolved.position.distance_to(original+Vector3(-1,0,2))<0.0001,"本人右方必须与身体朝向一致，不误用世界+X")
	actor.global_position+=Vector3(4,0,1);actor.rotation.y=PI/2
	assert(space.resolve("person_003",target).position==resolved.position,"等待期间移动转身不能改变旧观察的落点")
	assert(not space.resolve("person_002",target).ok,"其他人物不能使用此观察")
	assert(not space.resolve("person_003",{"anchor":"old","offset":{"x":0,"y":0,"z":1}}).ok,"不保留旧坐标兼容")
	var second: Dictionary=space.capture("person_003")
	var next: Dictionary=space.resolve("person_003",{"observation_id":second.id,"position":{"x":1,"y":0,"z":2}})
	assert(next.position.distance_to(actor.global_position+Vector3(2,0,1))<0.0001)
	var context: Dictionary=space.prepare_context("person_003",voice.store.context_for("person_003"),second)
	assert(not context.survival_observation.has("body_position") and not context.survival_observation.has("body_forward"))
	assert(context.space_observation.near_field.ground_samples.size()==54)
	assert(not context.survival_observation.known_objects.has("known_far_tree"),"事实列表不能绕过主动回忆")
	assert(not context.space_observation.far_field.has("landmarks"),"不得自动提供远场地图记忆")
	space.frames[snapshot.id].created_ms=Time.get_ticks_msec()-300001
	assert(space.resolve("person_003",target).code=="observation_expired")
	print("EGOCENTRIC_SPACE_PASSED rotation_translation_snapshot_owner_expiry_local_context_near_far_precision")
	scene.queue_free();await create_timer(0.2).timeout;quit()
