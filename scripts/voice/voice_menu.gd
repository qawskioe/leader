extends CanvasLayer
## 只在 F1 菜单显示配置和开发记录，不增加常驻 HUD。
var controller: Node
var panel: PanelContainer
var fields: Dictionary = {}
const ConversationLog=preload("res://scripts/voice/conversation_log.gd")
var grouped: Tree
var output: TextEdit
var status: Label
var session_status: Label
var device: OptionButton
var recipient: OptionButton
var local_only: CheckBox
var capswriter_asr: CheckBox
var tts_enabled: CheckBox
var actions_enabled: CheckBox
var autonomy_enabled: CheckBox
var cloud_fields: Array[Control] = []

func _ready() -> void:
	layer = 20
	panel = PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035,0.04,0.05,0.98)
	panel.add_theme_stylebox_override("panel",background)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var title := Label.new()
	title.text = "语音与社会反应测试 · F1 返回洞穴 · 按住 V 说话"
	title.add_theme_font_size_override("font_size",24)
	layout.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	var people_page:=HBoxContainer.new()
	people_page.name="人物"
	tabs.add_child(people_page)
	var selector:=VBoxContainer.new()
	selector.custom_minimum_size.x=170
	people_page.add_child(selector)
	var person_view:=preload("res://scripts/voice/person_inspector.gd").new()
	person_view.controller=controller
	person_view.person_id=controller.store.people.keys()[0]
	people_page.add_child(person_view)
	for id in controller.store.people:
		var button:=Button.new()
		button.set_meta("person_id",id)
		button.text=controller.store.people[id].name+"
"+controller.store.people[id].identity.former_work
		button.custom_minimum_size.y=70
		button.pressed.connect(func(): person_view.person_id=id; person_view.refresh())
		selector.add_child(button)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "服务与收音"
	tabs.add_child(settings_scroll)
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings)
	var help := Label.new()
	help.text = "文字模型分别生成各听众的私下理解、公开答复和行动意图。\n默认 CapsWriter 本机识别；公开答复交给 Gemini API：Gemini 3.8 Flash TTS / 人物独立音色 边生成边播放。\n当前支持附近探索、拿篮采集、取到手中、直接交付、存放、进食与休息。动作与数值由程序执行；持久记忆与遗忘尚未实现。"
	settings.add_child(help)
	var gather_help:=Label.new()
	gather_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	gather_help.text="实体采集：对准篮子按住 F 拿起；对准果实按住 F 摘到手中；右键逐个装篮；G 放下篮子。
回到洞内储食处，对准它按住 F 卸一份，松开再按卸下一份。篮子最多四份，负重时不能跑步或用 R 回到洞内。没有资源背包 UI。
可说：‘大山，拿篮子出去采些食物带回来。’果实采下后十分钟重新长出（测试参数）。"
	settings.add_child(gather_help)
	var decision_note:=Label.new()
	decision_note.text="日常角色判断使用本机文字网关；模型配置由网关管理。"
	settings.add_child(decision_note)
	capswriter_asr = CheckBox.new()
	capswriter_asr.text = "使用 CapsWriter 本机识别（请先启动其服务端，端口 6016）"
	capswriter_asr.button_pressed = controller.config.get("capswriter_asr",true)
	settings.add_child(capswriter_asr)
	tts_enabled = CheckBox.new()
	tts_enabled.text = "播放公开答复（Gemini API 3.8 / 人物独立音色；关闭后仅测试文字）"
	tts_enabled.button_pressed = controller.config.get("tts_enabled",true)
	settings.add_child(tts_enabled)
	actions_enabled = CheckBox.new()
	actions_enabled.text = "执行最低档生存意图（关闭后新指令仅作对话）"
	actions_enabled.button_pressed = controller.config.get("actions_enabled",true)
	settings.add_child(actions_enabled)
	autonomy_enabled=CheckBox.new()
	autonomy_enabled.text="人物自主处理饥饿与求助（打开菜单或人物详情时暂停新自主判断）"
	autonomy_enabled.button_pressed=controller.config.get("autonomy_enabled",true)
	settings.add_child(autonomy_enabled)
	local_only = CheckBox.new()
	local_only.text = "仅检查本地收音和传播范围（不上传；已开通服务后取消勾选）"
	local_only.button_pressed = controller.config.local_only
	settings.add_child(local_only)
	var grid := GridContainer.new()
	grid.columns = 2
	settings.add_child(grid)
	var labels := {"asr_url":"语音识别完整 URL","asr_model":"语音识别模型","asr_key":"语音 API Key","noise_floor_db":"噪声阈值 dBFS","quiet_db":"轻声对应电平（2米）","loud_db":"大声对应电平（20米）"}
	for key in labels:
		var label := Label.new()
		label.text = labels[key]
		grid.add_child(label)
		var edit := LineEdit.new()
		edit.text = str(controller.config[key])
		edit.secret = key.ends_with("_key")
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.custom_minimum_size.x = 620
		grid.add_child(edit)
		fields[key] = edit
		if not key.ends_with("_db"):
			cloud_fields.append(label)
			cloud_fields.append(edit)
	capswriter_asr.toggled.connect(_show_cloud_fields)
	_show_cloud_fields(capswriter_asr.button_pressed)
	var device_label := Label.new()
	device_label.text = "麦克风设备"
	grid.add_child(device_label)
	device = OptionButton.new()
	for name in AudioServer.get_input_device_list():
		device.add_item(name)
		if name == controller.config.input_device:
			device.select(device.item_count - 1)
	grid.add_child(device)
	var save := Button.new()
	save.text = "保存本机配置"
	save.pressed.connect(_save)
	settings.add_child(save)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(status)
	var tests := VBoxContainer.new()
	tests.name = "测试与输出"
	tabs.add_child(tests)
	var note := Label.new()
	note.text = "菜单显示私下理解、公开答复、意图与执行结果；仅公开台词会发声。赠与按钮仍是虚构事件，不改变物品；实际吃饭与搬运请在洞穴中说话安排。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tests.add_child(note)
	var row := HBoxContainer.new()
	tests.add_child(row)
	recipient = OptionButton.new()
	for id in controller.store.people:
		recipient.add_item(controller.store.people[id].name)
		recipient.set_item_metadata(recipient.item_count-1,id)
	row.add_child(recipient)
	var gift := Button.new()
	gift.text = "投放赠与测试事件"
	gift.pressed.connect(func(): controller.gift_test(recipient.get_item_metadata(recipient.selected)))
	row.add_child(gift)
	var reset := Button.new()
	reset.text = "重置生存测试（人物、位置与食物）"
	reset.pressed.connect(controller.reset_context)
	row.add_child(reset)
	var help_scenario:=Button.new()
	help_scenario.text="重置互助情境（小花需要送食物）"
	help_scenario.pressed.connect(controller.reset_help_scenario)
	tests.add_child(help_scenario)
	var gathering_scenario:=Button.new()
	gathering_scenario.text="重置采集互助（洞内无食物）"
	gathering_scenario.pressed.connect(controller.reset_gather_scenario)
	tests.add_child(gathering_scenario)
	var skill_scenario:=Button.new()
	skill_scenario.text="Luau拿取与修订场景"
	skill_scenario.pressed.connect(controller._prepare_luau_playtest)
	tests.add_child(skill_scenario)
	grouped=ConversationLog.new()
	grouped.people=controller.store.people
	grouped.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tests.add_child(grouped)
	var raw_tab:=VBoxContainer.new()
	raw_tab.name="原始日志（全部）"
	tabs.add_child(raw_tab)
	output = TextEdit.new()
	output.editable = false
	output.add_theme_color_override("font_readonly_color",Color(0.92,0.94,0.96))
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	raw_tab.add_child(output)
	var people_scroll := ScrollContainer.new()
	people_scroll.name = "人物身份与背景"
	tabs.add_child(people_scroll)
	var people_text := Label.new()
	people_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	people_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	people_text.text = "四人刚从天灾中逃离来到山洞。职业表示过去的经验，不代表已经发生对应劳动或拥有工具。\n\n"
	for id in controller.store.people:
		var person: Dictionary = controller.store.people[id]
		people_text.text += "%s（%s）\n旧职业：%s\n知道的事：%s\n需求：%s\n短期期待：%s\n关系：%s\n\n" % [person.name,id,person.identity.former_work,"；".join(person.known_facts),JSON.stringify(person.needs),"；".join(person.short_term.expectations),JSON.stringify(person.relationships)]
	people_scroll.add_child(people_text)
	var survival_tab := VBoxContainer.new()
	survival_tab.name = "生存状态"
	tabs.add_child(survival_tab)
	var survival_note := Label.new()
	survival_note.text = "调试数值只在本菜单显示。橙色果实代表一份食物。\n储食处用于存放食物；人物可直接取食，或把食物实际交到别人手中。\n可说：‘石头，拿一份食物交给小花。’‘小花，去吃饭。’\n初始共三份，不自动刷新；饥饿随时间缓慢增加。"
	survival_tab.add_child(survival_note)
	var survival_values := Label.new()
	survival_tab.add_child(survival_values)
	survival_values.text=controller.survival.debug_summary()
	controller.survival.state_changed.connect(func(): survival_values.text=controller.survival.debug_summary())
	var saves:=HBoxContainer.new();layout.add_child(saves)
	for action in [["保存进度","save"],["读取进度","load"],["保存并退出","quit"],["退出且不保存","discard"]]:
		var button:=Button.new();button.text=action[0];button.name="Session_"+action[1]
		button.pressed.connect(_session_action.bind(action[1]));saves.add_child(button)
	session_status=Label.new();session_status.text="保存会停止当前执行步骤，保留现场与未完成任务。";layout.add_child(session_status)
	var close := Button.new()
	close.text = "返回洞穴（F1）"
	close.pressed.connect(toggle)
	layout.add_child(close)
	panel.hide()

func _session_action(action: String) -> void:
	if action in ["quit","discard"]:
		controller.session_manager.quit_game(action=="quit");return
	var error: String=await controller.session_manager.save_game() if action=="save" else await controller.session_manager.load_game()
	if not error.is_empty():session_status.text=error

func _save() -> void:
	var value: Dictionary = controller.config.duplicate(true)
	value.tts_enabled = tts_enabled.button_pressed
	value.actions_enabled = actions_enabled.button_pressed
	value.autonomy_enabled = autonomy_enabled.button_pressed
	value.local_only = local_only.button_pressed
	value.capswriter_asr = capswriter_asr.button_pressed
	for key in fields:
		var text: String = fields[key].text.strip_edges()
		if key.ends_with("_db"):
			if not text.is_valid_float():
				status.text = "电平必须是数字：" + key
				return
			value[key] = float(text)
		else:
			value[key] = text
	if device.selected >= 0:
		value.input_device = device.get_item_text(device.selected)
	var error: String = controller.save_config(value)
	status.text = "已保存。按 F1 返回；用 V 录音，再打开‘测试与输出’查看电平和结果。" if error.is_empty() else error

func _show_cloud_fields(use_local_asr: bool) -> void:
	for field in cloud_fields:
		field.visible = not use_local_asr

func open() -> void:
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()

func close() -> void:
	panel.hide()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func is_open() -> bool:
	return panel.visible

func append_record(record: Dictionary) -> void:
	grouped.append_record(record)
	var text := "[%s] " % record.get("time", "")
	match record.get("type", ""):
		"audio":
			var names := PackedStringArray()
			for id in record.listeners:
				names.append(controller.store.people[id].name)
			text += "录音 %.2f 秒 | %.1f dBFS | 传播 %.1f 米\n听众：%s\n削波比例：%.2f%%" % [record.duration_seconds,record.dbfs,record.radius_m,"、".join(names),record.clipped_ratio*100]
		"transcript", "fixture":
			text += "转写／测试事件：" + record.event.text + "\n事件 ID：" + record.event.id
			if record.has("elapsed_ms"):
				text += "\n识别耗时：%d ms | usage：%s" % [record.elapsed_ms,JSON.stringify(record.get("usage",{}))]
		"role_result":
			var result: Dictionary = record.report
			text += "%s（%s）\n事件：%s\n" % [result.person_name,result.person_id,result.event_id]
			if result.has("error"):
				text += "失败：" + result.error
			else:
				var decision: Dictionary = result.decision
				text += "私下理解：%s\n公开答复（播放状态见下方日志）：%s\n本轮意图：%s\n路由依据：%s" % [decision.private_interpretation,decision.public_reply if not decision.public_reply.is_empty() else "保持沉默",decision.intent,decision.routing_reason]
			for call in result.calls:
				text += "\n调用 %s / %s：%d ms，usage：%s" % [call.stage,call.model,call.elapsed_ms,JSON.stringify(call.usage)]
		_:
			text += record.get("message", JSON.stringify(record))
			if record.has("elapsed_ms"):
				text += "\n耗时：%d ms" % record.elapsed_ms
			if record.has("log_path"):
				text += "\n日志：" + record.log_path
	# 不能用 text +=：它会重排全部历史，长时间运行后每次交互阻塞数秒。
	output.set_caret_line(output.get_line_count()-1)
	output.set_caret_column(output.get_line(output.get_line_count()-1).length())
	output.insert_text_at_caret(text + "\n\n")
