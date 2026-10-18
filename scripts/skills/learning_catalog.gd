extends RefCounted
## 本人未学成的方法索引；只供续写选择，绝不授予执行权限或暴露其他人物草稿。
static var _jobs_by_root: Dictionary={}
static func scan(people: Array, root: String="res://services/skill-runtime/runtime/jobs") -> Dictionary:
	if not _jobs_by_root.has(root):
		var jobs: Dictionary={}
		for name in DirAccess.get_directories_at(root):
			if not name.begins_with("job_"):continue
			var entry:=_entry(root.path_join(name))
			if not entry.is_empty():jobs[name]=entry
		_jobs_by_root[root]=jobs
	return _views(people,_jobs_by_root[root])

static func refresh_job(people: Array, job: String, root: String="res://services/skill-runtime/runtime/jobs") -> Dictionary:
	if not _jobs_by_root.has(root):return scan(people,root)
	var entry:=_entry(root.path_join(job))
	if entry.is_empty():_jobs_by_root[root].erase(job)
	else:_jobs_by_root[root][job]=entry
	return _views(people,_jobs_by_root[root])

static func _entry(folder: String) -> Dictionary:
	if not FileAccess.file_exists(folder+"/candidate_definition.json"):return {}
	var status:=_read(folder+"/status.json")
	if status.get("state")!="failed":return {}
	var context:=_read(folder+"/draft_context.json")
	if context.get("schema")!=1 or not context.get("person_id") is String or not context.get("goal_id") is String or not context.get("goal") is String:return {}
	if not context.goal_id.is_valid_identifier() or context.goal.is_empty():return {}
	return {"person_id":context.person_id,"goal_id":context.goal_id,"goal":context.goal,"last_result":status.get("message","未通过验证"),"modified":FileAccess.get_modified_time(folder+"/status.json")}

static func _views(people: Array, jobs: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in people: result[id]={}
	for entry in jobs.values():
		var id: String=entry.person_id
		var goal: String=entry.goal_id
		if not result.has(id):continue
		if result[id].has(goal) and result[id][goal].modified>=entry.modified:continue
		result[id][goal]={"goal_id":goal,"goal":entry.goal,"last_result":entry.last_result,"modified":entry.modified}
	for id in result:
		var entries: Array=result[id].values()
		entries.sort_custom(func(a,b):return a.modified>b.modified)
		for entry in entries: entry.erase("modified")
		result[id]=entries
	return result

static func write_context(folder: String, person: String, goal_id: String, goal: String) -> String:
	var file:=FileAccess.open(folder.path_join("draft_context.json"),FileAccess.WRITE)
	if file==null:return "无法保存草稿索引"
	file.store_string(JSON.stringify({"schema":1,"person_id":person,"goal_id":goal_id,"goal":goal}))
	file.close()
	return ""

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
