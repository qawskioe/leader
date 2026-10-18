extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const Mic=preload("res://scripts/voice/microphone.gd")
class FakeGateway extends Node:
	var calls: Array=[]
	func exchange(payload: Dictionary) -> Dictionary:
		calls.append(payload)
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify({"conversation":{"participation":"listen","addressees":[],"reason":"仅验证空间分段"},"intent":"none","capability_gap":null,"private_interpretation":"空间分段夹具","public_reply":"","speech_act":"statement","addressed_person":"","speech_style":"","routing_reason":"仅验证空间分段","task_status":"none","task_handling":{"state":"none","scope":"independent","reason":"仅验证空间分段"}})}
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(20).timeout.connect(func():push_error("spatial ASR timeout");quit(1))
	var audio:=AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes("res://tools/fixtures/command.wav"))
	assert(audio!=null and audio.format==AudioStreamWAV.FORMAT_16_BITS and not audio.stereo)
	var pcm:=PackedFloat32Array()
	for index in audio.data.size()/2: pcm.append(float(audio.data.decode_s16(index*2))/32768.0)
	# 复用仓库音频的前6.5秒，两段加停顿仍在正常15秒录音上限内。
	pcm=pcm.slice(0,int(audio.mix_rate*6.5))
	var duration:=float(pcm.size())/audio.mix_rate
	var pause:=PackedFloat32Array()
	pause.resize(int(audio.mix_rate*0.6))
	var combined:=pcm.duplicate()
	combined.append_array(pause)
	combined.append_array(pcm)
	assert(duration*2+0.6<=15.0)
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	scene.add_child(voice)
	voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	voice.config.local_only=false
	voice.config.tts_enabled=false
	voice.config.actions_enabled=false
	voice.config.noise_floor_db=-60.0
	voice.survival.enabled=false
	var fake:=FakeGateway.new()
	voice.add_child(fake)
	voice.pipeline.gateway=fake
	voice._job_config=voice.config.duplicate(true)
	voice._source=Vector3.ZERO
	voice._positions={"person_003":Vector3(0,0,-1),"person_002":Vector3(1,0,0)}
	for id in ["person_003","person_002"]:
		voice.survival.perception.memories[id].erase("person/player");voice.store.memory.observations[id].erase("person/player")
	for index in int((duration*2+0.6)*10):
		var time:=index*0.1
		var first: bool=time<duration+0.3
		voice._spatial_samples.append({"time":time,"source":Vector3.ZERO if first else Vector3(8,0,0),"forward":Vector3.FORWARD if first else Vector3.RIGHT,"positions":{"person_003":Vector3(0,0,-1),"person_002":Vector3(50,0,0)} if first else {"person_003":Vector3(50,0,-1),"person_002":Vector3(9,0,0)}})
	var result:=Mic.analyze(combined,audio.mix_rate,-60)
	result.wav=Mic.encode_wav(combined,audio.mix_rate)
	await voice._on_captured(result)
	# captured回调启动的是异步ASR；角色pipeline尚未开始时不能提前读取听闻结果。
	while voice.busy:await process_frame
	var event: Dictionary=voice._round_events.values().back()
	assert(event.spatial_segments.size()==2)
	assert(event.spatial_segments[0].focus_hint=="person_003")
	assert(event.spatial_segments[1].focus_hint=="person_002")
	assert(not event.spatial_segments[0].text.is_empty() and not event.spatial_segments[1].text.is_empty())
	assert(fake.calls.size()==2 and not voice.mic.recording)
	for id in ["person_003","person_002"]:
		var own: Dictionary=voice.store.people[id].heard_events.back()
		assert(own.spatial_segments.size()==1 and not own.has("player_voice_sources"),"听众只能获得实际听见的部分")
		var location: Dictionary=voice.survival.perception.known(id,"person/player")
		assert(location.position[0]==(0 if id=="person_003" else 8),"各自登记实际听见部分的声源位置")
	print("SPATIAL_ASR_PASSED ",JSON.stringify(event.spatial_segments))
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
