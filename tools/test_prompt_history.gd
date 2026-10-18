extends SceneTree
const History=preload("res://scripts/voice/prompt_history.gd")
func _initialize() -> void:
	var repeated:="这是一段系统事件说明，不是人物说出的话。".repeat(5)
	var working:={"recent_turns":[],"task":{"request":{"text":"先拿篮子再采果"}}}
	for n in 10:
		working.recent_turns.append({"event":{"id":str(n),"speaker":"body","text":repeated,"trigger":{"hunger":60+n}},"own_understanding":"我现在的判断"+str(n)})
	working.recent_turns.append({"event":{"id":"player","speaker":"player","text":repeated}})
	working.recent_turns.append({"event":{"id":"person","speaker":"person_002","text":repeated}})
	var original:=JSON.stringify(working)
	var packed:=History.compact(working)
	assert(JSON.stringify(packed).length()<original.length())
	assert(packed.recent_turns.size()==working.recent_turns.size())
	assert(packed.recent_turns[-1].event.text==repeated and packed.recent_turns[-2].event.text==repeated)
	for turn in packed.recent_turns:
		if turn.event.has("text_ref"):
			turn.event["text"]=packed.event_texts[turn.event.text_ref]
			turn.event.erase("text_ref")
	packed.erase("event_texts")
	assert(JSON.stringify(packed)==original,"恢复后必须逐字段完全相同，包括每次需求数值与主观理解")
	assert(JSON.stringify(working)==original,"不能修改源记忆")
	assert(History.compact({"recent_turns":[]})=={"recent_turns":[]})
	var long_id:="event_123456789_"+"skill_result_".repeat(8)
	var transcript:={"recent_turns":[],"task":{"action_event_id":long_id}}
	for index in 12:
		transcript.recent_turns.append({"event":{"id":long_id+str(index),"source_event_id":long_id,"text":"玩家说的原话保持完整","speaker":"player","result":{"source_event_id":long_id,"skill_ref":"技能引用不改","object_id":"物体引用不改"}},"own_reply":{"text":"","status":"保持沉默"},"own_understanding":"本人当时理解"+str(index)})
	var encoded:=History.compact(transcript)
	assert(encoded.has("event_id_aliases") and encoded.has("own_replies"))
	assert(JSON.stringify(encoded).length()<JSON.stringify(transcript).length())
	for turn in encoded.recent_turns:
		assert(turn.event.text=="玩家说的原话保持完整")
	var decoded:=History.expand(encoded)
	for turn in decoded.recent_turns:assert(turn.event.result.skill_ref=="技能引用不改")
	assert(decoded==transcript,"编号、嵌套因果关联、沉默状态、每条理解必须无损恢复")
	assert(transcript.recent_turns[0].event.source_event_id==long_id,"不得改存档")
	var long_history:={"recent_turns":[],"task":{"request":{"text":"当前任务保留"}}}
	for index in 130:
		var event:={"id":str(index),"speaker":"player","text":"第%d句原话"%index,"result":{"ok":index%2==0,"value":null}}
		if index%2==0:event["source_event_id"]=str(index-1)
		long_history.recent_turns.append({"event":event,"own_understanding":"当时的理解%d"%index})
	var table:=History.compact(long_history)
	assert(table.has("event_layouts") and table.has("turn_layouts") and table.recent_turns.size()==130)
	assert(JSON.stringify(table).length()<JSON.stringify(long_history).length())
	assert(History.expand_layouts(table)==long_history,"列式发送必须保留全部原话、顺序、字段有无、null与结果数值")
	var repeated_records:={"recent_turns":[]}
	for index in 20:
		repeated_records.recent_turns.append({"source_event_id":"unique_"+str(index),"observation_id":"frame_"+str(index),"distance_to_selected_point_m":0.123456789+index,"standing_position":{"x":index,"y":null,"z":0.04},"actual_result_code":"blocked"})
	var packed_records:=History.compact_structures(repeated_records)
	assert(JSON.stringify(packed_records).length()<JSON.stringify(repeated_records).length())
	assert(History.expand_structures(packed_records)==repeated_records,"嵌套记录布局必须保留全部字段、顺序和精确数值")
	print("PROMPT_HISTORY_PASSED lossless_system_text_dedup_no_dialogue_removal")
	quit()
