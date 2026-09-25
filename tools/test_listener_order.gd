extends SceneTree
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
func _initialize() -> void:
	var people:={"a":{"name":"大山"},"b":{"name":"月亮"},"c":{"name":"小花"}}
	var event:={"listeners":["a","c","b"],"spatial_segments":[{"text":"月亮，请给我空袋。","focus_hint":"a","audience":{"a":{},"b":{},"c":{}}}]}
	assert(Pipeline.ordered_listeners(event,people)==["b","a","c"],"明确点名优先于朝向，不能先等旁听者")
	assert(event.listeners==["a","c","b"],"不能更改实际听闻集合")
	event.spatial_segments[0].text="你给我空袋。"
	assert(Pipeline.ordered_listeners(event,people)==["a","c","b"])
	event.spatial_segments[0].text="月亮在外面吗？"
	assert(Pipeline.ordered_listeners(event,people)==["a","c","b"],"提及不等于开头点名")
	event.spatial_segments[0].text="月亮，请过来。";event.spatial_segments[0].audience.erase("b")
	assert(Pipeline.ordered_listeners(event,people)==["a","c","b"],"没听到点名这一段的人不能被当作该段的直接对象")
	assert(Pipeline.ordered_listeners({"listeners":["a","b"],"text":"月亮，过来"},people)==["b","a"])
	var prompt: String=Pipeline.prompt_for({"id":"b","name":"月亮","visible_people":[{"id":"a","name":"大山"},{"id":"c","name":"小花"}]},event)
	var wire: Dictionary=JSON.parse_string(prompt.get_slice("\n",prompt.get_slice_count("\n")-1))
	assert(wire.conversation_evidence.size()==1 and wire.conversation_evidence[0].opening_name_matches[0].id=="b","每个声音片段只提供一份证据，不按可见人数重复")
	print("LISTENER_ORDER_PASSED_named_before_gaze_hearing_preserved_mentions_not_commands")
	quit()
