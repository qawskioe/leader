extends Node3D
## PC VR 入口。世界规则仍使用原玩家；Eyes 只同步头部姿态，不参与渲染。
var origin: XROrigin3D
var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var active := false
var focused := false
var turn_ready := true
var voice: Node
var status_label: Label3D
var transcript_label: Label3D
var turn_frames_left := 0
var turn_serial := 0
var pending_speech := 0
var pending_speech_at := 0
var hands = preload("res://scripts/vr/hand_interaction.gd").new()
var feedback := ""
var feedback_until := 0
var targets: Dictionary={}
var diagnostic_clock := 0.0
const AudioTrace=preload("res://scripts/vr/audio_trace.gd")

func _ready() -> void:
	var interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null or not interface.is_initialized():
		push_warning("VR 未连接：继续桌面模式。连接 Link 后用 VR 启动入口重新启动。")
		return
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
	head.near = 0.05
	head.far = 120.0
	origin.add_child(head)
	left = _controller("left_hand", Color("70bfff"))
	right = _controller("right_hand", Color("ffc878"))
	transcript_label = Label3D.new()
	transcript_label.font_size = 26
	transcript_label.pixel_size = 0.001
	transcript_label.width = 360
	transcript_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transcript_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	transcript_label.position = Vector3(0,0.20,-0.08)
	transcript_label.text = "你的语音识别结果会显示在这里"
	left.add_child(transcript_label)
	for side in ["left","right"]:
		var marker:=MeshInstance3D.new()
		var sphere:=SphereMesh.new(); sphere.radius=0.035; sphere.height=0.07
		marker.mesh=sphere
		var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color("ffe28a")
		marker.material_override=material
		add_child(marker); targets[side]=marker
	status_label = Label3D.new()
	status_label.font_size = 28
	status_label.pixel_size = 0.001
	status_label.position = Vector3(0, 0.12, 0)
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	right.add_child(status_label)
	right.button_pressed.connect(_pressed)
	right.button_released.connect(_released)
	left.button_pressed.connect(func(action: String): _grip("left",action,true))
	left.button_released.connect(func(action: String): _grip("left",action,false))
	interface.session_focussed.connect(_resume)
	interface.session_visible.connect(_suspend)
	interface.session_stopping.connect(_suspend)
	focused = interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	active = true
	get_parent().camera.current = false
	head.current = true
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.physics_ticks_per_second = 90
	call_deferred("_connect_voice")
	print("VR_READY: 左摇杆移动，右摇杆分段转向，右扳机按住说话、松开发送。")

func _controller(tracker_name: String, color: Color) -> XRController3D:
	var hand := XRController3D.new()
	hand.tracker = tracker_name
	origin.add_child(hand)
	var mesh := MeshInstance3D.new()
	var shape := CapsuleMesh.new()
	shape.radius = 0.035
	shape.height = 0.13
	mesh.mesh = shape
	mesh.rotation.x = PI / 2
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	hand.add_child(mesh)
	return hand

func _connect_voice() -> void:
	voice = get_parent().get_parent().get_node_or_null("VoiceTest")
	if voice != null:
		var probe_pid:=OS.create_process(ProjectSettings.globalize_path("res://services/text-gateway/.venv/Scripts/python.exe"),[ProjectSettings.globalize_path("res://services/text-gateway/vr_audio_probe.py"),str(OS.get_process_id())],false)
		AudioTrace.record("probe_started",{"probe_pid":probe_pid,"focused":focused})
		voice.cancel_recording_on_focus_loss = false
		# 屏幕坐标的输入文字只适用于桌面；VR 用左手三维字幕。
		voice.player_input_note.hide()
		hands.sim = voice.survival
		for device in AudioServer.get_input_device_list():
			if "Oculus" in device:
				voice.config.input_device = device
				AudioServer.input_device = device
				break
		print("VR_AUDIO input=",AudioServer.input_device," devices=",AudioServer.get_input_device_list())
		voice.mic.prepare_continuous_input()
		voice.mic.captured.connect(func(result: Dictionary):
			feedback = "正在识别…" if result.get("ok",false) else "未收到有效声音 · A 重新连接麦克风"
			feedback_until = Time.get_ticks_msec()+6000)

func _suspend() -> void:
	focused = false
	_cancel_pending_speech()
	AudioTrace.record("xr_focus_lost",{"recording":is_instance_valid(voice) and voice.mic.recording})
	if is_instance_valid(voice):
		voice.mic.invalidate_connection()
		if voice.mic.recording: voice.mic.cancel()

func _resume() -> void:
	focused=true
	AudioTrace.record("xr_focused")
	if is_instance_valid(voice) and voice.mic.reconnect_required: _recover_audio()

func _recover_audio() -> void:
	if not is_instance_valid(voice) or voice.mic.recovering: return
	_cancel_pending_speech()
	feedback="正在重新连接麦克风…";feedback_until=Time.get_ticks_msec()+10000
	var ok: bool=await voice.mic.recover_connection(voice.config.input_device)
	feedback="录音连接已重建，请按住扳机说话确认" if ok else "头显麦克风未连接，请检查 Link"
	feedback_until=Time.get_ticks_msec()+8000

func _pressed(action: String) -> void:
	if action=="ax_button" and focused:
		_recover_audio();return
	if action=="by_button" and is_instance_valid(voice):
		var preparing:=pending_speech!=0
		_cancel_pending_speech()
		if not preparing: voice.cancel_interaction()
		feedback="已取消";feedback_until=Time.get_ticks_msec()+4000
		return
	if action in ["trigger_click","grip_click"]: AudioTrace.record("right_button_down",{"action":action,"focused":focused})
	_grip("right",action,true)
	if action == "trigger_click" and focused and is_instance_valid(voice):
		if voice.mic.recovering:
			feedback="正在恢复麦克风，请稍后重新按住说话";feedback_until=Time.get_ticks_msec()+4000;return
		pending_speech=Time.get_ticks_usec()
		pending_speech_at=Time.get_ticks_msec()
		_audio_request(pending_speech,"unmute_for_speech")

func _released(action: String) -> void:
	if action in ["trigger_click","grip_click"]: AudioTrace.record("right_button_up",{"action":action,"focused":focused})
	_grip("right",action,false)
	if action == "trigger_click" and is_instance_valid(voice):
		_cancel_pending_speech()
		voice.set_voice_input(false)

func _audio_request(id: int, action: String) -> void:
	var file:=FileAccess.open("res://services/text-gateway/runtime/vr_audio_request_%d.json"%OS.get_process_id(),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"id":id,"action":action,"unix_ms":int(Time.get_unix_time_from_system()*1000)}))

func _cancel_pending_speech() -> void:
	if pending_speech==0: return
	pending_speech=0
	_audio_request(Time.get_ticks_usec(),"cancel")

func _poll_speech_ready() -> void:
	if pending_speech==0: return
	var path:="res://services/text-gateway/runtime/vr_audio_ack_%d.json"%OS.get_process_id()
	if FileAccess.file_exists(path):
		var ack: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if ack is Dictionary and ack.get("id")==pending_speech:
			pending_speech=0
			if ack.get("ok",false) and focused:
				voice.set_voice_input(true)
			else:
				feedback="麦克风未就绪，本句未录音";feedback_until=Time.get_ticks_msec()+4000
			return
	if Time.get_ticks_msec()-pending_speech_at>2000:
		_cancel_pending_speech()
		feedback="麦克风准备超时，请重新按住说话";feedback_until=Time.get_ticks_msec()+4000

func _grip(side: String, action: String, pressed: bool) -> void:
	if action != "grip_click" or not focused or not is_instance_valid(voice): return
	var hand: XRController3D = left if side == "left" else right
	feedback = hands.grab(side,hand.global_position) if pressed else hands.release(side,hand.global_position)
	feedback_until = Time.get_ticks_msec()+5000
	voice.log_event({"type":"vr_interaction","hand":side,"pressed":pressed,"message":feedback})

func sync_head() -> void:
	if active: get_parent().camera.global_transform = head.global_transform

func _process(_delta: float) -> void:
	if not active: return
	if turn_frames_left>0:
		turn_frames_left-=1
		var current_camera:=get_viewport().get_camera_3d()
		AudioTrace.record("turn_frame",{"serial":turn_serial,"remaining":turn_frames_left,"delta_ms":_delta*1000,"head":str(head.global_position),"forward":str(-head.global_basis.z),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"camera":str(current_camera.get_path()) if current_camera else "none","focused":focused})
	diagnostic_clock += _delta
	if diagnostic_clock >= 10.0 and is_instance_valid(voice):
		diagnostic_clock = 0.0
		var positions: Dictionary={}
		for id in voice.survival.actors:
			var actor: Dictionary=voice.survival.actors[id]
			positions[id]={"position":str(actor.body.global_position),"stage":actor.stage}
		print("VR_STATUS ",JSON.stringify({"focused":focused,"head":str(head.global_position),"player":str(get_parent().global_position),"fps":Engine.get_frames_per_second(),"people":positions}))
	if is_instance_valid(voice):
		_poll_speech_ready()
		var recognized: String=voice.last_player_transcript
		var subtitle: String="你说：\n"+recognized if not recognized.is_empty() else "你的语音识别结果会显示在这里"
		if transcript_label.text!=subtitle: transcript_label.text=subtitle
		hands.reconcile()
		for side in targets:
			var hand: XRController3D=left if side=="left" else right
			var target: Array=[] if hands.held.has(side) else hands.candidate(hand.global_position)
			targets[side].visible=focused and not target.is_empty()
			if not target.is_empty(): targets[side].global_position=target[3]
		status_label.text = "正在录音 · 松开发送 · B 丢弃" if voice.mic.recording else "右扳机说话 · B 取消当前交互"
		if not voice.mic.recording and Time.get_ticks_msec()<feedback_until: status_label.text=feedback
		if voice.menu.is_open(): status_label.text = "电脑端菜单已打开，请先关闭"
		if pending_speech!=0: status_label.text="正在准备麦克风…"

static func horizontal_direction(basis: Basis, axis: Vector2) -> Vector3:
	var forward := -basis.z
	forward.y = 0
	if forward.length_squared() < 0.001: return Vector3.ZERO
	forward = forward.normalized()
	return (forward * axis.y + forward.cross(Vector3.UP) * axis.x).limit_length()

func movement() -> Vector3:
	if not active or not focused: return Vector3.ZERO
	var turn := right.get_vector2("primary").x
	if absf(turn) < 0.25: turn_ready = true
	if absf(turn) > 0.7 and turn_ready:
		# 围绕真实头部转向，避免偏离原点时被转出一段圆弧。
		var before := head.global_position
		var started:=Time.get_ticks_usec()
		origin.rotate_y(-signf(turn) * PI / 6)
		origin.global_position += before - head.global_position
		turn_serial+=1;turn_frames_left=4
		AudioTrace.record("snap_turn",{"serial":turn_serial,"yaw_delta":-signf(turn)*PI/6,"before":str(before),"after":str(head.global_position),"head_shift":head.global_position.distance_to(before),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0})
		turn_ready = false
	var axis := left.get_vector2("primary")
	if axis.length() < 0.2: return Vector3.ZERO
	return horizontal_direction(head.global_basis, axis)

func align_body() -> void:
	if not active: return
	# 将现实走动并入原身体碰撞；被墙挡住的偏移留在原点，不移动世界物品。
	var player := get_parent() as CharacterBody3D
	var offset := head.global_position - player.global_position
	offset.y = 0
	var before := player.global_position
	player.move_and_collide(offset)
	origin.global_position -= player.global_position - before
