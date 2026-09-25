extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D=scene.get_node("Player")
	player.set_physics_process(false)
	var voice: Node=scene.get_node_or_null("VoiceTest")
	if voice!=null:
		voice.config.local_only=true
		voice.config.autonomy_enabled=false
		voice.survival.enabled=false
		voice.menu.panel.hide()
	assert(scene.get_node("Outdoor").find_children("HarvestFruit_*","MeshInstance3D",true,false).size()==21)
	assert(scene.find_children("Basket_*_Base","MeshInstance3D",true,false).size()==2)
	player.position=Vector3(0,0.7,11)
	for goal in [Vector3(0,0,18),Vector3(-1,0,24),Vector3(-4,0,34),Vector3(-7,0,44),Vector3(-9,0,48)]:
		var arrived:=false
		for frame in 500:
			await physics_frame
			var offset: Vector3=goal-player.position
			offset.y=0
			if offset.length()<0.3:
				arrived=true
				break
			player.velocity=offset.normalized()*6.0
			player.velocity.y=-2.0
			player.move_and_slide()
			assert(player.position.y>-1.0,"不能穿过洞口接缝或地面")
		assert(arrived,"路线受阻："+str(goal)+" 实际位置："+str(player.position))
	print("OUTDOOR_PASSED: cave_to_grove_physical_walk, fruit_meshes=21, baskets=2")
	if DisplayServer.get_name()!="headless":
		player.position=Vector3(1,0.5,26)
		var camera: Camera3D=player.camera
		camera.look_at(Vector3(-8,2.3,47))
		for frame in 6: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/outdoor_first_person.png")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
