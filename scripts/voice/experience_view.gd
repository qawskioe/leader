extends RefCounted
## 只组织本次发送副本；当天经历仍在人物存储中，按需展开不等于回忆或遗忘。
var records: Dictionary={}
var _record_ids: Dictionary={}
var _page_sizes: Dictionary={}

func make_ref(value: Variant, topic: String, max_page_size: int=8) -> Dictionary:
	# 内容和分页权限相同便保持编号，避免其他资料的编码次序制造跨轮缓存差分。
	# 编号稳定不等于跨轮授权；read仍只读取本轮本人登记的records。
	var signature:=JSON.stringify([max_page_size,value])
	var key: String=_record_ids.get(signature,"")
	if key.is_empty():
		key="detail_"+signature.sha256_text().substr(0,24)
		assert(not records.has(key),"经历资料内容标识冲突")
		records[key]=value;_record_ids[signature]=key
	_page_sizes[key]=max_page_size
	var descriptor:={"experience_ref":key,"topic":topic,"count":value.size() if value is Array or value is Dictionary else str(value).length()}
	if max_page_size>8:descriptor["max_page_size"]=max_page_size
	return descriptor

func observation_view(observation: Dictionary) -> Dictionary:
	# 日常选择方法保留可见物体与地面概况；精确落点按需读取同一观察帧。
	# Luau及宿主仍使用完整采样，原坐标、顺序和精度都不改变。
	var result:=observation.duplicate(true)
	var near: Dictionary=result.get("near_field",{})
	if not near.get("ground_samples") is Array:return result
	var samples: Array=near.ground_samples
	var states: Dictionary={};var surfaces: Dictionary={}
	for sample in samples:
		var state: String=sample.state
		states[state]=int(states.get(state,0))+1
		if sample.has("surface_kind"):
			var kind: String=sample.surface_kind
			surfaces[kind]=int(surfaces.get(kind,0))+1
	var detail:=make_ref(samples,"observation/ground_samples",64)
	detail["states"]=states;detail["surface_kinds"]=surfaces
	near["ground_samples"]=detail
	return result

func pack(value: Variant, topic: String="detail") -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:
			var child: Variant=value[key]
			result[key]=make_ref(child,topic+"/"+str(key)) if JSON.stringify(child).length()>2400 else child
		return result
	if value is Array:
		return make_ref(value,topic) if value.size()>8 else value.map(func(item):return pack(item,topic))
	if value is String and value.length()>2400:return make_ref(value,topic)
	return value

func event_view(event: Dictionary) -> Dictionary:
	var result: Dictionary=pack(event,"event")
	# 原话与原请求始终直接保留；大执行证据仅保留摘要和本次可读引用。
	for key in ["text","original_event"]:
		if event.has(key):result[key]=event_view(event[key]) if key=="original_event" and event[key] is Dictionary else event[key]
	if event.get("result") is Dictionary:result.result=execution_view(event.result)
	if event.get("request_context") is Array:
		var conversation: Array=event.request_context
		# 与近期经历一致，最近澄清直接可见；更早原话保留可读目录。
		# 不能把完整会话藏成一个从最早四条开始分页的引用。
		result.request_context=conversation.slice(maxi(0,conversation.size()-12)).map(func(item):return pack(item,"request_context"))
		if conversation.size()>12:result["earlier_request_context"]=make_ref(conversation.slice(0,conversation.size()-12),"request_context/earlier")
	return result

func execution_view(record: Dictionary) -> Dictionary:
	# 动作结果的字段与短回执直接可见；长阶段/返回详情仍按需展开。
	# 整块引用会连同 success 和实际变化一起藏起来，使续办必须再读一次。
	var result: Dictionary=pack(record,"execution")
	for key in ["execution_summary","feedback"]:
		if record.get(key) is Dictionary:result[key]=pack(record[key],"execution/"+key)
	return result

func turn_view(turn: Dictionary) -> Dictionary:
	var result: Dictionary=pack(turn,"turn")
	result["event"]=event_view(turn.get("event",{}))
	return result

func build(working: Dictionary) -> Dictionary:
	var result: Dictionary=working.duplicate(true)
	var turns: Array=result.get("recent_turns",[])
	var groups: Dictionary={}
	for turn in turns.slice(0,maxi(0,turns.size()-12)):
		var event: Dictionary=turn.get("event",{})
		var category: String="conversation" if event.get("speaker","") not in ["world","body",""] else ("action" if event.has("result") else "world")
		if not groups.has(category):groups[category]=[]
		groups[category].append({"event_id":event.get("id",""),"kind":event.get("kind",""),"text":str(event.get("text","")).left(160),"detail":make_ref(turn,category)})
	result["recent_turns"]=turns.slice(maxi(0,turns.size()-12)).map(func(turn):return turn_view(turn))
	result["earlier_today"]={}
	for category in groups:result.earlier_today[category]=make_ref(groups[category],category)
	var task: Dictionary=result.get("task",{})
	# 当前原请求始终直接提供；进展保留最近四份结果摘要，完整序列可展开。
	if task.get("progress") is Array:
		task["progress_index"]=make_ref(task.progress.duplicate(true),"task/progress")
		task.progress=task.progress.slice(maxi(0,task.progress.size()-4)).map(func(item):return execution_view(item))
	for key in task:
		if key=="last_result" and task[key] is Dictionary:task[key]=execution_view(task[key])
		elif key not in ["request","progress","progress_index"]:task[key]=pack(task[key],"task/"+str(key))
	if task.get("request") is Dictionary:task.request=event_view(task.request)
	result.task=task
	result["meaning"]="最近12次经历及当前任务直接提供；earlier_today是当天更早经历的分类目录，仍然记得，不需要recall。read_experience可按experience_ref展开；没有返回的部分不得当作不存在或失败。"
	return result

func read(query: Variant) -> Dictionary:
	if not query is Dictionary or not query.get("ref") is String or not records.has(query.ref):
		return {"ok":false,"error":"ref必须来自本次本人输入中的experience_ref"}
	if query.keys().any(func(key):return key not in ["ref","offset","limit","keywords"]):return {"ok":false,"error":"仅支持ref/offset/limit/keywords"}
	var offset: Variant=query.get("offset",0)
	var limit: Variant=query.get("limit",4)
	var page_size: int=_page_sizes[query.ref]
	if not (offset is int or offset is float) or offset<0 or offset!=int(offset) or not (limit is int or limit is float) or limit<1 or limit>page_size or limit!=int(limit):
		return {"ok":false,"error":"offset须为非负整数，limit须为1至%d"%page_size}
	var keywords: Variant=query.get("keywords",[])
	if not keywords is Array or keywords.size()>4 or keywords.any(func(word):return not word is String or word.is_empty() or word.length()>80):
		return {"ok":false,"error":"keywords最多4个非空短关键词"}
	var value: Variant=records[query.ref]
	if not keywords.is_empty() and not value is Array:return {"ok":false,"error":"关键词只用于目录或记录数组"}
	if value is Array:
		if not keywords.is_empty():
			value=value.filter(func(item):
				var searchable: Variant=item
				if item is Dictionary and item.get("detail") is Dictionary and records.has(item.detail.get("experience_ref","")):searchable=records[item.detail.experience_ref]
				var text:=JSON.stringify(searchable).to_lower()
				return keywords.all(func(word):return text.contains(word.to_lower())))
		return {"ok":true,"records":value.slice(int(offset),int(offset+limit)).map(func(item):return pack(item,query.ref)),"total":value.size(),"next_offset":mini(int(offset+limit),value.size())}
	if value is Dictionary:
		var keys: Array=value.keys()
		var entries: Dictionary={}
		for key in keys.slice(int(offset),int(offset+limit)):entries[key]=pack(value[key],query.ref+"/"+str(key))
		return {"ok":true,"fields":entries,"total":keys.size(),"next_offset":mini(int(offset+limit),keys.size())}
	return {"ok":true,"text":str(value).substr(int(offset),2400),"total":str(value).length(),"next_offset":mini(int(offset)+2400,str(value).length())}
