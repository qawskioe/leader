extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
var failures:=0
func check(value: bool, label: String) -> void:
	print(label," ",value)
	if not value: failures+=1
func key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code; event.pressed=true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D=scene.get_node("Player")
	player.set_physics_process(false)
	var overlay:=Control.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	await process_frame
	print("MOUSE_MODE ",Input.mouse_mode," active=",player.is_processing_input())
	var before:=player.rotation.y
	var mouse:=InputEventMouseMotion.new()
	mouse.position=root.size/2; mouse.global_position=mouse.position
	mouse.relative=Vector2(40,0)
	Input.parse_input_event(mouse)
	await process_frame
	var turned:=absf(player.rotation.y-before)>0.01
	print("LOOK_THROUGH_OVERLAY ",turned)
	player.position=Vector3(0,-20,8)
	player._physics_process(1.0/60)
	var recovered:=player.position.y> -2
	print("FALL_RECOVERY ",recovered," position=",player.position)
	check(turned and recovered,"BASIC_CONTROLS")
	overlay.queue_free()
	await process_frame
	var voice:=Voice.new()
	voice.name="VoiceTest"
	scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=false
	voice.survival.enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	voice.menu.close()
	var gather: Node=voice.survival.gathering
	player.position=gather.baskets["1"].root.global_position+Vector3(0,0,1.1)
	check(gather.pickup("player","1"),"PICKUP_BASKET")
	var ids: Array=gather.resources.keys()
	for i in 2:
		var at: Vector3=gather.resources[ids[i]].mesh.global_position
		player.position=Vector3(at.x,0.5,at.z+1.15)
		check(gather.harvest("player",ids[i]),"HARVEST")
		if i==0: check(gather.load_hand("player"),"LOAD_ONE")
	player.position=Vector3(0,0.5,22)
	player.velocity=Vector3.ZERO
	for frame in 40:
		await physics_frame
		player._physics_process(1.0/60)
	check(player.last_safe_position.z>20,"AUTOMATIC_SAFE_POINT_RECORD")
	player.position=Vector3(0,-20,80)
	player._physics_process(1.0/60)
	check(player.position.distance_to(player.last_safe_position)<0.1 and player.position.z>20,"RETURN_NEAR_LAST_GROUND")
	check(gather.basket_for("player")=="1" and gather.baskets["1"].contents.items.size()==1 and gather.hands.has("player") and gather.carried_count()==2,"CARRIED_FOOD_PRESERVED")
	check(gather.hands.player.origin.resource_id==ids[1] and gather.baskets["1"].contents.items[0].origin.resource_id==ids[0],"FOOD_ORIGIN_PRESERVED")
	voice.menu.open()
	before=player.rotation.y
	Input.parse_input_event(mouse); Input.flush_buffered_events()
	check(is_equal_approx(before,player.rotation.y),"MENU_BLOCKS_LOOK")
	key(KEY_ESCAPE)
	check(not voice.menu.is_open() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ESC_CLOSES_MENU")
	var caption: Node=voice.captions.person_001
	caption.set_expanded(true)
	caption.field_reader.grab_focus()
	key(KEY_E)
	check(not caption.expanded and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"E_CLOSES_FOCUSED_DETAILS")
	caption.set_expanded(true); caption.visible=false
	caption._process(0)
	check(caption.expanded and caption.bubble.visible,"PERSON_DETAILS_REMAIN_OPEN")
	key(KEY_ESCAPE)
	check(not caption.expanded and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ESC_CLOSES_PERSON_DETAILS")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"FOCUS_RESTORES_LOOK")
	scene.queue_free()
	await create_timer(0.15).timeout
	print("PLAYER_CONTROLS_FAILURES ",failures," cloud_calls=0")
	quit(0 if failures==0 else 1)
