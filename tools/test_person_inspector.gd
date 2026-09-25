extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var voice:=Voice.new(); voice.name="VoiceTest"; scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=false; voice.survival.enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	voice.store.record_execution({"person_id":"person_004","intent":"gather_food","source_event_id":"fixture","success":true,"message":"把四份果实存到储食处"})
	voice.store.record_execution({"person_id":"person_004","intent":"eat","source_event_id":"fixture2","success":true,"message":"吃完一份食物，饥饿降低"})
	voice.store.people.person_004.needs.hunger=23
	voice.survival._sync("person_004")
	voice.menu.close()
	var caption: Node=voice.captions.person_004
	caption.set_expanded(true)
	caption.inspector.refresh()
	assert(caption.inspector.overview.text.contains("月亮") and caption.inspector.overview.text.contains("纤维编织"))
	assert(caption.inspector.overview.text.contains("休息") and caption.inspector.overview.text.contains("四份果实"))
	assert(caption.inspector.knowledge.text.contains("篮子") and caption.inspector.history.text.contains("吃完一份"))
	assert(not caption.inspector.overview.text.contains("刚才的实际结果"),"空闲人物不能把历史结果当成当前原因")
	voice.busy=true;voice._speech_order=["person_004"];voice._reports_received.clear()
	caption.hearing_until=0;caption._process(0)
	assert(caption.hearing_text=="已听见 · 正在理解","请求尚未返回时持续显示等待")
	voice._reports_received["person_004"]={};voice.busy=false;caption._process(0)
	assert(caption.hearing_text.is_empty(),"请求结束不残留等待")
	assert(caption.inspector.current_tab==0 and not caption.details.is_visible_in_tree())
	# 展开的档案不因人物转身或走出视线而消失。
	caption.visible=false; caption._process(0)
	assert(caption.expanded and caption.bubble.visible)
	for button in voice.menu.panel.find_children("*","Button",true,false):
		if button.get_meta("person_id","")=="person_001": button.pressed.emit()
	var found:=false
	for view in voice.menu.panel.find_children("*","TabContainer",true,false):
		if view.has_method("refresh"):
			print("MENU_SELECTION ",view.person_id," ",view.overview.text.left(60))
			assert(view.person_id=="person_001" and view.overview.text.contains("石头"))
			found=true
	assert(found,"F1 以人物选择切换完整档案")
	if DisplayServer.get_name()!="headless":
		for frame in 5: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/person_inspector.png")
	print("PERSON_INSPECTOR_PASSED: person_identity, live_status, knowledge, recent_results, technical_secondary, stable_selection")
	scene.queue_free(); await create_timer(0.2).timeout; quit()
