extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=false
	voice.survival.enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	voice.capability_gap_path="res://services/text-gateway/runtime/test_capability_gaps.json"
	var file:=FileAccess.open(voice.capability_gap_path,FileAccess.WRITE)
	file.store_string("{}"); file.close()
	var report:={"person_id":"person_004","event_id":"gap_test","decision":{"capability_gap":{"goal":"制作衣物","missing_capability":"缝制衣服","reason":"目前目录没有制衣行为"}}}
	voice._record_capability_gap(report)
	voice._record_capability_gap(report)
	assert(voice.captions.person_004.capability_label.visible)
	assert(voice._capability_gaps.size()==1 and voice._capability_gaps.values()[0].occurrences==2)
	voice._capability_gaps.clear()
	voice._record_capability_gap(report)
	assert(voice._capability_gaps.values()[0].occurrences==3,"重载后保留历史候选")
	report.decision.capability_gap.missing_capability="give_food"
	voice._record_capability_gap(report)
	assert(voice._capability_gaps.values()[1].status.contains("已有"),"已存在的接口不能确认成缺失")
	assert(voice.autonomy.requests.is_empty(),"缺口记录不自动触发开发或新一轮判断")
	print("CAPABILITY_GAPS_PASSED: persisted, deduped, candidate_only, existing_action_detected; cloud_calls=0")
	scene.queue_free(); await create_timer(0.15).timeout
	quit()
