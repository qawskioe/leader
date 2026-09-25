extends SceneTree
func _initialize() -> void:
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd")
	var context:={"id":"person_001","name":"石头","space_observation":{"id":"old_frame"},"needs":{"hunger":70},"working_context":{"recent_turns":[{"event":{"id":"old","speaker":"player","text":"带我去月亮旁边"},"own_understanding":"先沿前方走"}],"task":{"request":{"id":"old","text":"带我去月亮旁边"}}}}
	var event:={"id":"new","kind":"speech_intent","speaker":"player","text":"先别带路，再问一次月亮在哪里"}
	var original:=JSON.stringify(context)
	var prompt: String=pipeline.prompt_for(context,event)
	var wire: String=prompt.get_slice("\n",prompt.get_slice_count("\n")-1)
	var data: Dictionary=JSON.parse_string(wire)
	assert(data.self==JSON.parse_string(original) and data.current_event==event,"重新排版不能删改历史、状态或新指令")
	assert(JSON.stringify(context)==original,"不能改写原始上下文")
	assert(wire.find('"working_context"')<wire.find('"space_observation"'))
	assert(wire.rfind('"current_event"')>wire.rfind('"conversation_evidence"'),"本次要求应在历史与当前状态之后")
	context.space_observation.id="new_frame";context.needs.hunger=71;event.text="等一下，先回来"
	var second: String=pipeline.prompt_for(context,event)
	var prefix:=0
	while prefix<mini(prompt.length(),second.length()) and prompt[prefix]==second[prefix]: prefix+=1
	assert(prefix>=prompt.find('"space_observation"'),"仅当前状态变化不应打断此前稳定的历史前缀")
	print("PROMPT_ORDER_PASSED lossless_history_first_current_event_last_stable_prefix")
	quit()
