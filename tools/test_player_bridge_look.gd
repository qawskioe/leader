extends SceneTree
## 只验证真实输入事件与捕获状态；不启动生活模拟、麦克风或云端。
class MenuStub extends RefCounted:
	var opened:=false
	func is_open() -> bool:return opened
class GatheringStub extends RefCounted:
	var interaction_hint: Label
class SimulationStub extends RefCounted:
	var scene: Node
	var gathering=GatheringStub.new()
class VoiceStub extends Node:
	var menu=MenuStub.new()
	var captions: Dictionary={}
	var survival=SimulationStub.new()
class Bridge extends "res://scripts/player_control.gd":
	func visible_interactables() -> Array:return []
class PlayerProbe extends "res://scripts/first_person_controller.gd":
	var requested_motion: Array=[]
	func _input(event: InputEvent) -> void:
		var before:=rotation.y
		super._input(event)
		if event is InputEventMouseMotion and event.relative==Vector2(50,0):
			requested_motion.append(rotation.y-before)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("输入桥捕获验证需要实际显示服务");quit(2);return
	if not OS.get_cmdline_user_args().has("--player-control"):push_error("桥接显示验证须显式--player-control，避免捕获真实鼠标");quit(2);return
	var scene:=Node3D.new();root.add_child(scene)
	var player:=PlayerProbe.new();player.name="Player";scene.add_child(player);player.set_physics_process(false)
	var voice:=VoiceStub.new();voice.name="VoiceTest";voice.survival.scene=scene;scene.add_child(voice)
	var bridge:=Bridge.new();voice.add_child(bridge);bridge.set_process(false)
	bridge.ipc_root="user://test_player_bridge_look/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bridge.ipc_root))
	for minimized in [false,true]:
		root.mode=Window.MODE_MINIMIZED if minimized else Window.MODE_WINDOWED
		await create_timer(0.2).timeout
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		bridge.virtual_mouse_mode=Input.MOUSE_MODE_CAPTURED
		player.requested_motion.clear()
		bridge.active=true
		await bridge.perform({"id":"fixture_player_bridge_look","type":"look","x":50.0,"y":0.0})
		await process_frame
		assert(not player.requested_motion.is_empty(),"桥接鼠标事件必须交付实际玩家输入入口")
		assert(is_equal_approx(player.requested_motion.back(),-50.0*player.LOOK_SENSITIVITY),"释放真实鼠标后，转向仍须使用正常灵敏度")
		assert(bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED,"真实焦点不能覆盖逻辑捕获状态")
		assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"正常显示和最小化操作均不得捕获真实鼠标")
	root.mode=Window.MODE_WINDOWED
	await process_frame
	voice.menu.opened=true
	bridge.virtual_mouse_mode=Input.MOUSE_MODE_CAPTURED
	player.requested_motion.clear()
	bridge.active=true
	await bridge.perform({"id":"fixture_player_bridge_menu","type":"look","x":50.0,"y":0.0})
	await process_frame
	assert(not player.requested_motion.is_empty() and is_zero_approx(player.requested_motion.back()),"桥接不能绕过正常菜单的视角输入保护")
	for invalid_button in [1.0,null,{},"middle"]:
		bridge.active=true
		await bridge.perform({"id":"invalid_button","type":"mouse","button":invalid_button})
		var rejected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(bridge.ipc_root+"result.json"))
		assert(rejected.id=="invalid_button" and not rejected.error.is_empty() and not bridge.active,"非法按钮须返回错误并解除占用，不能卡住输入及保存退出")
	bridge.active=true
	await bridge.perform({"id":"capture_after_rejection","type":"capture"})
	var recovered: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(bridge.ipc_root+"result.json"))
	assert(recovered.id=="capture_after_rejection" and recovered.error.is_empty() and not bridge.active)
	assert(await bridge.stop_for_shutdown()=="","拒绝非法参数后仍应正常收束输入")
	print("PLAYER_BRIDGE_LOOK_PASSED focused_and_minimized_motion_normal_sensitivity_menu_protection; world_and_cloud_not_started")
	scene.queue_free();await process_frame
	quit()
