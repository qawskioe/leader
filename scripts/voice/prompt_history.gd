extends RefCounted
## 仅压缩发送副本中的重复系统说明，完整历史仍在人物记忆中。
static func compact(working: Dictionary) -> Dictionary:
	var result:=working.duplicate(true)
	var counts: Dictionary={}
	for turn in result.get("recent_turns",[]):
		var event: Dictionary=turn.event
		if event.get("speaker","") not in ["world","body"]: continue
		var text: String=event.get("text","")
		if text.length()>=60: counts[text]=counts.get(text,0)+1
	var references: Dictionary={}
	var texts: Dictionary={}
	for text in counts:
		if counts[text]<3: continue
		var key:="t%d"%(texts.size()+1)
		references[text]=key;texts[key]=text
	for turn in result.get("recent_turns",[]):
		var event: Dictionary=turn.event
		if event.get("speaker","") not in ["world","body"]: continue
		var text: String=event.get("text","")
		if references.has(text):
			event.erase("text")
			event["text_ref"]=references[text]
	if not texts.is_empty():result["event_texts"]=texts
	_compact_event_ids(result)
	var silent_count:=0
	for turn in result.get("recent_turns",[]):
		if turn.get("own_reply")=={"text":"","status":"保持沉默"}:silent_count+=1
	if silent_count>=3:
		result["own_replies"]={"silent":{"text":"","status":"保持沉默"}}
		for turn in result.recent_turns:
			if turn.get("own_reply")==result.own_replies.silent:
				turn.erase("own_reply");turn["own_reply_ref"]="silent"
	_compact_initial_locations(result)
	_compact_execution_results(result)
	# 长历史的字段名重复占用大量空间。列标题只发送一次，行仍保持原顺序与全部值。
	if result.get("recent_turns",[]).size()>=100:
		var event_layouts: Dictionary={};var turn_layouts: Dictionary={};var rows: Array=[]
		for turn in result.recent_turns:
			turn.event=_row(turn.event,event_layouts,"event")
			rows.append(_row(turn,turn_layouts,"turn"))
		result.recent_turns=rows
		result["event_layouts"]=event_layouts;result["turn_layouts"]=turn_layouts
	return compact_structures(result)

const INITIAL_LOCATIONS_REF := "self.working_context.last_known_locations"
const RESULT_REF_PREFIX := "self.working_context."

static func _compact_execution_results(working: Dictionary) -> void:
	var references: Dictionary={}
	# 完整事件及本人回应仍各自保留；只引用已出现的完全相同执行载荷。
	for index in working.get("recent_turns",[]).size():
		var event: Dictionary=working.recent_turns[index].event
		_compact_result_slot(event,"result","recent_turns.%d.event.result"%index,references)
	var task: Dictionary=working.get("task",{})
	for index in task.get("progress",[]).size():
		_compact_result_slot(task.progress,index,"task.progress.%d"%index,references)
	_compact_result_slot(task,"last_result","task.last_result",references)

static func _compact_result_slot(owner: Variant, key: Variant, path: String, references: Dictionary) -> void:
	if owner is Dictionary and not owner.has(key):return
	var value: Variant=owner[key]
	if not value is Dictionary:return
	# Variant编码区分int/float、null/缺字段；仅JSON相等不足以证明事实完全相同。
	var signature:=var_to_bytes(value).hex_encode()
	if references.has(signature):
		var reference:={"context_ref":RESULT_REF_PREFIX+references[signature]}
		if JSON.stringify(reference).length()<JSON.stringify(value).length():
			owner[key]=reference
			return
	else:references[signature]=path
	# 先登记外层；不同事件包装仍可复用相同的宿主执行载荷，不产生失效内部路径。
	for field in ["feedback","movement_history","execution_summary"]:
		_compact_result_slot(value,field,path+"."+field,references)

static func _expand_execution_results(working: Dictionary) -> void:
	for turn in working.get("recent_turns",[]):
		_expand_result_slot(turn.event,"result",working)
	var task: Dictionary=working.get("task",{})
	for index in task.get("progress",[]).size():
		_expand_result_slot(task.progress,index,working)
	_expand_result_slot(task,"last_result",working)

static func _expand_result_slot(owner: Variant, key: Variant, working: Dictionary) -> void:
	if owner is Dictionary and not owner.has(key):return
	var value: Variant=owner[key]
	if not value is Dictionary:return
	var reference: Variant=value.get("context_ref")
	if value.size()==1 and reference is String and reference.begins_with(RESULT_REF_PREFIX):
		var restored: Variant=working
		for field in value.context_ref.trim_prefix(RESULT_REF_PREFIX).split("."):
			if restored is Array:
				assert(field.is_valid_int() and int(field)>=0 and int(field)<restored.size(),"执行结果引用的数组下标必须有效")
				restored=restored[int(field)]
			else:
				assert(restored is Dictionary and restored.has(field),"执行结果引用必须指向本次输入中的已有记录")
				restored=restored[field]
		assert(restored is Dictionary,"执行载荷必须引用完整记录")
		assert(not (restored.size()==1 and restored.get("context_ref") is String and restored.context_ref.begins_with(RESULT_REF_PREFIX)),"执行载荷必须引用先前的完整结果，不能形成引用链")
		owner[key]=restored.duplicate(true)
		value=owner[key]
	for field in ["feedback","movement_history","execution_summary"]:
		_expand_result_slot(value,field,working)

static func _compact_initial_locations(working: Dictionary) -> void:
	var task: Dictionary=working.get("task",{})
	if not task.get("initial_locations") is Dictionary or not working.get("last_known_locations") is Dictionary:return
	var initial: Dictionary=task.initial_locations
	var latest: Dictionary=working.last_known_locations
	# 目录增删时不引用，避免把后来才认识的地点带入原任务。
	if initial.is_empty() or initial.size()!=latest.size():return
	var overrides: Dictionary={}
	var field_overrides: Dictionary={}
	for key in initial:
		if not latest.has(key):return
		if typeof(initial[key])==typeof(latest[key]) and initial[key]==latest[key]:continue
		var previous: Variant=initial[key]
		var current: Variant=latest[key]
		# 只覆盖同一字段集合；增删字段或改变记录类型仍用完整旧条目。
		if previous is Dictionary and current is Dictionary and previous.size()==current.size() and previous.keys().all(func(field):return current.has(field) and typeof(previous[field])==typeof(current[field])):
			var changed: Dictionary={}
			for field in previous:
				if previous[field]!=current[field]:changed[field]=previous[field]
			if JSON.stringify(changed).length()<JSON.stringify(previous).length():
				field_overrides[key]=changed
				continue
		overrides[key]=previous
	var encoded:={"context_ref":INITIAL_LOCATIONS_REF,"overrides":overrides}
	if not field_overrides.is_empty():encoded["field_overrides"]=field_overrides
	if JSON.stringify(encoded).length()<JSON.stringify(initial).length():task.initial_locations=encoded

static func _expand_initial_locations(working: Dictionary) -> void:
	var task: Dictionary=working.get("task",{})
	var initial: Dictionary=task.get("initial_locations",{})
	if initial.get("context_ref")!=INITIAL_LOCATIONS_REF:return
	assert(initial.get("overrides") is Dictionary and working.get("last_known_locations") is Dictionary)
	var restored: Dictionary=working.last_known_locations.duplicate(true)
	for key in initial.overrides:
		assert(restored.has(key),"起始地点覆盖条目必须在引用目录中")
		restored[key]=initial.overrides[key]
	for key in initial.get("field_overrides",{}):
		assert(not initial.overrides.has(key) and restored.get(key) is Dictionary,"字段覆盖必须引用独立的地点记录")
		for field in initial.field_overrides[key]:
			assert(restored[key].has(field),"起始地点字段必须在引用条目中")
			restored[key][field]=initial.field_overrides[key][field]
	task.initial_locations=restored

static func _row(record: Dictionary, layouts: Dictionary, prefix: String) -> Array:
	var fields: Array=record.keys()
	var layout:=""
	for key in layouts:
		if layouts[key]==fields:layout=key;break
	if layout.is_empty():layout=prefix+str(layouts.size());layouts[layout]=fields
	var row: Array=[layout]
	for field in fields:row.append(record[field])
	return row

static func expand_layouts(working: Dictionary) -> Dictionary:
	var expanded:=expand_structures(working)
	if not expanded.has("turn_layouts"):return expanded
	var turns: Array=[]
	for row in expanded.recent_turns:
		var turn:=_unrow(row,expanded.turn_layouts)
		turn.event=_unrow(turn.event,expanded.event_layouts)
		turns.append(turn)
	expanded.recent_turns=turns
	expanded.erase("turn_layouts");expanded.erase("event_layouts")
	return expanded

static func expand(working: Dictionary) -> Dictionary:
	# 传输布局不能直接交给宿主执行；先恢复字段，再恢复因果ID和重复说明。
	var expanded:=expand_layouts(working)
	_expand_execution_results(expanded)
	_expand_initial_locations(expanded)
	_restore_ids(expanded,expanded.get("event_id_aliases",{}))
	for turn in expanded.get("recent_turns",[]):
		var event: Dictionary=turn.event
		if event.has("text_ref"):
			event["text"]=expanded.event_texts[event.text_ref];event.erase("text_ref")
		if turn.has("own_reply_ref"):
			turn["own_reply"]=expanded.own_replies[turn.own_reply_ref].duplicate(true);turn.erase("own_reply_ref")
	for key in ["event_id_aliases","event_texts","own_replies"]:expanded.erase(key)
	return expanded

static func _restore_ids(value: Variant, aliases: Dictionary) -> void:
	if value is Dictionary:
		for key in value:
			if key in EVENT_ID_FIELDS and value[key] is String and aliases.has(value[key]):value[key]=aliases[value[key]]
			else:_restore_ids(value[key],aliases)
	elif value is Array:
		for item in value:_restore_ids(item,aliases)

static func _unrow(row: Array, layouts: Dictionary) -> Dictionary:
	var fields: Array=layouts[row[0]]
	assert(row.size()==fields.size()+1)
	var record: Dictionary={}
	for index in fields.size():record[fields[index]]=row[index+1]
	return record

const EVENT_ID_FIELDS=["id","event_id","source_event_id","original_event_id","action_event_id"]
static func _event_id(value: Variant) -> bool:
	return value is String and value.length()>=40 and (value.begins_with("event_") or value.begins_with("need_") or value.begins_with("offer_") or value.begins_with("handover_"))

static func _visit_ids(value: Variant, counts: Dictionary, aliases: Dictionary={}) -> void:
	if value is Dictionary:
		for key in value:
			if key in EVENT_ID_FIELDS and _event_id(value[key]):
				if aliases.is_empty():counts[value[key]]=counts.get(value[key],0)+1
				elif aliases.has(value[key]):value[key]=aliases[value[key]]
			else:_visit_ids(value[key],counts,aliases)
	elif value is Array:
		for item in value:_visit_ids(item,counts,aliases)

static func _compact_event_ids(working: Dictionary) -> void:
	var counts: Dictionary={};_visit_ids(working,counts)
	var aliases: Dictionary={};var originals: Dictionary={}
	for identifier in counts:
		if counts[identifier]<2:continue
		var key:="event_ref_%d"%aliases.size()
		aliases[identifier]=key;originals[key]=identifier
	if aliases.is_empty():return
	_visit_ids(working,{},aliases)
	working["event_id_aliases"]=originals

## 重复的深层执行记录按字段布局无损编码，不删短期事件或几何事实。
static func _count_structures(value: Variant, counts: Dictionary) -> void:
	if value is Dictionary:
		var signature:=JSON.stringify(value.keys())
		if signature.length()>80:counts[signature]=counts.get(signature,0)+1
		for child in value.values():_count_structures(child,counts)
	elif value is Array:
		for child in value:_count_structures(child,counts)

static func _encode_structures(value: Variant, references: Dictionary) -> Variant:
	if value is Dictionary:
		var signature:=JSON.stringify(value.keys())
		if references.has(signature):
			var values: Array=[]
			for child in value.values():values.append(_encode_structures(child,references))
			return {"record_ref":references[signature],"values":values}
		var object: Dictionary={}
		for key in value:object[key]=_encode_structures(value[key],references)
		return object
	if value is Array:
		var array: Array=[]
		for child in value:array.append(_encode_structures(child,references))
		return array
	return value

static func compact_structures(working: Dictionary) -> Dictionary:
	var counts: Dictionary={};_count_structures(working,counts)
	var layouts: Dictionary={};var references: Dictionary={}
	for signature in counts:
		if counts[signature]<3:continue
		var key:="shape_"+str(layouts.size());references[signature]=key;layouts[key]=JSON.parse_string(signature)
	var result: Dictionary={}
	for key in working:result[key]=_encode_structures(working[key],references)
	if not layouts.is_empty():result["structure_layouts"]=layouts
	return result

static func _decode_structures(value: Variant, layouts: Dictionary) -> Variant:
	if value is Dictionary:
		if value.size()==2 and value.has("record_ref") and value.has("values") and layouts.has(value.record_ref):
			var fields: Array=layouts[value.record_ref];var record: Dictionary={}
			assert(fields.size()==value.values.size())
			for index in fields.size():record[fields[index]]=_decode_structures(value.values[index],layouts)
			return record
		var record: Dictionary={}
		for key in value:record[key]=_decode_structures(value[key],layouts)
		return record
	if value is Array:
		var array: Array=[]
		for child in value:array.append(_decode_structures(child,layouts))
		return array
	return value

static func expand_structures(working: Dictionary) -> Dictionary:
	var layouts: Dictionary=working.get("structure_layouts",{})
	var result: Dictionary={}
	for key in working:
		if key!="structure_layouts":result[key]=_decode_structures(working[key],layouts)
	return result
