extends SceneTree
const Memory=preload("res://scripts/voice/memory_store.gd")

func _initialize() -> void:
	create_timer(25).timeout.connect(func():push_error("memory async save test timeout");quit(1))
	_run.call_deferred()

func _run() -> void:
	var folder:="user://memory_async_"+str(Time.get_ticks_usec())
	var memory=Memory.new()
	assert(memory.initialize(folder+"/characters.json",["a","b"],true).is_empty())
	var source: Dictionary={"text":"initial","nested":[{"value":1}]}
	var key: String=memory.put("a","fact","same",source,0.9,true)
	source.nested[0].value=99
	assert(memory.records.a[key].data.nested[0].value==1)
	assert(memory.records.a[key].is_read_only() and memory.records.a[key].data.is_read_only())
	memory.short_events.a.append(memory.freeze_owned({"event":{"id":"old","text":"before"},"at":0.0}))
	memory.tasks.a={"request":{"id":"task"},"state":"waiting"}
	var frozen: Dictionary=memory._snapshot_for_save()
	assert(memory.request_save().is_empty())
	# 写入期间继续改原状态；旧检查点必须完整，且不能吞掉新脏状态。
	memory.put("a","fact","same",{"text":"new","nested":[{"value":2}]},0.9,true)
	memory.advance(2.0)
	memory.short_events.a.clear()
	memory.tasks.a.state="completed"
	memory.contact("a","b")
	assert(frozen.records.a[key].data.text=="initial")
	assert(frozen.short_term.events.a.size()==1 and frozen.short_term.tasks.a.state=="waiting")
	assert((await memory.flush_pending(self)).is_empty() and memory.dirty)
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(memory.path))
	assert(saved.records.a[key].data.text=="initial" and saved.clock==0.0)
	assert(memory.request_save().is_empty())
	assert((await memory.flush_pending(self)).is_empty() and not memory.dirty)
	saved=JSON.parse_string(FileAccess.get_file_as_string(memory.path))
	assert(saved.records.a[key].data.text=="new" and saved.clock==2.0)
	assert(saved.short_term.events.a.is_empty() and saved.short_term.tasks.a.state=="completed")
	var mutable: Dictionary=memory.retained("a","fact")[0]
	mutable.nested[0].value=3
	assert(memory.retained_view("a","fact")[0].nested[0].value==2)
	assert(memory.mark("a",{"id":key,"importance":0.8,"reason":"keep"}).ok)
	memory.consolidate("rest")
	assert(memory.recall("a",{"kind":"fact","keywords":[],"limit":1}).ok)
	assert(memory.request_save().is_empty())
	# 同步明确保存也必须先收束旧后台写入，避免旧文件覆盖新状态。
	memory.advance(1.0)
	assert(memory.save().is_empty())
	saved=JSON.parse_string(FileAccess.get_file_as_string(memory.path))
	assert(saved.clock==3.0)
	var loaded=Memory.new()
	assert(loaded.initialize(memory.path,["a","b"]).is_empty())
	assert(loaded.records.a[key].data.is_read_only())
	var view: Array=loaded.retained_view("a","fact")
	view.clear()
	assert(loaded.retained_view("a","fact").size()==1,"调用者不能修改缓存列表")
	loaded.put("a","fact","same",{"text":"updated"},0.9,true)
	assert(loaded.retained_view("a","fact")[0].text=="updated","写入立即更新对应类型视图")
	var expiry=Memory.new()
	assert(expiry.initialize("",["a"],true).is_empty())
	expiry.policy.forget_threshold=0.5
	expiry.put("a","fact","temporary",{"text":"fades"},0.1)
	expiry.consolidate("rest")
	assert(expiry.retained_view("a","fact").size()==1)
	var item: Dictionary=expiry.records.a.values()[0]
	expiry.clock=float(item.half_life_days)*float(expiry.policy.day_seconds)+1.0
	assert(expiry.retained_view("a","fact").is_empty(),"缓存到遗忘边界失效，不等待清扫")
	var blocked:=FileAccess.open(folder+"/blocked",FileAccess.WRITE)
	blocked.store_string("file");blocked.close()
	loaded.path=folder+"/blocked/characters.json";loaded.dirty=true
	assert(loaded.request_save().is_empty())
	assert(not (await loaded.flush_pending(self)).is_empty() and loaded.dirty)
	var detached=Memory.new()
	var detached_path:=folder+"/detached.json"
	assert(detached.initialize(detached_path,["a"],true).is_empty())
	detached.put("a","fact","last",{"text":"saved on release"})
	assert(detached.request_save().is_empty())
	detached=null
	assert(FileAccess.file_exists(detached_path),"释放记忆所有者时收束后台任务")
	var concurrent=Memory.new()
	assert(concurrent.initialize(folder+"/concurrent.json",["a"],true).is_empty())
	for index in 2000:concurrent.put("a","fact","stress_"+str(index),{"nested":{"value":index,"list":[index,index+1]}})
	assert(concurrent.request_save().is_empty())
	var reader_frames:=0
	while concurrent._save_task!=-1:
		var entry: Dictionary=concurrent.records.a.values().back().data
		var decoded: Dictionary=JSON.parse_string(JSON.stringify(entry))
		assert(entry.nested.value==1999 and decoded.nested.list[0]==1999 and decoded.nested.list[1]==2000)
		assert(concurrent.poll_save().is_empty())
		reader_frames+=1
		await process_frame
	assert(reader_frames>0)
	var checked: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(concurrent.path))
	assert(checked.records.a.size()==2000)
	print("MEMORY_ASYNC_SAVE_PASSED immutable_snapshot, in_flight_updates, mutable_recall_copy, metadata_updates, save_barrier, reload, io_error, owner_release, concurrent_readers; model_calls=0")
	quit()
