extends Node
## 本机识别 → 独立结构化判断 → 仅公开台词的 Gemini 流式空间语音。

const Caption = preload("res://scripts/voice/character_caption.gd")
var captions: Dictionary = {}
var _display_event_id := ""
var _display_round := 0
var _skill_playtest_waiting:=false
var _skill_playtest_started:=false
var _input_generation:=0
var _active_speech_output: Node
var _event_rounds: Dictionary = {}
var _round_events: Dictionary = {}
var _cancelled_player_tasks: Dictionary = {}
var _recording_config: Dictionary={}
var _pending_captures: Array[Dictionary]=[]
var _player_offers: Array[Dictionary]=[]
var player_input_note: Label
var last_player_transcript := ""
var _capability_gaps: Dictionary = {}
var capability_gap_path:="user://capability_gaps.json"
const TurnContext=preload("res://scripts/voice/turn_context.gd")

const Spatial = preload("res://scripts/voice/spatial_speech.gd")
var _spatial_samples: Array = []
var _recording_started := 0
var _last_spatial_sample := -100

const PeopleStore = preload("res://scripts/voice/people_store.gd")
const CapsWriter = preload("res://scripts/voice/capswriter_client.gd")
var capswriter: Node
const Cloud = preload("res://scripts/voice/cloud_client.gd")
const Pipeline = preload("res://scripts/voice/decision_pipeline.gd")
const Mic = preload("res://scripts/voice/microphone.gd")
const Menu = preload("res://scripts/voice/voice_menu.gd")
const Gateway = preload("res://scripts/voice/text_gateway_client.gd")
const TTS = preload("res://scripts/voice/tts_client.gd")
const SpeechOutput = preload("res://scripts/voice/tts_output.gd")
const Autonomy=preload("res://scripts/survival/autonomy.gd")
var autonomy:=Autonomy.new()
const HelpTasks=preload("res://scripts/survival/help_tasks.gd")
var help_tasks:=HelpTasks.new()
var information_waits:=preload("res://scripts/survival/information_waits.gd").new()
var _social_requests: Dictionary={} # 仅宿主持有请求者原任务，不能泄露给被请求者。
var _autonomy_clock:=0.0
var _speech_order: Array=[]
var _reports_received: Dictionary={}

const Survival = preload("res://scripts/survival/simulation.gd")
var survival: Node
const Skills=preload("res://scripts/skills/controller.gd")
var skills: Node
var social_learning: Node
var _execution_feedback: Array[Dictionary] = []
var _completed_assistance: Dictionary = {}
var _allow_execution := false
var tts: Node
var _speech_queue: Array[Dictionary] = []
var _speech_busy := false
var _decisions_done := false
const CONFIG_PATH := "user://voice_config.json"
var config := {"asr_url":"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions","asr_model":"qwen3-asr-flash","asr_key":"","noise_floor_db":-48.0,"quiet_db":-40.0,"loud_db":-15.0,"input_device":"Default","local_only":true}
var store := PeopleStore.new()
var cloud: Node
var gateway: Node
var pipeline: Node
var mic: Node
var menu: CanvasLayer
var busy := false
var cancel_recording_on_focus_loss := true
var session_manager: Node
var _positions: Dictionary = {}
var _source := Vector3.ZERO
var _job_config: Dictionary = {}
var _event_started := 0
var _log_path := ""
var _snapshot_path := ""
var _public_dialogue: Array[Dictionary] = []

func _ready() -> void:
	config["capswriter_asr"] = true
	config["local_only"] = false
	config["tts_enabled"] = true
	config["actions_enabled"] = true
	config["autonomy_enabled"] = true
	var error := store.initialize("res://data/people.json","" if DisplayServer.get_name()=="headless" else "user://memory/characters.json")
	assert(error.is_empty(), error)
	for id in store.people:
		assert(get_parent().get_node_or_null("People/" + store.people[id].node) != null, "人物数据与场景节点不一致")
	for id in store.people:
		var caption:=Caption.new()
		get_parent().get_node("People/"+store.people[id].node).add_child(caption)
		caption.set_person_name(store.people[id].name)
		caption.controller=self
		caption.person_id=id
		caption.details.people=store.people
		captions[id]=caption
	survival = Survival.new()
	survival.store = store
	survival.scene = get_parent()
	add_child(survival)
	skills=Skills.new();skills.sim=survival;skills.store=store;add_child(skills)
	var skill_error: String=skills.initialize_current("user://skills/tests/"+str(Time.get_ticks_usec())+".json") if DisplayServer.get_name()=="headless" else skills.initialize_current()
	assert(skill_error.is_empty(),skill_error)
	skills.finished.connect(_on_skill_result)
	skills.learning_finished.connect(_on_learning_finished)
	social_learning=preload("res://scripts/skills/social_learning.gd").new()
	social_learning.skills=skills;social_learning.sim=survival;social_learning.store=store;add_child(social_learning)
	social_learning.event_ready.connect(func(event: Dictionary): autonomy.offer_request(event,_autonomy_clock))
	social_learning.changed.connect(log_event)
	social_learning.load_knowledge()
	survival.action_result.connect(_on_action_result)
	survival.life_world.fact.connect(_on_world_fact)
	survival.gathering.item_offered.connect(func(event: Dictionary): _player_offers.append(event))
	survival.handover.offered.connect(func(event: Dictionary): _player_offers.append(event))
	survival.gathering.interaction_result.connect(func(result: Dictionary): log_event({"type":"player_interaction","message":"玩家操作："+str(result.get("message",str(result.action)+("已递出，等待对方决定" if result.get("pending",false) else "完成" if result.ok else "未完成，请检查距离、双手与篮子容量"))),"interaction":result}))
	if FileAccess.file_exists(CONFIG_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if saved is Dictionary:
			for key in config:
				if saved.has(key) and typeof(saved[key]) == typeof(config[key]):
					config[key] = saved[key]
	capswriter = CapsWriter.new()
	add_child(capswriter)
	cloud = Cloud.new()
	add_child(cloud)
	gateway = Gateway.new()
	add_child(gateway)
	tts = TTS.new()
	add_child(tts)
	pipeline = Pipeline.new()
	pipeline.space=survival.space
	pipeline.gateway = gateway
	pipeline.store = store
	add_child(pipeline)
	pipeline.report_ready.connect(_on_report)
	pipeline.completed.connect(_on_completed)
	mic = Mic.new()
	add_child(mic)
	mic.captured.connect(_on_captured)
	_prepare_desktop_microphone.call_deferred()
	session_manager=preload("res://scripts/survival/session_controller.gd").new();session_manager.host=self;add_child(session_manager)
	menu = Menu.new()
	menu.controller = self
	add_child(menu)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://voice_tests"))
	var session := "%s_%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	_log_path = "user://voice_tests/" + session + ".jsonl"
	_snapshot_path = "user://voice_tests/" + session + "_people.json"
	var input_layer:=CanvasLayer.new()
	input_layer.layer=9; add_child(input_layer)
	player_input_note=Label.new()
	player_input_note.position=Vector2(12,12)
	player_input_note.size=Vector2(550,72)
	player_input_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	player_input_note.max_lines_visible=3
	player_input_note.add_theme_color_override("font_shadow_color",Color.BLACK)
	player_input_note.add_theme_constant_override("shadow_offset_x",2)
	player_input_note.add_theme_constant_override("shadow_offset_y",2)
	input_layer.add_child(player_input_note)
	log_event({"type":"session","message":"按住 V 说话；T 输入文字；E 展开人物信息。采集：F 拿篮子／摘果／逐份卸货，右键装篮，G 放下篮子。F1 查看说明与记录。","log_path":ProjectSettings.globalize_path(_log_path)})
	var text_input=preload("res://scripts/voice/player_text_input.gd").new();text_input.voice=self;add_child(text_input)
	if OS.get_cmdline_user_args().has("--player-control"): add_child(preload("res://scripts/player_control.gd").new())
	var startup_scenario:=""
	for option in ["luau-playtest","gather-scenario","help-scenario"]:
		if OS.get_cmdline_user_args().has("--"+option):startup_scenario=option;break
	if DisplayServer.get_name()!="headless" or not startup_scenario.is_empty():
		get_tree().auto_accept_quit=false;session_manager.booting=true;session_manager.startup.call_deferred(startup_scenario)
	if not config_error(true).is_empty():
		menu.open()
func config_error(require_asr: bool) -> String:
	if config.get("tts_enabled",true) and not TTS.config_error().is_empty():
		return TTS.config_error()
	var error:=validate_config(config, require_asr and not config.get("capswriter_asr",false))
	if not error.is_empty(): return error
	return Gateway.config_error()

static func validate_config(value: Dictionary, require_asr: bool) -> String:
	var fields: Array[String] = []
	if require_asr:
		fields.append_array(["asr_url", "asr_key", "asr_model"])
	for key in fields:
		if not value.get(key) is String or value[key].strip_edges().is_empty():
			return "请配置：" + key
	for key in (["asr_url"] if require_asr else []):
		if not value[key].begins_with("https://"):
			return "接口必须使用 HTTPS：" + key
	for key in ["noise_floor_db", "quiet_db", "loud_db"]:
		if not value.get(key) is float and not value.get(key) is int:
			return "音量参数必须是数字：" + key
		if not is_finite(float(value[key])) or value[key] < -90 or value[key] > 0:
			return "音量参数必须在 -90 到 0 dBFS 之间：" + key
	if value.quiet_db >= value.loud_db or value.noise_floor_db > value.quiet_db:
		return "需要：噪声阈值 ≤ 轻声电平 < 大声电平"
	return ""

func save_config(value: Dictionary) -> String:
	if busy or mic.recording:
		return "本次请求结束后再修改配置"
	# 允许先保存尚未填完的供应商配置；数值不能无效。
	for key in ["noise_floor_db", "quiet_db", "loud_db"]:
		if not is_finite(float(value[key])) or value[key] < -90 or value[key] > 0:
			return "音量参数必须在 -90 到 0 dBFS 之间"
	if value.quiet_db >= value.loud_db or value.noise_floor_db > value.quiet_db:
		return "需要：噪声阈值 ≤ 轻声电平 < 大声电平"
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return "无法保存本机配置"
	config = value.duplicate(true)
	file.store_string(JSON.stringify(config, "\t"))
	return ""

func _input(event: InputEvent) -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	if (focused is TextEdit and focused.editable) or focused is LineEdit: return
	if event is InputEventKey and not event.echo:
		if event.physical_keycode==KEY_BACKSPACE and event.pressed and not menu.is_open():
			cancel_interaction();get_viewport().set_input_as_handled();return
		if event.physical_keycode == KEY_F1 and event.pressed:
			if mic.recording:
				mic.cancel()
				log_event({"type":"cancelled","message":"打开菜单，取消本次录音"})
			for caption in captions.values():
				if caption.expanded: caption.set_expanded(false)
			menu.toggle()
			get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_V:
			set_voice_input(event.pressed)
			get_viewport().set_input_as_handled()

func set_voice_input(pressed: bool) -> void:
	if pressed:
		if menu.is_open():
			log_event({"type":"input_rejected","message":"菜单打开，未开始录音；关闭菜单后再说话"})
		else: _begin_recording()
	elif mic.recording: mic.finish({"source":_source,"positions":_positions.duplicate(true),"samples":_spatial_samples.duplicate(true),"config":(_recording_config if not _recording_config.is_empty() else config).duplicate(true)})

func cancel_interaction() -> void:
	if mic.recording:
		mic.cancel();_spatial_samples.clear()
		for caption in captions.values(): caption.show_hearing("本句已取消，未送出",3.0)
		log_event({"type":"cancelled","message":"已丢弃本句录音，没有发送。"});return
	_input_generation+=1
	mic.cancel() # 也丢弃松键后尚未完成的后台音频预处理。
	_pending_captures.clear()
	information_waits.reset();_social_requests.clear()
	pipeline.cancel()
	tts.cancel()
	if is_instance_valid(_active_speech_output): _active_speech_output._fail("玩家取消")
	_speech_queue.clear()
	# 台词结束后，技能或后台学习仍可运行；最新自主轮次会覆盖_speech_order。
	# 取消对象必须包含当前执行器持有的工作，不能只看最后一轮听众。
	var participants: Array=_speech_order.duplicate()
	for id in skills.active.keys()+skills.learning.keys():
		if id not in participants: participants.append(id)
	for id in participants:
		var lessons: Array=social_learning.cancel(id)
		skills.cancel(id)
		if survival.actors[id].stage!="idle": survival.stop(id)
		for index in range(autonomy.requests.size()-1,-1,-1):
			if id in autonomy.requests[index].listeners or autonomy.requests[index].get("lesson_request_id","") in lessons: autonomy.requests.remove_at(index)
		captions[id].clear()
	busy=false;_decisions_done=false;_allow_execution=false
	log_event({"type":"cancelled","message":"已取消当前交互，迟到的识别与模型结果不会执行；已发生的世界变化保留。"})

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(session_manager):
		session_manager.quit_game.call_deferred();return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and cancel_recording_on_focus_loss and is_instance_valid(mic) and mic.recording:
		mic.cancel()
		log_event({"type":"cancelled","message":"窗口失去焦点，已取消录音"})

func _begin_recording() -> void:
	if is_instance_valid(session_manager) and session_manager.is_locked():return
	var input_started := Time.get_ticks_usec()
	if mic.recording: return
	if _pending_captures.size()>=3:
		log_event({"type":"input_rejected","message":"已有三句录音等待处理，本次未开始收音"})
		return
	var error := config_error(true)
	if not config.local_only and not error.is_empty():
		log_event({"type":"error","message":error})
		menu.open()
		return
	_recording_config = config.duplicate(true)
	_positions.clear()
	_source = get_parent().get_node("Player/Eyes").global_position
	for id in store.people:
		var position: Vector3 = get_parent().get_node("People/" + store.people[id].node).global_position
		_positions[id] = position + Vector3(0,1.6,0)
	if AudioServer.input_device != config.input_device:
		AudioServer.input_device = config.input_device
	mic.noise_floor_db = config.noise_floor_db
	_spatial_samples.clear()
	_recording_started=Time.get_ticks_msec()
	_last_spatial_sample=-100
	mic.start()
	_sample_space()
	log_event({"type":"recording","message":"正在录音；松开 V 送出"})
	print("VOICE_INPUT_START_MS ",(Time.get_ticks_usec()-input_started)/1000.0)

static func listeners_for(source: Vector3, positions: Dictionary, radius: float) -> Array:
	var ids: Array = []
	for id in positions:
		if source.distance_to(positions[id]) <= radius:
			ids.append(id)
	return ids

func _prepare_desktop_microphone() -> void:
	var xr:=XRServer.find_interface("OpenXR")
	if xr!=null and xr.is_initialized(): return # VR 在自己的入口选择头显输入。
	AudioServer.input_device=config.input_device
	mic.prepare_continuous_input()
	log_event({"type":"progress","message":"桌面收音设备："+str(config.input_device)})

func _prepare_luau_playtest() -> void:
	await preload("res://scripts/skills/luau_playtest.gd").prepare(self)

func _on_captured(result: Dictionary) -> void:
	if not result.ok:
		for caption in captions.values(): caption.show_hearing("本句未识别到有效声音",3.0)
		log_event({"type":"error","message":result.error})
		return
	var context: Dictionary=result.get("capture_context",{})
	if context.is_empty(): context={"source":_source,"positions":_positions.duplicate(true),"samples":_spatial_samples.duplicate(true),"config":(_recording_config if not _recording_config.is_empty() else config).duplicate(true)}
	if context.samples.is_empty():
		log_event({"type":"error","message":"录音缺少空间采样，本轮取消，避免错误分配交谈对象"})
		return
	var capture:=context.duplicate(true)
	capture["result"]=result.duplicate(true)
	capture.result.erase("capture_context")
	for caption in captions.values():
		if not caption.hearing_text.is_empty(): caption.show_hearing("正在辨认这句话…",10.0)
	if busy:
		_pending_captures.append(capture)
		log_event({"type":"input_queued","message":"你的录音已保留，等待当前回应结束后优先处理","queue_size":_pending_captures.size()})
		return
	_process_capture(capture)

func _process_capture(capture: Dictionary) -> void:
	if capture.has("text_event"):
		_dispatch_text(capture.text_event,capture.config)
		return
	var generation:=_input_generation
	_display_event_id=""
	var result: Dictionary=capture.result
	var capture_source: Vector3=capture.source
	var capture_positions: Dictionary=capture.positions
	var capture_samples: Array=capture.samples
	_job_config=capture.config
	busy = true
	_allow_execution=true
	_decisions_done = false
	_event_started = Time.get_ticks_msec()
	log_event({"type":"utterance_finished","message":"录音结束，提交本句；此时才允许人物处理指令","while_recording":mic.recording})
	var radius := Mic.radius_for(result.db, _job_config.quiet_db, _job_config.loud_db)
	var listeners := listeners_for(capture_source, capture_positions, radius)
	log_event({"type":"audio","dbfs":result.db,"radius_m":radius,"listeners":listeners,"duration_seconds":result.duration_seconds,"clipped_ratio":result.clipped_ratio})
	if _job_config.local_only:
		busy = false
		log_event({"type":"local_capture","message":"本地收音检查结束，音频没有上传。配置服务后取消‘仅检查本地收音’即可测试云端链路。","wav_bytes":result.wav.size()})
		return
	log_event({"type":"progress","message":"正在转写语音…"})
	var response: Dictionary
	var segments: Array=[]
	if _job_config.get("capswriter_asr",false):
		var names := PackedStringArray()
		for id in store.people: names.append(store.people[id].name)
		var context := CapsWriter.build_context(names,_public_dialogue)
		var split_started:=Time.get_ticks_msec()
		var parts := Spatial.split(result.wav,capture_samples)
		log_event({"type":"spatial_split","parts":parts.size(),"elapsed_ms":Time.get_ticks_msec()-split_started,"samples":capture_samples.size()})
		var texts: PackedStringArray=[]
		var elapsed:=0
		listeners=[]
		for part in parts:
			var analysis:=Mic.analyze(part.pcm,16000,_job_config.noise_floor_db)
			if not analysis.ok: continue
			response=await capswriter.transcribe(part.wav,context)
			if generation!=_input_generation: return
			if not response.ok:
				busy=false
				log_event({"type":"error","stage":"asr","message":response.error})
				return
			elapsed+=int(response.get("elapsed_ms",0))
			texts.append(response.text)
			var segment_radius:=Mic.radius_for(analysis.db,_job_config.quiet_db,_job_config.loud_db)
			var evidence: Dictionary={}
			var focus_votes: Dictionary={}
			var count:=0
			for sample in capture_samples:
				if sample.time<part.start or sample.time>=part.end: continue
				count+=1
				var seen:=Spatial.perception(sample.source,sample.forward,sample.positions,segment_radius)
				for id in seen.heard:
					if not evidence.has(id): evidence[id]={"count":0,"distance_m":0.0,"angle_degrees":0.0}
					evidence[id].count+=1
					evidence[id].distance_m+=seen.heard[id].distance_m
					evidence[id].angle_degrees+=seen.heard[id].angle_degrees
				var hint: String=sample.get("focus_hint",seen.focus_hint)
				if hint!="" and seen.heard.has(hint): focus_votes[hint]=int(focus_votes.get(hint,0))+1
			var focus:=""
			for id in focus_votes:
				if focus_votes[id]>count*0.65: focus=id
			var audience: Dictionary={}
			for id in evidence:
				# 只短暂掠过传播范围的人不获得整段内容。
				if evidence[id].count<maxi(1,int(ceil(count*0.8))): continue
				evidence[id].distance_m=snappedf(evidence[id].distance_m/evidence[id].count,0.1)
				evidence[id].angle_degrees=snappedf(evidence[id].angle_degrees/evidence[id].count,1.0)
				audience[id]=evidence[id]
				if not id in listeners: listeners.append(id)
			segments.append({"start_seconds":part.start,"end_seconds":part.end,"text":response.text,"focus_hint":focus,"audience":audience})
		response={"ok":not texts.is_empty(),"text":" ".join(texts),"elapsed_ms":elapsed}
		if texts.is_empty(): response["error"]="分段后没有可识别的有效声音"
	else:
		response = await cloud.complete(_job_config.asr_url, _job_config.asr_key, Cloud.asr_payload(_job_config.asr_model, result.wav))
	if generation!=_input_generation: return
	if not response.ok:
		log_event({"type":"error","stage":"asr","message":response.error})
		busy = false
		return
	var event := {"id":_new_id(),"kind":"speech_intent","speaker":"player","text":response.text,"listeners":listeners,"radius_m":radius,"source_position":[capture_source.x,capture_source.y,capture_source.z]}
	if not segments.is_empty(): event["spatial_segments"]=segments
	_remember_public("玩家",response.text)
	log_event({"type":"transcript","event":event,"elapsed_ms":response.get("elapsed_ms",0),"usage":response.get("usage",{}),"connection_reused":response.get("connection_reused",false)})
	if listeners.is_empty():
		log_event({"type":"notice","message":"此句传播范围内没有成员，未调用角色模型"})
	_start_pipeline(event, _job_config)

func _record_scene_restart() -> void:
	while not survival.ready_for_actions: await get_tree().physics_frame
	for id in store.people:
		if store.working_tasks.has(id):
			# 重载只中断正在执行的物理动作，不能复活已结束的任务或清除预算暂停。
			if store.working_tasks[id].state=="action_submitted":
				store.working_tasks[id].state="interrupted_scene_reload"
			store.working_tasks[id]["continuity_note"]="场景重新载入，物理世界没有从该任务结果恢复；原任务保留，但旧动作结果不能当作当前持有或物品状态，需要以当前观察重新确认。"
		var observed: Dictionary=survival.observation(id)
		store.hear(id,{"id":_new_id(),"kind":"body_state","speaker":"body","text":"场景恢复后的当前身体确认：携带食物%d份，手拿单份采摘食物：%s，持有水袋：%s。旧动作结果只代表过去，当前能否行动以本次身体状态、观察和开放行为目录为准。"%[observed.carried_food,observed.hand_harvested_food,observed.holding_water_bag]})
	store.memory.dirty=true

func say_text(value: String) -> String:
	if is_instance_valid(session_manager) and session_manager.is_locked():return "正在存取或等待恢复存档"
	var text:=value.strip_edges()
	if text.is_empty() or text.length()>500:return "请输入1至500字"
	if mic.recording:return "正在录音，请先结束本句录音"
	if _pending_captures.size()>=3:return "已有三句话等待处理；请等待或按 Backspace 取消"
	if config.local_only:return "当前只检查本地收音，请先配置服务"
	var error:=config_error(false)
	if not error.is_empty():return error
	var eye: Node3D=get_parent().get_node("Player/Eyes")
	var positions: Dictionary={}
	for id in store.people:positions[id]=get_parent().get_node("People/"+store.people[id].node).global_position+Vector3(0,1.6,0)
	# 文字采用普通音量的固定传播半径；不预选接收者，仍以说话时的位置和朝向判断。
	var heard:=Spatial.perception(eye.global_position,-eye.global_basis.z,positions,6.0)
	if heard.heard.is_empty():return "当前说话范围内没有人听见；请靠近人物后再发送。"
	var event:={"id":_new_id(),"kind":"speech_intent","speaker":"player","text":text,"listeners":heard.heard.keys(),"radius_m":6.0,"source_position":[eye.global_position.x,eye.global_position.y,eye.global_position.z],"spatial_segments":[{"text":text,"focus_hint":heard.focus_hint,"audience":heard.heard}]}
	if busy or not _pending_captures.is_empty():
		_pending_captures.append({"text_event":event.duplicate(true),"config":config.duplicate(true)})
		log_event({"type":"input_queued","message":"已发送，等待处理："+text,"queue_size":_pending_captures.size(),"queued_event":event})
	else:
		_dispatch_text(event,config.duplicate(true))
	return ""

func _dispatch_text(event: Dictionary, job: Dictionary) -> void:
	busy=true;_allow_execution=true;_decisions_done=false;_event_started=Time.get_ticks_msec();_job_config=job
	_remember_public("玩家",event.text)
	log_event({"type":"transcript","input_method":"text","event":event})
	_start_pipeline(event,_job_config)

func gift_test(recipient_id: String) -> void:
	if config.local_only:
		log_event({"type":"notice","message":"当前为仅检查本地收音；取消该选项后才能发送赠与测试"})
		return
	if busy or mic.recording:
		log_event({"type":"notice","message":"请等待当前请求结束"})
		return
	var error := config_error(false)
	if not error.is_empty():
		log_event({"type":"error","message":error})
		return
	assert(store.people.has(recipient_id))
	busy = true
	_allow_execution=false
	_decisions_done = false
	_event_started = Time.get_ticks_msec()
	_job_config = config.duplicate(true)
	# 独立测试夹具：明确声明四人共同目击，不冒充实际发生的物品转移。
	var event := {"id":_new_id(),"kind":"observed_test","speaker":"test_fixture","text":"虚构目击测试：四人共同看见玩家把一份食物交给%s，并说‘这是对你今天付出的认可’。只评估人物反应，不修改实际物资。" % store.people[recipient_id].name,"recipient_id":recipient_id,"listeners":store.people.keys()}
	log_event({"type":"fixture","event":event})
	_start_pipeline(event, _job_config)

func _execution_allowed() -> bool:
	# 同时保留请求发起时权限和当前开关；关闭后到达的模型/语音回调不能启动操作。
	return _allow_execution and _job_config.get("actions_enabled",true) and config.get("actions_enabled",true) and (not is_instance_valid(session_manager) or not session_manager.is_locked())

func _on_report(report: Dictionary) -> void:
	if _round_events.get(report.event_id,{}).get("speaker")=="player":
		captions[report.person_id].show_hearing("已听见 · 决策处理失败" if report.has("error") else ("已听见 · 旁听" if report.decision.get("conversation",{}).get("participation")=="listen" else "已听见 · 已作出回应"),5.0)
	_reports_received[report.person_id]=true
	log_event({"type":"role_result","report":report})
	_resume_waited_result(report)
	if report.has("decision") and report.decision.get("task_handling",{}).get("state")=="cancelled":
		var task: Dictionary=store.working_tasks.get(report.person_id,{})
		var request_id: String=task.get("request",{}).get("id","")
		if request_id!="":
			_cancelled_player_tasks[report.person_id+"/"+request_id]=true
			for index in range(autonomy.requests.size()-1,-1,-1):
				var pending: Dictionary=autonomy.requests[index]
				if pending.get("kind")=="skill_progress" and report.person_id in pending.get("listeners",[]) and _task_was_cancelled(report.person_id,pending):
					autonomy.requests.remove_at(index)
	if report.has("decision") and report.decision.has("offer_response") and _execution_allowed():
		_resolve_player_offer(report)
	if report.has("decision") and report.decision.get("capability_gap")!=null: _record_capability_gap(report)
	if _execution_allowed() and report.has("decision") and report.decision.intent=="rest":
		var lessons: Array=social_learning.cancel(report.person_id)
		skills.cancel(report.person_id)
		survival.stop(report.person_id)
		help_tasks.cancel_helper(report.person_id)
		for index in range(autonomy.requests.size()-1,-1,-1):
			if (autonomy.requests[index].get("kind")=="skill_ready" and report.person_id in autonomy.requests[index].listeners) or autonomy.requests[index].get("lesson_request_id","") in lessons: autonomy.requests.remove_at(index)
		_on_action_result({"person_id":report.person_id,"source_event_id":report.event_id,"intent":"rest","success":true,"message":"已停止当前行动"})
	if report.has("decision") and report.decision.get("revision_request")!=null:
		if _execution_allowed():
			_begin_revision(report.person_id,report.event_id,report.decision.revision_request)
		else: log_event({"type":"learning_not_started","event_id":report.event_id,"person_id":report.person_id,"message":"本轮没有修订权限"})
	if report.has("decision") and report.decision.get("learning_request")!=null:
		if _execution_allowed():
			if not _job_config.get("tts_enabled",true):
				captions[report.person_id].begin_public(report.decision.public_reply)
				_begin_self_learning(report.person_id,report.event_id,report.decision)
		else: log_event({"type":"learning_not_started","event_id":report.event_id,"person_id":report.person_id,"message":"本轮没有行动权限，未启动编写"})
	if report.has("decision") and report.decision.get("skill_call")!=null:
		if _execution_allowed():
			var submitted: Dictionary=skills.invoke(report.person_id,report.event_id,report.decision.skill_call)
			if submitted.ok:
				var source: Dictionary=store.event_for(report.person_id,report.event_id)
				source=source.get("original_event",source)
				if report.decision.task_handling.scope=="existing_request":source=store.working_tasks.get(report.person_id,{}).get("request",source)
				var assistance: Dictionary={}
				if source.get("kind")=="social_request":
					assistance={"request_id":source.get("root_request_id",source.id),"requester_id":source.get("beneficiary_id",source.speaker),"helper_id":report.person_id,"requested_by":source.speaker,"request_text":source.text}
				survival.actors[report.person_id].assistance=assistance
				if not assistance.is_empty(): help_tasks.accept(assistance,report.person_id,_autonomy_clock,report.event_id)
			log_event({"type":"skill_submitted","person_id":report.person_id,"event_id":report.event_id,"call":report.decision.skill_call,"message":("开始执行技能："+submitted.name) if submitted.ok else ("技能未启动："+submitted.error)})
			if not submitted.ok:
				_on_skill_result({"person_id":report.person_id,"source_event_id":report.event_id,"intent":"skill","skill_ref":report.decision.skill_call.ref,"success":false,"goal_verified":false,"message":submitted.error,"category":submitted.get("category","")})
		else:
			log_event({"type":"skill_not_executed","person_id":report.person_id,"event_id":report.event_id,"message":"本轮没有行动权限，技能调用未执行"})
	# 是否需要公开说明由人物判断；内部触发不能吞掉实际障碍或计划变更。
	if _job_config.get("tts_enabled",true) and report.has("decision") and not report.decision.public_reply.strip_edges().is_empty():
		_speech_queue.append(report)
	_pump_speech()

func _resolve_player_offer(report: Dictionary) -> void:
	var target: String=report.person_id
	if _round_events.get(report.event_id,{}).get("item_kind")=="object":
		var actual: Dictionary=survival.handover.respond(report.event_id,target,report.decision.offer_response=="accept")
		log_event({"type":"item_handover","person_id":target,"result":actual,"message":actual.message})
		var received:={"id":report.event_id+"_result","kind":"received_item" if actual.ok else "item_offer_result","speaker":"world","listeners":[target],"source_event_id":report.event_id,"text":actual.message+"。根据实际结果决定下一步，可以保持沉默。"}
		store.hear(target,received)
		if actual.ok:_player_offers.append(received)
		store.save_snapshot(_snapshot_path)
		return
	var result: Dictionary=survival.gathering.resolve_offer(report.event_id,target,report.decision.offer_response=="accept")
	log_event({"type":"player_handover","person_id":target,"result":result,"message":result.message})
	var event:={"id":report.event_id+"_result","kind":("received_water" if result.get("item_kind")=="water" else "received_food") if result.success else "item_offer_result","speaker":"world","listeners":[target],"source_event_id":report.event_id,"text":result.message+"。根据真实结果自行决定下一步，可以保持沉默。"}
	store.hear(target,event)
	if result.success:
		_player_offers.append(event)
		for observer in store.people:
			if observer==target: continue
			var giver: Vector3=get_parent().get_node("Player/Eyes").global_position
			var receiver: Vector3=survival.actors[target].body.global_position+Vector3(0,1.1,0)
			if survival.perception.sees(observer,giver) and survival.perception.sees(observer,receiver):
				store.hear(observer,{"id":report.event_id+"_seen","kind":"observed_action","speaker":"world","text":"你看见玩家把"+("水袋" if result.get("item_kind")=="water" else "一份食物")+"交给了"+store.people[target].name})
	store.save_snapshot(_snapshot_path)

func _on_completed() -> void:
	_decisions_done = true
	_pump_speech()

func _pump_speech() -> void:
	if _speech_busy: return
	if _speech_queue.is_empty():
		if _decisions_done: _finish_turn()
		return
	# 后问的人先返回时先缓存；沉默／失败的前序人物收到结果后可跳过。
	for id in _speech_order:
		if not _reports_received.has(id): return
		var index:=-1
		for candidate in _speech_queue.size():
			if _speech_queue[candidate].person_id==id: index=candidate; break
		if index>=0:
			var next: Dictionary=_speech_queue[index]
			_speech_queue.remove_at(index)
			_speech_queue.push_front(next)
			break
	var report: Dictionary = _speech_queue.pop_front()
	var generation:=_input_generation
	_speech_busy = true
	var person: Dictionary = store.people[report.person_id]
	var output := SpeechOutput.new()
	_active_speech_output=output
	get_parent().get_node("People/"+person.node).add_child(output)
	var chunk_callback := Callable(output,"push_chunk")
	tts.audio_chunk.connect(chunk_callback)
	output.failed.connect(func(_message: String): tts.cancel())
	output.playback_started.connect(func():
		captions[report.person_id].begin_public(report.decision.public_reply)
		store.mark_reply(report.person_id,report.event_id,"正在向玩家播放，尚未完整说完")
		log_event({"type":"speaking_started","person_id":report.person_id,"before_speech_done":not output.ended,"while_recording":mic.recording,"elapsed_ms":Time.get_ticks_msec()-_event_started,"message":person.name+"开始说话（Gemini API 3.8 / "+person.voice+"）"}))
	log_event({"type":"tts_request","person_id":report.person_id,"style":report.decision.speech_style,"provider":"Google Gemini API / Gemini 3.8 Flash TTS","voice":person.voice,"message":"正在合成公开台词："+person.name})
	# 不把 report、人物上下文或私下理解传给语音服务。
	var result: Dictionary = await tts.speak(report.decision.public_reply,report.decision.speech_style,person.voice)
	tts.audio_chunk.disconnect(chunk_callback)
	if generation!=_input_generation:
		output.queue_free();_speech_busy=false;_pump_speech.call_deferred();return
	if result.ok:
		output.finish()
		log_event({"type":"tts_generated","person_id":report.person_id,"elapsed_ms":result.elapsed_ms,"audio_seconds":result.audio_seconds})
		if not output.complete: await output.drained
		if generation!=_input_generation:
			output.queue_free();_speech_busy=false;_pump_speech.call_deferred();return
		if output.error_message.is_empty():
			store.mark_reply(report.person_id,report.event_id,"已播放完成；附近成员听闻另行记录")
			var listener_position: Vector3 = get_parent().get_node("Player").global_position+Vector3(0,1.66,0)
			if listener_position.distance_to(output.global_position)<=output.max_distance:
				_remember_public(person.name,report.decision.public_reply)
			_deliver_public(report.person_id,report.event_id,report.decision.public_reply,output.max_distance,report.decision,report.get("knowledge_offer",{}))
			log_event({"type":"spoken","person_id":report.person_id,"text":report.decision.public_reply,"message":person.name+"公开台词播放结束；听闻已记录，明确请求另行排队"})
		else:
			store.mark_reply(report.person_id,report.event_id,"播放失败，不能确认玩家听到了完整答复")
			log_event({"type":"error","stage":"tts_playback","person_id":report.person_id,"message":output.error_message})
	else:
		output.stop()
		store.mark_reply(report.person_id,report.event_id,"播放失败，不能确认玩家听到了完整答复")
		log_event({"type":"error","stage":"tts","person_id":report.person_id,"message":result.error})
	captions[report.person_id].end_public(result.ok and output.error_message.is_empty())
	output.queue_free()
	_speech_busy = false
	_pump_speech.call_deferred()

func _finish_turn() -> void:
	if not busy:
		return
	busy = false
	var error: Error = store.save_snapshot(_snapshot_path)
	log_event({"type":"completed","elapsed_ms":Time.get_ticks_msec()-_event_started,"snapshot_saved":error == OK,"message":"本轮对话结束。已接受的行动由程序继续执行，结果会另行反馈。"})
	if error != OK:
		log_event({"type":"error","message":"无法保存人物快照，错误码 %d" % error})

func reset_context(clear_memory: bool=true) -> void:
	if busy or mic.recording:
		return
	if not _pending_captures.is_empty():
		log_event({"type":"input_rejected","message":"还有录音等待处理，暂不重置场景"})
		return
	skills.reset_context()
	social_learning.reset()
	mic.cancel()
	var memory_path: String=store.memory.path
	if not clear_memory:
		var save_error: String=store.memory.save()
		assert(save_error.is_empty(),save_error)
	var error: String = store.initialize("res://data/people.json",memory_path,clear_memory)
	assert(error.is_empty(), error)
	for id in store.people: skills.sync_person(id)
	_public_dialogue.clear()
	for caption in captions.values(): caption.reset_display()
	_execution_feedback.clear()
	_player_offers.clear()
	_completed_assistance.clear()
	autonomy.reset(_autonomy_clock)
	help_tasks.reset()
	information_waits.reset();_social_requests.clear()
	survival.reset()
	log_event({"type":"reset","message":"已恢复人物需求、位置和三份食物；"+("已重置人物记忆，旧日志保留" if clear_memory else "保留人物记忆，记住的位置仍需重新观察")})

func _on_learning_finished(result: Dictionary) -> void:
	var original: Dictionary=result.get("original_event",{})
	log_event({"type":"skill_learning","person_id":result.person_id,"message":result.message,"learning":result})
	if original.is_empty(): return
	if not result.ok:
		var failed:={"id":result.job+"_failed","kind":"skill_progress","speaker":"world","listeners":[result.person_id],"source_event_id":original.id,"original_event":original.duplicate(true),"learning_failed":true,"goal_id":result.get("goal_id",""),"learning_goal":result.get("goal",""),"text":"本次方法未学成。原因："+result.message}
		# 学习结果发生时本人已经知道；排队只延迟下一次判断，不延迟记忆。
		# 否则玩家先追加教导时，模型看不到原目标编号，会另建目标丢失草稿。
		_record_learning_failure(result.person_id,failed)
		return
	var event:={"id":result.job+"_ready","kind":"skill_ready","speaker":"world","listeners":[result.person_id],"source_event_id":original.id,"original_event":original.duplicate(true),"skill_ref":result.ref,"text":"已学会新方法，可用于现场行动。"}
	if result.get("revision_of","")!="":
		event.kind="skill_revised"
		event.text="方法已修订，可使用新版本。"
	store.hear(result.person_id,event)
	store.memory.save()
	autonomy.offer_request(event,_autonomy_clock)
	log_event({"type":"skill_continuation_queued","person_id":result.person_id,"source_event_id":original.id,"message":"学习完成，已排队继续原请求"})

func _on_skill_result(result: Dictionary) -> void:
	store.record_execution(result)
	if result.get("success",false):
		var definition: Dictionary=skills.library.definitions.get(result.get("skill_ref",""),{})
		if not definition.is_empty():
			for observer in store.people:
				if observer!=result.person_id and survival.perception.sees(observer,survival.actors[result.person_id].body.global_position+Vector3(0,1.2,0)):
					store.remember_skill(observer,result.person_id,definition.id,"observed","亲眼看见对方执行了"+definition.name,str(result.source_event_id))
			social_learning._save_knowledge()
	log_event({"type":"action_result","person_id":result.person_id,"event_id":result.source_event_id,"result":result,"message":store.people[result.person_id].name+"："+result.message})
	_queue_task_result(result)
	store.save_snapshot(_snapshot_path)

func _task_was_cancelled(person_id: String, event: Dictionary) -> bool:
	var original: Dictionary=event.get("original_event",event)
	var request_id: String=original.get("id","")
	if request_id=="": return false
	if _cancelled_player_tasks.has(person_id+"/"+request_id): return true
	if store.superseded_tasks.has(person_id+"/"+request_id): return true
	var task: Dictionary=store.working_tasks.get(person_id,{})
	return task.get("state")=="cancelled" and task.get("request",{}).get("id")==request_id

func _resume_waited_result(report: Dictionary) -> void:
	var task: Dictionary=store.working_tasks.get(report.person_id,{})
	if task.get("wait_decision_event_id","")!=report.event_id or task.get("state")!="wait": return
	var result: Dictionary=task.get("last_result",{})
	if not result.is_empty() and result.get("source_event_id")==task.get("waiting_action_event_id"):
		_queue_task_result(result)

func _queue_task_result(result: Dictionary) -> void:
	# 执行结束不等于原请求完成；把实际结果交还本人，取消则不续办。
	if store.independent_actions.has(result.person_id+"/"+str(result.source_event_id)): return
	var source: Dictionary=_round_events.get(result.source_event_id,{})
	var root_event: Dictionary=source.get("original_event",source)
	var task: Dictionary=store.working_tasks.get(result.person_id,{})
	var bound: bool=task.get("action_event_id","")==str(result.source_event_id)
	if bound: root_event=task.request
	if not store.is_person_request(root_event): return
	var outcome: Dictionary=result.get("runtime",{})
	var cancelled: bool=result.get("cancelled",false) or outcome.get("code","")=="cancelled" or _task_was_cancelled(result.person_id,{"original_event":root_event})
	var step: int=int(source.get("skill_followup_step",0))+1
	var waited: bool=bound and task.get("waiting_action_event_id","")==str(result.source_event_id)
	if waited: step=1
	if bound: step=maxi(step,task.get("progress",[]).size())
	if not source.is_empty() and not cancelled and step<=16:
		# 使用当时提交此动作时绑定的任务现场，不能用后来另一任务覆盖迟到结果。
		var original: Dictionary=root_event
		var event:={"id":str(result.source_event_id)+"_skill_result","kind":"skill_progress","speaker":"world","listeners":[result.person_id],"source_event_id":result.source_event_id,"original_event":original.duplicate(true),"skill_followup_step":step,"result":result.duplicate(true),"text":"上一步实际结果："+str(result.message)}
		if waited: event.id+="_for_"+str(original.id)
		autonomy.offer_request(event,_autonomy_clock)
	elif not source.is_empty() and not cancelled and step>16:
		if store.working_tasks.has(result.person_id):
			store.working_tasks[result.person_id].state="paused_budget"
			store.working_tasks[result.person_id]["stop_reason"]="连续执行达到16次续接预算，任务尚未判定完成，等待玩家继续或调整"
			store.memory.dirty=true
		log_event({"type":"error","person_id":result.person_id,"event_id":result.source_event_id,"message":"连续执行达到16次续接预算，已暂停，未宣称任务完成。可让人物继续或调整任务。"})

func _on_action_result(result: Dictionary) -> void:
	store.record_execution(result)
	log_event({"type":"action_result","result":result,"message":store.people[result.person_id].name+"："+result.message})
	_queue_task_result(result)
	store.save_snapshot(_snapshot_path)

func _on_world_fact(fact: Dictionary) -> void:
	# 事实来自物资/身体结算；技能名字和模型的成功声明不是事实来源。
	help_tasks.world_fact(fact)
	_record_world_witnesses(fact)
	log_event({"type":"world_fact","person_id":fact.person_id,"source_event_id":fact.source_event_id,"fact":fact})
	var origin: Dictionary=fact.get("origin",{})
	if fact.kind=="consumed" and origin.get("requester_id","")==fact.person_id and origin.get("helper_id",fact.person_id)!=fact.person_id:
		var request_id: String=origin.get("request_id","")
		if request_id!="" and not _completed_assistance.has(request_id):
			_completed_assistance[request_id]=true
			_execution_feedback.append({"person_id":fact.person_id,"source_event_id":fact.source_event_id,"food_origin":origin,"material":fact.material,"success":true})
	store.save_snapshot(_snapshot_path)

func _process(_delta: float) -> void:
	if is_instance_valid(session_manager) and session_manager.is_locked():return
	_autonomy_clock+=_delta
	if is_instance_valid(menu):
		var eye: Vector3=get_parent().get_node("Player/Eyes").global_position
		for caption in captions.values():
			caption.visible=not menu.is_open() and eye.distance_to(caption.global_position)<12.0
	if is_instance_valid(mic) and mic.recording: _sample_space()
	if not is_instance_valid(mic) or busy or mic.recording: return
	if not _pending_captures.is_empty():
		_process_capture(_pending_captures.pop_front())
		return
	if not _player_offers.is_empty() and not menu.is_open() and not config.local_only and config.get("actions_enabled",true):
		var event: Dictionary=_player_offers.pop_front()
		if event.kind=="item_offer" and not survival.gathering.offers.has(event.id) and not survival.handover.pending.has(event.id): return
		busy=true; _decisions_done=false; _allow_execution=true
		_event_started=Time.get_ticks_msec(); _job_config=config.duplicate(true)
		_start_pipeline(event,_job_config)
		return
	# 输入下一句话只暂停新自主判断；先前已经递出的物品仍须及时获得接收决定。
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	if _execution_feedback.is_empty():
		_try_autonomy()
		return
	if config.local_only or not config_error(false).is_empty(): return
	var result: Dictionary=_execution_feedback.pop_front()
	busy=true
	_decisions_done=false
	# 真实受益反馈仍是正常决策；只限制虚构测试，不吞掉人物选择的后续动作。
	_allow_execution=true
	_event_started=Time.get_ticks_msec()
	_job_config=config.duplicate(true)
	var event:={"id":_new_id(),"kind":"assistance_completed","speaker":"world","text":"你刚消耗的食物或水来自这次他人的交付，来源与交付经过见assistance。","result":result,"assistance":result.food_origin,"listeners":[result.person_id]}
	_display_event_id=event.id
	log_event({"type":"execution_feedback","message":"让"+store.people[result.person_id].name+"判断是否回应帮助者"})
	_start_pipeline(event,_job_config)

func _remember_public(speaker: String, text: String) -> void:
	_public_dialogue.append({"speaker":speaker,"text":text})
	while _public_dialogue.size()>3: _public_dialogue.pop_front()

func log_event(record: Dictionary) -> void:
	if record.get("type","")=="reset": _display_event_id=""
	if record.has("event"): _display_event_id=record.event.id
	if record.has("report"): record["event_id"]=record.report.event_id
	elif record.has("result"): record["event_id"]=record.result.get("source_event_id",_display_event_id)
	elif record.has("source_event_id"): record["event_id"]=record.source_event_id
	elif not _display_event_id.is_empty(): record["event_id"]=_display_event_id
	if not _display_event_id.is_empty() and not _event_rounds.has(_display_event_id):
		_display_round+=1
		_event_rounds[_display_event_id]=_display_round
	if record.has("event_id"): record["round_number"]=_event_rounds.get(record.event_id,0)
	if record.get("type","") in ["recording","input_queued","input_rejected","utterance_finished"]:
		record.erase("event_id"); record.erase("round_number")
		if is_instance_valid(player_input_note): player_input_note.text="你："+record.message
	if record.get("type")=="transcript" and is_instance_valid(player_input_note):
		last_player_transcript=str(record.event.text)
		var names: PackedStringArray=[]
		for listener in record.event.listeners: names.append(store.people[listener].name)
		player_input_note.text="你说："+str(record.event.text).left(90)+"\n听众："+("、".join(names) if not names.is_empty() else "范围内没有人物")
		player_input_note.tooltip_text=record.event.text
	if record.get("type")=="error" and record.get("stage")=="asr" and is_instance_valid(player_input_note):
		player_input_note.text="本次语音识别失败："+record.message
	record["time"] = Time.get_datetime_string_from_system()
	print("VOICE_TEST ", JSON.stringify(record))
	var display_id: String=record.get("person_id",record.get("speaker",""))
	if record.has("report"): display_id=record.report.person_id
	if record.has("result"): display_id=record.result.get("person_id",display_id)
	for id in captions:
		if id==display_id or (display_id.is_empty() and record.get("type","") in ["transcript","fixture","completed","execution_feedback","error"]):
			captions[id].append_record(record)

	if is_instance_valid(menu):
		menu.append_record(record)
	if _log_path.is_empty():
		return
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if file == null:
		push_error("无法写入语音测试日志")
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))

func _new_id() -> String:
	return "event_%s_%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]

func _sample_space() -> void:
	var now:=Time.get_ticks_msec()-_recording_started
	if now-_last_spatial_sample<100: return
	_last_spatial_sample=now
	var eyes: Camera3D=get_parent().get_node("Player/Eyes")
	var positions: Dictionary={}
	for id in store.people:
		positions[id]=get_parent().get_node("People/"+store.people[id].node).global_position+Vector3(0,1.6,0)
	var visible_positions: Dictionary={}
	for id in positions:
		if _clear_sight(eyes.global_position,positions[id]): visible_positions[id]=positions[id]
	_spatial_samples.append({"time":float(mic.samples.size()+mic.effect.get_frames_available())/AudioServer.get_mix_rate(),"source":eyes.global_position,"forward":-eyes.global_basis.z,"positions":positions,"focus_hint":Spatial.perception(eyes.global_position,-eyes.global_basis.z,visible_positions,20.0).focus_hint})
	var radius:=Mic.radius_for(mic.level_db,config.quiet_db,config.loud_db)
	for id in captions:
		if mic.level_db>=mic.noise_floor_db and eyes.global_position.distance_to(positions[id])<=radius:
			captions[id].show_hearing("声音范围内 · 正在收听",0.5)

func _clear_sight(from: Vector3, to: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(from,to,1)
	query.exclude=[get_parent().get_node("Player").get_rid()]
	return get_parent().get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _deliver_public(speaker_id: String, event_id: String, text: String, radius: float, decision: Dictionary = {}, offer: Dictionary = {}) -> void:
	if text.strip_edges().is_empty(): return
	var source: Vector3=get_parent().get_node("People/"+store.people[speaker_id].node).global_position+Vector3(0,1.6,0)
	var audience: Array=[]
	var voice_locations: Dictionary={}
	var reply_request: Dictionary=_round_events.get(event_id,{})
	reply_request=reply_request.get("original_event",reply_request)
	var reply_key: String=reply_request.get("id",event_id)
	var location_reply: bool=decision.get("speech_act")=="reply" and reply_request.get("kind")=="information_request"
	for id in store.people:
		if id==speaker_id: continue
		var at: Vector3=get_parent().get_node("People/"+store.people[id].node).global_position+Vector3(0,1.6,0)
		if source.distance_to(at)>radius or not _clear_sight(source,at): continue
		store.hear(id,{"id":event_id+"_spoken","kind":"public_speech","speaker":speaker_id,"speaker_name":store.people[speaker_id].name,"text":text})
		if survival.perception.hear_voice(id,speaker_id,event_id,source):
			survival._sync(id)
			if location_reply: voice_locations[id]=["person/"+speaker_id]
		audience.append(id)
	if decision.get("skill_dialogue")!=null:
		if _execution_allowed(): social_learning.public_decision(speaker_id,store.event_for(speaker_id,event_id),decision,audience)
		log_event({"type":"public_heard","speaker":speaker_id,"listeners":audience,"source_event_id":event_id})
		return
	if decision.get("learning_request")!=null and _execution_allowed():
		_begin_self_learning(speaker_id,event_id,decision)
	for record in store.people[speaker_id].skill_knowledge:
		if record.event_id in decision.get("shared_skill_knowledge",[]):
			for listener in audience: store.remember_skill(listener,record.person_id,record.goal_id,"claim","听"+store.people[speaker_id].name+"转述："+str(record.source),event_id)
	if not decision.get("shared_skill_knowledge",[]).is_empty(): social_learning._save_knowledge()
	var learned_by: Dictionary={}
	# 只有真实听到对应答复才结束等待；已目视对方也必须继续处理回答。
	var answered: String=information_waits.heard_reply(reply_key,speaker_id,audience) if location_reply else ""
	if not answered.is_empty():
		learned_by[answered]=[]
		# 超时反馈可能仍在预算队列里；迟到但已听见的答复使它失效。
		for index in range(autonomy.requests.size()-1,-1,-1):
			var queued: Dictionary=autonomy.requests[index]
			if queued.kind=="information_unanswered" and queued.get("source_event_id")==reply_request.get("source_event_id") and answered in queued.listeners:
				autonomy.requests.remove_at(index)
	for listener in audience:
		var learned: Array=voice_locations.get(listener,[]).duplicate()
		for entry: Dictionary in offer.get("entries",{}).values():
			if survival.perception.hear_from(listener,speaker_id,event_id,entry): learned.append(entry.id)
		if not learned.is_empty():
			learned_by[listener]=learned
			survival._sync(listener)
			log_event({"type":"information_shared","person_id":listener,"speaker":speaker_id,"source_event_id":event_id,"knowledge_ids":learned,"message":store.people[listener].name+"听到"+store.people[speaker_id].name+"提供的线索，已记为待核实情报"})
	if not offer.get("rejected",[]).is_empty():
		log_event({"type":"information_rejected","person_id":speaker_id,"source_event_id":event_id,"knowledge_ids":offer.rejected,"message":"未分享不存在于本人记录中的情报引用"})
	# 只把实际听见的答应交给请求者；不将远处任务状态泄露给她。
	if decision.get("skill_call")!=null:
		for task in help_tasks.tasks.values():
			if task.helper==speaker_id and task.event_id==event_id and task.status not in ["satisfied","cancelled"] and task.assistance.requester_id in audience:
				help_tasks.heard_acceptance(task.assistance,speaker_id,text,_autonomy_clock)
	var target: String=decision.get("addressed_person","")
	if config.get("autonomy_enabled",false) and decision.get("speech_act")=="reply" and _social_requests.has(reply_key):
		var waiting: Dictionary=_social_requests[reply_key]
		if speaker_id==waiting.recipient and target==waiting.requester and target in audience:
			_social_requests.erase(reply_key)
			var task: Dictionary=store.working_tasks.get(target,{})
			var closed: bool=task.get("request",{}).get("id")==waiting.original_event.id and task.get("state") in ["completed","cancelled","refused","paused_budget"]
			if not closed and not _task_was_cancelled(target,{"original_event":waiting.original_event}):
				autonomy.offer_request({"id":event_id+"_reply_heard","kind":"social_reply","speaker":speaker_id,"speaker_name":store.people[speaker_id].name,"listeners":[target],"source_event_id":event_id,"original_event":waiting.original_event.duplicate(true),"text":store.people[speaker_id].name+"回答了你先前的请求：“"+text+"”。"},_autonomy_clock)
	if config.get("autonomy_enabled",false) and decision.get("speech_act","")=="request" and decision.get("request_kind")=="information" and store.people.has(target):
		var question_source: Dictionary=store.event_for(speaker_id,event_id)
		var task: Dictionary=store.working_tasks.get(speaker_id,{})
		if store.is_person_request(task.get("request",{})) and task.get("state") not in ["completed","cancelled","refused","paused_budget"]:question_source["original_event"]=task.request.duplicate(true)
		information_waits.begin(speaker_id,target,question_source,text,_autonomy_clock)
	if config.get("autonomy_enabled",false) and decision.get("speech_act","")=="request" and target in audience:
		var request:={"id":event_id+"_request_"+target,"kind":"information_request" if decision.get("request_kind","help")=="information" else "social_request","speaker":speaker_id,"speaker_name":store.people[speaker_id].name,"text":text,"listeners":[target],"source_event_id":event_id}
		var source_event: Dictionary=store.event_for(speaker_id,event_id)
		if request.kind=="social_request" and source_event.has("assistance"):
			request["beneficiary_id"]=source_event.assistance.requester_id
			request["root_request_id"]=source_event.assistance.request_id
		elif request.kind=="social_request" and source_event.has("beneficiary_id"):
			request["beneficiary_id"]=source_event.beneficiary_id
			request["root_request_id"]=source_event.root_request_id
		if autonomy.offer_request(request,_autonomy_clock):
			if request.kind=="social_request":
				var original: Dictionary=source_event.get("original_event",source_event)
				var task: Dictionary=store.working_tasks.get(speaker_id,{})
				if store.is_person_request(task.get("request",{})) and task.get("state") not in ["completed","cancelled","refused","paused_budget"]:original=task.request
				_social_requests[request.id]={"requester":speaker_id,"recipient":target,"original_event":original.duplicate(true)}
				if _social_requests.size()>256:_social_requests.erase(_social_requests.keys()[0])
			log_event({"type":"request_queued","person_id":target,"source_event_id":event_id,"message":store.people[target].name+"听到了求助，等待自主判断"})
	if config.get("autonomy_enabled",false) and decision.get("speech_act","")!="request" and learned_by.has(target):
		autonomy.offer_request({"id":event_id+"_information_"+target,"kind":"information_received","speaker":speaker_id,"speaker_name":store.people[speaker_id].name,"listeners":[target],"source_event_id":event_id,"text":store.people[speaker_id].name+"告诉你："+text+"。","knowledge_ids":learned_by[target]},_autonomy_clock)
	log_event({"type":"public_heard","speaker":speaker_id,"listeners":audience,"source_event_id":event_id})

func _record_learning_failure(id: String, event: Dictionary) -> void:
	store.hear(id,event)
	var error: String=store.memory.save()
	assert(error.is_empty(),error)
	autonomy.offer_request(event,_autonomy_clock)

func _learning_submission_failed(id: String, event_id: String, original: Dictionary, submitted: Dictionary, request: Dictionary) -> void:
	assert(not submitted.ok)
	# 拒绝发生在创建任务之前；记录本人收到的提交结果，不虚构编写job或执行成果。
	var event:={"id":event_id+"_learning_rejected_"+id,"kind":"skill_progress","speaker":"world","listeners":[id],"source_event_id":original.id,"original_event":original.duplicate(true),"learning_failed":true,"learning_started":false,"goal_id":request.get("goal_id",""),"learning_goal":request.get("goal",request.get("feedback","")),"revision_of":request.get("ref",""),"text":"学习未启动："+str(submitted.error)}
	var task: Dictionary=store.working_tasks.get(id,{})
	if task.get("action_event_id","")==event_id:
		task.state="submission_failed"
		task["submission_error"]=str(submitted.error)
	_record_learning_failure(id,event)

func _begin_revision(id: String, event_id: String, request: Dictionary) -> void:
	if not _execution_allowed():return
	var original: Dictionary=store.event_for(id,event_id)
	var submitted: Dictionary=skills.request_revision(id,original,request)
	log_event({"type":"learning_requested","event_id":event_id,"person_id":id,"message":"正在学习：根据教导修订原技能；旧版本保留" if submitted.ok else submitted.error,"request":submitted})
	if not submitted.ok:_learning_submission_failed(id,event_id,original,submitted,request)

func _begin_self_learning(id: String, event_id: String, decision: Dictionary) -> void:
	if not _execution_allowed():return
	var event: Dictionary=store.event_for(id,event_id)
	var original: Dictionary=event.get("original_event",event)
	var submitted: Dictionary=skills.request_learning(id,original,decision.learning_request)
	log_event({"type":"learning_requested","event_id":event_id,"person_id":id,"message":"已说明打算，开始自行学习" if submitted.ok else submitted.error,"request":submitted})
	if not submitted.ok:_learning_submission_failed(id,event_id,original,submitted,decision.learning_request)

func _record_world_witnesses(fact: Dictionary) -> void:
	var actor: Node3D=get_parent().get_node("Player") if fact.person_id=="player" else survival.actors[fact.person_id].body
	var actor_name: String="玩家" if fact.person_id=="player" else store.people[fact.person_id].name
	var source: Vector3=actor.global_position+Vector3(0,1.2,0)
	var material: String="水" if fact.material=="water" else "食物"
	var descriptions:={"consumed":"消耗了一份"+material,"given":"递出了"+material,"stored":"存放了"+material,"taken":"取出了"+material,"filled":"装入了"+material}
	if not descriptions.has(fact.kind): return
	for id in store.people:
		if id==fact.person_id or not survival.perception.sees(id,source): continue
		store.hear(id,{"id":str(fact.source_event_id)+"_seen_"+str(Time.get_ticks_usec()),"kind":"observed_action","speaker":"world","actor_id":fact.person_id,"text":actor_name+descriptions[fact.kind]})

func _start_pipeline(event: Dictionary, job: Dictionary) -> void:
	if event.get("speaker")=="player":
		for id in captions:
			captions[id].show_hearing("已听见 · 正在理解" if id in event.listeners else "这句话未传给她",8.0)
	if event.get("speaker")=="player" and event.get("kind")=="speech_intent": _skill_playtest_waiting=false
	for id in event.listeners: skills.sync_person(id)
	_speech_order=Pipeline.ordered_listeners(event,store.people)
	_reports_received.clear()
	_update_nearby()
	for id in store.people:
		store.people[id]["help_context"]=help_tasks.context(id,_autonomy_clock)
	_round_events[event.id]=event.duplicate(true)
	for id in event.listeners:
		var own: Dictionary=event.duplicate(true)
		if own.has("spatial_segments"):
			var heard: PackedStringArray=[]
			for segment in own.spatial_segments:
				if segment.audience.has(id): heard.append(segment.text)
			own.text=" ".join(heard)
		var context:=TurnContext.describe(own,store.people)
		var source: Dictionary=_round_events.get(context.source_event_id,{}).duplicate(true)
		log_event({"type":"turn_started","person_id":id,"event":own,"turn_context":context,"source_event":source,"source_round":_event_rounds.get(context.source_event_id,0)})
	pipeline.run(event,job)

func _update_nearby() -> void:
	for id in store.people:
		var source: Vector3=get_parent().get_node("People/"+store.people[id].node).global_position+Vector3(0,1.6,0)
		var nearby: Array=[]
		for other in store.people:
			if other==id: continue
			var at: Vector3=get_parent().get_node("People/"+store.people[other].node).global_position+Vector3(0,1.6,0)
			if survival.perception.sees(id,at):
				nearby.append({"id":other,"name":store.people[other].name,"visible_action":store.people[other].current_action.name})
		store.people[id]["visible_people"]=nearby

func _try_autonomy() -> void:
	if _skill_playtest_waiting: return
	if config.local_only or not config.get("actions_enabled",false): return
	if not survival.ready_for_actions or not survival.enabled or menu.is_open(): return
	for caption in captions.values():
		if caption.expanded: return
	if not config_error(false).is_empty(): return
	# 先让刚接受的技能发出第一条世界请求（可能立即递物），再开无关模型轮次。
	# 不等待整个动作结束；第一条请求已到达就解除，物理与玩家输入始终继续。
	if skills.has_starting_call(): return
	var event:=autonomy.next_task_event(_autonomy_clock,survival.actors)
	if event.is_empty():
		if not config.get("autonomy_enabled",false): return
		for id in store.people:
			var visible_food: Variant=store.people[id].get("survival_observation",{}).get("carried_food")
			if visible_food!=null and visible_food>0: help_tasks.promises.erase(id)
			store.people[id]["help_context"]=help_tasks.context(id,_autonomy_clock)
		var unanswered: Dictionary=information_waits.next_event(_autonomy_clock,survival.actors)
		if not unanswered.is_empty(): autonomy.offer_request(unanswered,_autonomy_clock)
		event=autonomy.next_event(_autonomy_clock,store.people,survival.actors)
	if event.is_empty(): return
	if event.get("original_event",{}).get("speaker")=="player" and _task_was_cancelled(event.listeners[0],event):
		log_event({"type":"stale_task_discarded","person_id":event.listeners[0],"event_id":event.id,"message":"旧请求已取消或被新任务接替，丢弃迟到续办，不调用模型"})
		return
	busy=true
	_decisions_done=false
	_allow_execution=true
	_event_started=Time.get_ticks_msec()
	_job_config=config.duplicate(true)
	log_event({"type":"autonomous_event","event":event,"person_id":event.listeners[0],"message":store.people[event.listeners[0]].name+"自主判断："+event.text})
	_start_pipeline(event,_job_config)

func reset_help_scenario() -> void:
	if busy or mic.recording: return
	reset_context()
	store.people.person_002.known_facts.append("测试情境：脚踝疼，暂时难以独自往返较远的储食处，希望有人把食物送到手中。")
	store.people.person_002.short_term.expectations.append("希望附近的人帮忙取一份食物，但需要自己选择如何处理。")
	for id in store.people:
		store.people[id].needs.hunger=85 if id=="person_002" else 10
		if survival.ready_for_actions: survival._sync(id)
	survival._refresh_visuals()
	log_event({"type":"help_scenario","message":"互助测试：储食处三份，小花脚踝疼且饥饿；不指定帮助者、回应或台词。关闭菜单后观察自主选择。"})

func reset_gather_scenario() -> void:
	if busy or mic.recording: return
	reset_context()
	for item in survival.storage_contents.items:
		if is_instance_valid(item.get("visual")): item.visual.queue_free()
	survival.storage_contents.clear()
	survival._refresh_visuals()
	log_event({"type":"gather_scenario","message":"采集互助情境：洞内没有食物，果树和篮子已恢复。可亲自采集，也可观察人物自主求助与采集；没有预设动作和台词。"})

func _record_capability_gap(report: Dictionary) -> void:
	if _capability_gaps.is_empty() and FileAccess.file_exists(capability_gap_path):
		var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(capability_gap_path))
		if saved is Dictionary: _capability_gaps=saved
	var gap: Dictionary=report.decision.capability_gap
	var key: String=(gap.goal+"/"+gap.missing_capability).sha256_text()
	var status: String="目录已有这个接口，需要检查使用方式或执行条件" if gap.missing_capability in survival.INTENTS else "待开发审查，尚未确认缺失"
	if not _capability_gaps.has(key): _capability_gaps[key]={"goal":gap.goal,"missing_capability":gap.missing_capability,"reason":gap.reason,"status":status,"occurrences":0,"people":[]}
	var entry: Dictionary=_capability_gaps[key]
	entry.occurrences+=1
	if report.person_id not in entry.people: entry.people.append(report.person_id)
	var file:=FileAccess.open(capability_gap_path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(_capability_gaps,"  "))
	else: push_error("无法保存能力缺口记录")
	log_event({"type":"capability_gap","person_id":report.person_id,"source_event_id":report.event_id,"gap":entry.duplicate(true),"message":"能力缺口候选："+gap.missing_capability+"；"+status})

func _exit_tree() -> void:
	var error: String=store.memory.save()
	if error!="": push_error(error)
