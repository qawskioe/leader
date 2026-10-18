extends RefCounted
## 玩家操作状态与系统鼠标捕获分开；自动桥接只改变前者。
const AUTOMATION_GROUP:="player_control_mouse"
static func _bridge(context: Node) -> Node:
	return context.get_tree().get_first_node_in_group(AUTOMATION_GROUP) if context.is_inside_tree() else null
static func is_automated(context: Node) -> bool:
	return OS.get_cmdline_user_args().has("--player-control") or _bridge(context)!=null
static func get_mode(context: Node) -> int:
	var bridge:=_bridge(context)
	if bridge!=null:return bridge.virtual_mouse_mode
	# Player先于VoiceTest/PlayerControl创建；自动启动时也不能捕获真实鼠标。
	return Input.MOUSE_MODE_CAPTURED if OS.get_cmdline_user_args().has("--player-control") else Input.mouse_mode
static func set_mode(context: Node, mode: int) -> void:
	var bridge:=_bridge(context)
	if bridge!=null:
		bridge.virtual_mouse_mode=mode
	elif not OS.get_cmdline_user_args().has("--player-control"):
		Input.mouse_mode=mode
static func is_captured(context: Node) -> bool:
	return get_mode(context)==Input.MOUSE_MODE_CAPTURED
