extends SceneTree
const Waits=preload("res://scripts/survival/information_waits.gd")
func _initialize() -> void:
	var waits=Waits.new()
	var actors={"a":{"stage":"idle"}}
	var original={"id":"player_question","speaker":"player","text":"问问她在哪里"}
	waits.begin("a","b",original,"你在哪里？",10)
	assert(waits.next_event(54,actors).is_empty())
	assert(waits.heard_reply("unrelated","b",["a"]).is_empty())
	assert(waits.heard_reply("player_question_request_b","c",["a"]).is_empty())
	assert(waits.heard_reply("player_question_request_b","b",["c"]).is_empty(),"未听到的答复不能结束等待")
	actors.a.stage="walking"
	assert(waits.next_event(56,actors).is_empty())
	actors.a.stage="idle"
	var event: Dictionary=waits.next_event(56,actors)
	assert(event.kind=="information_unanswered" and event.original_event==original)
	assert(event.trigger.check_number==1 and event.listeners==["a"])
	assert(not event.has("target_heard") and "不知道对方是否听见" in event.text)
	assert(waits.next_event(100,actors).is_empty(),"一次询问只能产生一次到期反馈")
	waits.begin("a","b",event,"再问一次",100)
	var second: Dictionary=waits.next_event(145,actors)
	assert(second.trigger.check_number==2 and second.original_event==original)
	waits.begin("a","b",second,"再问一次",200)
	assert(waits.next_event(300,actors).is_empty(),"同一请求不能无限自动唤醒")
	waits.reset()
	waits.begin("a","b",original,"你在哪里？",0)
	assert(waits.heard_reply("player_question_request_b","b",["a"])=="a")
	assert(waits.next_event(100,actors).is_empty(),"真实听到匹配回答后不再超时")
	waits.begin("a","b",original,"你在哪里？",0)
	waits.reset()
	assert(waits.next_event(100,actors).is_empty())
	print("INFORMATION_WAITS_PASSED deadline_heard_only_one_shot_budget_reset")
	quit()
