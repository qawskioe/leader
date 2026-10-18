extends RefCounted
## 只翻译程序触发记录；不读取模型的 routing_reason 来解释为什么开始本轮。
static func describe(event: Dictionary, people: Dictionary) -> Dictionary:
	var trigger: Dictionary=event.get("trigger",{})
	var kind: String=event.get("kind","")
	var title:="处理事件"
	var cause: String=event.get("text","")
	var purpose:="决定如何回应这件事。"
	var speaker: String=event.get("speaker","")
	var name: String=people.get(speaker,{}).get("name",event.get("speaker_name",speaker))
	match kind:
		"item_offer":
			title="%s递来物品"%("玩家" if speaker=="player" else name)
			purpose="决定接受还是拒绝；物品仍在递出者手中，尚未交付。"
		"need_changed":
			purpose="决定怎样满足生存需求：自己行动、求助或等待。"
			match trigger.get("reason",""):
				"need_initial":
					title="首次检查生存需求"
					cause="需求检查发现生存需求达到触发条件；不是有人对她说话。"
				"need_retry":
					title="等待后再次检查生存需求"
					cause="距上次判断 %.0f 秒，仍然生存需求；定时复查，所检查的状态未变。"%trigger.elapsed_seconds
				"need_changed":
					title="情况变化后检查生存需求"
					var changes: PackedStringArray=[]
					var labels:={"thirst_band":"口渴档位","personal_water":"随身水量","hunger_band":"饥饿档位","storage_food_seen":"看到的库存","carried_food":"手持食物","holding_basket":"持篮状态","knowledge_revision":"观察发现发生变化","personal_basket_food":"自己篮中食物"}
					for key in trigger.changes:
						if key=="resources":
							changes.append("与当前需求相关的食物或水源变化："+", ".join(trigger.changes[key].objects))
							continue
						if key=="knowledge_revision":
							changes.append("观察记录更新：发现新物品或确认了状态变化")
							continue
						var change: Dictionary=trigger.changes[key]
						changes.append("%s：%s → %s"%[labels.get(key,key),_value(change.before),_value(change.after)])
					cause="；".join(changes)
				_: title="检查生存需求"; cause="旧记录没有细分首次检查、情况变化或定时复查。"
			var need: String="口渴" if trigger.get("thirst",0)>trigger.get("hunger",0) else "饥饿"
			title=title.replace("生存需求",need)
			cause=cause.replace("生存需求",need)
			purpose=purpose.replace("生存需求",need)
		"skill_ready":
			title="学会技能后继续原请求"
			cause="原请求："+str(event.get("original_event",{}).get("text",event.get("text","")))
			purpose="检查当前情况，决定如何使用新技能完成原请求。"
		"skill_progress":
			title="技能执行后检查原请求"
			cause=str(event.get("result",{}).get("message",""))
			purpose="已完成则停止；尚未完成才继续原请求："+str(event.get("original_event",{}).get("text",""))
		"task_observation_changed":
			title="等待时观察到玩家变化"
			purpose="结合当前观察与原请求，决定继续行动还是等待；观察变化本身不指定动作。"
		"skill_revised":
			title="动作修订完成"
			cause="此前教导已落实到新版本，不是收到新的教导。"
			purpose="原话要求演示才试用，否则结束；不再申请同一修订。"
		"social_request":
			title="回应%s的请求"%name
			cause="%s说：“%s”"%[name,event.text]
			purpose="决定是否接受请求，以及准备怎么做。"
		"social_reply":
			title="听到%s的求助答复"%name
			cause=event.text
			purpose="结合当前观察继续原请求；听到答复不代表实际交付完成，不必自动回话。"
		"information_request":
			title="回答%s的情报询问"%name
			cause="%s问：“%s”"%[name,event.text]
			purpose="根据自己的记忆回答；不知道就直说，不代替对方执行任务。"
		"information_received":
			title="收到%s的情报"%name
			purpose="决定是否按线索去确认或行动；听闻不等于亲眼确认。"
		"speech_intent":
			title="回应玩家的话"
			cause="玩家说：“%s”"%event.text
			purpose="理解听到的话，决定是否回应或行动。"
		"help_continue","work_problem":
			var assistance: Dictionary=event.get("assistance",{})
			var beneficiary: String=people.get(assistance.get("requester_id",""),{}).get("name","对方")
			title="继续处理%s的求助"%beneficiary
			var result: Dictionary=trigger.get("result",{})
			if not result.is_empty():
				cause=("等待后复查，原请求仍未完成。上次结果：" if trigger.get("reason")=="help_retry" else "上一步实际结果：")+str(result.message)
			purpose="接下来如何完成请求：“%s”"%assistance.get("request_text","帮助对方")
		"information_unanswered":
			title="询问后尚未听到回答"
			cause=event.text
			purpose="根据原请求和当前观察，决定接下来怎么办。"
		"assistance_completed":
			title="得到帮助后决定是否回应"
			cause=str(event.get("result",{}).get("message","已实际吃到帮助者提供的食物"))
			purpose="结合实际受益与关系，决定是否向帮助者说话；允许沉默。"
		"received_food": title="收到食物后决定下一步"; purpose="决定吃掉、保留或处理手中的食物。"
		"received_item","received_water": title="收到物品后决定下一步"; purpose="根据实际收到的物品与原请求决定下一步；允许保持沉默。"
		"observed_test": title="回应测试情境"; purpose="仅评估这个虚构情境，不修改物资。"
	return {"title":title,"cause":cause,"purpose":purpose,"source_event_id":event.get("source_event_id","")}

static func _value(value: Variant) -> String:
	if value==null: return "未看到／未知"
	if value is bool: return "有" if value else "无"
	return str(value)
