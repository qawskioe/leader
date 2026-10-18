extends SceneTree
const Memory=preload("res://scripts/voice/memory_store.gd")

func _initialize() -> void:
	var memory=Memory.new()
	assert(memory.initialize("",["a","b"],true).is_empty())
	memory.put("a","fact","first",{"text":"original"},0.9,true)
	var captured: Array=memory.retained_view("a","fact")
	memory.put("a","fact","first",{"text":"replacement"},0.9,true)
	memory.put("a","fact","second",{"text":"appended"},0.9,true)
	assert(captured.size()==1 and captured[0].text=="original","已捕获的输入不能被后续写入改变")
	var current: Array=memory.retained_view("a","fact")
	assert(current.size()==2 and current[0].text=="replacement" and current[1].text=="appended")
	current.clear()
	assert(memory.retained_view("a","fact").size()==2)
	assert(memory.retained_view("b","fact").is_empty(),"索引必须按人物隔离")

	var fading=Memory.new()
	assert(fading.initialize("",["a"],true).is_empty())
	fading.put("a","fact","first",{"text":"faded"},0.1)
	fading.put("a","fact","second",{"text":"resident"},0.9,true)
	fading.consolidate("rest")
	var first: Dictionary=fading.records.a.values()[0]
	fading.clock=float(first.half_life_days)*float(fading.policy.day_seconds)*16.0
	var loaded=Memory.new()
	assert(loaded.load_data(fading.export_data(),["a"]).is_empty())
	assert(loaded.retained_view("a","fact").size()==1 and loaded.retained_view("a","fact")[0].text=="resident","加载应按存档时钟过滤")
	loaded.put("a","fact","first",{"text":"revived"},0.1)
	var revived: Array=loaded.retained_view("a","fact")
	assert(revived.size()==2 and revived[0].text=="revived" and revived[1].text=="resident","复活条目保留原索引顺序")
	loaded.consolidate("rest")
	loaded.policy.forget_threshold=0.8
	loaded.clock+=float(first.half_life_days)*float(loaded.policy.day_seconds)
	assert(loaded.retained_view("a","fact").size()==1,"阈值改变及跨遗忘边界仍须刷新")
	print("MEMORY_RETAINED_VIEWS_PASSED: replacement, append_order, captured_input, caller_ownership, privacy, loaded_clock, revival_order, policy_expiry")
	quit()
