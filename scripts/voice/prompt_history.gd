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
	# 长历史的字段名重复占用大量空间。列标题只发送一次，行仍保持原顺序与全部值。
	if result.get("recent_turns",[]).size()>=100:
		var event_layouts: Dictionary={};var turn_layouts: Dictionary={};var rows: Array=[]
		for turn in result.recent_turns:
			turn.event=_row(turn.event,event_layouts,"event")
			rows.append(_row(turn,turn_layouts,"turn"))
		result.recent_turns=rows
		result["event_layouts"]=event_layouts;result["turn_layouts"]=turn_layouts
	return compact_structures(result)

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
