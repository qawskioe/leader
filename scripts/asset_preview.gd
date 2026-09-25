extends Node3D
## 把独立资产组合成可走动的检查场景。生活道具当前只用于展示。

var static_collision_count := 0


func _ready() -> void:
	_build_collisions($Cave)
	if has_node("Outdoor"): _build_collisions($Outdoor)
	_add_lighting()
	for person in $People.get_children():
		var animations := person.find_children("*", "AnimationPlayer", true, false)
		assert(not animations.is_empty(), "人物模型缺少动画播放器：" + person.name)
		var player := animations[0] as AnimationPlayer
		assert(player.has_animation("Idle"), "人物模型缺少 Idle 动画：" + person.name)
		player.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		player.play("Idle")
		var body := CharacterBody3D.new()
		body.name = person.name
		body.transform = person.transform
		body.collision_layer = 2
		body.collision_mask = 3
		body.floor_snap_length = 0.3
		$People.remove_child(person)
		$People.add_child(body)
		person.name = "Model"
		person.transform = Transform3D.IDENTITY
		body.add_child(person)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.30
		capsule.height = 1.70
		shape.shape = capsule
		shape.position.y = 0.85
		body.add_child(shape)
	if OS.get_cmdline_user_args().has("--capture"):
		_capture_preview()
	elif OS.get_cmdline_user_args().has("--map-preview"):
		$Player.position = Vector3(5.3, 0.5, 7.7)
		$Player.look_at(Vector3(-0.6, 0.5, -1.0))
		$Player.camera.look_at(Vector3(-0.6, 3.6, -1.0))
	elif OS.get_cmdline_user_args().has("--forest-preview") or OS.get_cmdline_user_args().has("--forest-capture"):
		$Player.position = Vector3(-1.1, 0.42, 26)
		$Player.rotation.y = PI
		$Player.camera.look_at(Vector3(-5.5, 4.0, 49))
		$Player.camera.fov = 76.0
		if OS.get_cmdline_user_args().has("--forest-capture"):
			_capture_forest()
	elif OS.get_cmdline_user_args().has("--outdoor-preview"):
		$Player.position=Vector3(0,0.65,20)
		$Player.rotation.y=PI
	elif DisplayServer.get_name() != "headless":
		var voice_test := preload("res://scripts/voice/voice_test.gd").new()
		voice_test.name = "VoiceTest"
		add_child(voice_test)


func _build_collisions(node: Node) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("Solid_"):
		var instance := node as MeshInstance3D
		var shape := instance.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = "StaticCollision"
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		instance.add_child(body)
		static_collision_count += 1
	for child in node.get_children():
		_build_collisions(child)


func _omni(label: String, at: Vector3, color: Color, energy: float, radius: float, shadows: bool) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = label
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = radius
	lamp.omni_attenuation = 0.8
	lamp.shadow_enabled = shadows
	add_child(lamp)


func _add_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.030, 0.037)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.43, 0.49, 0.57)
	environment.ambient_light_energy = 0.23
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if has_node("Outdoor"):
		var sky:=Sky.new()
		var sky_material:=ProceduralSkyMaterial.new()
		sky_material.sky_top_color=Color(0.23,0.46,0.65)
		sky_material.sky_horizon_color=Color(0.72,0.78,0.70)
		sky_material.ground_horizon_color=Color(0.54,0.58,0.42)
		sky.sky_material=sky_material
		environment.sky=sky
		environment.background_mode=Environment.BG_SKY
		var sun:=DirectionalLight3D.new()
		sun.name="OutdoorSun"
		sun.rotation_degrees=Vector3(-52,-28,0)
		sun.light_color=Color(1.0,0.92,0.75)
		sun.light_energy=0.05
		sun.shadow_enabled=true
		sun.directional_shadow_max_distance=120
		add_child(sun)
	world.environment = environment
	add_child(world)
	_omni("EntranceDaylight", Vector3(0, 3.7, 11), Color(0.66,0.79,1), 1.1, 16, false)
	_omni("ChamberBounce", Vector3(0, 5.8, 4), Color(0.84,0.88,1), 0.35, 19, false)
	_omni("ColumnSide", Vector3(5, 5.4, -3), Color(1,0.80,0.57), 0.45, 16, true)
	_omni("FarBounce", Vector3(-4, 4, -7), Color(0.60,0.73,0.83), 0.25, 15, false)
	_omni("HearthGlow", Vector3(-4.7, 0.85, 3.2), Color(1,0.40,0.12), 0.9, 7, true)


func _capture_preview() -> void:
	assert(DisplayServer.get_name() != "headless", "截图必须使用真实渲染器")
	$Player.set_physics_process(false)
	var camera: Camera3D = $Player.camera
	camera.global_position = Vector3(5.4, 2.35, 7.7)
	camera.look_at(Vector3(-0.6, 3.8, -1.0))
	for frame in range(12):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png("res://previews/godot_interior.png")
	assert(result == OK, "无法保存 Godot 预览图")
	print("GODOT_CAPTURE_OK")
	get_tree().quit()


func _capture_forest() -> void:
	assert(DisplayServer.get_name() != "headless", "森林截图必须使用真实渲染器")
	$Player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for frame in range(30):
		await RenderingServer.frame_post_draw
	var start_usec := Time.get_ticks_usec()
	for frame in range(90):
		await RenderingServer.frame_post_draw
	var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
	print("FOREST_RENDER_METRICS: fps=", snappedf(90.0 / elapsed, 0.1),
		" draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		" primitives=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var result := get_viewport().get_texture().get_image().save_png("res://previews/forest_godot.png")
	assert(result == OK, "无法保存森林预览图")
	print("FOREST_CAPTURE_OK")
	get_tree().quit()
