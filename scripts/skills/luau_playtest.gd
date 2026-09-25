extends RefCounted
## 迁移验证入口：真实人物与物体，不自动调用模型。
static func prepare(voice: Node, path: String="user://skills/egocentric/playtest.json") -> void:
	while not voice.survival.ready_for_actions: await voice.get_tree().physics_frame
	voice.reset_context(false)
	var error: String=voice.skills.initialize(path);assert(error.is_empty(),error)
	error=voice.skills.library.install_builtins();assert(error.is_empty(),error)
	for id in voice.store.people:
		voice.skills.sync_person(id)
		voice.store.people[id].needs.hunger=0;voice.store.people[id].needs.thirst=0
	voice.config.autonomy_enabled=false;voice.config.actions_enabled=true;voice.config.local_only=false
	voice.skills.ensure_luau_world()
	var sim: Node=voice.survival
	var actor: Dictionary=sim.actors.person_003
	actor.body.global_position=sim.water.SOURCE+Vector3(0,0.6,-0.45);actor.body.rotation.y=0
	for frame in 30: await voice.get_tree().physics_frame
	var motor=preload("res://scripts/skills/body_motor.gd").new();motor.initialize(actor,"person_003")
	populate(sim,voice.skills.world_objects,motor,"person_003")
	var player: Node3D=voice.get_parent().get_node("Player")
	player.global_position=actor.body.global_position+Vector3(-1.5,0.7,2.0)
	player.look_at(Vector3(actor.body.global_position.x,player.global_position.y,actor.body.global_position.z))
	voice.menu.close()
	voice.log_event({"type":"luau_playtest_ready","person_id":"person_003","message":"大山已会拿取、松手、指定位置放置、转身观察和走到可见地面附近。可说：大山，拿起木块；把木块放在你脚边；松手则允许物品自然掉落。E 可教导修改动作。","library":path})
	print("LUAU_PLAYTEST_READY builtin_count=",voice.store.people.person_003.available_skills.size())

static func populate(sim: Node, objects: Node, motor: RefCounted, person: String) -> void:
	for id in ["wood_block","stone_tool"]:
		if objects.objects.has(id): continue
		var body:=RigidBody3D.new();body.name=id;body.freeze=false;body.collision_layer=1;body.collision_mask=1;sim.scene.add_child(body)
		var mesh:=MeshInstance3D.new()
		if id=="wood_block":
			var block:=BoxMesh.new();block.size=Vector3.ONE*0.12;mesh.mesh=block
		else:
			var stone:=CylinderMesh.new();stone.height=0.12;stone.top_radius=0.06;stone.bottom_radius=0.06;mesh.mesh=stone
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(0.45,0.26,0.12) if id=="wood_block" else Color(0.38,0.4,0.43);mesh.material_override=mat;body.add_child(mesh)
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*0.12;shape.shape=box;body.add_child(shape)
		var at: Vector3=sim.actors[person].body.global_position+Vector3(-0.18 if id=="wood_block" else 0.18,0,0.65)
		var hit: Dictionary=sim.scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2,1,[body.get_rid(),sim.actors[person].body.get_rid()]))
		assert(not hit.is_empty(),"初始物品需要实际地面支撑")
		body.global_position=hit.position+Vector3.UP*0.07
		body.set_meta("display_name","木块" if id=="wood_block" else "石块")
		objects.register_object(id,body,Vector3.UP*0.06)
		var label:=Label3D.new();label.text="木块" if id=="wood_block" else "石块";label.position.y=0.16;label.font_size=25;label.pixel_size=0.002;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;body.add_child(label)
		sim.perception._record(person,id,"interactable",body.global_position,true,{"name":label.text,"graspable":true})
