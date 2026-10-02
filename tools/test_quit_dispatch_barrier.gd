extends SceneTree
class VoiceProbe extends "res://scripts/voice/voice_test.gd":
	var dispatches:=0
	func _try_autonomy() -> void:dispatches+=1
class SessionProbe extends "res://scripts/survival/session_controller.gd":
	func _message(text: String, error: bool=false) -> void:
		super._message(text,error)
		if text.begins_with("已保存"):
			# 保存已解锁、SceneTree尚未真正退出的窗口，模拟正常帧调度。
			host._process(0)
			if host.dispatches!=0:
				push_error("退出保存后重新发起了自主判断");get_tree().quit(1);return
			print("QUIT_DISPATCH_BARRIER_PASSED saved_without_new_decisions")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("quit dispatch test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=VoiceProbe.new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	voice.session_manager.queue_free()
	var session:=SessionProbe.new();session.host=voice;voice.add_child(session);voice.session_manager=session
	session.path="user://sessions/quit_dispatch_%d.json"%Time.get_ticks_usec()
	voice.menu.close();voice._pending_captures.clear();voice._player_offers.clear();voice._execution_feedback.clear()
	session.load_failed=true
	await session.quit_game()
	assert(not session.quitting,"存档失败后必须取消退出状态，保留人工处理入口")
	session.load_failed=false;voice.menu.close()
	await session.quit_game()
