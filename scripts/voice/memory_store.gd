extends RefCounted
## 持久记忆库。保留/遗忘由游戏时钟管理；检索只读取调用人物自己的记录。
var path:=""
var clock:=0.0
var records: Dictionary={}
var contacts: Dictionary={}
var policy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/memory_policy.json"))
var _revision:=0
var dirty:=false:
	set(value):
		dirty=value
		if value:_revision+=1
var _save_task: int=-1
var _save_revision: int=-1
var _save_result: Dictionary={}
var _kind_keys: Dictionary={}
var _retained_cache: Dictionary={}
var loaded:=false
var next_sweep:=60.0
# 当天经历与未完成任务独立持久化；长期检索不是短期记忆的入口。
var short_events: Dictionary={}
var tasks: Dictionary={}
var observations: Dictionary={}
var consolidated_day:=0
var last_consolidation: Dictionary={}
var context_cache_revision:=0


func initialize(file: String, people: Array, fresh: bool=false) -> String:
	var pending_error:=_complete_save(true)
	if not pending_error.is_empty():return pending_error
	path=file;clock=0;records={};contacts={};loaded=false
	_kind_keys={};_retained_cache={}
	short_events={};tasks={};observations={};consolidated_day=0;last_consolidation={}
	for id in people: records[id]={};contacts[id]={};short_events[id]=[];observations[id]={}
	if not fresh and path!="" and FileAccess.file_exists(path):
		var parser:=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path))!=OK:return "人物记忆文件不是有效JSON"
		var error:=load_data(parser.data,people)
		if not error.is_empty():return error
	next_sweep=clock+60;dirty=fresh
	prune()
	return ""

func export_data() -> Dictionary:
	return {"schema":1,"clock":clock,"records":records,"contacts":contacts,"short_term":{"events":short_events,"tasks":tasks,"observations":observations,"day":consolidated_day,"last_consolidation":last_consolidation}}.duplicate(true)

# 历史正文写入后保持只读。快照复制索引，工作线程不读取仍在变化的容器。
static func freeze_owned(value: Variant) -> Variant:
	if value is Dictionary:
		if value.is_read_only():return value
		for child in value.values():freeze_owned(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only():return value
		for child in value:freeze_owned(child)
		value.make_read_only()
	else:
		assert(not value is Object,"记忆正文不能引用场景对象")
	return value

func replace_records_owned(value: Dictionary) -> void:
	var known_people:=records.keys()
	records={}
	_kind_keys={};_retained_cache={}
	for person in known_people:records[person]={}
	for person in value:
		records[person]={}
		for key in value[person]:
			var item: Dictionary=value[person][key].duplicate()
			freeze_owned(item)
			records[person][key]=item
			_track_record(person,key,item.kind)

func _track_record(person: String, key: String, kind: String) -> void:
	if not _kind_keys.has(person):_kind_keys[person]={}
	var cache_key:=person+"/"+kind
	if not _kind_keys[person].has(kind):
		_kind_keys[person][kind]={}
		_retained_cache[cache_key]=_new_retained_cache()
	var existed: bool=_kind_keys[person][kind].has(key)
	_kind_keys[person][kind][key]=true
	var cached: Dictionary=_retained_cache.get(cache_key,{})
	if cached.is_empty():return
	if not _retained_cache_policy_matches(cached):
		_retained_cache.erase(cache_key)
		return
	_expire_retained_cache(person,cached)
	var item: Dictionary=records[person][key]
	# 加载时逐条建索引，后续只更新该条。被过滤的旧条目复活时重新按原索引排序。
	if existed and not cached.items.has(key) and strength(item)>=float(policy.forget_threshold):
		_retained_cache.erase(cache_key)
		return
	_cache_retained_record(cached,key,item)

func _new_retained_cache() -> Dictionary:
	return {"items":{},"deadlines":{},"expires_at":INF,"day_seconds":policy.day_seconds,"threshold":policy.forget_threshold}

func _retained_cache_policy_matches(cached: Dictionary) -> bool:
	return cached.day_seconds==policy.day_seconds and cached.threshold==policy.forget_threshold

func _expire_retained_cache(person: String, cached: Dictionary) -> void:
	if clock<cached.expires_at:return
	# 到期只检查截止时间已过的条目，不重新读取整类历史正文。
	for key in cached.deadlines.keys():
		if float(cached.deadlines[key])>clock:continue
		if not records[person].has(key) or strength(records[person][key])<float(policy.forget_threshold):
			cached.items.erase(key);cached.deadlines.erase(key)
	cached.expires_at=INF if cached.deadlines.is_empty() else cached.deadlines.values().min()

func _cache_retained_record(cached: Dictionary, key: String, item: Dictionary) -> void:
	var previous_deadline: float=cached.deadlines.get(key,INF)
	if strength(item)<float(policy.forget_threshold):
		cached.items.erase(key)
		cached.deadlines.erase(key)
	else:
		cached.items[key]=item.data
		var deadline:=INF
		if not item.permanent and float(item.get("consolidated_at",0))>=0 and float(policy.forget_threshold)>0:
			var base:=maxf(float(item.last_recalled),float(item.get("consolidated_at",0)))
			deadline=base+float(item.half_life_days)*float(policy.day_seconds)*log(1.0/float(policy.forget_threshold))/log(2.0)
		cached.deadlines[key]=deadline
		cached.expires_at=minf(cached.expires_at,deadline)
	if previous_deadline!=INF and previous_deadline==cached.expires_at:
		cached.expires_at=INF if cached.deadlines.is_empty() else cached.deadlines.values().min()

func _snapshot_for_save() -> Dictionary:
	var copied_records: Dictionary={}
	var copied_events: Dictionary={}
	for person in records:
		copied_records[person]=records[person].duplicate()
		copied_records[person].make_read_only()
	for person in short_events:
		copied_events[person]=short_events[person].duplicate()
		copied_events[person].make_read_only()
	copied_records.make_read_only();copied_events.make_read_only()
	return freeze_owned({"schema":1,"clock":clock,"records":copied_records,"contacts":contacts.duplicate(true),"short_term":{"events":copied_events,"tasks":tasks.duplicate(true),"observations":observations.duplicate(true),"day":consolidated_day,"last_consolidation":last_consolidation.duplicate(true)}})

func load_data(data: Variant, people: Array) -> String:
	var destination:=path
	initialize("",people,true)
	path=destination
	if not data is Dictionary or data.get("schema")!=1 or not data.get("records") is Dictionary or not data.get("contacts") is Dictionary or not data.get("clock") is float and not data.get("clock") is int: return "人物记忆文件格式错误"
	if not is_finite(data.clock) or data.clock<0: return "记忆时钟损坏"
	# 派生索引依据存档时间判断保留范围，不能先按零时刻建好再等待首个自动保存重建。
	clock=data.clock
	for id in data.records:
		if not records.has(id) or not data.records[id] is Dictionary: return "人物记忆归属错误"
		for key in data.records[id]:
			var item: Variant=data.records[id][key]
			if not item is Dictionary or item.get("id")!=key or not item.get("kind") in policy.half_life_days or not item.get("data") is Dictionary or not item.get("importance") is float and not item.get("importance") is int: return "记忆条目损坏"
			for number in ["created_at","updated_at","last_recalled","recall_count","half_life_days"]:
				if not (item.get(number) is int or item.get(number) is float) or not is_finite(item[number]) or item[number]<0: return "记忆时间或衰退参数损坏"
			if item.half_life_days<=0 or not item.get("permanent") is bool or not is_finite(item.importance) or item.importance<0 or item.importance>1: return "记忆保留参数损坏"
			if item.has("consolidated_at") and (not (item.consolidated_at is float or item.consolidated_at is int) or not is_finite(item.consolidated_at) or item.consolidated_at< -1): return "记忆整理时间损坏"
	replace_records_owned(data.records)
	for id in data.contacts:
		if not contacts.has(id) or not data.contacts[id] is Dictionary: return "关系记忆归属错误"
		for other in data.contacts[id]:
			var tie: Variant=data.contacts[id][other]
			if not tie is Dictionary: return "关系记录损坏"
			for number in ["last_contact","familiarity"]:
				if not (tie.get(number) is int or tie.get(number) is float) or not is_finite(tie[number]) or tie[number]<0: return "关系参数损坏"
		contacts[id]=data.contacts[id]
	loaded=true
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
			short_events[id]=short.events[id].duplicate()
			for entry in short_events[id]:freeze_owned(entry)
			observations[id]=short.observations[id]
		for id in short.tasks:
			if not records.has(id) or not short.tasks[id] is Dictionary or not short.tasks[id].get("request") is Dictionary: return "短期任务损坏"
			if short.tasks[id].has("execution_origin") and not preload("res://scripts/skills/execution_journal.gd").valid_origin(short.tasks[id].execution_origin):return "请求自身运动原点损坏"
		tasks=short.tasks;consolidated_day=int(short.day)
		last_consolidation=short.get("last_consolidation",{})
	next_sweep=clock+60;dirty=false
	return ""

func put(person: String, kind: String, source_id: String, data: Dictionary, importance: float=0.5, permanent: bool=false) -> String:
	assert(records.has(person) and kind in policy.half_life_days and not source_id.is_empty())
	var id:=kind+"/"+source_id.sha256_text()
	var previous: Dictionary=records[person].get(id,{}).duplicate()
	if not previous.is_empty():
		previous.data=freeze_owned(data.duplicate(true))
		previous.last_recalled=clock
		previous.updated_at=clock
		previous["consolidated_at"]=clock if previous.permanent else -1.0
		previous.make_read_only();records[person][id]=previous
	else:
		records[person][id]=freeze_owned({"id":id,"source_id":source_id,"kind":kind,"data":data.duplicate(true),"created_at":clock,"updated_at":clock,"last_recalled":clock,"recall_count":0,"consolidated_at":clock if permanent or importance>=policy.permanent_importance else -1.0,"importance":clampf(importance,0,1),"permanent":permanent or importance>=policy.permanent_importance,"half_life_days":float(policy.half_life_days[kind])*(0.5+importance)})
	_track_record(person,id,kind)
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
	# 近期经历转入检索后，传输基准不能继续直接提供整理前的经历。
	context_cache_revision+=1
	var archived:=0
	var carried:=0
	for person in records:
		for item in records[person].values():
			if float(item.get("consolidated_at",0))<0:
				# 大步推进游戏时间也从经历后的第一个日终开始衰退，不平白刷新几年的旧记忆。
				var updated: Dictionary=item.duplicate()
				updated.consolidated_at=minf(clock,(floorf(float(item.updated_at)/float(policy.day_seconds))+1)*float(policy.day_seconds)) if reason=="day_end" else clock
				updated.make_read_only();records[person][item.id]=updated
				_track_record(person,item.id,item.kind)
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
			if strength(records[person][id])<float(policy.forget_threshold):
				var kind: String=records[person][id].kind
				records[person].erase(id)
				_kind_keys[person][kind].erase(id)
				var cached: Dictionary=_retained_cache.get(person+"/"+kind,{})
				if not cached.is_empty():cached.items.erase(id);cached.deadlines.erase(id)
				dirty=true
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
	return retained_view(person,kind).duplicate(true)

func retained_view(person: String, kind: String) -> Array:
	assert(records.has(person))
	var cache_key:=person+"/"+kind
	var cached: Dictionary=_retained_cache.get(cache_key,{})
	if not cached.is_empty() and _retained_cache_policy_matches(cached):
		_expire_retained_cache(person,cached)
		return cached.items.values()
	cached=_new_retained_cache()
	for key in _kind_keys.get(person,{}).get(kind,{}):
		_cache_retained_record(cached,key,records[person][key])
	_retained_cache[cache_key]=cached
	return cached.items.values()

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
		var item: Dictionary=candidates[index].item.duplicate()
		result.append(item.duplicate(true))
		item.last_recalled=clock;item.recall_count+=1;item.half_life_days=minf(float(policy.max_half_life_days),float(item.half_life_days)*float(policy.recall_growth))
		item.make_read_only();records[person][item.id]=item
		_track_record(person,item.id,item.kind)
	dirty=dirty or not result.is_empty()
	return {"ok":true,"records":result,"matching_count":candidates.size(),"note":"本人记忆，不保证现在仍成立；主观反应不是客观事实。"}

func mark(person: String, request: Variant) -> Dictionary:
	assert(records.has(person))
	if not request is Dictionary or request.size()!=3 or not request.get("id") is String or not request.get("reason") is String or request.reason.strip_edges().is_empty() or request.reason.length()>300: return {"ok":false,"error":"记忆标记需要id、importance和reason"}
	var importance: Variant=request.get("importance")
	if not (importance is int or importance is float) or not is_finite(importance) or importance<0 or importance>1: return {"ok":false,"error":"重要性为0至1"}
	if not records[person].has(request.id): return {"ok":false,"error":"本人没有该记忆"}
	var item: Dictionary=records[person][request.id].duplicate()
	item.importance=importance;item.permanent=importance>=float(policy.permanent_importance);item["importance_reason"]=request.reason
	if item.permanent and float(item.get("consolidated_at",0))<0: item.consolidated_at=clock
	item.half_life_days=minf(float(policy.max_half_life_days),float(policy.half_life_days[item.kind])*(0.5+importance)*pow(float(policy.recall_growth),item.recall_count))
	item.make_read_only();records[person][request.id]=item
	_track_record(person,request.id,item.kind)
	dirty=true
	return {"ok":true,"permanent":item.permanent}

func save() -> String:
	var pending_error:=_complete_save(true)
	if not pending_error.is_empty():return pending_error
	if path=="" or not dirty: return ""
	var error:=write_snapshot(_snapshot_for_save(),ProjectSettings.globalize_path(path))
	if error.is_empty():dirty=false
	return error

func request_save() -> String:
	var pending_error:=poll_save()
	if not pending_error.is_empty():return pending_error
	if path=="" or not dirty or _save_task!=-1:return ""
	var snapshot:=_snapshot_for_save()
	var destination:=ProjectSettings.globalize_path(path)
	_save_revision=_revision
	_save_result={"error":""}
	var holder:=_save_result
	var script: Script=get_script()
	_save_task=WorkerThreadPool.add_task(func():holder.error=script.write_snapshot(snapshot,destination))
	return ""

func poll_save() -> String:
	return _complete_save(false)

func flush_pending(tree: SceneTree) -> String:
	while _save_task!=-1 and not WorkerThreadPool.is_task_completed(_save_task):await tree.process_frame
	return poll_save()

func _complete_save(wait: bool) -> String:
	if _save_task==-1:return ""
	if not wait and not WorkerThreadPool.is_task_completed(_save_task):return ""
	WorkerThreadPool.wait_for_task_completion(_save_task)
	var error: String=_save_result.error
	_save_task=-1;_save_result={}
	if error.is_empty() and _save_revision==_revision:dirty=false
	return error

static func write_snapshot(snapshot: Dictionary, destination: String) -> String:
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir())!=OK: return "无法创建记忆目录"
	var file:=FileAccess.open(destination+".tmp",FileAccess.WRITE)
	if file==null: return "无法保存人物记忆"
	# Godot 4.6 JSON遍历使用可写Dictionary索引；只读容器仍有共享临时值。
	# 在线程内深拷贝成独占容器再编码，避免两个保存任务或主线程读取争用。
	# https://github.com/godotengine/godot/blob/4.6/core/io/json.cpp#L168
	file.store_string(JSON.stringify(snapshot.duplicate(true)));file.close()
	if DirAccess.rename_absolute(destination+".tmp",destination)!=OK: return "无法替换人物记忆文件"
	return ""

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and _save_task!=-1:
		# RefCounted进入析构后不再通过self分派方法，只收束已经创建的任务。
		WorkerThreadPool.wait_for_task_completion(_save_task)
		var error: String=_save_result.error
		if not error.is_empty():push_error(error)

func catalog(person: String) -> Dictionary:
	assert(records.has(person))
	var counts: Dictionary={}
	for kind in policy.half_life_days: counts[kind]=0
	for item in records[person].values():
		if strength(item)>=float(policy.forget_threshold) and float(item.get("consolidated_at",0))>=0: counts[item.kind]+=1
	counts["relationship"]=contacts[person].size()
	return {"state":"只列已整理的长期记忆；当天经历与未完成任务已直接提供，不需要recall","available_counts":counts,"kinds":{"heard":"自己听到的原话","reflection":"本人过去的主观反应，不等于事实","action":"实际行动结果","landmark":"已知地点与参照物","skill":"曾听说或见过的技能线索","fact":"背景经历","relationship":"与他人的熟悉度"},"usage":"问题依赖过去发生的事时，先读取相关记忆再判断是否忘记。自主选择类别、关键词与数量；不需要历史就直接行动。"}
