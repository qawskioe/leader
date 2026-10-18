extends SceneTree
## 使用真实显示服务检查捕获状态；不启动生活模拟、账号或正式存档。
class MenuStub extends RefCounted:
	func is_open() -> bool:return false
class VoiceStub extends Node:
	var menu=MenuStub.new()
	var captions: Dictionary={}

func _initialize() -> void:run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("鼠标捕获验证需要实际显示服务");quit(2);return
	var scene:=Node3D.new();root.add_child(scene)
	var player=preload("res://scripts/first_person_controller.gd").new()
	player.set_physics_process(false);scene.add_child(player)
	var voice:=VoiceStub.new();voice.name="VoiceTest";scene.add_child(voice)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"正常输入失焦时释放鼠标")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"正常输入重新聚焦后捕获鼠标")
	var bridge=preload("res://scripts/player_control.gd").new()
	bridge.set_process(false);voice.add_child(bridge)
	bridge.active=true
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED,"桥接保持逻辑操作状态且不捕获真实鼠标")
	bridge.active=false
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED,"桥接未执行时也不把真实焦点写回逻辑状态")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and bridge.virtual_mouse_mode==Input.MOUSE_MODE_CAPTURED)
	print("PLAYER_FOCUS_PASSED normal_release_restore_bridge_never_native_capture; world_and_cloud_not_started")
	scene.queue_free();await process_frame;quit()
