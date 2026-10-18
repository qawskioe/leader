extends SceneTree
class PipelineDouble extends Node:
	var events: Array=[]
	func run(event: Dictionary, _config: Dictionary) -> void:events.append(event)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("player voice location timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;sim.enabled=false
	var receiver: Node3D=sim.actors.person_001.body
	receiver.global_position=Vector3(1,.2,6);receiver.rotation.y=PI/2
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	player.global_position=Vector3(-2,.2,6)
	for id in ["person_001","person_003"]:
		sim.perception.memories[id].erase("person/player");voice.store.memory.observations[id].erase("person/player")
	await physics_frame
	assert(not sim.perception.sees("person_001",player.global_position+Vector3.UP))
	var source: Vector3=player.global_position+Vector3.UP*1.66
	var packet:={"id":"fixture_player_sound","kind":"speech_intent","speaker":"player","listeners":["person_001"],"text":"请来找我。","source_position":[source.x,source.y,source.z],"heard_at_seconds":20.0}
	packet.player_voice_sources={"person_001":{"position":[source.x,source.y,source.z],"at_seconds":20.0},"person_003":{"position":[50,1.6,50],"at_seconds":20.0}}
	packet.source_position=[100,1.6,100] # 不能用她没听到的全句起点覆盖本人部分的声源。
	# 模拟输入排队期间移动，处理时仍只能获知原声源与原时间。
	player.global_position=Vector3(50,.2,50);sim.perception.clock=80
	var probe:=PipelineDouble.new();voice.add_child(probe);voice.pipeline=probe
	voice._start_pipeline(packet,voice.config)
	var heard: Dictionary=sim.perception.known("person_001","person/player")
	assert(heard.heard_from=="player" and heard.source_event_id==packet.id and heard.heard_at_seconds==20)
	assert(not heard.visible_now and heard.position_error_per_axis_m>0 and heard.position_error_per_axis_m<.5 and heard.extra.is_empty())
	assert(Vector3(heard.position[0],heard.position[1],heard.position[2]).distance_to(source-Vector3.UP*1.6)<2)
	assert(sim.perception.known("person_003","person/player").is_empty(),"未听见者不能取得玩家位置")
	var position: Array=heard.position.duplicate()
	sim.perception.observe("person_001")
	assert(sim.perception.known("person_001","person/player").position==position,"不能跟踪未看见的移动")
	voice._start_pipeline({"id":"fixture_followup","kind":"skill_progress","speaker":"world","listeners":["person_003"],"text":"过去请求的续办","original_event":packet},voice.config)
	assert(sim.perception.known("person_003","person/player").is_empty(),"续办事件不能重新传播过去的声音")
	assert(sim.perception.hear_voice("person_001","player","fixture_newer_sound",Vector3(4,1.8,6),60))
	var newer: Dictionary=sim.perception.known("person_001","person/player")
	voice._start_pipeline(packet,voice.config)
	assert(sim.perception.known("person_001","person/player")==newer,"迟到旧声源不能覆盖更新的线索")
	player.global_position=receiver.global_position+Vector3(3,0,0);sim.perception.observe("person_001")
	var visible: Dictionary=sim.perception.known("person_001","person/player")
	assert(visible.visible_now)
	voice._start_pipeline(packet,voice.config)
	assert(sim.perception.known("person_001","person/player")==visible,"当前目视不应被旧粗略声源覆盖")
	assert(probe.events.size()==4)
	print("PLAYER_VOICE_LOCATION_PASSED real_dispatch_listener_only_queued_pose_time_not_tracking_visual_priority")
	scene.queue_free();await create_timer(.2).timeout;quit()
