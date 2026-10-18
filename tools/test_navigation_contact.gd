extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(25).timeout.connect(func(): push_error("碰撞验证超时");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/contact_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var sim=voice.survival;var id:="person_003";var body: CharacterBody3D=sim.actors[id].body
	var observation: Dictionary=sim.space.capture(id)
	var position: Dictionary={}
	for sample in observation.near_field.ground_samples:
		if sample.get("surface_kind")=="dry_ground" and absf(sample.position.x-3)<0.01 and absf(sample.position.z-0.75)<0.01: position=sample.position
	assert(not position.is_empty())
	var target:={"observation_id":observation.id,"position":position}
	var at: Vector3=sim.space.resolve(id,target).position
	var direction:=at-body.global_position;direction.y=0
	# 离线碰撞夹具：开始移动后出现阻挡，不能被当成真实游玩。
	var wall:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new()
	box.size=Vector3(6,3,0.3);shape.shape=box;shape.disabled=true;wall.add_child(shape);scene.add_child(wall)
	wall.global_position=body.global_position+direction*0.5+Vector3.UP*1.3
	wall.rotation.y=atan2(direction.x,direction.z)
	await physics_frame
	var ref:=""
	for entry in voice.skills.library.describe(id):
		if voice.skills.library.definitions[entry.ref].id=="walk_to": ref=entry.ref
	assert(voice.skills.invoke(id,"blocked_probe",{"ref":ref,"arguments":{"target":target}}).ok)
	while sim.actors[id].stage!="skill_moving": await physics_frame
	shape.set_deferred("disabled",false)
	if "--clear-last-contact" in OS.get_cmdline_user_args():
		# 重现水池现场：先实际撞墙，停止时最近一帧却只剩地面接触。
		var touched:=false
		while not touched:
			await physics_frame
			for index in body.get_slide_collision_count():
				if absf(body.get_slide_collision(index).get_normal().y)<.85:touched=true
		await physics_frame
		sim.enabled=false;shape.set_deferred("disabled",true)
		await physics_frame;await physics_frame
		body.velocity=Vector3(0,-.1,0);body.move_and_slide()
		for index in body.get_slide_collision_count():
			assert(absf(body.get_slide_collision(index).get_normal().y)>=.85,"夹具最后一帧必须已没有墙面接触")
		sim._finish_skill_motion(id,false,"夹具模拟本段停止，最后一帧墙面接触已消失")
	var result: Dictionary=await voice.skills.finished
	assert(not result.success)
	var feedback: Dictionary=result.runtime.returned
	assert(feedback.code=="movement_failed" and not feedback.has("world_contacts"))
	assert(not feedback.touch_contacts.is_empty(),"真实受阻后必须保留实际接触面")
	assert(not sim.actors[id].has("motion_contacts"),"已结束的接触不能残留到下一段移动")
	var local_direction:=Vector3(position.x,0,position.z).normalized()
	for contact in feedback.touch_contacts.values():
		var normal:=Vector3(contact.normal.x,contact.normal.y,contact.normal.z)
		assert(absf(normal.length()-1)<0.001 and normal.dot(local_direction)<-0.9,"接触法线必须换算到原观察坐标系，指向墙外而非穿墙方向")
		assert(Vector3(contact.position.x,contact.position.y,contact.position.z).length()<4,"不能向模型泄露世界坐标")
	print("NAVIGATION_CONTACT_PASSED actual_collision_local_normal_no_world_coordinate_leak")
	scene.queue_free();await create_timer(0.2).timeout;quit()
