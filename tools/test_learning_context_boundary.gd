extends SceneTree
## 穿过真实日常决策管道检查发送边界；完整开发记录仍保留给审查与编写。
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
class Gateway extends Node:
	var prompts: Array[String]=[]
	func exchange(request: Dictionary) -> Dictionary:
		prompts.append(request.prompt)
		await get_tree().process_frame
		return {"ok":true,"model":"fixture","text":JSON.stringify({"intent":"none","private_interpretation":"方法尚未学成","public_reply":"","speech_style":"","routing_reason":"没有新行动请求","speech_act":"statement","addressed_person":"","capability_gap":null,"task_status":"none","task_handling":{"state":"none","scope":"independent","reason":"记录学习结果"},"conversation":null})}

func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(12).timeout.connect(func():push_error("learning context boundary timeout");quit(1))
	var pipeline:=Pipeline.new();root.add_child(pipeline)
	var gateway:=Gateway.new();root.add_child(gateway);pipeline.gateway=gateway
	var file:="user://learning_context_%d.json"%Time.get_ticks_usec()
	pipeline.store=preload("res://scripts/voice/people_store.gd").new()
	assert(pipeline.store.initialize("res://data/people.json",file,true).is_empty())
	var developer_review:={"passed":false,"owner":"uncertain","retryable":true,"issues":["独立回放超时，尚未证明方法可用。",{"runtime":{"trace":[{"source":"DEVELOPER_ONLY_SOURCE".repeat(5000),"private_other_role":"OTHER_ROLE_PRIVATE","world_position":{"x":900,"y":0,"z":900}}]}}]}
	pipeline.store.people.person_001["learning"]={"message":"技能验证超时，未加载","state":"failed","completed":false,"job":"job_developer_only","model":"author_fixture","review":developer_review}
	var original:=JSON.stringify(pipeline.store.people.person_001.learning)
	var reports: Array=[];pipeline.report_ready.connect(func(report):reports.append(report))
	pipeline.run({"id":"learning_boundary","kind":"skill_progress","speaker":"world","text":"本次方法未学成","listeners":["person_001"]},{})
	await pipeline.completed
	assert(reports.size()==1 and not reports[0].has("error"),JSON.stringify(reports))
	assert(gateway.prompts.size()==1)
	var prompt: String=gateway.prompts[0]
	for forbidden in ["DEVELOPER_ONLY_SOURCE","OTHER_ROLE_PRIVATE","job_developer_only","author_fixture"]:
		assert(not prompt.contains(forbidden),"后台开发详情进入日常模型："+forbidden)
	assert(prompt.contains("技能验证超时，未加载") and prompt.contains("独立回放超时，尚未证明方法可用。"),"不能过滤掉人物判断所需的学习状态与失败原因")
	assert(prompt.length()<15000,"一次失败审查不得让日常请求携带整包开发轨迹")
	assert(JSON.stringify(pipeline.store.people.person_001.learning)==original,"发送过滤不能改掉开发审查、存档或编写依据")
	var other:=Pipeline.prompt_for(pipeline.store.context_for("person_002"),{"id":"other","kind":"need_changed","speaker":"body","text":"检查需求"})
	assert(not other.contains("技能验证超时，未加载"),"本人的学习结果不能转给另一角色")
	# completed仍在信号派发栈内；延迟释放，不在await恢复点同步free发送者。
	pipeline.queue_free();gateway.queue_free();await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("LEARNING_CONTEXT_BOUNDARY_PASSED actual_pipeline_brief_failure_full_developer_evidence_preserved")
	quit()
