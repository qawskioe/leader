extends SceneTree
## 离线回放真实状态轮询与排版边界，不启动编写进程或云端请求。
const Voice=preload("res://scripts/voice/voice_test.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.survival.enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	create_timer(20).timeout.connect(func():push_error("人物详情排版回归超时");quit(1))
	voice.menu.close();voice.skills.set_process(false)
	voice.set_process(false)
	for card in voice.captions.values():card.set_process(false)
	var id:="person_004"
	var job:="job_progress_fixture_"+str(Time.get_ticks_usec())
	var folder:="res://services/skill-runtime/runtime/jobs/"+job
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))==OK)
	var file:=FileAccess.open(folder+"/status.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"state":"writing","model":"fixture","message":"Codex：mcp_tool_call"}));file.close()
	var original:={"id":"learning_view_fixture","kind":"speech_intent","speaker":"player","text":"请学会带我去果树林，我掉队就等我，跟上再走。"}
	voice.skills.learning[id]={"job":job,"pid":OS.get_process_id(),"started":Time.get_ticks_msec(),"goal_id":"lead_fixture","goal":"带玩家到记得的果树林，实际检查是否跟上。","original_event":original}
	voice.survival.actors[id].stage="skill_learning"
	voice.survival.actors[id]["skill_owner"]=voice.skills.get_instance_id()
	voice.skills._process(0.4)
	var learning: Dictionary=voice.store.people[id].learning
	assert(learning.request_text==original.text and learning.goal_id=="lead_fixture")
	assert(learning.message=="正在编写和检查方法" and learning.technical_message=="Codex：mcp_tool_call")
	assert(not voice.store.context_for(id).learning.has("technical_message"),"工具内部进度不进入角色判断输入")
	var caption: Node=voice.captions[id]
	caption.set_expanded(true);caption.inspector.refresh();caption._process(0)
	assert(caption.inspector.overview.text.contains("收到的要求："+original.text))
	assert(caption.inspector.overview.text.contains(learning.goal) and not caption.inspector.overview.text.contains("mcp_tool_call"))
	caption.inspector.current_tab=4
	assert(caption.inspector.raw.text.contains("mcp_tool_call"),"开发原始记录仍可随时查看")
	caption.inspector.current_tab=0
	var camera: Camera3D=root.get_camera_3d()
	assert(camera!=null)
	# 强制详情投影到左侧，与真实玩家台词区域相邻，验证实际容器布局。
	caption.global_position=camera.global_position-camera.global_basis.z*4+camera.global_basis.x*2-Vector3(0,2.25,0)
	voice.player_input_note.text="你说："+original.text+"\n听众：月亮"
	for viewport_size in [Vector2i(1280,800),Vector2i(800,600)]:
		root.size=viewport_size
		for note_y in [12.0,float(viewport_size.y)-84.0]:
			voice.player_input_note.position=Vector2(12,note_y)
			for frame in 4:await process_frame
			caption._process(0)
			await process_frame
			var panel: Rect2=caption.bubble.get_global_rect()
			var note: Rect2=voice.player_input_note.get_global_rect()
			assert(caption.bubble.visible)
			assert(not panel.intersects(note),"详情挡住玩家台词："+str(panel)+" / "+str(note))
			assert(Rect2(Vector2.ZERO,Vector2(viewport_size)).encloses(panel),"详情超出视口："+str(panel))
	caption.set_expanded(false)
	caption.global_position=camera.global_position-camera.global_basis.z*2.5-camera.global_basis.x*.7+Vector3(0,-1.1,0)
	caption.begin_public("请跟着我。\n看不见你，我会等。\n你跟上以后，我再走。\n一起到达果树林再停。")
	for viewport_size in [Vector2i(1280,800),Vector2i(800,600)]:
		root.size=viewport_size
		for frame in 4:await process_frame
		voice.player_input_note.position=Vector2(12,12);caption._process(0)
		var card: Rect2=caption.head_panel.screen_rect(camera)
		assert(card.intersects(voice.player_input_note.get_global_rect()),"重现正式控制器的卡片遮挡前提")
		voice._position_player_note()
		assert(not card.grow(8).intersects(voice.player_input_note.get_global_rect()),"正式控制器未让出台词区域")
		var at: Vector2=voice.player_input_note.position
		voice._position_player_note();assert(voice.player_input_note.position==at,"无遮挡后不反复换角落")
		voice.player_input_note.hide();voice._position_player_note()
		assert(voice.player_input_note.position==at,"VR隐藏的桌面台词不参与排版")
		voice.player_input_note.show()
	voice.skills._end_learning(id,false,"测试：环境无法启动终端")
	assert(voice.store.people[id].learning.state=="failed" and voice.store.people[id].learning.request_text==original.text)
	voice.store.working_tasks.erase(id);caption._process(0)
	assert(caption.skill_status.text.is_empty(),"旧学习记录不能覆盖当前空闲/行动状态")
	# 相邻旁听者仍给出听闻提示，但不与视线目标一起展示完整状态卡。
	var other: Node=voice.captions["person_003"]
	for card in voice.captions.values():card.visible=card==caption or card==other
	other.global_position=camera.global_position-camera.global_basis.z*3+camera.global_basis.x*1.5-Vector3(0,1.1,0)
	for card in [caption,other]:card.public_text="";card.remaining=0;card.speaking=false
	voice.busy=true;voice._speech_order=[id,"person_003"];voice._reports_received.clear()
	caption._process(0);other._process(0)
	assert(caption._focus_target(camera)==caption)
	assert(caption.head_panel.title.text.contains("E 详情") and not other.head_panel.title.text.contains("E 详情"),"E提示只能属于实际视线目标")
	assert(other.head_panel.title.text.contains("听见") and not other.head_panel.status.visible,"旁听提示不能展开完整人物状态")
	var key:=InputEventKey.new();key.physical_keycode=KEY_E;key.pressed=true
	other._input(key);caption._input(key)
	assert(caption.expanded and not other.expanded,"按E与状态卡使用同一个视线目标")
	caption.set_expanded(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder+"/status.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("LEARNING_PROGRESS_VIEW_PASSED goal_preserved, human_phase, raw_access, model_boundary, transcript_clear, viewport_fit, head_card_clear, no_stale_status; real_model_calls=0")
	scene.queue_free();await process_frame;quit()
