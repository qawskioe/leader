extends SceneTree
class Probe extends "res://scripts/voice/voice_test.gd":
	func _pump_speech() -> void: pass
	func log_event(_entry: Dictionary) -> void: pass
func _initialize() -> void: run.call_deferred()
func run() -> void:
	# 只检查队列入口；无需启动场景、渲染和后台麦克风线程。
	var voice:=Probe.new()
	voice._job_config={"tts_enabled":true,"actions_enabled":false}
	voice._round_events["failure"]={"kind":"skill_progress","speaker":"world"}
	voice._on_report({"event_id":"failure","person_id":"person_003","decision":{"intent":"none","public_reply":"刚才手里的石块碰到了障碍，我需要调整动作。"}})
	assert(voice._speech_queue.size()==1,"内部执行轮中的公开障碍说明必须进入语音队列")
	voice._on_report({"event_id":"failure","person_id":"person_003","decision":{"intent":"none","public_reply":""}})
	assert(voice._speech_queue.size()==1,"普通沉默动作不会额外生成播报")
	print("INTERNAL_SPEECH_PASSED failure_explanation_queued_silent_action_unchanged")
	voice.free();quit()
