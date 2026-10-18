extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new(); voice.name="VoiceTest"; scene.add_child(voice)
	voice.config.local_only=false; voice.config.autonomy_enabled=true; voice.config.actions_enabled=true; voice.config.tts_enabled=false
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	voice.reset_gather_scenario()
	var reports: Array=[]
	voice.pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	var deadline:=Time.get_ticks_msec()+330000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.5).timeout
		if voice.survival.eaten>=2 and not voice.busy: break
	var passed: bool=voice.survival.eaten>=2 and voice.survival.gathering.harvested>=2 and reports.all(func(r: Dictionary): return not r.has("error"))
	var data:={"passed":passed,"reports":reports,"eaten":voice.survival.eaten,"harvested":voice.survival.gathering.harvested,"stock":voice.survival.storage_food,"log":voice._log_path}
	var file:=FileAccess.open("res://services/text-gateway/runtime/arrival_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	print("ARRIVAL_LIVE ",passed," calls=",reports.size()," eaten=",voice.survival.eaten," harvested=",voice.survival.gathering.harvested)
	scene.queue_free(); await create_timer(0.2).timeout; quit(0 if passed else 1)
