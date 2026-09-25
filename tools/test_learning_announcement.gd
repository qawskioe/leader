extends SceneTree
class HeldSpeech extends "res://scripts/voice/voice_test.gd":
	func _pump_speech() -> void: pass
class Recorder extends Node:
	var calls:=0
	func request_learning(_id: String, _event: Dictionary, _request: Dictionary) -> Dictionary:
		calls+=1
		return {"ok":true}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=HeldSpeech.new();scene.add_child(voice)
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=true;voice._allow_execution=true;voice._job_config=voice.config.duplicate(true)
	while not voice.survival.ready_for_actions: await physics_frame
	var recorder:=Recorder.new();scene.add_child(recorder);voice.skills=recorder
	var event={"id":"self_plan","speaker":"player","kind":"speech_intent","text":"喝水"}
	voice.store.hear("person_003",event)
	var plan={"intent":"none","recipient_id":"","capability_gap":null,"private_interpretation":"没有已知老师","routing_reason":"说明自学理由","learning_request":{"goal_id":"drink_nearby"},"public_reply":"我不知道附近谁会，我先自己试着学。","speech_style":"平静说明","speech_act":"reply","addressed_person":"player"}
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":event.id,"decision":plan,"calls":[]})
	assert(recorder.calls==0 and voice._speech_queue.size()==1,"自学前先排队说明，不抢先编写")
	voice._deliver_public("person_003",event.id,plan.public_reply,10,plan)
	assert(recorder.calls==1,"完整公开说明后才启动自学")
	print("LEARNING_ANNOUNCEMENT_PASSED queued_before_build, public_delivery_starts_build; real_tts=0, model_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
