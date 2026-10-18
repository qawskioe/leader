extends SceneTree
const People=preload("res://scripts/voice/people_store.gd")

func _initialize() -> void:
	var store=People.new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	var id:="person_001"
	var old_record: Dictionary=store.memory.freeze_owned({"text":"captured","nested":[{"value":1}]})
	store.people[id].heard_events=[old_record]
	var captured: Array=store.people[id].heard_events
	store.memory.put(id,"heard","new",{"text":"current"})
	store.refresh_memory_views()
	store.flush_retired_history()
	assert(captured.size()==1 and captured[0].text=="captured" and captured[0].nested[0].value==1,"后台释放不能清空调用者捕获的旧视图")
	assert(captured[0].is_read_only())
	assert(store.people[id].heard_events.size()==1 and store.people[id].heard_events[0].text=="current")
	store.memory.put(id,"heard","new",{"text":"revised"})
	store.refresh_memory_views()
	store=null
	assert(captured[0].text=="captured","释放所有者时须收束任务并保留外部引用")
	print("PEOPLE_HISTORY_VIEWS_PASSED: captured_input, readonly_payload, current_view, owner_release")
	quit()
