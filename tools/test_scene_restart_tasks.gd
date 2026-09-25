extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("scene restart task test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	for state in ["completed","cancelled","refused","paused_budget","wait","awaiting_judgement","action_submitted"]:
		voice.store.working_tasks.person_003={"state":state,"request":{"id":"old","speaker":"player","text":"拿水袋"},"progress":[],"stop_reason":"保留原原因"}
		await voice._record_scene_restart()
		var task: Dictionary=voice.store.working_tasks.person_003
		var expected: String="interrupted_scene_reload" if state=="action_submitted" else state
		assert(task.state==expected,"场景重载不能复活或重置任务：%s -> %s"%[state,task.state])
		assert(task.stop_reason=="保留原原因" and task.request.text=="拿水袋")
		assert(task.continuity_note.contains("物理世界"))
	print("SCENE_RESTART_TASKS_PASSED preserve_terminal_wait_budget_pending_states_interrupt_only_running_action")
	scene.queue_free();await create_timer(0.2).timeout;quit()
