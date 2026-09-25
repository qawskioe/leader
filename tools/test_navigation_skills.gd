extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/navigation_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var sim=voice.survival;var id:="person_003";var body: CharacterBody3D=sim.actors[id].body
	var refs: Dictionary={}
	for entry in voice.skills.library.describe(id):refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	var initial:=body.global_position
	var observation: Dictionary=sim.space.capture(id)
	var sample: Dictionary={}
	for point in observation.near_field.ground_samples:
		if point.get("surface_kind")=="dry_ground" and absf(point.position.x-3)<0.01 and absf(point.position.z-0.75)<0.01:sample=point
	assert(not sample.is_empty())
	assert(voice.skills.invoke(id,"walk",{"ref":refs.walk_to,"arguments":{"target":{"observation_id":observation.id,"position":sample.position}}}).ok)
	var walked: Dictionary=await voice.skills.finished
	assert(walked.success,walked.message)
	var feedback: Dictionary=walked.runtime.returned
	assert(feedback.scope=="selected_ground_point_only" and feedback.selected_target.observation_id==observation.id)
	var selected: Dictionary=feedback.selected_target.position
	assert(Vector3(selected.x,selected.y,selected.z).distance_to(Vector3(sample.position.x,sample.position.y,sample.position.z))<0.0001,"跨Luau/JSON往返后保留原落脚点，允许浮点序列化误差")
	var standing: Dictionary=sim.space.resolve(id,feedback.standing_position)
	assert(standing.ok and Vector2(standing.position.x-body.global_position.x,standing.position.z-body.global_position.z).length()<0.001,"移动反馈必须给出原观察系的实际站位；等待IPC期间竖直落地仍可能继续")
	assert(feedback.distance_to_selected_point_m<=0.50 and feedback.message.contains("不证明"))
	assert(initial.distance_to(body.global_position)>1)
	var ground: Dictionary=sim.space.resolve(id,{"observation_id":observation.id,"position":sample.position})
	assert(Vector2(body.global_position.x-ground.position.x,body.global_position.z-ground.position.z).length()<=0.50,"预留0.45米站位后不能再多提前0.2米结束")
	var wood: Node3D=voice.skills.world_objects.objects.wood_block.body
	var remembered: Vector3=wood.global_position
	body.rotation.y=atan2(body.global_position.x-remembered.x,body.global_position.z-remembered.z)
	sim.perception.observe(id)
	observation=sim.space.capture(id)
	var target: Dictionary={"observation_id":observation.id,"position":sim.space.local_point(id,observation.id,remembered)}
	assert(voice.skills.invoke(id,"look",{"ref":refs.look_toward,"arguments":{"target":target}}).ok)
	var looked: Dictionary=await voice.skills.finished
	assert(looked.success)
	assert(sim.perception.known(id,"wood_block").visible_now,"转身后应重新看见原位置的木块")
	observation=sim.space.capture(id)
	var ground_at:=remembered-Vector3.UP*0.06
	target={"observation_id":observation.id,"position":sim.space.local_point(id,observation.id,ground_at)}
	assert(voice.skills.invoke(id,"return",{"ref":refs.walk_to,"arguments":{"target":target}}).ok)
	walked=await voice.skills.finished
	assert(walked.success,walked.message)
	assert(voice.skills.invoke(id,"take_returned",{"ref":refs.take_object,"arguments":{"object":"wood_block"}}).ok)
	var taken: Dictionary=await voice.skills.finished
	assert(taken.success,taken.message)
	assert(voice.skills.invoke(id,"release_returned",{"ref":refs.release_object,"arguments":{"object":"wood_block"}}).ok)
	var released: Dictionary=await voice.skills.finished
	assert(released.success)
	for frame in 45: await physics_frame
	remembered=wood.global_position
	# 移走看不见的物品；朝记忆位置观察不能自动追踪其新位置。
	body.rotation.y+=PI;sim.perception.observe(id)
	wood.global_position+=Vector3(30,0,0)
	observation=sim.space.capture(id)
	target={"observation_id":observation.id,"position":sim.space.local_point(id,observation.id,remembered)}
	assert(voice.skills.invoke(id,"look_again",{"ref":refs.look_toward,"arguments":{"target":target}}).ok)
	looked=await voice.skills.finished
	assert(looked.success and not sim.perception.known(id,"wood_block").visible_now)
	var direction:=remembered-body.global_position;direction.y=0
	assert(body.global_basis.z.angle_to(direction)<0.02,"观察方向必须仍为记忆位置")
	print("NAVIGATION_SKILLS_PASSED actual_walk_turn_reobserve_no_hidden_tracking")
	scene.queue_free();await create_timer(0.2).timeout;quit()
