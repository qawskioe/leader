extends SceneTree
## 私有桌面的无模型真实输入/正式保存退出；unsafe仅复现旧退出遗漏。
class VoiceProbe extends "res://scripts/voice/voice_test.gd":
	func _prepare_desktop_microphone() -> void:pass
class SessionProbe extends "res://scripts/survival/session_controller.gd":
	var bridge: Node
	func _message(text: String, error: bool=false) -> void:
		super._message(text,error)
		if text.begins_with("已保存"):
			assert(not bridge.active and bridge._stopping and not bridge.is_processing(),"保存退出前必须排空输入并停止接单")
			assert(not Input.is_action_pressed("player_forward"),"退出不能留下按键按住")
			var command:=FileAccess.open(bridge.ipc_root+"command.json",FileAccess.WRITE)
			command.store_string(JSON.stringify({"id":"too_late","type":"key","key":"W"}));command.close()
			bridge._process(0.2)
			assert(FileAccess.file_exists(bridge.ipc_root+"command.json") and not bridge.active,"退出期间的新桥接输入不得执行")
			var next_bridge:=preload("res://scripts/player_control.gd").new();next_bridge.ipc_root=bridge.ipc_root
			get_tree().root.add_child(next_bridge);next_bridge.set_process(false)
			assert(not FileAccess.file_exists(bridge.ipc_root+"command.json") and not Input.is_action_pressed("player_forward"),"新进程桥接初始化须丢弃旧未接收输入")
			next_bridge.queue_free()
			print("PLAYER_CONTROL_SHUTDOWN_PASSED pending_key_drained_released_no_new_intake_normal_save_quit; cloud_calls=0")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("player bridge shutdown timeout");quit(1))
	assert(DisplayServer.get_name()!="headless" and "--player-control" in OS.get_cmdline_user_args(),"须用私有桌面显示且禁止系统捕获")
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=VoiceProbe.new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	voice.session_manager.path="user://sessions/player_bridge_shutdown_%d.json"%Time.get_ticks_usec()
	var bridge: Node=voice.get_node("PlayerControl");bridge.set_process(false)
	bridge.ipc_root="user://player_bridge_shutdown_%d/"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bridge.ipc_root))
	while not voice.survival.ready_for_actions or voice.session_manager.booting:await physics_frame
	voice.menu.close();bridge.active=true
	var pending_capture: bool="--pending-capture" in OS.get_cmdline_user_args()
	bridge.perform({"id":"pending_capture","type":"capture"} if pending_capture else {"id":"pending_key","type":"key","key":"W","seconds":2.0})
	await process_frame
	assert(bridge.active and (pending_capture or Input.is_action_pressed("player_forward")),"需要真实尚未完成的异步输入或截图")
	if "--unsafe" in OS.get_cmdline_user_args():
		print("PLAYER_CONTROL_UNSAFE_PENDING_QUIT_REPRODUCED")
		quit();return
	if "--drain-control" in OS.get_cmdline_user_args():
		while bridge.active:await process_frame
		assert(not Input.is_action_pressed("player_forward"))
		print("PLAYER_CONTROL_DRAIN_CONTROL_PASSED operation_completed_before_quit; cloud_calls=0")
		quit();return
	voice.session_manager.queue_free()
	var session:=SessionProbe.new();session.host=voice;session.bridge=bridge;voice.add_child(session);voice.session_manager=session
	session.path="user://sessions/player_bridge_shutdown_saved_%d.json"%Time.get_ticks_usec()
	session.load_failed=true
	await session.quit_game()
	assert(not session.quitting and not bridge._stopping and bridge.is_processing(),"保存失败后必须恢复桥接接单")
	session.load_failed=false;voice.menu.close();bridge.active=true
	bridge.perform({"id":"pending_key_retry","type":"key","key":"W","seconds":0.4})
	await process_frame
	assert(bridge.active and Input.is_action_pressed("player_forward"),"保存失败后须仍能执行新输入")
	await session.quit_game()
