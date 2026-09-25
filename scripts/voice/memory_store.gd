extends RefCounted
## 持久记忆库。保留/遗忘由游戏时钟管理；检索只读取调用人物自己的记录。
var path:=""
var clock:=0.0
var records: Dictionary={}
var contacts: Dictionary={}
var policy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/memory_policy.json"))
var dirty:=false
var loaded:=false
var next_sweep:=60.0
# 当天经历与未完成任务独立持久化；长期检索不是短期记忆的入口。
var short_events: Dictionary={}
var tasks: Dictionary={}
var observations: Dictionary={}
var consolidated_day:=0
var last_consolidation: Dictionary={}


func initialize(file: String, people: Array, fresh: bool=false) -> String:
	path=file;clock=0;records={};contacts={};loaded=false
	short_events={};tasks={};observations={};consolidated_day=0;last_consolidation={}
	for id in people: records[id]={};contacts[id]={};short_events[id]=[];observations[id]={}
	if not fresh and path!="" and FileAccess.file_exists(path):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or data.get("schema")!=1 or not data.get("records") is Dictionary or not data.get("contacts") is Dictionary or not data.get("clock") is float and not data.get("clock") is int: return "人物记忆文件格式错误"
		for id in data.records:
			if not records.has(id) or not data.records[id] is Dictionary: return "人物记忆归属错误"
			for key in data.records[id]:
				var item: Variant=data.records[id][key]
				if not item is Dictionary or item.get("id")!=key or not item.get("kind") in policy.half_life_days or not item.get("data") is Dictionary or not item.get("importance") is float and not item.get("importance") is int: return "记忆条目损坏"
				for number in ["created_at","updated_at","last_recalled","recall_count","half_life_days"]:
					if not (item.get(number) is int or item.get(number) is float) or not is_finite(item[number]) or item[number]<0: return "记忆时间或衰退参数损坏"
				if item.half_life_days<=0 or not item.get("permanent") is bool or not is_finite(item.importance) or item.importance<0 or item.importance>1: return "记忆保留参数损坏"
				if item.has("consolidated_at") and (not (item.consolidated_at is float or item.consolidated_at is int) or not is_finite(item.consolidated_at) or item.consolidated_at< -1): return "记忆整理时间损坏"
			records[id]=data.records[id]
		for id in data.contacts:
			if not contacts.has(id) or not data.contacts[id] is Dictionary: return "关系记忆归属错误"
			for other in data.contacts[id]:
				var tie: Variant=data.contacts[id][other]
				if not tie is Dictionary: return "关系记录损坏"
				for number in ["last_contact","familiarity"]:
					if not (tie.get(number) is int or tie.get(number) is float) or not is_finite(tie[number]) or tie[number]<0: return "关系参数损坏"
			contacts[id]=data.contacts[id]
		if not is_finite(data.clock) or data.clock<0: return "记忆时钟损坏"
		clock=data.clock;loaded=true
		consolidated_day=int(clock/float(policy.day_seconds))
		if data.has("short_term"):
			var short: Variant=data.short_term
			if not short is Dictionary or not short.get("events") is Dictionary or not short.get("tasks") is Dictionary or not short.get("observations") is Dictionary or not short.get("day") is int and not short.get("day") is float: return "短期记忆文件损坏"
			for id in short.events:
				if not records.has(id) or not short.events[id] is Array or not short.observations.get(id) is Dictionary: return "短期记忆归属或内容错误"
				for entry in short.events[id]:
					if not entry is Dictionary or not entry.get("event") is Dictionary or not entry.event.get("id") is String: return "短期事件损坏"
				for entry in short.observations[id].values():
					if not entry is Dictionary or not entry.get("position") is Array or entry.position.size()!=3: return "短期观察损坏"
				short_events[id]=short.events[id];observations[id]=short.observations[id]
			for id in short.tasks:
				if not records.has(id) or not short.tasks[id] is Dictionary or not short.tasks[id].get("request") is Dictionary: return "短期任务损坏"
			tasks=short.tasks;consolidated_day=int(short.day)
			last_consolidation=short.get("last_consolidation",{})
	next_sweep=clock+60;dirty=fresh
	prune()
	return ""

func put(person: String, kind: String, source_id: String, data: Dictionary, importance: float=0.5, permanent: bool=false) -> String:
	assert(records.has(person) and kind in policy.half_life_days and not source_id.is_empty())
	var id:=kind+"/"+source_id.sha256_text()
	var previous: Dictionary=records[person].get(id,{})
	if not previous.is_empty():
		previous.data=data.duplicate(true)
		previous.last_recalled=clock
		previous.updated_at=clock
		previous["consolidated_at"]=clock if previous.permanent else -1.0
	else:
		records[person][id]={"id":id,"source_id":source_id,"kind":kind,"data":data.duplicate(true),"created_at":clock,"updated_at":clock,"last_recalled":clock,"recall_count":0,"consolidated_at":clock if permanent or importance>=policy.permanent_importance else -1.0,"importance":clampf(importance,0,1),"permanent":permanent or importance>=policy.permanent_importance,"half_life_days":float(policy.half_life_days[kind])*(0.5+importance)}
	dirty=true
	return id

func strength(item: Dictionary) -> float:
	if item.permanent or float(item.get("consolidated_at",0))<0: return 1.0
	return pow(0.5,maxf(0,clock-maxf(float(item.last_recalled),float(item.get("consolidated_at",0))))/(float(item.half_life_days)*float(policy.day_seconds)))

func advance(seconds: float) -> void:
	assert(is_finite(seconds) and seconds>=0)
	clock+=seconds;dirty=true
	if int(clock/float(policy.day_seconds))>consolidated_day: consolidate("day_end")
	if clock>=next_sweep: prune();next_sweep=clock+60

func note_observation(person: String, entry: Dictionary) -> void:
	assert(observations.has(person))
	observations[person][entry.id]=entry.duplicate(true)
	dirty=true

func consolidate(reason: String="rest") -> Dictionary:
	assert(reason in ["day_end","rest"])
	var archived:=0
	var carried:=0
	for person in records:
		for item in records[person].values():
			if float(item.get("consolidated_at",0))<0:
				# 大步推进游戏时间也从经历后的第一个日终开始衰退，不平白刷新几年的旧记忆。
				item.consolidated_at=minf(clock,(floorf(float(item.updated_at)/float(policy.day_seconds))+1)*float(policy.day_seconds)) if reason=="day_end" else clock
				archived+=1
		short_events[person].clear()
		var task: Dictionary=tasks.get(person,{})
		if not task.is_empty() and task.get("state") not in ["completed","cancelled"]:
			carried+=1
			var pinned: Dictionary=task.get("observations",{})
			for key in observations[person].keys():
				if not pinned.has(key): observations[person].erase(key)
		else:
			tasks.erase(person);observations[person].clear()
	consolidated_day=int(clock/float(policy.day_seconds))
	last_consolidation={"reason":reason,"time":clock,"archived_records":archived,"carried_tasks":carried}
	dirty=true
	prune()
	return last_consolidation.duplicate(true)

func prune() -> void:
	for person in records:
		for id in records[person].keys():
			if strength(records[person][id])<float(policy.forget_threshold): records[person].erase(id);dirty=true
		for id in contacts[person].keys():
			if familiarity(person,id)<float(policy.relationship_forget_threshold): contacts[person].erase(id);dirty=true

func contact(person: String, other: String) -> void:
	assert(contacts.has(person))
	if other==person or other.is_empty(): return
	contacts[person][other]={"last_contact":clock,"familiarity":minf(1.0,familiarity(person,other)+0.2)}
	dirty=true

func familiarity(person: String, other: String) -> float:
	var entry: Dictionary=contacts[person].get(other,{})
	if entry.is_empty(): return 0.0
	return float(entry.familiarity)*pow(0.5,maxf(0,clock-float(entry.last_contact))/(float(policy.relationship_half_life_days)*float(policy.day_seconds)))

func retained(person: String, kind: String) -> Array:
	assert(records.has(person))
	var result: Array=[]
	for item in records[person].values():
		if item.kind==kind and strength(item)>=float(policy.forget_threshold): result.append(item.data.duplicate(true))
	return result

func recall(person: String, request: Variant) -> Dictionary:
	assert(records.has(person))
	if not request is Dictionary or request.size()!=3 or request.get("kind") not in policy.half_life_days and request.get("kind")!="relationship" or not request.get("keywords") is Array or request.keywords.size()>6 or not request.get("limit") is int and not request.get("limit") is float: return {"ok":false,"error":"回忆需要kind、keywords数组和limit"}
	if request.limit<1 or request.limit>8 or float(request.limit)!=floorf(request.limit): return {"ok":false,"error":"单次回忆数量为1至8条"}
	for term in request.keywords:
		if not term is String or term.is_empty() or term.length()>80: return {"ok":false,"error":"回忆关键词格式错误"}
	prune()
	if request.kind=="relationship":
		var ties: Array=[]
		for other in contacts[person]:
			if request.keywords.is_empty() or request.keywords.any(func(term): return other.contains(term)):
				ties.append({"id":"relationship/"+other,"kind":"relationship","data":{"person_id":other,"familiarity":familiarity(person,other),"last_contact":contacts[person][other].last_contact},"updated_at":contacts[person][other].last_contact})
		ties.sort_custom(func(a,b): return a.updated_at>b.updated_at)
		return {"ok":true,"records":ties.slice(0,int(request.limit)),"matching_count":ties.size(),"note":"回忆关系不等于实际联系，不重置熟悉度衰退。"}
	var candidates: Array=[]
	for item in records[person].values():
		if item.kind!=request.kind or float(item.get("consolidated_at",0))<0: continue
		var text:=JSON.stringify(item.data).to_lower()
		var score:=0
		for term in request.keywords:
			if text.contains(term.to_lower()): score+=1
		if request.keywords.is_empty() or score>0: candidates.append({"item":item,"score":score})
	candidates.sort_custom(func(a,b): return a.score>b.score if a.score!=b.score else float(a.item.updated_at)>float(b.item.updated_at))
	var result: Array=[]
	for index in mini(int(request.limit),candidates.size()):
		var item: Dictionary=candidates[index].item
		result.append(item.duplicate(true))
		item.last_recalled=clock;item.recall_count+=1;item.half_life_days=minf(float(policy.max_half_life_days),float(item.half_life_days)*float(policy.recall_growth))
	dirty=dirty or not result.is_empty()
	return {"ok":true,"records":result,"matching_count":candidates.size(),"note":"本人记忆，不保证现在仍成立；主观反应不是客观事实。"}

func mark(person: String, request: Variant) -> Dictionary:
	assert(records.has(person))
	if not request is Dictionary or request.size()!=3 or not request.get("id") is String or not request.get("reason") is String or request.reason.strip_edges().is_empty() or request.reason.length()>300: return {"ok":false,"error":"记忆标记需要id、importance和reason"}
	var importance: Variant=request.get("importance")
	if not (importance is int or importance is float) or not is_finite(importance) or importance<0 or importance>1: return {"ok":false,"error":"重要性为0至1"}
	if not records[person].has(request.id): return {"ok":false,"error":"本人没有该记忆"}
	var item: Dictionary=records[person][request.id]
	item.importance=importance;item.permanent=importance>=float(policy.permanent_importance);item["importance_reason"]=request.reason
	if item.permanent and float(item.get("consolidated_at",0))<0: item.consolidated_at=clock
	item.half_life_days=minf(float(policy.max_half_life_days),float(policy.half_life_days[item.kind])*(0.5+importance)*pow(float(policy.recall_growth),item.recall_count))
	dirty=true
	return {"ok":true,"permanent":item.permanent}

func save() -> String:
	if path=="" or not dirty: return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())!=OK: return "无法创建记忆目录"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return "无法保存人物记忆"
	file.store_string(JSON.stringify({"schema":1,"clock":clock,"records":records,"contacts":contacts,"short_term":{"events":short_events,"tasks":tasks,"observations":observations,"day":consolidated_day,"last_consolidation":last_consolidation}}));file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK: return "无法替换人物记忆文件"
	dirty=false
	return ""

func catalog(person: String) -> Dictionary:
	assert(records.has(person))
	var counts: Dictionary={}
	for kind in policy.half_life_days: counts[kind]=0
	for item in records[person].values():
		if strength(item)>=float(policy.forget_threshold) and float(item.get("consolidated_at",0))>=0: counts[item.kind]+=1
	counts["relationship"]=contacts[person].size()
	return {"state":"只列已整理的长期记忆；当天经历与未完成任务已直接提供，不需要recall","available_counts":counts,"kinds":{"heard":"自己听到的原话","reflection":"本人过去的主观反应，不等于事实","action":"实际行动结果","landmark":"已知地点与参照物","skill":"曾听说或见过的技能线索","fact":"背景经历","relationship":"与他人的熟悉度"},"usage":"问题依赖过去发生的事时，先读取相关记忆再判断是否忘记。自主选择类别、关键词与数量；不需要历史就直接行动。"}
