extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const Mic=preload("res://scripts/voice/microphone.gd")
class FakeGateway extends Node:
	var calls: Array=[]
	func exchange(payload: Dictionary) -> Dictionary:
		calls.append(payload)
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify({"intent":"none","recipient_id":"","capability_gap":null,"private_interpretation":"夹具","public_reply":"","speech_act":"statement","addressed_person":"","speech_style":"neutral","routing_reason":"夹具"})}
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var audio:=AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes("res://services/gemini-tts/runtime/survival_command.wav"))
	assert(audio!=null and audio.format==AudioStreamWAV.FORMAT_16_BITS and not audio.stereo)
	var pcm:=PackedFloat32Array()
	for index in audio.data.size()/2: pcm.append(float(audio.data.decode_s16(index*2))/32768.0)
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
	for index in int((duration*2+0.6)*10):
		var time:=index*0.1
		voice._spatial_samples.append({"time":time,"source":Vector3.ZERO,"forward":Vector3.FORWARD if time<duration+0.3 else Vector3.RIGHT,"positions":voice._positions})
	var result:=Mic.analyze(combined,audio.mix_rate,-60)
	result.wav=Mic.encode_wav(combined,audio.mix_rate)
	await voice._on_captured(result)
	if voice.pipeline.busy: await voice.pipeline.completed
	var event: Dictionary=voice.store.people.person_003.heard_events.back()
	assert(event.spatial_segments.size()==2)
	assert(event.spatial_segments[0].focus_hint=="person_003")
	assert(event.spatial_segments[1].focus_hint=="person_002")
	assert(not event.spatial_segments[0].text.is_empty() and not event.spatial_segments[1].text.is_empty())
	assert(fake.calls.size()==2 and not voice.mic.recording)
	print("SPATIAL_ASR_PASSED ",JSON.stringify(event.spatial_segments))
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
