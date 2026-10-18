extends SceneTree
const History=preload("res://scripts/voice/prompt_history.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")

func _initialize() -> void:
	create_timer(10).timeout.connect(func():push_error("location reference test timeout");quit(1))
	var working:=_working()
	var original:=working.duplicate(true)
	var packed:=History.compact(working)
	var readable:=History.expand_layouts(packed)
	assert(readable.task.initial_locations.context_ref==History.INITIAL_LOCATIONS_REF)
	assert(readable.task.initial_locations.overrides=={})
	assert(History.expand(packed)==original,"完全重复的起始目录必须可完整恢复")
	assert(JSON.stringify(packed).length()<JSON.stringify(original).length())
	assert(working==original,"不能改写任务或记忆原件")
	# 来源、时刻、可用性改变也不是同一事实；字段覆盖必须恢复旧值。
	working.last_known_locations.place_0.position.x=9.000000001
	working.last_known_locations.place_1.source="heard"
	working.last_known_locations.place_2.time=999
	working.last_known_locations.place_3.available=false
	packed=History.compact(working);readable=History.expand_layouts(packed)
	assert(readable.task.initial_locations.overrides.is_empty() and readable.task.initial_locations.field_overrides.size()==4)
	assert(readable.task.initial_locations.field_overrides.place_0.position.x==original.task.initial_locations.place_0.position.x)
	assert(History.expand(packed)==working,"覆盖必须恢复旧位置及旧来源，不能继承当前状态")
	# 正常续办的目录只有观察时刻变化时，不应重发每个地点的身份、来源和备注。
	var changed_times:=_working()
	for key in changed_times.last_known_locations:changed_times.last_known_locations[key].time+=1000
	var changed_before:=changed_times.duplicate(true)
	var time_packet:=History.compact(changed_times)
	var time_readable:=History.expand_layouts(time_packet)
	assert(not JSON.stringify(time_readable.task.initial_locations).contains("保留来源和观察时刻"),"单字段变化不能重复发送整条未变化的位置元数据")
	assert(History.expand(time_packet)==changed_times,"字段覆盖仍恢复全部旧时刻和旧位置")
	assert(changed_times==changed_before,"目录差分不得改写本人的任务或记忆")
	for variant in ["extra","missing","replaced","tiny"]:
		var candidate:=_working()
		match variant:
			"extra":candidate.last_known_locations["new_place"]={"position":{"x":1,"y":2,"z":3}}
			"missing":candidate.last_known_locations.erase("place_0")
			"replaced":
				candidate.last_known_locations.erase("place_0");candidate.last_known_locations["other_place"]={"position":{"x":0,"y":0,"z":0}}
			"tiny":
				candidate.task.initial_locations={"p":1};candidate.last_known_locations={"p":1}
		var encoded:=History.compact(candidate)
		assert(History.expand_layouts(encoded).task.initial_locations==candidate.task.initial_locations,"键集合不同或编码更大时保持原目录："+variant)
		assert(History.expand(encoded)==candidate)
	# 字段集合或条目类型变化时整条回退，不继承后来才出现的字段。
	var changed_shape:=_working()
	changed_shape.last_known_locations.place_0["later_field"]="后来才知道"
	changed_shape.last_known_locations.place_1.erase("source")
	changed_shape.last_known_locations.place_2=["不同记录类型"]
	changed_shape.last_known_locations.place_3.position=null
	changed_shape.last_known_locations.place_4.available=null
	var shape_packet:=History.compact(changed_shape)
	var shape_readable:=History.expand_layouts(shape_packet)
	assert(shape_readable.task.initial_locations.overrides.size()==5)
	assert(not shape_readable.task.initial_locations.has("field_overrides"))
	assert(History.expand(shape_packet)==changed_shape,"整条回退保留字段有无和原始类型")
	var context:={"id":"person_001","name":"石头","available_skills":[],"working_context":working}
	var source:=context.duplicate(true)
	var packet:=Pipeline.request_for(context,{"id":"order_1","kind":"speech_intent","speaker":"player","text":"继续取水"})
	var wire: Dictionary=JSON.parse_string(packet.prompt)
	assert(History.expand(wire.self.working_context)==JSON.parse_string(JSON.stringify(working)),"发送后完整还原与同一次JSON传输一致")
	assert(context==source and packet.prefix.contains("overrides"))
	print("PROMPT_LOCATION_REFERENCE_PASSED exact_roundtrip_changed_facts_keysets_size_guard_no_mutation_wire_contract")
	quit()

func _working() -> Dictionary:
	var locations: Dictionary={}
	for index in 12:
		locations["place_"+str(index)]={"id":"place_"+str(index),"name":"看到过的地点"+str(index),"position":{"x":0.123456789+index,"y":0.0,"z":float(index*2)},"source":"seen","time":10+index,"available":true,"observation_id":"observation_1","note":"保留来源和观察时刻"}
	return {"recent_turns":[],"task":{"request":{"id":"order_1","text":"装水再回来"},"initial_locations":locations.duplicate(true)},"last_known_locations":locations.duplicate(true)}
