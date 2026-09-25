extends TabContainer
## 人物是阅读单位；状态来自模拟，经历来自实际记录，技术数据放在最后。
var controller: Node
var person_id:=""
var overview: RichTextLabel
var knowledge: RichTextLabel
var history: RichTextLabel
var conversation: RichTextLabel
var raw: TextEdit
var elapsed:=0.0
var teaching_choice: OptionButton
var teaching_text: TextEdit
var teaching_status: Label
var _teaching_refs: Array=[]
const STAGES={"skill_learning":"正在学习","skill_wait":"正在执行技能","skill_moving":"技能执行：接近目标","to_store_basket":"去拿指定的食物篮子","water_pickup":"去拿水袋","water_source":"前往水源","water_return":"带水回营地","water_give":"给人送水","water_drink_bag":"走向记得的水袋","idle":"休息，当前没有动作","to_storage":"走向储食处","to_recipient":"正在给人送食物","to_basket":"去拿篮子","to_grove":"前往记得的果树区域","to_harvest":"靠近准备采摘的果实","gather_pick":"伸手采摘果实","gather_load":"把果实装进篮子","gather_return":"带着采集物返回储食处","gather_unload":"逐份存放篮中的食物","eating":"正在吃饭","scanning":"观察周围","exploring":"前往要检查的区域"}

func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	custom_minimum_size=Vector2(580,390)
	overview=_page("当前状况")
	knowledge=_page("她知道什么")
	history=_page("最近做过什么")
	conversation=_page("对话与想法")
	raw=TextEdit.new(); raw.name="完整人物数据"; raw.editable=false
	raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; add_child(raw)
	tab_changed.connect(func(index: int):
		if index==4 and is_instance_valid(controller) and controller.store.people.has(person_id): raw.text=JSON.stringify(controller.store.people[person_id],"  "))
	refresh()
	var teaching:=VBoxContainer.new();teaching.name="教导技能";add_child(teaching)
	var explanation:=Label.new();explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;explanation.text="指定已有技能，直接提交你的教导给强模型。保留原话，仍须通过独立验证；不会绕过世界规则。";teaching.add_child(explanation)
	teaching_choice=OptionButton.new();teaching.add_child(teaching_choice)
	teaching_text=TextEdit.new();teaching_text.custom_minimum_size=Vector2(320,150);teaching_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;teaching_text.placeholder_text="例如：拿起后手腕不要突然翻转，动作慢一些。";teaching.add_child(teaching_text)
	var submit:=Button.new();submit.text="提交教导";submit.pressed.connect(_submit_teaching);teaching.add_child(submit)
	teaching_status=Label.new();teaching_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;teaching.add_child(teaching_status)

func _submit_teaching() -> void:
	var text:=teaching_text.text.strip_edges()
	if text.is_empty() or text.length()>1000: teaching_status.text="请输入1至1000字的教导。";return
	if teaching_choice.selected<0: teaching_status.text="当前没有可修订技能。";return
	if controller.busy or controller.mic.recording: teaching_status.text="请等当前说话处理完，再提交教导。";return
	var ref: String=teaching_choice.get_item_metadata(teaching_choice.selected)
	var event:={"id":"teaching_%d"%Time.get_ticks_usec(),"kind":"direct_skill_teaching","speaker":"player","listeners":[person_id],"text":text}
	controller.store.hear(person_id,event)
	var result: Dictionary=controller.skills.request_revision(person_id,event,{"ref":ref,"feedback":"玩家在详情页选中该技能直接教导；请依据原话独立判断。"})
	teaching_status.text="教导已提交，正在独立修订；旧版本保留。" if result.ok else result.error
	controller.log_event({"type":"learning_requested","person_id":person_id,"event_id":event.id,"message":teaching_status.text,"request":result})

func _page(title: String) -> RichTextLabel:
	var scroll:=ScrollContainer.new(); scroll.name=title; add_child(scroll)
	var margin:=MarginContainer.new(); margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	scroll.add_child(margin)
	var text:=RichTextLabel.new(); text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.bbcode_enabled=true; text.fit_content=true; text.scroll_active=false; text.selection_enabled=true
	text.add_theme_font_size_override("normal_font_size",18)
	text.add_theme_constant_override("line_separation",5)
	margin.add_child(text)
	return text

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed+=delta
	if elapsed<0.5: return
	elapsed=0; refresh()

static func brief(person: Dictionary, actor: Dictionary, sim: Node) -> String:
	var basket: String=sim.gathering.basket_for(person.id)
	var carried: int=actor.carried+(1 if sim.gathering.hands.has(person.id) else 0)
	var load: String="手中 %d 份食物"%carried if carried>0 else "手中没有食物"
	if actor.stage in ["skill_wait_teacher","skill_teaching","skill_studying"]: return str(person.get("learning",{}).get("message","正在学习"))
	if basket!="": load+=" · 篮中 %d 份"%sim.gathering.baskets[basket].contents.items.size()
	for bag in sim.water.bags.values():
		if bag.holder!="" and sim.actors.has(bag.holder) and sim.actors[bag.holder].body==actor.body: load+=" · 水袋 %d 份水"%bag.contents.count
	return "%s · %s\n%s"%[person.needs.food+" · "+person.needs.get("water",""),STAGES.get(actor.stage,actor.stage),load]

func _name(id: String) -> String:
	return "玩家" if id=="player" else str(controller.store.people.get(id,{}).get("name",id))

func refresh() -> void:
	if not is_instance_valid(controller) or not controller.store.people.has(person_id): return
	var sim: Node=controller.survival
	if not is_instance_valid(sim) or not sim.ready_for_actions: return
	var person: Dictionary=controller.store.people[person_id]
	if is_instance_valid(teaching_choice):
		var entries: Array=person.get("available_skills",[]).filter(func(item: Dictionary): return item.get("revision_supported",false))
		var refs: Array=entries.map(func(item: Dictionary): return item.ref)
		if refs!=_teaching_refs:
			_teaching_refs=refs;teaching_choice.clear()
			for item in entries:
				teaching_choice.add_item(item.name);teaching_choice.set_item_metadata(teaching_choice.item_count-1,item.ref)
	var actor: Dictionary=sim.actors[person_id]
	var identity: Dictionary=person.identity
	var why:="暂无新的待处理事件。"
	var caption: Node=controller.captions.get(person_id)
	if actor.stage!="idle":
		var event: Dictionary=controller._round_events.get(actor.event_id,{})
		if not event.is_empty(): why=preload("res://scripts/voice/turn_context.gd").describe(event,controller.store.people).cause
		else: why="正在执行已接受的"+str(actor.get("skill_name","技能"))
	# 空闲时不把持久化的旧结果当成本次行动的原因；经历在“最近做过什么”中带时间展示。
	if caption!=null and person_id in controller._speech_order and not controller._reports_received.has(person_id): why="正在考虑："+caption.turn_heading.text
	var lines: PackedStringArray=[person.name+" · "+identity.former_work,"", "现在",brief(person,actor,sim),"饥饿：%.0f / 100；口渴：%.0f / 100"%[person.needs.hunger,person.needs.get("thirst",0)]]
	if actor.stage=="skill_learning": why=person.get("learning",{}).get("message","正在学习")
	if actor.stage=="skill_body": why="正在按技能编写的姿态与接触目标控制骨骼。"
	lines.append("\n当前事情的来由\n"+why)
	var learning: Dictionary=person.get("learning",{})
	if not learning.is_empty():
		lines.append("\n最近的学习结果\n"+str(learning.get("message","")))
		for issue in learning.get("review",{}).get("issues",[]):
			if issue is Dictionary:
				lines.append("审查指出（%.2f 秒）：%s\n建议：%s"%[float(issue.get("time_ms",0))/1000.0,str(issue.get("problem","")),str(issue.get("suggestion",""))])
			else: lines.append("审查信息："+str(issue))
		if not learning.get("review",{}).is_empty(): lines.append("这是审查模型的判断，程序根因仍需核对。")
	lines.append("\n过去的职业与专长\n"+identity.former_work+"\n"+"、".join(identity.experience))
	lines.append("共同生活经验："+"、".join(identity.shared_basics))
	lines.append("以上为背景专长；尚无技艺熟练度记录。")
	lines.append("\n已掌握的可执行技能")
	var learned: Array=person.get("available_skills",[])
	if learned.is_empty(): lines.append("尚未登记可执行技能；职业经历不等于已经掌握技能代码。")
	for skill in learned:
		lines.append(skill.name+"："+skill.description+"\n来源："+skill.learned_from)
	var expectations: Array=person.short_term.expectations
	var objects: Dictionary=sim.perception.memories.get(person_id,{})
	var known_baskets:=0
	var known_fruit:=0
	for entry in objects.values():
		if entry.kind=="basket": known_baskets+=1
		if entry.kind in ["fruit","forage_area"]: known_fruit+=1
	lines.append("\n重要情报\n"+("记得篮子的位置" if known_baskets>0 else "尚不知道篮子的位置")+"；"+("有食物位置线索" if known_fruit>0 else "尚无食物位置线索")+"。来源及是否仍可靠，见‘她知道什么’。")
	lines.append("\n最近的实际经历")
	for i in range(person.execution_results.size()-1,maxi(-1,person.execution_results.size()-4),-1):
		var result: Dictionary=person.execution_results[i]
		lines.append(("完成：" if result.success else "未完成：")+result.message)
	if person.execution_results.is_empty(): lines.append("尚无实际行动结果。")
	lines.append("\n眼下的期待\n"+("；".join(expectations) if not expectations.is_empty() else "尚未记录短期期待"))
	var tasks: Array=person.get("help_context",{}).get("own_help_tasks",[])
	if not tasks.is_empty():
		lines.append("\n接下的帮助")
		for task in tasks: lines.append("帮"+_name(task.assistance.requester_id)+"："+task.assistance.request_text+"\n最近进展："+str(task.get("last_result","尚未完成第一步")))
	overview.text=_format_page("\n".join(lines))
	var entries: Dictionary=sim.perception.memories.get(person_id,{})
	lines=PackedStringArray(["她知道什么","亲眼观察、自己操作与他人提供的情报分开；旧位置可能已经变化。",""])
	for key in entries:
		var entry: Dictionary=entries[key]
		var label: String={"water_source":"来路水源","water_bag":"水袋 "+key.get_slice("/",1),"storage":"储食处","basket":"篮子 "+key.get_slice("/",1),"fruit":"一处果实位置","forage_area":"来时见过的果树区域","route":"来路","person":_name(key.get_slice("/",1))}.get(entry.kind,entry.kind)
		if entry.kind in ["interactable","surface"]: label=str(entry.get("extra",{}).get("name",key))
		var status:="现在可见" if entry.get("visible_now",false) else "记住的线索，现状待确认"
		if entry.get("heard_from","")!="": status="听"+_name(entry.heard_from)+"说，尚未亲自确认"
		var at:=Vector3(entry.position[0],entry.position[1],entry.position[2])
		var location:="最后位置距本人约 %.0f 米"%actor.body.global_position.distance_to(at)
		var extra: Dictionary=entry.get("extra",{})
		if extra.get("holder","")!="":
			status+="；由"+_name(extra.holder)+"持有（"+str(extra.get("hand",""))+"）"
		elif extra.has("own_transfer"):
			status+="；最近亲手"+("存入" if extra.own_transfer>0 else "取出")+str(abs(extra.own_transfer))+"份"
		elif extra.get("food_count")!=null: status+="；当时有 %s 份食物"%extra.food_count
		elif entry.get("available")==false: status+="；最后确认时不可用或已不在原处"
		var age:="抵达时的经历" if entry.observed_at_seconds<0 else "原始记录在 %.0f 秒前"%maxf(0,sim.perception.clock-entry.observed_at_seconds)
		lines.append(label+"\n"+status+"\n"+location+" · "+age+"\n来源："+entry.source+"\n")
	if entries.is_empty(): lines.append("目前没有记录位置情报。")
	lines.append("\n她认为谁可能会什么（不等于他人的真实技能清单）")
	for clue in person.get("skill_knowledge",[]):
		var skill_label: String={"drink_nearby":"饮水","approach_then_drink":"接近水源并饮水","approach_known":"接近已知目标"}.get(clue.goal_id,clue.goal_id)
		lines.append(_name(clue.person_id)+" · "+skill_label+"\n来源："+str(clue.source)+" · "+str(clue.recorded_at)+"\n"+str(clue.get("meaning","过去线索，需当面确认")))
	knowledge.text=_format_page("\n".join(lines))
	lines=PackedStringArray(["最近做过什么","这里列实际结果，不把计划写成已经完成。",""])
	var results: Array=person.execution_results
	for i in range(results.size()-1,maxi(-1,results.size()-13),-1):
		var result: Dictionary=results[i]
		lines.append(str(result.get("recorded_time","较早记录"))+" · "+("完成" if result.success else "未完成")+"\n"+result.message+"\n")
	if results.is_empty(): lines.append("还没有实际行动结果。")
	history.text=_format_page("\n".join(lines))
	lines=PackedStringArray(["最近的表达与理解",""])
	var reflections: Array=person.reflections
	for i in range(reflections.size()-1,maxi(-1,reflections.size()-9),-1):
		var reflection: Dictionary=reflections[i]
		lines.append(str(reflection.get("recorded_time","较早记录"))+"\n想法："+reflection.private_interpretation+"\n公开表达："+(reflection.public_reply if not reflection.public_reply.is_empty() else "没有说话")+"\n状态："+str(reflection.get("public_reply_status",""))+"\n")
	lines.append("最近听到了什么")
	var heard: Array=person.heard_events
	for i in range(heard.size()-1,maxi(-1,heard.size()-9),-1):
		var event: Dictionary=heard[i]
		if event.get("speaker","") in ["world","body","test_fixture"]: continue
		lines.append(_name(event.speaker)+"："+event.text)
	conversation.text=_format_page("\n".join(lines))


func _format_page(text: String) -> String:
	var rows:=text.split("\n")
	var result:=PackedStringArray()
	var headings:=["已掌握的可执行技能","现在","当前事情的来由","过去的职业与专长","重要情报","最近的实际经历","眼下的期待","接下的帮助","最近听到了什么"]
	for i in rows.size():
		var escaped: String=rows[i].replace("[","[lb]")
		if i==0: result.append("[font_size=25]"+escaped+"[/font_size]")
		elif rows[i] in headings: result.append("[font_size=20][color=#e4c589]"+escaped+"[/color][/font_size]")
		else: result.append(escaped)
	return "\n".join(result)
