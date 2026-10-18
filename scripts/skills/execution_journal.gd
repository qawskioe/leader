extends RefCounted
## 技能只读当前请求的真实执行回执；不写自报进度，不检索其他人的经历。
static func valid_origin(value: Variant) -> bool:
	if not value is Array or value.size()!=4:return false
	for vector in value:
		if not vector is Array or vector.size()!=3:return false
		for number in vector:
			if not (number is int or number is float) or not is_finite(number):return false
	var frame:=preload("res://scripts/skills/verification_snapshot.gd").restored_transform(value)
	var basis:=frame.basis
	return basis.is_equal_approx(basis.orthonormalized()) and is_equal_approx(absf(basis.determinant()),1.0)

static func request_origin(task: Dictionary, current: Transform3D) -> Transform3D:
	if not task.has("execution_origin"):
		task["execution_origin"]=preload("res://scripts/skills/verification_snapshot.gd").transform(current)
	assert(valid_origin(task.execution_origin),"本人请求运动原点必须是有效正交坐标系")
	return preload("res://scripts/skills/verification_snapshot.gd").restored_transform(task.execution_origin)

static func execution_evidence(arguments: Dictionary, parameter_kinds: Dictionary, runtime: Dictionary) -> Dictionary:
	var frames: Dictionary={}
	var movements: Array=[]
	var complete: bool=runtime.get("status","")=="completed"
	var trace: Array=runtime.get("trace",[])
	for index in trace.size():
		var step: Dictionary=trace[index]
		var result: Dictionary=step.get("result",{})
		if step.get("operation","") in ["perceive","walk_options"] and result.get("observation_id") is String:
			frames[result.observation_id]={"seen":result,"index":index,"source":"execution_query"}
		if step.get("operation","")!="approach":continue
		var selected: Dictionary=step.get("arguments",{}).get("object",{}) if step.get("arguments",{}).get("object") is Dictionary else {}
		# 世界正常拒绝非法输入；不能把其中夹带的任意Lua字段再写入续办历史。
		if not preload("res://scripts/skills/spatial_target.gd").valid(selected):selected={}
		var token: String=selected.get("observation_id","")
		var frame: Dictionary=frames.get(token,{})
		if frame.is_empty():
			var retained: Dictionary=runtime.get("argument_frames",{}).get(token,{})
			if not retained.is_empty():frame={"seen":retained,"index":-2,"source":"retained_argument_frame"}
		var standing: Dictionary=result.get("standing_position",{})
		var entry:={"ok":result.get("ok",false),"code":result.get("code",""),"observation_id":token,"requested_target":selected.duplicate(true),"elapsed_ms":step.get("elapsed_ms",0),"references":{}}
		entry["evidence_complete"]=not frame.is_empty() and standing.get("observation_id")==token and standing.get("position") is Dictionary and result.get("selected_target")==selected
		if not entry.evidence_complete:complete=false
		if not frame.is_empty():
			var seen: Dictionary=frame.seen
			entry["observation_source"]=frame.source
			entry["observation_odometry"]=seen.get("odometry",{}).duplicate(true)
			entry["request_odometry"]=seen.get("request_odometry",{}).duplicate(true)
			entry["observation_immediately_preceded"]=frame.index==index-1
			for key in arguments:
				if parameter_kinds.get(key,"reference")!="reference" or not arguments[key] is String:continue
				var reference: String=arguments[key]
				var near: Dictionary=seen.get("near",{}).get("landmarks",{})
				var known: Dictionary=seen.get("known",{})
				var identity:=reference
				if not near.has(identity) and not known.has(identity):identity="person/"+reference
				var observed: Dictionary=near.get(identity,known.get(identity,{}))
				if observed.is_empty():continue
				var remembered:={"reference_id":identity}
				for field in ["position","approx_position","visible_now","source","observed_at_seconds","position_error_per_axis_m"]:
					if observed.has(field):remembered[field]=observed[field]
				entry.references[reference]=remembered.duplicate(true)
		if entry.evidence_complete:entry["standing_position"]=standing.duplicate(true)
		movements.append(entry)
	return {"skill_arguments":arguments.duplicate(true),"movement_history":{"complete":complete,"entries":movements}}

static func context(person_id: String, request_id: String, records: Array) -> Dictionary:
	assert(not request_id.is_empty())
	var calls: Array=[]
	for record in records:
		assert(record.person_id==person_id,"请求执行记录混入其他人物")
		var runtime: Dictionary=record.get("runtime",{})
		var summary: Dictionary=record.get("execution_summary",{})
		var phases: Array=summary.get("phases",runtime.get("phase_summary",preload("res://scripts/skills/egocentric_space.gd").execution_phases(runtime.get("trace",[]))))
		var movement: Dictionary=record.get("movement_history",{})
		calls.append({"source_event_id":record.source_event_id,"skill_ref":record.get("skill_ref",""),"status":summary.get("status",runtime.get("status","")),"arguments":record.get("skill_arguments",{}).duplicate(true),"movements":movement.get("entries",[]).duplicate(true),"movements_complete":movement.get("complete",false),"phases":phases.duplicate(true),"facts":record.get("world_facts",[]).duplicate(true)})
	return {"request_id":request_id,"calls":calls,"meaning":"宿主保存的本人当前请求执行记录；facts与phases是实际世界结果，不是方法自报成功。新请求不包含旧请求记录；这是过去进展，物品当前状态仍须重新观察。"}
