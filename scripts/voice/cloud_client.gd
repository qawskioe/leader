extends Node
const Catalog=preload("res://scripts/survival/action_catalog.gd")
## 当前 ASR 适配 Qwen input_audio；角色模型使用非流式 Chat Completions。

func complete(url: String, key: String, payload: Dictionary) -> Dictionary:
	if not url.begins_with("https://") or key.strip_edges().is_empty():
		return {"ok":false,"error":"缺少 HTTPS 接口地址或 API Key，请在 F1 配置"}
	var request := HTTPRequest.new()
	request.timeout = 45.0
	request.body_size_limit = 2 * 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	var started := Time.get_ticks_msec()
	var err := request.request(url, PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()
		return {"ok":false,"error":"无法发起请求，错误码 %d" % err}
	var response: Array = await request.request_completed
	request.queue_free()
	var elapsed := Time.get_ticks_msec() - started
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok":false,"error":"网络请求失败或超时，结果码 %d" % response[0],"elapsed_ms":elapsed}
	if response[1] < 200 or response[1] >= 300:
		# 不把服务端原文写进日志，避免意外回显凭据或音频。
		return {"ok":false,"error":"云端返回 HTTP %d；检查区域、模型名、权限和额度" % response[1],"elapsed_ms":elapsed}
	var result := parse_response(response[3].get_string_from_utf8())
	result["elapsed_ms"] = elapsed
	return result

static func parse_response(body: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(body) != OK:
		return {"ok":false,"error":"云端响应不是有效 JSON"}
	var data: Variant = parser.data
	if not data is Dictionary or not data.get("choices") is Array or data.choices.is_empty():
		return {"ok":false,"error":"云端返回缺少 choices"}
	var choice: Variant = data.choices[0]
	if not choice is Dictionary or not choice.get("message") is Dictionary or not choice.message.get("content") is String:
		return {"ok":false,"error":"云端返回缺少文字 content"}
	if choice.get("finish_reason", "stop") in ["length", "content_filter"]:
		return {"ok":false,"error":"模型输出被截断或过滤"}
	if choice.message.content.strip_edges().is_empty():
		return {"ok":false,"error":"云端返回空文本"}
	return {"ok":true,"text":choice.message.content,"usage":data.get("usage", {})}

static func asr_payload(model: String, wav: PackedByteArray) -> Dictionary:
	return {"model":model,"stream":false,"messages":[{"role":"user","content":[{"type":"input_audio","input_audio":{"data":"data:audio/wav;base64," + Marshalls.raw_to_base64(wav)}}]}]}

static func validate_decision(text: String, require_social_fields: bool = false, require_conversation: bool = false) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok":false,"error":"决策不是有效 JSON"}
	var data: Variant = parser.data
	if not data is Dictionary:
		return {"ok":false,"error":"决策必须为 JSON 对象，不接受解释段落或 Markdown"}
	var allowed := ["private_interpretation", "public_reply", "routing_reason", "speech_style", "intent", "speech_act", "addressed_person", "capability_gap", "shared_knowledge", "request_kind", "task_status", "task_handling", "skill_call", "learning_request", "revision_request", "skill_dialogue", "conversation", "offer_response"]
	for field in data:
		if field not in allowed and field!="shared_skill_knowledge":
			return {"ok":false,"error":"决策包含未知字段：" + str(field)}
	for field in ["private_interpretation", "public_reply", "routing_reason"]:
		if not data.get(field) is String:
			return {"ok":false,"error":"决策缺少文字字段：" + field}
		if data[field].length() > 1000:
			return {"ok":false,"error":"决策文字超过 1000 字：" + field}
	if not data.get("speech_style") is String or (data.speech_style.strip_edges().is_empty() and not data.public_reply.strip_edges().is_empty()) or data.speech_style.length()>300:
		return {"ok":false,"error":"缺少有效的公开语气 speech_style"}
	if data.get("intent") not in Catalog.IDS:
		return {"ok":false,"error":"缺少有效的行动意图 intent"}
	if data.has("task_status") and data.task_status not in ["active","completed","cancelled","none"]: return {"ok":false,"error":"task_status必须为active/completed/cancelled/none"}
	if data.get("task_status") in ["completed","cancelled"] and (data.get("skill_call")!=null or data.get("intent","none")!="none"): return {"ok":false,"error":"结束任务不能同时提交新动作"}
	if not data.has("skill_call"): data.skill_call=null
	if data.skill_call!=null:
		if not data.skill_call is Dictionary or data.skill_call.size()!=2 or not data.skill_call.get("ref") is String or data.skill_call.ref.is_empty() or data.skill_call.ref.length()>160 or not data.skill_call.get("arguments") is Dictionary or data.skill_call.arguments.size()>16:
			return {"ok":false,"error":"技能调用必须包含 ref 和 arguments"}
		if data.intent!="none": return {"ok":false,"error":"同轮不能同时调用技能与取消动作"}
		for key in data.skill_call.arguments:
			var value: Variant=data.skill_call.arguments[key]
			if not key is String or not (preload("res://scripts/skills/spatial_target.gd").valid(value) or (value is String and value.length()<=400) or value is bool or ((value is int or value is float) and is_finite(value) and absf(value)<=10000)):
				return {"ok":false,"error":"技能参数必须为声明的数据类型，不能传递代码、函数或任意嵌套对象"}
	if not data.has("learning_request"): data.learning_request=null
	if data.learning_request!=null:
		if not data.learning_request is Dictionary or data.learning_request.size()!=2 or not data.learning_request.get("goal_id") is String or not data.learning_request.goal_id.is_valid_identifier() or data.learning_request.goal_id.length()>80 or not data.learning_request.get("goal") is String or data.learning_request.goal.strip_edges().is_empty() or data.learning_request.goal.length()>1000:
			return {"ok":false,"error":"学习请求需要goal_id（技能标识）和goal（可观察的具体目标）"}
		if data.intent!="none" or data.skill_call!=null: return {"ok":false,"error":"学习不能与其他动作在同轮同时发起"}
	if data.public_reply.length() > 200:
		return {"ok":false,"error":"公开台词超过 200 字"}
	if not data.has("skill_dialogue"): data.skill_dialogue=null
	if data.skill_dialogue!=null:
		var action: Variant=data.skill_dialogue
		if not action is Dictionary or action.size()!=4 or action.get("kind") not in ["ask","teach","decline"] or not action.get("person_id") is String or action.person_id.is_empty() or action.person_id.length()>100 or not action.get("goal_id") is String or not action.goal_id.is_valid_identifier() or action.goal_id.length()>80 or not action.get("reason") is String or action.reason.strip_edges().is_empty() or action.reason.length()>400:
			return {"ok":false,"error":"技能交谈需要 kind/person_id/goal_id/reason"}
		if data.intent!="none" or data.skill_call!=null or data.learning_request!=null or data.get("revision_request")!=null or data.get("offer_response")!=null: return {"ok":false,"error":"求教、授课与其他动作不能同时提交"}
		if data.public_reply.strip_edges().is_empty() or data.get("addressed_person")!=action.person_id: return {"ok":false,"error":"技能交谈必须有对实际对象说出的台词"}
	if data.learning_request!=null and data.public_reply.strip_edges().is_empty(): return {"ok":false,"error":"自行学习前需要简短说明打算与理由"}
	if data.get("shared_skill_knowledge")==null: data.shared_skill_knowledge=[]
	if not data.shared_skill_knowledge is Array or data.shared_skill_knowledge.size()>4: return {"ok":false,"error":"技能线索分享必须为最多4个事件ID"}
	for reference in data.shared_skill_knowledge:
		if not reference is String or reference.is_empty() or reference.length()>200: return {"ok":false,"error":"技能线索引用无效"}
	if not data.shared_skill_knowledge.is_empty() and data.public_reply.strip_edges().is_empty(): return {"ok":false,"error":"未公开说出不能分享技能线索"}
	if not data.has("revision_request"): data.revision_request=null
	if data.revision_request!=null:
		var revision: Variant=data.revision_request
		if not revision is Dictionary or revision.size()!=2 or not revision.get("ref") is String or revision.ref.is_empty() or revision.ref.length()>160 or not revision.get("feedback") is String or revision.feedback.strip_edges().is_empty() or revision.feedback.length()>1000:
			return {"ok":false,"error":"技能修订必须包含原技能 ref 和具体 feedback"}
		if data.intent!="none" or data.skill_call!=null or data.learning_request!=null or data.get("offer_response")!=null: return {"ok":false,"error":"技能修订不能同时发起其他动作或学习"}
	# 模型常将不适用的可选字段写为 null；与未提供等价，不能误拒绝普通事件。
	if data.has("offer_response") and data.offer_response==null:
		data.erase("offer_response")
	if data.has("offer_response") and data.offer_response not in ["accept","decline"]:
		return {"ok":false,"error":"递物决定必须为 accept 或 decline"}
	if data.has("offer_response") and (data.intent!="none" or data.skill_call!=null or data.learning_request!=null):
		return {"ok":false,"error":"递物决定先等待实际交付，不能同时执行其他动作"}
	if require_conversation and not data.has("conversation"):
		return {"ok":false,"error":"缺少交谈位置判断 conversation"}
	if data.has("conversation"):
		var c: Variant=data.conversation
		if not c is Dictionary or c.size()!=3 or not c.get("addressees") is Array or c.addressees.size()>16 or c.get("participation") not in ["listen","reply","interject"] or not c.get("reason") is String:
			return {"ok":false,"error":"交谈位置判断格式无效"}
		if c.reason.strip_edges().is_empty() or c.reason.length()>400:
			return {"ok":false,"error":"交谈位置判断需要简短依据"}
		for target in c.addressees:
			if not target is String or target.is_empty() or target.length()>100: return {"ok":false,"error":"交谈对象必须为 ID"}
		# reply 表示承接交谈或命令，可以沉默行动；不能把发声当作动作的前提。
		if c.participation=="listen" and not data.public_reply.strip_edges().is_empty():
			return {"ok":false,"error":"旁听决定不能同时提交公开台词"}
		if c.participation=="interject" and data.public_reply.strip_edges().is_empty():
			return {"ok":false,"error":"插话必须包含公开台词"}
	if require_social_fields and (not data.has("speech_act") or not data.has("addressed_person")):
		return {"ok":false,"error":"决策缺少 speech_act 或 addressed_person，不能判断是否为请求"}
	if not data.has("speech_act"): data["speech_act"]="statement"
	if not data.has("addressed_person") or (data.addressed_person==null and data.speech_act!="request"): data["addressed_person"]=""
	if data.speech_act not in ["statement","request","reply"] or not data.addressed_person is String:
		return {"ok":false,"error":"speech_act只能statement/request/reply；addressed_person必须是人物ID字符串，无说话对象填空字符串"}
	if data.speech_act=="request" and (data.addressed_person.is_empty() or data.public_reply.strip_edges().is_empty()):
		return {"ok":false,"error":"求助必须有明确对象和公开台词"}
	if require_social_fields and not data.has("capability_gap"):return {"ok":false,"error":"缺少capability_gap"}
	if not data.has("capability_gap"):data.capability_gap=null
	if data.capability_gap!=null:
		if not data.capability_gap is Dictionary or data.capability_gap.size()!=3:
			return {"ok":false,"error":"能力缺口必须为 null 或三字段对象"}
		for key in ["goal","missing_capability","reason"]:
			if not data.capability_gap.get(key) is String or data.capability_gap[key].strip_edges().is_empty() or data.capability_gap[key].length()>300:
				return {"ok":false,"error":"能力缺口字段无效："+key}
	# 两个可选字段；旧决策明确表示不分享，旧请求仍按行动请求处理。
	if data.get("shared_knowledge")==null: data.shared_knowledge=[]
	if not data.has("request_kind"): data.request_kind="help"
	# 非请求没有请求类别；模型显式 null 与省略等价。实际请求仍严格校验。
	if data.request_kind in [null,""] and data.speech_act!="request": data.request_kind="help"
	if data.request_kind not in ["help","information"] or not data.shared_knowledge is Array or data.shared_knowledge.size()>4:
		return {"ok":false,"error":"情报分享或请求类别格式无效"}
	for key in data.shared_knowledge:
		if not key is String or key.is_empty() or key.length()>150:
			return {"ok":false,"error":"分享必须引用本人 known_objects 的条目 ID"}
	if not data.shared_knowledge.is_empty() and data.public_reply.strip_edges().is_empty():
		return {"ok":false,"error":"没有公开台词不能分享情报"}
	return {"ok":true,"decision":data}

## 任务处置由模型选择；只检查结构自洽，不从台词猜测意图。
static func validate_task_handling(data: Dictionary) -> Dictionary:
	var handling: Variant=data.get("task_handling")
	if not handling is Dictionary or handling.size()!=3 or handling.get("scope") not in ["current_request","existing_request","independent"] or handling.get("state") not in ["execute","wait","ask","blocked","completed","refused","cancelled","none"] or not handling.get("reason") is String or handling.reason.strip_edges().is_empty() or handling.reason.length()>400:
		return {"ok":false,"error":"task_handling需要state、scope和非空reason；scope为current_request/existing_request/independent；state为execute/wait/ask/blocked/completed/refused/cancelled/none"}
	var action: bool=data.intent!="none" or data.get("skill_call")!=null or data.get("learning_request")!=null or data.get("revision_request")!=null or data.get("offer_response")=="accept" or (data.get("skill_dialogue") is Dictionary and data.skill_dialogue.kind=="teach")
	var asking: bool=data.speech_act=="request" and not data.addressed_person.is_empty() and not data.public_reply.strip_edges().is_empty()
	if data.get("offer_response")=="accept" and handling.state!="execute":
		return {"ok":false,"error":"offer_response=accept本身就是提交接物操作，必须用task_handling.state=execute、task_status=active；intent仍为none。程序会尝试交付，不需要玩家再次确认，不能填wait。交付是否成功以随后结果为准。"}
	if (handling.state=="execute")!=action:
		return {"ok":false,"error":"execute必须提交实际执行入口；其他处置状态不能同时执行动作。台词不会启动动作"}
	if (handling.state=="ask")!=asking:
		return {"ok":false,"error":"ask必须向明确对象发出公开请求；公开请求需选择ask状态"}
	if handling.state in ["completed","cancelled"] and data.get("task_status")!=handling.state:
		return {"ok":false,"error":"任务结束状态与task_status不一致"}
	if data.get("task_status") in ["completed","cancelled"] and handling.state!=data.task_status:
		return {"ok":false,"error":"task_status结束时task_handling也必须一致"}
	if handling.state=="none" and data.get("task_status")=="active":
		return {"ok":false,"error":"任务仍active，必须说明执行、等待、询问或受阻等实际处置，不能填none"}
	return {"ok":true}

static func knowledge_offer(decision: Dictionary, context: Dictionary, observations: Dictionary) -> Dictionary:
	var offer:={"entries":{},"rejected":[]}
	var known: Dictionary=context.get("survival_observation",{}).get("known_objects",{})
	var remembered: Dictionary=context.get("working_context",{}).get("last_known_locations",{})
	for key in decision.get("shared_knowledge",[]):
		if (known.has(key) or remembered.has(key)) and observations.has(key): offer.entries[key]=observations[key].duplicate(true)
		else: offer.rejected.append(key)
	return offer
