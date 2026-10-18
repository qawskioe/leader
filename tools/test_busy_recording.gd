extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
class Effect extends RefCounted:
	func get_frames_available() -> int: return 0
class FakeMic extends Node:
	var recording:=false
	var samples:=PackedVector2Array()
	var effect:=Effect.new()
	var noise_floor_db: float
	var level_db: float=-96.0
	func start() -> void: recording=true
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new(); scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=false; voice.survival.enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	var fake:=FakeMic.new(); voice.add_child(fake); voice.mic=fake
	voice.menu.close()
	voice.busy=true; voice._display_event_id="active"; voice._job_config={"active_job":true}
	voice._begin_recording()
	assert(fake.recording and voice._job_config=={"active_job":true} and voice._display_event_id=="active")
	fake.recording=false
	voice._on_captured({"ok":true,"db":-30.0,"duration_seconds":1.0,"clipped_ratio":0.0,"wav":PackedByteArray([1,2])})
	assert(voice._queued_capture_count()==1 and voice.busy)
	var saved: Dictionary=voice._pending_inputs[0].payload
	voice._spatial_samples.clear(); voice._positions.clear()
	assert(not saved.samples.is_empty() and not saved.positions.is_empty(),"排队录音保留独立空间快照")
	voice.busy=false
	voice._process(0.0)
	assert(voice._pending_inputs.is_empty() and not voice.busy,"当前任务结束后处理此前排队录音")
	print("BUSY_RECORDING_PASSED: capture_while_busy, active_job_unchanged, isolated_snapshot, queued_priority; real_microphone=false")
	scene.queue_free(); await create_timer(0.2).timeout; quit()
