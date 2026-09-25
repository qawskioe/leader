extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
var player: CharacterBody3D
var sim: Node
func _initialize() -> void: _run.call_deferred()
func hold_f() -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_F; event.physical_keycode=KEY_F; event.pressed=true
	Input.parse_input_event(event)
	await create_timer(1.0).timeout
	event.pressed=false
	Input.parse_input_event(event)
	await physics_frame
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("PLAYER_GATHERING_REQUIRES_WINDOW: 实际F输入测试需要支持鼠标捕获的窗口；无界面请运行test_desktop_basket和test_forest_gathering")
		quit(2);return
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=scene.get_node_or_null("VoiceTest")
	if voice!=null:
		voice.config.local_only=true; voice.config.autonomy_enabled=false
		voice.menu.panel.hide()
		sim=voice.survival
	else:
		var store:=Store.new()
		assert(store.initialize().is_empty())
		sim=Sim.new(); sim.scene=scene; sim.store=store
		scene.add_child(sim)
	player=scene.get_node("Player")
	player.set_physics_process(false)
	while not sim.ready_for_actions: await physics_frame
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var gather: Node=sim.gathering
	var key: String=gather.resources.keys()[0]
	# 没有篮子不能把果实放进不存在的背包。
	assert(not gather.harvest("player",key))
	var basket_position: Vector3=gather.baskets["1"].root.global_position
	player.global_position=basket_position+Vector3(0,0,1.1)
	player.camera.look_at(basket_position+Vector3(0,0.35,0))
	gather.baskets["1"].reserved="person_003" # 内部预约不能阻止玩家实际拿走无人持有的物品。
	await hold_f()
	assert(gather.basket_for("player")=="1","F 必须拿到实体篮子")
	assert(not gather.pickup("person_003","1"),"篮子不能同时被两人持有")
	var fruit_position: Vector3=gather.resources[key].mesh.global_position
	player.global_position=Vector3(fruit_position.x,0.5,fruit_position.z+1.15)
	player.camera.look_at(fruit_position)
	gather.resources[key].reserved="person_003"
	await hold_f()
	assert(gather.hands.has("player") and gather.baskets["1"].contents.items.is_empty(),"先到手里，不自动装篮")
	assert(not gather.harvest("player",key),"同一果实不能重复采摘")
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_RIGHT; click.pressed=true
	Input.parse_input_event(click)
	await physics_frame
	click.pressed=false; Input.parse_input_event(click)
	assert(not gather.hands.has("player") and gather.baskets["1"].contents.items.size()==1,"右键明确装篮")
	assert(sim.storage_food==3,"没运回来不能增加库存")
	if DisplayServer.get_name()!="headless":
		player.camera.rotation=Vector3(-0.6,0,0)
		for frame in 5: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/player_basket.png")
	# 此处瞬移只用于输入接口测试；完整物理往返由 test_gathering 覆盖。
	player.global_position=Sim.STORAGE+Vector3(0,0.3,1.2)
	player.camera.look_at(Sim.STORAGE+Vector3(0,0.4,0))
	await hold_f()
	assert(sim.storage_food==4 and gather.baskets["1"].contents.items.is_empty())
	assert(sim.storage_origins.back().collector_id=="player")
	assert(gather.drop("player"))
	var before: int=gather.regrown
	gather.resources[key].regrow_at=gather.elapsed
	await create_timer(0.1).timeout
	assert(gather.resources[key].available and gather.regrown==before+1)
	gather.reset()
	assert(gather.carried_count()==0 and gather.basket_for("player")=="")
	print("PLAYER_GATHERING_PASSED: F_pickup, F_harvest, explicit_load, exclusive_basket, no_remote_stock, unload_origin, regrowth, reset")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
