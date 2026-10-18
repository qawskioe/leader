extends SceneTree
## 真实玩家输入/菜单/文字入口；只允许无窗口、最小化或隐藏父窗口的独立夹具。
class MenuProbe extends "res://scripts/voice/voice_menu.gd":
	func _ready() -> void:
		panel=PanelContainer.new();add_child(panel);panel.hide()
class GatheringStub extends RefCounted:
	var interaction_hint: Label
	func basket_for(_person: String) -> String:return ""
class SimulationStub extends RefCounted:
	var scene: Node
	var gathering=GatheringStub.new()
class VoiceProbe extends Node:
	var menu: Node
	var captions: Dictionary={}
	var survival=SimulationStub.new()
	var spoken: Array[String]=[]
	func say_text(value: String) -> String:spoken.append(value);return ""
class BridgeProbe extends "res://scripts/player_control.gd":
	func visible_interactables() -> Array:return []
class NativeMouseWatch extends Node:
	var captured_frames:=0
	func _process(_delta: float) -> void:
		if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:captured_frames+=1
var failures:=0
func check(value: bool, label: String) -> void:
	print("AUTOMATION_MOUSE_CHECK ",label,"=",value)
	if not value:failures+=1
func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	if DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().has("--hidden-mouse-fixture"):root.mode=Window.MODE_MINIMIZED
	run.call_deferred()
func run() -> void:
	# 原生自动化由独立桌面隔离，显式标明前提；不能从引擎焦点标志推断用户前台。
	var hidden_fixture: bool=OS.get_cmdline_user_args().has("--hidden-mouse-fixture")
	if not OS.get_cmdline_user_args().has("--player-control") or (DisplayServer.get_name()!="headless" and root.mode!=Window.MODE_MINIMIZED and not hidden_fixture):
		push_error("鼠标隔离回归只允许无窗口、最小化或独立桌面夹具和--player-control，不捕获用户桌面");quit(2);return
	print("AUTOMATION_MOUSE_WINDOW ",JSON.stringify({"pid":OS.get_process_id(),"display":DisplayServer.get_name(),"mode":root.mode,"hidden_fixture":hidden_fixture,"unfocusable":root.get_flag(Window.FLAG_NO_FOCUS)}))
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var scene:=Node3D.new();root.add_child(scene)
	var floor_node:=Node3D.new();floor_node.name="Solid_CaveFloor";scene.add_child(floor_node)
	var floor_body:=StaticBody3D.new();floor_node.add_child(floor_body)
	var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,.2,30)
	floor_shape.shape=box;floor_shape.position.y=-.1;floor_body.add_child(floor_shape)
	var player=preload("res://scripts/first_person_controller.gd").new();player.name="Player";player.position=Vector3(0,.05,1);scene.add_child(player)
	var voice:=VoiceProbe.new();voice.name="VoiceTest";voice.survival.scene=scene;scene.add_child(voice)
	var menu:=MenuProbe.new();voice.menu=menu;voice.add_child(menu)
	var text_input=preload("res://scripts/voice/player_text_input.gd").new();text_input.voice=voice;voice.add_child(text_input)
	var bridge:=BridgeProbe.new();bridge.ipc_root="user://test_player_automation_mouse/";voice.add_child(bridge);bridge.set_process(false)
	bridge.virtual_mouse_mode=Input.MOUSE_MODE_CAPTURED
	var watch:=NativeMouseWatch.new();scene.add_child(watch)
	await physics_frame
	var initial_yaw: float=player.rotation.y
	for sequence in 3:
		await bridge.perform({"id":"mouse_look_%d"%sequence,"type":"look","x":50.0,"y":0.0})
		check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"look_%d_native_visible"%sequence)
	check(is_equal_approx(player.rotation.y-initial_yaw,-150.0*player.LOOK_SENSITIVITY),"normal_camera_relative_input")
	var initial_position: Vector3=player.global_position
	await bridge.perform({"id":"mouse_walk","type":"key","key":"W","seconds":.2})
	check(player.global_position.distance_to(initial_position)>.2,"normal_keyboard_movement")
	menu.open()
	check(bridge.virtual_mouse_mode==Input.MOUSE_MODE_VISIBLE,"menu_updates_logical_mode")
	var menu_yaw: float=player.rotation.y
	await bridge.perform({"id":"mouse_menu_look","type":"look","x":50.0,"y":0.0})
	check(is_equal_approx(player.rotation.y,menu_yaw),"menu_blocks_camera")
	menu.close()
	check(bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"menu_close_keeps_native_visible")
	await bridge.perform({"id":"mouse_text_open","type":"key","key":"T"})
	check(text_input.panel.visible and bridge.virtual_mouse_mode==Input.MOUSE_MODE_VISIBLE,"text_open_logical_mode")
	await bridge.perform({"id":"mouse_text_type","type":"type","text":"限定输入回归"})
	await bridge.perform({"id":"mouse_text_send","type":"key","key":"Enter"})
	check(voice.spoken==["限定输入回归"] and not text_input.panel.visible,"normal_focused_text_submission")
	check(bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"text_close_keeps_native_visible")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"focus_cannot_capture_native_mouse")
	for sequence in 3:
		await bridge.perform({"id":"mouse_capture_%d"%sequence,"type":"capture"})
	var receipt: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(bridge.ipc_root+"result.json"))
	check(receipt.native_mouse_mode==Input.MOUSE_MODE_VISIBLE and receipt.logical_mouse_mode==Input.MOUSE_MODE_CAPTURED,"receipt_reports_both_mouse_modes")
	if DisplayServer.get_name()!="headless" and root.mode==Window.MODE_WINDOWED and hidden_fixture:
		check(receipt.capture_error==OK,"private_desktop_renders_player_view")
		# 只在独立桌面夹具中请求本窗口焦点；外部观察器验证它不能进入用户前台。
		root.grab_focus();await process_frame
	check(watch.captured_frames==0,"zero_native_captured_frames")
	print("AUTOMATION_MOUSE_RESULT failures=",failures," native_captured_frames=",watch.captured_frames)
	scene.queue_free();await process_frame;await process_frame
	if failures==0:print("PLAYER_AUTOMATION_MOUSE_PASSED real_input_ui_focus_no_native_capture")
	quit(0 if failures==0 else 1)
