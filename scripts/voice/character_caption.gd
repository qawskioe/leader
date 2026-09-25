extends Node3D
## 头顶只显示身份与公开台词，不接收人物反思或模型报告。
var name_label: Label3D
var speech_label: Label3D
var speaking := false
var remaining := 0.0
const ConversationLog=preload("res://scripts/voice/conversation_log.gd")
var controller: Node
var person_id := ""
var details: Tree
var bubble: PanelContainer
var title: Button
var summary: Label
var state: Label
var expanded := false
var public_text := ""
var public_state := "尚未发言"
var field_reader: TextEdit
var leader_line: Line2D
var round_number := 0
var current_event_id:=""
var turn_heading: Label
var turn_cause: Label
var turn_purpose: Label
var capability_label: Label
var live_summary: Label
var skill_status: Label3D
var review_preview: Node3D
var head_panel: Node3D
var hearing_label: Label3D
var hearing_text:=""
var hearing_until:=0
var inspector: TabContainer
const Inspector=preload("res://scripts/voice/person_inspector.gd")

func _ready() -> void:
	review_preview=preload("res://scripts/voice/skill_review_preview.gd").new()
	review_preview.position=Vector3(0,3.2,0);add_child(review_preview)
	head_panel=preload("res://scripts/voice/head_panel.gd").new()
	head_panel.position.y=2.05;add_child(head_panel)
	name_label=_label(48,600)
	skill_status=_label(30,900)
	skill_status.position.y=1.88
	skill_status.hide()
	hearing_label=_label(30,700)
	hearing_label.position.y=2.25
	hearing_label.modulate=Color("85e6ef")
	hearing_label.hide()
	name_label.position.y=2.08
	name_label.modulate=Color("eddbb6")
	speech_label=_label(44,1000)
	speech_label.position.y=2.40
	speech_label.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
	speech_label.visible=false
	# 保留旧 Label3D 作为字幕状态接口；阅读卡片由屏幕投影显示，确保字号稳定。
	name_label.hide()
	speech_label.hide()
	var layer:=CanvasLayer.new()
	layer.layer=8
	add_child(layer)
	leader_line=Line2D.new()
	leader_line.width=1.5
	leader_line.default_color=Color(0.85,0.74,0.52,0.7)
	layer.add_child(leader_line)
	bubble=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.035,0.045,0.055,0.94)
	style.border_color=Color("a38d68")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=8
	style.content_margin_bottom=8
	bubble.add_theme_stylebox_override("panel",style)
	layer.add_child(bubble)
	var box:=VBoxContainer.new()
	bubble.add_child(box)
	title=Button.new()
	title.flat=true
	title.alignment=HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size",20)
	title.pressed.connect(func(): set_expanded(not expanded))
	box.add_child(title)
	live_summary=Label.new()
	live_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	live_summary.add_theme_font_size_override("font_size",18)
	box.add_child(live_summary)
	turn_heading=Label.new()
	turn_heading.add_theme_font_size_override("font_size",20)
	turn_heading.add_theme_color_override("font_color",Color("ffe0a0"))
	turn_heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(turn_heading)
	turn_cause=Label.new()
	turn_cause.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	turn_cause.max_lines_visible=3
	box.add_child(turn_cause)
	turn_purpose=Label.new()
	turn_purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	turn_purpose.max_lines_visible=2
	box.add_child(turn_purpose)
	capability_label=Label.new()
	capability_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	capability_label.max_lines_visible=3
	capability_label.add_theme_color_override("font_color",Color("f2b06b"))
	capability_label.hide()
	box.add_child(capability_label)
	state=Label.new()
	state.add_theme_color_override("font_color",Color("e4c589"))
	state.text=public_state
	box.add_child(state)
	summary=Label.new()
	summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size",18)
	summary.max_lines_visible=4
	box.add_child(summary)
	inspector=Inspector.new()
	box.add_child(inspector)
	inspector.hide()
	var technical:=VBoxContainer.new()
	technical.name="事件调试"
	inspector.add_child(technical)
	details=ConversationLog.new()
	details.custom_minimum_size=Vector2(340,240)
	technical.add_child(details)
	details.hide()
	field_reader=TextEdit.new()
	field_reader.editable=false
	field_reader.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	field_reader.custom_minimum_size=Vector2(340,110)
	field_reader.text="点击上面的任一字段，在此查看完整内容和说明；可选择复制。"
	technical.add_child(field_reader)
	field_reader.hide()
	details.item_selected.connect(func():
		var item: TreeItem=details.get_selected()
		var value: Variant=item.get_metadata(1)
		field_reader.text=item.get_text(0)+"\n"+item.get_tooltip_text(0)+"\n"+(JSON.stringify(value,"  ") if value!=null else item.get_text(1)))

func _label(size: int, width: float) -> Label3D:
	var label:=Label3D.new()
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false
	label.font_size=size
	label.outline_size=12
	label.outline_modulate=Color(0.04,0.03,0.02,0.95)
	label.pixel_size=0.0025
	label.width=width
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func set_person_name(value: String) -> void:
	name_label.text=value
	title.text=value+"  ▸ 详情 [E]"

func show_hearing(text: String, seconds: float=5.0) -> void:
	hearing_text=text
	hearing_until=Time.get_ticks_msec()+int(seconds*1000)
	hearing_label.text=text
	hearing_label.visible=not text.is_empty()

func begin_public(text: String) -> void:
	speaking=true
	remaining=0
	speech_label.text=text.strip_edges()
	speech_label.visible=not speech_label.text.is_empty()
	speech_label.hide()
	public_text=text
	public_state="正在说话"
	_refresh()
	name_label.modulate=Color("ffe69a")

func end_public(success: bool) -> void:
	speaking=false
	remaining=2.5 if success else 0.0
	public_state="已说完" if success else "播放失败"
	_refresh()
	if not success: clear()

func clear() -> void:
	speaking=false
	remaining=0
	speech_label.text=""
	speech_label.visible=false
	name_label.modulate=Color("eddbb6")
	# 自动消退仅影响旧字幕；卡片保留上一句，供玩家辨认边界。
	if is_instance_valid(summary): _refresh()

func _process(delta: float) -> void:
	if not speaking and remaining>0:
		remaining-=delta
		if remaining<=0: clear()
	if not is_instance_valid(controller): return
	# 请求等待可能超过短提示时限；用实际待返回状态驱动，不伪装成已经结束。
	if controller.busy and person_id in controller._speech_order and not controller._reports_received.has(person_id):
		hearing_text="已听见 · 正在理解"
	elif Time.get_ticks_msec()>hearing_until: hearing_text=""
	hearing_label.text=hearing_text
	hearing_label.visible=not hearing_text.is_empty()
	if is_instance_valid(controller.survival) and controller.survival.ready_for_actions:
		var actor: Dictionary=controller.survival.actors[person_id]
		var person: Dictionary=controller.store.people[person_id]
		review_preview.show_job(str(person.get("learning",{}).get("job","")))
		var message: String=person.get("learning",{}).get("message","")
		var issues: Array=person.get("learning",{}).get("review",{}).get("issues",[])
		if not issues.is_empty() and person.get("learning",{}).get("state","failed")=="failed":
			var issue: Variant=issues[0]
			message="动作审查未通过\n"+(str(issue.get("problem","")) if issue is Dictionary else str(issue)).left(95)
		if actor.stage=="skill_body": message="正在执行身体动作"
		elif controller._skill_playtest_waiting and person_id=="person_003" and issues.is_empty(): message="已掌握饮水 · 等待你的教导" if not person.get("available_skills",[]).is_empty() else "尚未掌握饮水 · 等你开口"
		skill_status.text=message
		skill_status.visible=not message.is_empty()
	head_panel.visible=not controller.menu.is_open()
	var current_status:=skill_status.text
	if current_status.is_empty() and controller.survival.ready_for_actions:
		current_status=Inspector.brief(controller.store.people[person_id],controller.survival.actors[person_id],controller.survival)
	if public_state.begins_with("判断失败") or public_state.begins_with("出错"): current_status=public_state+"\n"+current_status
	if not hearing_text.is_empty():current_status=hearing_text+"\n"+current_status
	# 闲置人物只留姓名，视线最接近的人展开状态；公开发言和故障仍主动显示。
	var camera:=get_viewport().get_camera_3d()
	var focused: Node=null
	var best:=0.94
	if camera!=null:
		for caption in controller.captions.values():
			if not caption.visible: continue
			var offset: Vector3=caption.global_position+Vector3(0,1.6,0)-camera.global_position
			var score:=(-camera.global_basis.z).dot(offset.normalized())
			if score>best:
				best=score;focused=caption
	var compact:=focused!=self and not expanded and public_text.is_empty() and hearing_text.is_empty() and skill_status.text.is_empty() and not public_state.begins_with("判断失败") and not public_state.begins_with("出错")
	head_panel.update_content(name_label.text,current_status,public_text,compact)
	name_label.hide();speech_label.hide();skill_status.hide();hearing_label.hide()
	if not expanded:
		bubble.hide()
		leader_line.hide()
		return
	inspector.controller=controller; inspector.person_id=person_id
	if is_instance_valid(controller.survival) and controller.survival.ready_for_actions:
		live_summary.text=Inspector.brief(controller.store.people[person_id],controller.survival.actors[person_id],controller.survival)
		if not hearing_text.is_empty(): live_summary.text=hearing_text+"\n"+live_summary.text
	turn_heading.hide(); turn_cause.hide(); turn_purpose.hide()
	live_summary.visible=not expanded
	state.visible=not expanded and not public_text.is_empty()
	summary.visible=not expanded and not public_text.is_empty()
	var another_open:=false
	for caption in controller.captions.values():
		if caption!=self and caption.expanded: another_open=true
	if camera==null: return
	var anchor:=global_position+Vector3(0,2.25,0)
	bubble.visible=not controller.menu.is_open() and not another_open and (expanded or (visible and not camera.is_position_behind(anchor) and controller._clear_sight(camera.global_position,global_position+Vector3(0,1.65,0))))
	leader_line.visible=bubble.visible and not expanded
	if not bubble.visible:
		if expanded and not controller.menu.is_open(): set_expanded(false)
		return
	var viewport_size:=get_viewport().get_visible_rect().size
	if expanded: inspector.custom_minimum_size=Vector2(340,clampf(viewport_size.y-110,300,760))
	bubble.custom_minimum_size.x=clampf(viewport_size.x*0.32,380,480) if expanded else 380
	bubble.size.x=bubble.custom_minimum_size.x
	bubble.reset_size()
	var point:=camera.unproject_position(anchor)
	bubble.position=Vector2(clampf(point.x-bubble.size.x/2,8,maxf(8,viewport_size.x-bubble.size.x-8)),clampf(point.y-bubble.size.y,8,maxf(8,viewport_size.y-bubble.size.y-8)))
	if expanded:
		# 选择离人物/验证视窗较远的一侧，不再把详情居中盖住动作。
		bubble.position=Vector2(8 if point.x>=viewport_size.x/2 else maxf(8,viewport_size.x-bubble.size.x-8),8)
	if not expanded:
		for attempt in controller.captions.size():
			for id in controller.captions:
				var other: Node=controller.captions[id]
				if id>=person_id or not other.bubble.visible: continue
				if bubble.get_global_rect().grow(6).intersects(other.bubble.get_global_rect()):
					bubble.position.y=maxf(8,other.bubble.position.y-bubble.size.y-10)
	leader_line.points=PackedVector2Array([point,bubble.position+Vector2(bubble.size.x/2,bubble.size.y)])

func _refresh() -> void:
	state.text=public_state+(" · 记录 #%d"%round_number if round_number>0 else "")
	summary.text="公开表达："+public_text
	state.visible=not public_text.is_empty()
	summary.tooltip_text=public_text
	summary.visible=not public_text.is_empty()

func set_expanded(value: bool) -> void:
	expanded=value
	inspector.visible=value
	if value:
		inspector.controller=controller; inspector.person_id=person_id
		inspector.current_tab=0; inspector.refresh()
	if value and is_instance_valid(controller):
		for caption in controller.captions.values():
			if caption!=self: caption.set_expanded(false)
	details.visible=value
	field_reader.visible=value
	title.text=name_label.text+("  ▾ 收起 [E]" if value else "  ▸ 详情 [E]")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	if (focused is TextEdit and focused.editable) or focused is LineEdit: return
	if not event is InputEventKey or event.echo or not event.pressed or event.physical_keycode!=KEY_E: return
	if not is_instance_valid(controller) or controller.menu.is_open(): return
	if expanded:
		set_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if not head_panel.visible: return
	var camera: Camera3D=get_viewport().get_camera_3d()
	var best: Node
	var score:=0.85
	for caption in controller.captions.values():
		if not caption.visible or not caption.head_panel.visible: continue
		if not controller._clear_sight(camera.global_position,caption.global_position+Vector3(0,1.65,0)): continue
		var dot:=(-camera.global_basis.z).dot((caption.global_position+Vector3(0,1.6,0)-camera.global_position).normalized())
		if dot>score:
			score=dot
			best=caption
	if best==self:
		set_expanded(true)
		get_viewport().set_input_as_handled()

func append_record(record: Dictionary) -> void:
	details.append_record(record)
	if record.get("type")=="turn_started":
		current_event_id=record.event.id
		round_number=record.get("round_number",0)
		turn_heading.text=record.turn_context.title
		turn_cause.text="起因："+record.turn_context.cause
		turn_cause.tooltip_text=turn_cause.text
		turn_purpose.text="要决定："+record.turn_context.purpose
		turn_purpose.tooltip_text=turn_purpose.text
		public_text=""
		capability_label.hide()
		public_state="正在判断"
		_refresh()
		return
	# 旧轮次的异步动作／语音仍入历史，不能覆盖当前轮次的来由和状态。
	if not current_event_id.is_empty() and record.get("event_id","")!=current_event_id: return
	if record.get("type","")=="role_result": round_number=record.get("round_number",0)
	match record.get("type",""):
		"autonomous_event":
			round_number=record.get("round_number",0)
			public_text=""
			public_state="正在自主判断" if record.event.kind=="need_changed" else ("正在重新安排未完成的帮助" if record.event.kind in ["work_problem","help_continue"] else "正在考虑对方的请求")
		"capability_gap":
			capability_label.text="能力缺口候选："+record.gap.missing_capability+"\n想完成："+record.gap.goal
			capability_label.tooltip_text=record.gap.reason+"\n"+record.gap.status
			capability_label.show()
		"request_queued": public_state="听到请求 · 等待判断"
		"role_result":
			if record.report.has("decision"):
				public_text=record.report.decision.public_reply
				public_state="已生成 · 尚未说出" if not public_text.is_empty() else "本轮保持沉默"
			else: public_state="判断失败 · 展开查看"
		"tts_request": public_state="正在生成语音 · 尚未说出"
		"speaking_started": public_state="正在说话"
		"spoken": public_state="已说完"
		"action_submitted": public_state="行动已提交，等待实际结果"
		"action_result": public_state=("行动完成：" if record.result.success else "行动失败：")+record.result.message
		"error":
			public_state="出错 · 展开查看"
			show_hearing("语音播放失败 · 未说出答复" if str(record.get("stage","")).begins_with("tts") else str(record.get("message","本次处理失败")),20.0)
	_refresh()

func reset_display() -> void:
	current_event_id=""
	round_number=0
	turn_heading.text=""; turn_cause.text=""; turn_purpose.text=""
	capability_label.hide()
	public_text=""
	public_state="尚未发言"
	clear()
