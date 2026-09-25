extends SceneTree
const Motion=preload("res://scripts/survival/ground_motion.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var baseline:=OS.get_cmdline_user_args().has("--baseline")
	var failures:=0
	# 取自实际运行 SURVIVAL_DIAGNOSTIC 的卡住坐标。
	for body: CharacterBody3D in [scene.get_node("People/Person04"),scene.get_node("Player")]:
		body.set_physics_process(false)
		body.position=Vector3(1.192707,0.027142,8.772327)
		body.velocity=Vector3.ZERO
		for goal in [Vector3(1.2,0,10),Vector3(1.2,0,8),Vector3(1.2,0,10)]:
			for frame in 300:
				await physics_frame
				var direction: Vector3=goal-body.position
				direction.y=0
				if direction.length()<0.15: break
				body.velocity=direction.normalized()*1.5
				body.velocity.y=-2
				if baseline: body.move_and_slide()
				else: Motion.move(body,1.0/60)
			var reached:=Vector2(body.position.x-goal.x,body.position.z-goal.z).length()<0.15
			print("ENTRY_EDGE ",body.name," baseline=",baseline," reached=",reached," position=",body.position)
			if not reached:
				failures+=1
				break
		body.position=Vector3(8,1,-5)
	scene.queue_free()
	await create_timer(0.15).timeout
	print("EDGE_FAILURES ",failures)
	quit(0 if failures==0 else 1)
