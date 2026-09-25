extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
func _initialize() -> void:
	var store:=Store.new();assert(store.initialize().is_empty())
	var id:="person_001"
	var old:={"id":"old_help","speaker":"person_004","kind":"social_request","text":"帮我接篮子"}
	var current:={"id":"new_food","speaker":"player","kind":"speech_intent","text":"石头，吃一份食物，不用说话"}
	store.hear(id,old);store.hear(id,current)
	store.working_tasks[id]={"request":old,"state":"wait","action_event_id":"old_help"}
	var decision:={"intent":"none","skill_call":{"ref":"eat@fixture","arguments":{}},"private_interpretation":"玩家叫我吃饭，不用说话","public_reply":"","speech_act":"statement","addressed_person":"","task_status":"active","conversation":{"participation":"listen","addressees":[],"reason":"沉默行动"},"task_handling":{"state":"execute","scope":"current_request","reason":"执行玩家本次命令"}}
	assert(Cloud.validate_task_handling(decision).ok)
	store.remember(id,current.id,decision)
	assert(store.working_tasks[id].request.id==current.id and store.superseded_tasks[id+"/old_help"]==current.id,"沉默不能把本次命令错误绑定旧任务")
	var need:={"id":"need","kind":"need_changed","speaker":"body","text":"口渴"};store.hear(id,need)
	decision.task_handling.scope="independent"
	store.remember(id,need.id,decision)
	assert(store.working_tasks[id].request.id==current.id and store.independent_actions.has(id+"/need"),"自主动作不覆盖玩家任务")
	var result:={"id":"continue","kind":"skill_progress","speaker":"world","text":"实际吃完","original_event":current};store.hear(id,result)
	decision.task_handling.scope="existing_request"
	store.remember(id,result.id,decision)
	assert(store.working_tasks[id].request.id==current.id)
	print("TASK_SCOPE_PASSED silent_current_request_independent_existing")
	quit()
