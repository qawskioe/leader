extends SceneTree
const Handles=preload("res://scripts/voice/skill_handles.gd")
func _initialize() -> void:
	var old:={"available_skills":[{"ref":"take@abcdef","revision_of":"","parameters":{"object":"物品"}},{"ref":"take@modified","revision_of":"take@abcdef"}],"working_context":{"recent_turns":[{"event":{"result":{"skill_ref":"take@abcdef"}},"own_reply":{"text":"不要改我的台词 take@abcdef"}}]}}
	old["skill_refs"]=[{"ref":"old@private_history","superseded_by":"take@modified"}]
	var context:=old.duplicate(true)
	var event:={"result":{"skill_ref":"take@modified"}}
	var mapping:=Handles.bind(context,event)
	assert(not context.has("skill_refs") and old.has("skill_refs"),"不发送重复版本目录，不改人物存档")
	var authoring=preload("res://scripts/skills/luau_contract.gd").authoring_context()
	assert(authoring.operations==preload("res://scripts/skills/luau_contract.gd").OPERATIONS)
	assert("pose_bones" not in authoring.operations and "grasp" in authoring.operations and "throw" not in authoring.operations)
	assert(context.available_skills[0].ref=="skill_1" and context.available_skills[1].ref=="skill_2")
	assert(event.result.skill_ref=="skill_2" and mapping.skill_2=="take@modified")
	assert(context.working_context.recent_turns[0].event.result.skill_ref=="skill_1")
	assert(context.working_context.recent_turns[0].own_reply.text==old.working_context.recent_turns[0].own_reply.text)
	var decision:={"skill_call":{"ref":"skill_2","arguments":{"object":"basket/1"}},"revision_request":null}
	Handles.resolve(decision,mapping)
	assert(decision.skill_call.ref=="take@modified" and decision.skill_call.arguments.object=="basket/1")
	var other:={"available_skills":[{"ref":"other@123"}]}
	var another:=Handles.bind(other,{})
	assert(another.skill_1!=mapping.skill_1 and not mapping.has("take@abcde"),"不同人物/请求不能共用句柄或猜测相近哈希")
	assert(old.available_skills[0].ref=="take@abcdef","源存档不能改写")
	print("SKILL_HANDLES_PASSED exact_person_request_mapping_versions_dialogue_preserved")
	quit()
