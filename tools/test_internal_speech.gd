extends SceneTree
class Probe extends "res://scripts/voice/voice_test.gd":
	func _pump_speech() -> void: pass
	func log_event(_entry: Dictionary) -> void: pass
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Probe.new();scene.add_child(voice);voice.set_process(false)
	voice._job_config={"tts_enabled":true,"actions_enabled":false}
	voice._round_events["failure"]={"kind":"skill_progress","speaker":"world"}
	voice._on_report({"event_id":"failure","person_id":"person_003","decision":{"intent":"none","public_reply":"刚才手里的石块碰到了障碍，我需要调整动作。"}})
	assert(voice._speech_queue.size()==1,"内部执行轮中的公开障碍说明必须进入语音队列")
	voice._on_report({"event_id":"failure","person_id":"person_003","decision":{"intent":"none","public_reply":""}})
	assert(voice._speech_queue.size()==1,"普通沉默动作不会额外生成播报")
	print("INTERNAL_SPEECH_PASSED failure_explanation_queued_silent_action_unchanged")
	scene.queue_free();await create_timer(0.2).timeout;quit()
