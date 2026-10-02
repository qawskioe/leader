extends Tree
## 面向阅读的轮次／人物视图；原始记录逐条保存并可展开。
var people: Dictionary = {}
var turns: Dictionary = {}
var active: TreeItem
var cards: Dictionary = {}
var sequence := 0
const HELP := "展开箭头可随时查看详情，再点即可收起。生成答复 ≠ 已经说出口；语音生成完成 ≠ 播放结束；听闻记录 ≠ 听众已经回复。私下理解不会朗读。"
const EXPLANATIONS := {
	"learning_request":"请求强模型编写已开放验收目标。学会后继续原请求，不表示已经执行该动作。",
	"skill_call":"按本人已掌握技能的引用和参数发起执行；不能携带新代码或自行授予技能。",
	"skill_ref":"技能定义的固定内容引用；人物保存此索引，不各自复制代码。",
	"goal_verified":"代码返回成功不等于任务目标已核验。当前 false 表示没有自动判定目标达成。",
	"turn_started":"人物本轮判断正式开始，来由由程序触发记录生成。",
	"trigger":"调度程序实际采用的触发原因，不是模型事后解释。",
	"reason":"need_initial 首次需求检查；need_changed 检查状态变化；need_retry 定时复查；help_result 行动结果；help_retry 帮助未完成后的复查。",
	"changes":"与上次需求判断相比，调度程序检测到变化的状态。",
	"elapsed_seconds":"距该人物上次被调度判断的实际秒数，含预算或忙碌造成的延迟。",
	"checks_since_result":"同一实际结果之后，已经发起的继续检查次数。",
	"source_event":"关联事件原文；没有原文时不猜测，不伪造关联。",
	"shared_knowledge":"本句公开分享的本人已知条目，未实际说完前不传播。",
	"knowledge_offer":"模型决策时冻结的待分享信息；不是播放时重新查询世界。",
	"heard_from":"本次直接提供情报的人。",
	"original_source":"转述前的原始证据来源。",
	"heard_at_seconds":"听到的时间，不等于原始观察时间。",
	"request_kind":"information 是情报询问，help 是请求行动。",
	"help_continue":"上一步完成或失败后，检查原帮助请求还有哪些未完成；不是自动播报。",
	"heard_help_promise":"本人实际听到的答应及等待时间，不包含远处实时进度。",
	"own_help_tasks":"本人接下的持续帮助任务，采集完成不代表交付完成。",
	"usage":"模型用量统计；token 是模型计量文字的单位，不等于汉字数。",
	"attribution":"上游按消息／内容拆分的用量归属，主要用于排查与核账，不是人物想法。",
	"input_tokens":"模型接收的输入 token 数。", "output_tokens":"模型生成的输出 token 数；推理通常包含在其中，不应再次相加。",
	"total_tokens":"输入与输出的 token 合计。", "reasoning_tokens":"输出中用于推理的 token 数，不是可以展开阅读的推理文字。",
	"cached_tokens":"本次命中缓存的输入 token 数。", "cache_write_tokens":"上游报告写入缓存的 token 数。",
	"elapsed_ms":"这条记录对应阶段的耗时，单位毫秒；各阶段可能重叠，不应直接累加。",
	"audio_seconds":"生成音频的长度（秒），不是生成耗时或播放完成时间。",
	"listeners":"这条事件的听众。听闻表示写入记录，不表示已理解或回复。",
	"capability_gap":"模型提出的开发候选，未经核实，不自动执行开发。",
	"recipient_id":"实际物品交付对象；与说话对象 addressed_person 独立。",
	"speech_style":"模型自由描述的公开表达方式，不是固定三档，不朗读此字段。",
	"speech_act":"交流类型：request 请求对方处理；statement 普通陈述；reply 回答。",
	"addressed_person":"希望交流的对象 ID；只有实际听到公开请求的人才进入自主响应队列。",
	"public_heard":"已播放的公开台词写入附近成员听闻，没有自动触发她们的新一轮回复。",
	"tts_generated":"语音生成完成；可能仍在播放。", "speaker":"发言者。", "person_id":"人物的稳定内部编号。",
	"source_event_id":"引发这条记录的原事件编号，用于关联过程。", "event_id":"本轮事件的唯一编号。",
	"items":"逐条消息的统计明细。", "content":"消息内容部分的统计明细。", "request_fields":"请求字段对应的用量。",
	"input_tokens_details":"输入用量的细分统计。", "output_tokens_details":"输出用量的细分统计。",
	"time":"记录产生的本机时间。", "type":"记录类型，不是人物说的话。",
	"focus_hint":"根据朝向估计的交谈对象，不是强制指定目标。", "spatial_segments":"按音频时间分段的文字与空间线索。",
	"start_seconds":"片段相对录音开始的时间（秒）。", "end_seconds":"片段结束时间（秒）。"
}

func _ready() -> void:
	columns=2
	set_column_title(0,"轮次 / 人物 / 信息")
	set_column_title(1,"内容与状态（展开箭头查看详情）")
	column_titles_visible=true
	set_column_expand_ratio(0,1)
	set_column_expand_ratio(1,3)
	hide_root=true
	create_item()
	add_theme_constant_override("v_separation",10)
	item_activated.connect(func():
		var item:=get_selected()
		if item!=null and item.get_metadata(0) is String and turns.has(item.get_metadata(0)):
			var target: TreeItem=turns[item.get_metadata(0)]
			target.collapsed=false
			target.select(0)
			scroll_to_item(target)
			return
		if item!=null and item.get_child_count()>0: item.collapsed=not item.collapsed)

func person_name(id: String) -> String:
	return str(people[id].name) if people.has(id) else id

func _row(parent: TreeItem, title: String, value: String="") -> TreeItem:
	var item:=create_item(parent)
	item.set_text(0,title)
	item.set_text(1,value)
	item.set_tooltip_text(1,value)
	return item

func _new_turn(title: String) -> TreeItem:
	sequence+=1
	var item:=_row(get_root(),"第 %d 轮"%sequence,title)
	item.set_custom_bg_color(0,Color("243b4c"))
	item.set_custom_bg_color(1,Color("243b4c"))
	_row(item,"轮次状态","进行中")
	return item

func _field(parent: TreeItem, key: String, value: String) -> void:
	for child in parent.get_children():
		if child.get_text(0)==key:
			child.set_text(1,value)
			child.set_tooltip_text(1,value)
			return
	_row(parent,key,value)

func _card(turn: TreeItem, id: String) -> TreeItem:
	var key:=str(turn.get_instance_id())+"/"+id
	if not cards.has(key):
		var item:=_row(turn,person_name(id),"人物回应")
		item.set_custom_color(0,Color("ffe0a0"))
		cards[key]=item
		for child in turn.get_children():
			if child.get_text(0)=="技术详情与原始记录": child.move_after(item)
	return cards[key]

func _json(parent: TreeItem, key: String, value: Variant) -> void:
	var compound: bool=value is Dictionary or value is Array
	var text:=str(value)
	if value is String and people.has(value): text=person_name(value)+"（"+value+"）"
	if compound: text="%d 项"%value.size()
	var item:=_row(parent,key,text)
	item.set_metadata(1,value)
	var explanation: String=EXPLANATIONS.get(key,"")
	if key.begins_with("msg_") or key.begins_with("rs_"): explanation="上游消息／推理条目的内部 ID，仅用于对应统计。"
	if not explanation.is_empty():
		item.set_tooltip_text(0,explanation)
		_row(item,"说明",explanation)
	if value is Dictionary:
		for sub in value: _json(item,str(sub),value[sub])
	elif value is Array:
		for index in value.size(): _json(item,"[%d]"%index,value[index])
	item.collapsed=item.get_child_count()>0

func append_record(record: Dictionary) -> void:
	var kind: String=record.get("type","")
	if kind=="recording": active=_new_turn("正在录音，松开 V 后处理")
	var event_id: String=record.get("event_id",record.get("source_event_id",""))
	if record.has("event"): event_id=record.event.id
	if record.has("report"): event_id=record.report.event_id
	if record.has("result"): event_id=record.result.get("source_event_id",event_id)
	var turn: TreeItem=turns.get(event_id)
	if turn==null:
		if not event_id.is_empty() and active!=null and turns.values().has(active): active=_new_turn("等待本轮信息")
		if active==null: active=_new_turn("会话与系统记录")
		turn=active
		if not event_id.is_empty():
			if kind=="execution_feedback":
				turn=_new_turn("程序执行结果反馈")
				active=turn
			turns[event_id]=turn
	if kind in ["transcript","fixture","autonomous_event"]:
		turn.set_text(1,record.event.text)
		turn.set_tooltip_text(1,record.event.text)
	if record.has("round_number") and record.round_number>0: turn.set_text(0,"第 %d 轮"%record.round_number)
	var id: String=record.get("person_id",record.get("speaker",""))
	if record.has("report"): id=record.report.person_id
	if record.has("result"): id=record.result.get("person_id",id)
	var parent:=_card(turn,id) if people.has(id) else turn
	if kind=="turn_started":
		var context: Dictionary=record.turn_context
		turn.set_text(1,context.title)
		turn.set_tooltip_text(1,context.cause)
		var origin:=_row(parent,"本轮来由",context.title)
		if parent.get_first_child()!=origin: origin.move_before(parent.get_first_child())
		_field(origin,"为什么开始",context.cause)
		_field(origin,"这次要决定",context.purpose)
		_json(origin,"本轮触发原文",record.event)
		if not record.source_event.is_empty():
			var source:=_row(origin,"关联事件","第 %s 轮 · 双击跳转；展开可直接查看原文"%record.source_round if record.source_round>0 else "展开查看关联事件原文")
			source.set_metadata(0,context.source_event_id)
			source.set_metadata(1,record.source_event)
			_json(source,"原事件",record.source_event)
			source.collapsed=true
	if kind=="role_result":
		var report: Dictionary=record.report
		if report.has("error"):
			_field(parent,"判断失败",str(report.error))
		else:
			var decision: Dictionary=report.decision
			_field(parent,"私下理解（不朗读）",decision.private_interpretation)
			if decision.has("conversation"):
				var c: Dictionary=decision.conversation
				var labels:={"listen":"旁听，不发言","reply":"参与回应","interject":"主动插话"}
				_field(parent,"为何参与这次交谈",str(labels.get(c.participation,c.participation))+"："+c.reason)
			_field(parent,"公开答复",decision.public_reply if not decision.public_reply.strip_edges().is_empty() else "保持沉默")
			_field(parent,"行动意图",{"none":"无","eat":"吃饭","fetch_food":"搬一份食物","rest":"休息","gather_food":"拿篮子外出采集","give_food":"交付一份食物","store_food":"存放食物","explore":"附近探索"}.get(decision.intent,decision.intent))
			if decision.get("learning_request")!=null: _field(parent,"提出学习","编写"+{"drink_nearby":"近处饮水","approach_then_drink":"接近水源并饮水"}.get(decision.learning_request.goal_id,decision.learning_request.goal_id)+"技能，完成后继续原请求")
			if decision.get("skill_call")!=null: _field(parent,"技能调用",JSON.stringify(decision.skill_call))
			_field(parent,"播放状态","已生成，尚未播放" if not decision.public_reply.strip_edges().is_empty() else "保持沉默")
		for call in report.calls:
			var usage: Dictionary=call.get("usage",{})
			_field(parent,"模型调用","%s · %.2f 秒 · 输入 %s / 输出 %s token"%[call.model,call.elapsed_ms/1000.0,str(usage.get("input_tokens","未报告")),str(usage.get("output_tokens","未报告"))])
	match kind:
		"tts_request": _field(parent,"播放状态","正在生成语音，尚未开始播放")
		"speaking_started": _field(parent,"播放状态","正在说话")
		"tts_generated": _field(parent,"语音生成","已生成 %.2f 秒音频；生成耗时 %.2f 秒（不表示播放结束）"%[record.audio_seconds,record.elapsed_ms/1000.0])
		"spoken": _field(parent,"播放状态","已说完")
		"public_heard":
			var names: PackedStringArray=[]
			for listener in record.listeners: names.append(person_name(listener))
			_field(parent,"听到了这段话的人","、".join(names) if not names.is_empty() else "无")
		"information_shared": _field(parent,"收到情报（待核实）",record.message+"："+"、".join(record.knowledge_ids))
		"information_rejected": _field(parent,"无效情报引用",record.message)
		"action_result": _field(parent,"实际行动结果",record.result.message)
		"capability_gap": _field(parent,"能力缺口候选（待审查）",record.gap.goal+"；缺少："+record.gap.missing_capability+"；"+record.gap.status)
		"completed": _field(turn,"轮次状态","本轮对话已结束；已提交的行动可能仍在执行")
		"error":
			_field(parent,"错误",str(record.get("message","未知错误")))
			if record.get("stage","") in ["tts","tts_playback"]: _field(parent,"播放状态","播放失败，不能确认完整说出")
		"cancelled","local_capture": _field(turn,"轮次状态",str(record.get("message","已结束")))
	var detail: TreeItem
	for child in parent.get_children():
		if child.get_text(0)=="技术详情与原始记录": detail=child
	if detail==null:
		detail=_row(parent,"技术详情与原始记录","随时展开；保留全部字段")
		_row(detail,"阅读说明",HELP)
		detail.collapsed=true
	var entry:=_row(detail,str(record.get("time","")),str(EXPLANATIONS.get(kind,record.get("message",kind))))
	entry.set_metadata(1,record.duplicate(true))
	for key in record: _json(entry,key,record[key])
	entry.collapsed=true
