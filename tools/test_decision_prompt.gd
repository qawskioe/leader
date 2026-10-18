extends SceneTree
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
const Prompt=preload("res://scripts/voice/decision_prompt.gd")
func _initialize() -> void:
 create_timer(5).timeout.connect(func():quit(1))
 var context:={"id":"person_001","name":"石头","needs":{"hunger":12},"relationships":{},"available_skills":[],"working_context":{"task":{"request":{"id":"order","text":"采四份食物"}},"recent_turns":[]}}
 for kind in ["speech_intent","social_request","session_restored","skill_ready","skill_revised","item_offer","skill_lesson_offer","skill_lesson_request"]:
  var event:={"id":"test","kind":kind,"speaker":"world","text":"方法可用了","original_event":{"id":"order","speaker":"player","text":"采四份食物"}}
  var prompt: String=Pipeline.prompt_for(context,event)
  for removed in ["不知道别人的私下想法","旧recipient_id","eat/drink/explore","只有原话要求演示","不要再输出ready","Godot","Luau","强模型会编写"]:
   assert(not prompt.contains(removed),"废弃规则或实现细节重新进入输入："+removed)
  assert(prompt.count(Prompt.ROLE)==1 and prompt.count(Prompt.CONTRACT)==1)
  assert(prompt.contains("本轮接物接口")== (kind=="item_offer"),"只在适用事件提供接物说明")
  assert(prompt.contains("物品交接是已有的事件互动"),"请求和恢复任务时也要知道原生交接流程")
  assert(prompt.contains("学生自行选择是否求教") and prompt.contains("教学实际结束后才获得方法"),"最终完整输入说明邀请、双方选择与实际授予边界")
  var wire: Dictionary=JSON.parse_string(Pipeline.prompt_for(context,event).split("\n")[-1])
  assert(wire.current_event.original_event.text=="采四份食物" and wire.self.needs.hunger==12)
 var schema_text: String=Prompt.CONTRACT
 assert(schema_text.contains("teach另填ref") and schema_text.contains("goal_id只关联求教目标"))
 context.available_skills=[{"id":"actual_method_id","ref":"skill_1","name":"可传授的方法","parameters":{},"callable":true}]
 var teaching_event:={"id":"teach_probe","kind":"skill_lesson_request","speaker":"person_002","goal_id":"student_requested_topic","text":"请教我这个能力"}
 var request: Dictionary=Pipeline.request_for(context,teaching_event)
 var wire: Dictionary=JSON.parse_string(request.prompt.split("\n")[-1])
 var catalog: Dictionary=JSON.parse_string(request.reference)
 assert(wire.current_event.goal_id=="student_requested_topic" and wire.self.available_skills[0].ref=="skill_1")
 assert(catalog.skill_catalog[0].id=="actual_method_id" and catalog.skill_catalog[0].ref=="skill_1","完整输入同时提供本人方法版本与独立求教目标")
 for field in ["conversation","skill_call","revision_request","task_handling","task_status","public_reply","speech_style"]:
  assert(schema_text.contains(field))
 var original:={"id":"original_request","speaker":"player","text":"把同一个篮子还给我"}
 var result_event:={"id":"result_event","kind":"skill_progress","speaker":"world","text":"已实际交还","original_event":original,"result":{"success":true,"code":"transferred"}}
 var remembered_event: Dictionary=result_event.duplicate(true)
 remembered_event.erase("original_event");remembered_event.original_event_id=original.id
 context.working_context={"task":{"request":original},"recent_turns":[{"event":remembered_event}]}
 var result_wire: Dictionary=JSON.parse_string(Pipeline.request_for(context,result_event).prompt)
 assert(result_wire.self.working_context.recent_turns[0].event.get("context_ref")=="current_event","历史原请求ID与本次完整原请求指向同一事实时，应共享本次事件")
 assert(result_wire.current_event.original_event.context_ref=="self.working_context.task.request")
 context.working_context.recent_turns[0].event.text="同一编号但不同事实，不能据编号去重"
 result_wire=JSON.parse_string(Pipeline.request_for(context,result_event).prompt)
 assert(not result_wire.self.working_context.recent_turns[0].event.has("context_ref"),"仍需逐字段核对，不能只凭事件ID吞掉不同事实")
 print("DECISION_PROMPT_PASSED current_contract_conditional_offer_original_task_preserved; model_behavior_not_tested")
 quit()
