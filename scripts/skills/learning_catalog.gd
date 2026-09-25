extends RefCounted
## 本人未学成的方法索引；只供续写选择，绝不授予执行权限或暴露其他人物草稿。
static func scan(people: Array, root: String="res://services/skill-runtime/runtime/jobs") -> Dictionary:
	var result: Dictionary={}
	for id in people: result[id]={}
	for name in DirAccess.get_directories_at(root):
		if not name.begins_with("job_"): continue
		var folder:=root.path_join(name)
		if not FileAccess.file_exists(folder+"/candidate_definition.json"): continue
		var status:=_read(folder+"/status.json")
		if status.get("state")!="failed": continue
		var request:=_read(folder+"/build_request.json")
		var id: String=request.get("verification_snapshot",{}).get("person_id","")
		var goal: String=request.get("goal_id","")
		if not result.has(id) or not goal.is_valid_identifier(): continue
		var modified:=FileAccess.get_modified_time(folder+"/status.json")
		if result[id].has(goal) and result[id][goal].modified>=modified: continue
		var description: String=request.get("creation",{}).get("goal",request.get("revision",{}).get("feedback",""))
		if description.is_empty(): continue
		result[id][goal]={"goal_id":goal,"goal":description,"last_result":status.get("message","未通过验证"),"modified":modified}
	for id in result:
		var entries: Array=result[id].values()
		entries.sort_custom(func(a,b):return a.modified>b.modified)
		for entry in entries: entry.erase("modified")
		result[id]=entries
	return result

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
