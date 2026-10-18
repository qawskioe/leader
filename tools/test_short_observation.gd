extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(10).timeout.connect(func():quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/short_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var store=voice.store;var sim=voice.survival;var space=sim.space
	var id:="person_003"
	var wood: Node3D=voice.skills.world_objects.objects.wood_block.body
	var old: Array=store.memory.observations[id].wood_block.position.duplicate()
	store.hear(id,{"id":"request","speaker":"player","text":"把你面前那两个东西搬到池塘外面"})
	store.remember(id,"request",{"private_interpretation":"石块和木块都要搬","public_reply":"","task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"处理玩家的搬运请求"},"skill_call":{"ref":"take","arguments":{"object":"stone_tool"}}})
	sim.actors[id].body.rotation.y=PI
	# 改变人物看不到的真实物体，短期记忆不得自动跟随。
	wood.global_position+=Vector3(30,0,0)
	sim.perception.observe(id)
	var observation: Dictionary=space.capture(id)
	var context: Dictionary=space.prepare_context(id,store.context_for(id),observation)
	assert(not context.space_observation.near_field.landmarks.has("wood_block"))
	assert(context.survival_observation.known_objects.has("wood_block"),"转身不能把当天见过的近处物品移出行动目录")
	assert(not context.survival_observation.known_objects.wood_block.visible_now)
	assert(not context.survival_observation.known_objects.wood_block.has("position"),"相对坐标只从明确的最后观察引用读取")
	assert(context.working_context.task.understanding.contains("木块"))
	assert(context.working_context.last_known_locations.wood_block.visible_now==false)
	assert(store.memory.observations[id].wood_block.position==old)
	var local: Dictionary=context.working_context.last_known_locations.wood_block.position
	var resolved: Dictionary=space.resolve(id,{"observation_id":observation.id,"position":local})
	assert(resolved.position.distance_to(Vector3(old[0],old[1],old[2]))<0.001)
	assert(not context.working_context.task.initial_locations.wood_block.visible_now)
	store.memory.advance(store.memory.policy.day_seconds)
	observation=space.capture(id);context=space.prepare_context(id,store.context_for(id),observation)
	assert(context.working_context.task.understanding.contains("木块") and context.working_context.last_known_locations.has("wood_block"))
	assert(context.working_context.recent_turns.is_empty())
	print("SHORT_OBSERVATION_PASSED task_identity_out_of_view_stale_position_relative_frame_day_carry_no_omniscience")
	scene.queue_free();await create_timer(0.2).timeout;quit()
