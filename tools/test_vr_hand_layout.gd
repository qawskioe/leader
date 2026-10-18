extends SceneTree
## PC 图形夹具复用正式手部提示与持物槽；不声明验证了头显双眼或实体手柄。
class MockRig extends "res://scripts/vr/player_rig.gd":
	func _ready() -> void:set_process(false)

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(35).timeout.connect(func():push_error("PC hand layout timeout");quit(1))
	assert(str(ProjectSettings.get_setting("application/config/custom_user_dir_name")).begins_with("Leader-isolated-vr-profile-"))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_size(Vector2i(1024,720))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var voice=scene.get_node("VoiceTest")
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false;voice.config.actions_enabled=false
	while not voice.survival.ready_for_actions or voice.session_manager.is_locked():await process_frame
	var sim=voice.survival;sim.enabled=false;voice.menu.close()
	for caption in voice.captions.values():caption.hide()
	var player: Node3D=scene.get_node("Player")
	player.set_physics_process(false);player.set_process(false)
	player.global_position=Vector3(0,0,8.4)
	var rig:=MockRig.new();player.add_child(rig)
	rig.voice=voice;rig.hands.sim=sim
	rig.left=XRController3D.new();rig.add_child(rig.left)
	rig.right=XRController3D.new();rig.add_child(rig.right)
	rig.left.global_position=player.global_position+Vector3(-.6,1.1,-.4)
	rig.right.global_position=player.global_position+Vector3(.18,1.1,-.24)
	rig._create_hand_labels();player.vr=rig;rig.active=true;rig.focused=true
	var camera: Camera3D=player.get_node("Eyes")
	camera.global_position=player.global_position+Vector3(0,1.7,.25)
	camera.look_at(player.global_position+Vector3(.1,1.26,-.55))
	var bag: Dictionary=sim.water.bags["1"]
	assert(bag.holder=="","私有布局夹具应从未持有水袋开始")
	assert(sim.world_objects.attach_to("water_bag/1","player","Hand.R",sim.water.hold_pose.bind("player")).ok)
	rig.hands.reconcile();sim.world_objects.sync_held("water_bag/1")
	sim.water._update_labels()
	assert(not bag.label.visible)
	rig.feedback="已拿起 · 松开握键放下";rig.feedback_until=Time.get_ticks_msec()+5000
	rig._process(0)
	assert(rig.status_label.text.begins_with("水袋 · 0 / 3 份水\n"))
	assert(rig.status_label.no_depth_test and rig.status_label.autowrap_mode!=TextServer.AUTOWRAP_OFF)
	for index in 4:await process_frame
	await RenderingServer.frame_post_draw
	var first:="D:/Leader/work/meta-link-recovery/hand_layout_pc_relaxed.png"
	assert(root.get_texture().get_image().save_png(first)==OK)
	rig.right.rotation.z=-.4
	sim.world_objects.sync_held("water_bag/1")
	rig.feedback="水袋与地面或墙壁重叠；把手移到空处，再握住并松开"
	rig._process(0)
	for index in 3:await process_frame
	await RenderingServer.frame_post_draw
	var second:="D:/Leader/work/meta-link-recovery/hand_layout_pc_rotated.png"
	assert(root.get_texture().get_image().save_png(second)==OK)
	var started:=Time.get_ticks_usec()
	for index in 1000:sim.world_objects.player_hold_transform("water_bag/1",player)
	var mean_ms:=(Time.get_ticks_usec()-started)/1000000.0
	print("PC_HAND_LAYOUT_PASSED images=",first,",",second," hold_pose_mean_ms=",mean_ms," model_calls=0 tts_calls=0")
	player.vr=null;quit()
