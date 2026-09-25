extends RefCounted
## 注册入口只供受信任的本机开发／验证流程调用，模型决策不能写入此库。
const Luau=preload("res://scripts/skills/luau_contract.gd")
var path: String
var definitions: Dictionary={}
var owners: Dictionary={}

func initialize(file_path: String, people: Dictionary) -> String:
	path=file_path;definitions={};owners={}
	for id in people: owners[id]=[]
	if not FileAccess.file_exists(path): return ""
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema")!=1 or not data.get("definitions") is Dictionary or not data.get("owners") is Dictionary: return "技能库格式无效"
	for ref in data.definitions:
		var definition: Variant=data.definitions[ref]
		if not _valid_definition(definition) or ref!=_reference(definition): return "技能定义或内容指纹不匹配"
	for id in data.owners:
		if not people.has(id) or not data.owners[id] is Array: return "技能持有人无效"
		var seen: Array=[]
		for entry in data.owners[id]:
			if not entry is Dictionary or not data.definitions.has(entry.get("ref")) or not entry.get("source") is String or entry.ref in seen: return "人物技能索引损坏"
			seen.append(entry.ref)
		owners[id]=data.owners[id].duplicate(true)
	definitions=data.definitions.duplicate(true)
	for ref in definitions:
		if not _dependencies_valid(ref,[]): definitions={};return "技能依赖不存在或形成循环"
	return ""

static func _reference(definition: Dictionary) -> String:
	return definition.id+"@"+JSON.stringify(definition).sha256_text()

static func _valid_definition(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["id","name","description","program_json"]:
		if not value.get(key) is String or value[key].is_empty(): return false
	if value.id.length()>80 or not value.id.is_valid_identifier() or value.name.length()>80 or value.description.length()>500 or value.program_json.length()>65536: return false
	if not value.get("parameters") is Dictionary or value.parameters.size()>16: return false
	for key in value.parameters:
		if not key is String or not key.is_valid_identifier() or key.begins_with("_") or not value.parameters[key] is String or value.parameters[key].length()>200: return false
	var kinds: Variant=value.get("parameter_kinds",{})
	if not kinds is Dictionary:return false
	for key in kinds:
		if not value.parameters.has(key) or kinds[key] not in ["reference","text","number","integer","boolean","hand"]:return false
	var program: Variant=JSON.parse_string(value.program_json)
	if not Luau.valid(program): return false
	var dependencies: Variant=value.get("dependencies",{})
	if not dependencies is Dictionary or dependencies.size()>16: return false
	for alias in dependencies:
		if not alias is String or not alias.is_valid_identifier() or alias.begins_with("_") or alias.length()>80: return false
		if not dependencies[alias] is String or dependencies[alias].is_empty(): return false
	return true

static func valid_argument(value: Variant, kind: String) -> bool:
	match kind:
		"reference":return preload("res://scripts/skills/spatial_target.gd").valid(value)
		"text":return value is String and value.length()<=400
		"hand":return value in ["Hand.L","Hand.R"]
		"boolean":return value is bool
		"number","integer":return (value is int or value is float) and is_finite(value) and absf(value)<=10000 and (kind=="number" or floorf(value)==value)
	return false

func register_verified(definition: Dictionary, receipt: Dictionary) -> Dictionary:
	if not _valid_definition(definition): return {"ok":false,"error":"技能定义无效"}
	if not receipt.get("definition_json") is String: return {"ok":false,"error":"验证记录缺少定义正文"}
	# 凭据由本机验证程序产生，摘要绑定本次测试的完整定义；不是模型自行声明 passed。
	if receipt.get("verifier") not in ["leader-luau-tests-v1","leader-shipped-builtin-v1"] or receipt.get("passed")!=true or receipt.get("definition_sha256")!=str(receipt.get("definition_json","")).sha256_text() or JSON.parse_string(receipt.get("definition_json",""))!=definition:
		return {"ok":false,"error":"缺少匹配的验证记录"}
	var ref:=_reference(definition)
	if definitions.has(ref):
		if definitions[ref]!=definition: return {"ok":false,"error":"同一技能引用不能替换定义"}
		return {"ok":true,"ref":ref}
	definitions[ref]=definition.duplicate(true)
	if not _dependencies_valid(ref,[]): definitions.erase(ref);return {"ok":false,"error":"技能依赖不存在或形成循环"}
	var error:=save()
	if error!="": definitions.erase(ref);return {"ok":false,"error":error}
	return {"ok":true,"ref":ref}

func install_builtins() -> String:
	for id in ["release_object","place_object","look_toward","walk_to","give_object"]:
		var source:=FileAccess.get_file_as_string("res://data/skills/"+id+".luau")
		var capabilities: Array=["release","pose_bones","inspect_body","relax"]
		var definition:={"id":id,"name":"松手","description":"松开本人实际持有的指定物品","parameters":{"object":"本人已知的可交互物品ID"},"program_json":JSON.stringify(Luau.make_program(source,capabilities))}
		if id=="place_object":
			definition.name="放到指定位置"
			definition.description="将本人持有的物品移到已知放置面，再松手并确认落稳；必须提供观察编号及人物相对坐标，不能用松手替代指定放置。目标较远时先走近；路线、可见性和实际伸手仍由世界检查。"
			definition.parameters={"object":"本人持有的物品ID","target":"{observation_id:本次space_observation.id,position:{x,y,z}}；本人观察时脚底为原点，x右y上z前，单位米；模型自行决定目标。"}
			definition.program_json=JSON.stringify(Luau.make_program(source,["observe","approach","surface","move_held","check_placement","release","pose","pose_bones","inspect_body","relax"]))
		if id=="give_object":
			definition.name="递交手中物品"
			definition.description="把本人实际握持的物品交给指定人物或玩家，保留原物品和内容（空袋不会自动装水）。不会自动走近；需先到接收者两米内且无阻挡，对方必须有空手。NPC会自行决定接受或拒绝；只有实际持有人转移才算成功。"
			definition.parameters={"object":"本人已握持且接入身体交互的物品ID","recipient":"实际接收者人物ID，交给玩家用player"}
			definition.program_json=JSON.stringify(Luau.make_program(source,["handover"]))
		if id in ["look_toward","walk_to"]:
			definition.name="转身观察" if id=="look_toward" else "走到所选地面附近"
			definition.description="朝本人选择的相对坐标转身并重新观察，可以使用最后所见位置。不会自动移动或追踪视野外物品；执行完成后的下一轮space_observation就是新视角的观察，直接据此决定下一步，不需要另等观察事件。" if id=="look_toward" else "朝本次可见地面坐标走一段，停在约0.45米附近。用地面采样的真实高度，不用物品握持点高度；不自动绕障碍，不走向未确认地面。目标在背后时先转身观察。"
			definition.parameters={"target":"{observation_id:本次space_observation.id,position:{x,y,z}}，人物观察时的相对坐标；方向和目的地由本人选择"}
			definition.program_json=JSON.stringify(Luau.make_program(source,["look_toward"] if id=="look_toward" else ["approach"]))
		for person in owners:
			var installed:=_install_shipped(person,definition)
			if not installed.ok:return installed.error
	return install_life_skills()

func install_life_skills() -> String:
	var specifications: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/life_skills.json"))
	for person in owners:
		var refs: Dictionary={}
		for entry in owners[person]:
			if not entry.has("superseded_by"):refs[definitions[entry.ref].id]=entry.ref
		for spec in specifications:
			var dependencies: Dictionary={}
			for alias in spec.dependencies:
				if not refs.has(spec.dependencies[alias]):return "初始技能依赖缺失："+str(spec.dependencies[alias])
				dependencies[alias]=refs[spec.dependencies[alias]]
			var definition:={"id":spec.id,"name":spec.name,"description":spec.description,"parameters":spec.parameters,"parameter_kinds":spec.parameter_kinds,"internal":spec.internal,"dependencies":dependencies,"program_json":JSON.stringify(Luau.make_program(FileAccess.get_file_as_string("res://data/skills/"+spec.id+".luau"),spec.capabilities))}
			var installed:=_install_shipped(person,definition)
			if not installed.ok:return installed.error
			refs[spec.id]=installed.ref
	return ""

func _install_shipped(person: String, definition: Dictionary) -> Dictionary:
	var previous: Dictionary={}
	for entry in owners[person]:
		if not entry.has("superseded_by") and definitions[entry.ref].id==definition.id:previous=entry;break
	if not previous.is_empty():
		# 玩家修改的技能保持原版本；只升级工程提供且尚未自行修改的默认方法。
		if not previous.source.begins_with("初始生活"):return {"ok":true,"ref":previous.ref}
		var old: Dictionary=definitions[previous.ref].duplicate(true);old.erase("revision_of")
		if old==definition:return {"ok":true,"ref":previous.ref}
		definition=definition.duplicate(true);definition["revision_of"]=previous.ref
	var raw:=JSON.stringify(definition)
	var registered:=register_verified(definition,{"verifier":"leader-shipped-builtin-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	if not registered.ok:return registered
	var error:=grant(person,registered.ref,"初始生活技能") if previous.is_empty() else revise(person,previous.ref,registered.ref,"初始生活技能：工程修订")
	return registered if error=="" else {"ok":false,"error":error}

func grant(person_id: String, ref: String, source: String) -> String:
	if not owners.has(person_id) or not definitions.has(ref) or source.strip_edges().is_empty(): return "无法登记技能掌握记录"
	for entry in owners[person_id]:
		if entry.ref==ref: return ""
	owners[person_id].append({"ref":ref,"source":source,"recorded_at":Time.get_datetime_string_from_system()})
	var error:=save()
	if error!="": owners[person_id].pop_back()
	return error

func learn_from(student: String, teacher: String, ref: String, source: String) -> String:
	if not owners.has(student):return "学生不存在"
	var linked:=execution_context(teacher,ref)
	if not linked.ok:return linked.error
	var previous: Array=owners[student].duplicate(true)
	for dependency in linked.context.definitions:
		if not resolve(student,dependency).is_empty():continue
		owners[student].append({"ref":dependency,"source":source,"recorded_at":Time.get_datetime_string_from_system(),"dependency_only":dependency!=ref})
	for entry in owners[student]:
		if entry.ref==ref:entry.erase("dependency_only")
	var error:=save()
	if error!="":owners[student]=previous
	return error

func resolve(person_id: String, ref: String) -> Dictionary:
	for entry in owners.get(person_id,[]):
		if entry.ref==ref and definitions.has(ref): return definitions[ref].duplicate(true)
	return {}

func revise(person_id: String, old_ref: String, new_ref: String, source: String) -> String:
	if resolve(person_id,old_ref).is_empty() or not definitions.has(new_ref): return "修订引用无效"
	if definitions[old_ref].id!=definitions[new_ref].id or definitions[new_ref].get("revision_of","")!=old_ref: return "修订必须属于同一技能并指向原版本"
	var previous: Array=owners[person_id].duplicate(true)
	for entry in owners[person_id]:
		if entry.ref==old_ref:
			if entry.has("superseded_by"): return "原版本已被修订，请基于当前版本继续"
			entry["superseded_by"]=new_ref
	owners[person_id].append({"ref":new_ref,"source":source,"recorded_at":Time.get_datetime_string_from_system()})
	var error:=save()
	if error!="": owners[person_id]=previous
	return error

func describe(person_id: String) -> Array:
	var result: Array=[]
	for entry in owners.get(person_id,[]):
		if entry.has("superseded_by") or entry.get("dependency_only",false): continue
		var definition: Dictionary=definitions[entry.ref]
		var descriptor: Dictionary={"ref":entry.ref,"name":definition.name,"description":definition.description,"parameters":definition.parameters.duplicate(true),"learned_from":entry.source,"revision_of":definition.get("revision_of",""),"revision_supported":true,"language":"leader-luau-1"}
		var program: Dictionary=JSON.parse_string(definition.program_json)
		descriptor["parameter_kinds"]=definition.get("parameter_kinds",{}).duplicate()
		descriptor["internal"]=definition.get("internal",false)
		var operations: Array=program.capabilities.duplicate()
		var linked:=execution_context(person_id,entry.ref)
		descriptor["callable"]=linked.ok
		if not linked.ok: descriptor["unavailable_reason"]=linked.error
		else:
			for component in linked.context.definitions.values():
				for op in component.program.capabilities:
					if op not in operations: operations.append(op)
		if definition.parameters.has("object") and operations.any(func(op):return op in ["observe","reach","grasp","release","move_held","check_placement","handover"]):
			descriptor["object_requirement"]="目标必须已接入身体物品交互，观察记录extra.graspable=true；这只说明物品支持抓握，不表示当前距离已经伸手可及。需结合本人相对坐标判断距离、朝向与姿势，走近和伸手是不同操作。知道位置不代表具备这个接口。未接入的物品应核对现有行为目录或明确能力缺口。"
		result.append(descriptor)
	return result

func save() -> String:
	var directory:=ProjectSettings.globalize_path(path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return "无法创建技能库目录"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return "无法保存技能库"
	file.store_string(JSON.stringify({"schema":1,"definitions":definitions,"owners":owners}))
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK: return "无法完成技能库文件替换"
	return ""

func _dependencies_valid(ref: String, ancestors: Array, cache: Dictionary={}) -> bool:
	if ref in ancestors or ancestors.size()>=8 or not definitions.has(ref): return false
	if not cache.has("nodes"): cache.nodes={}
	cache.nodes[ref]=true
	if cache.nodes.size()>32: return false
	# 共享依赖按深度记忆结果，避免菱形依赖图被指数次重复遍历。
	var key: String=ref+"/"+str(ancestors.size())
	if cache.has(key): return cache[key]
	var next:=ancestors.duplicate();next.append(ref)
	for dependency in definitions[ref].get("dependencies",{}).values():
		if not _dependencies_valid(dependency,next,cache): cache[key]=false;return false
	cache[key]=true
	return true

func execution_context(person_id: String, ref: String) -> Dictionary:
	var all: Dictionary={}
	if not _dependencies_valid(ref,[]): return {"ok":false,"error":"技能依赖不存在、循环或超过深度限制"}
	var todo: Array=[ref]
	while not todo.is_empty():
		var current: String=todo.pop_back()
		if all.has(current): continue
		if all.size()>=32: return {"ok":false,"error":"技能依赖过多"}
		var definition:=resolve(person_id,current)
		if definition.is_empty(): return {"ok":false,"error":"人物尚未掌握复合技能所需的依赖"}
		var dependencies: Dictionary=definition.get("dependencies",{}).duplicate(true)
		all[current]={"program":JSON.parse_string(definition.program_json),"parameters":definition.parameters.duplicate(true),"dependencies":dependencies}
		todo.append_array(dependencies.values())
	return {"ok":true,"context":{"root":ref,"definitions":all}}
