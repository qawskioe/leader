extends SceneTree
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
const Prompt=preload("res://scripts/voice/decision_prompt.gd")
func _initialize() -> void:
 var context:={"id":"person_001","name":"石头","needs":{"hunger":12},"relationships":{},"available_skills":[],"working_context":{"task":{"request":{"id":"order","text":"采四份食物"}},"recent_turns":[]}}
 for kind in ["speech_intent","skill_ready","skill_revised","item_offer"]:
  var event:={"id":"test","kind":kind,"speaker":"world","text":"方法可用了","original_event":{"id":"order","speaker":"player","text":"采四份食物"}}
  var prompt: String=Pipeline.prompt_for(context,event)+"\n\n"+Prompt.MEMORY
  for removed in ["不知道别人的私下想法","旧recipient_id","eat/drink/explore","只有原话要求演示","不要再输出ready","Godot","Luau","强模型会编写"]:
   assert(not prompt.contains(removed),"废弃规则或实现细节重新进入输入："+removed)
  assert(prompt.count(Prompt.ROLE)==1 and prompt.count(Prompt.CONTRACT)==1)
  assert(prompt.contains("本轮接物接口")== (kind=="item_offer"),"只在适用事件提供接物说明")
  var wire: Dictionary=JSON.parse_string(Pipeline.prompt_for(context,event).split("\n")[-1])
  assert(wire.current_event.original_event.text=="采四份食物" and wire.self.needs.hunger==12)
 var schema_text: String=Prompt.CONTRACT
 for field in ["conversation","skill_call","revision_request","task_handling","task_status","public_reply","speech_style"]:
  assert(schema_text.contains(field))
 print("DECISION_PROMPT_PASSED current_contract_conditional_offer_original_task_preserved; model_behavior_not_tested")
 quit()
