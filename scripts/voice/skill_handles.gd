extends RefCounted
## 调用句柄只在本次请求中有效；存档与执行仍使用内容寻址的完整版本引用。
static func bind(context: Dictionary, event: Dictionary) -> Dictionary:
	var forward: Dictionary={};var reverse: Dictionary={}
	for skill in context.get("available_skills",[]):
		var handle:="skill_%d"%(reverse.size()+1)
		assert(not forward.has(skill.ref))
		forward[skill.ref]=handle;reverse[handle]=skill.ref
	rewrite(context,forward);rewrite(event,forward)
	context["skill_reference_rule"]="available_skills.ref是本次调用短编号，只从当前目录选择；程序会精确映射回本人掌握的完整版本。历史中未映射的长引用是其他版本，不是本轮调用入口。短编号仅在本次请求内有效。"
	return reverse

static func rewrite(value: Variant, mapping: Dictionary) -> void:
	if value is Dictionary:
		for key in value:
			if key in ["ref","skill_ref","revision_of"] and value[key] is String and mapping.has(value[key]):value[key]=mapping[value[key]]
			else:rewrite(value[key],mapping)
	elif value is Array:
		for entry in value:rewrite(entry,mapping)

static func resolve(decision: Dictionary, mapping: Dictionary) -> void:
	for field in ["skill_call","revision_request"]:
		if decision.get(field) is Dictionary:
			assert(mapping.has(decision[field].ref),"句柄必须先通过本轮目录校验")
			decision[field].ref=mapping[decision[field].ref]
