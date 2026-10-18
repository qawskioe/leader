extends SceneTree
class GatheringDouble extends RefCounted:
	var cancellations:=0
	func cancel_player_action() -> void:cancellations+=1
class MicDouble extends Node:
	var recording:=true
	var recovering:=false
	var reconnect_required:=false
	var reconnects:=0
	func cancel() -> void: recording=false
	func invalidate_connection() -> void: reconnect_required=true
	func recover_connection(_device: String) -> bool:
		recovering=true;reconnects+=1
		await get_tree().process_frame
		recovering=false;reconnect_required=false
		return true
class VoiceDouble extends Node:
	var mic: Node
	var config={"input_device":"fixture"}
	var survival={"gathering":GatheringDouble.new()}
class RigDouble extends "res://scripts/vr/player_rig.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
func _initialize() -> void:
	create_timer(8).timeout.connect(func():quit(1))
	for action in ["player_interact","player_drink"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	run.call_deferred()
func run() -> void:
	var mic:=MicDouble.new();root.add_child(mic)
	var voice:=VoiceDouble.new();voice.mic=mic;root.add_child(voice)
	var rig:=RigDouble.new();rig.voice=voice;rig.focused=true;root.add_child(rig)
	Input.action_press("player_interact");Input.action_press("player_drink")
	rig._suspend()
	assert(not rig.focused and not mic.recording and mic.reconnect_required)
	assert(not Input.is_action_pressed("player_interact") and not Input.is_action_pressed("player_drink") and voice.survival.gathering.cancellations==1,"失焦同时取消计时交互与录音")
	rig._resume()
	assert(mic.recovering and mic.reconnects==1)
	rig._pressed("trigger_click")
	assert(rig.pending_speech==0,"重连期间不能假装录音已开始")
	await process_frame;await process_frame
	assert(not mic.reconnect_required and rig.focused)
	rig._resume()
	assert(mic.reconnects==1,"重复焦点通知不能重复开设备")
	rig._pressed("ax_button")
	await process_frame;await process_frame
	assert(mic.reconnects==2,"A键提供手动恢复入口")
	print("VR_AUDIO_RECOVERY_PASSED wake_rebind, no_record_while_recovering, dedupe, manual_a; actual_mic_signal_not_tested")
	rig.queue_free();voice.queue_free();mic.queue_free();await process_frame;quit()
