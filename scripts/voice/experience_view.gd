extends RefCounted
## 只组织本次发送副本；当天经历仍在人物存储中，按需展开不等于回忆或遗忘。
var records: Dictionary={}
var serial:=0

func make_ref(value: Variant, topic: String) -> Dictionary:
	serial+=1
	var key:="detail_%d"%serial
	records[key]=value
	return {"experience_ref":key,"topic":topic,"count":value.size() if value is Array or value is Dictionary else str(value).length()}

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
		task.progress=task.progress.slice(maxi(0,task.progress.size()-4)).map(func(item):return pack(item,"task/result"))
	for key in task:
		if key not in ["request","progress","progress_index"]:task[key]=pack(task[key],"task/"+str(key))
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
	if not (offset is int or offset is float) or offset<0 or offset!=int(offset) or not (limit is int or limit is float) or limit<1 or limit>8 or limit!=int(limit):
		return {"ok":false,"error":"offset须为非负整数，limit须为1至8"}
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
