extends SceneTree
## 独立离线存档：真实大正文写入时界面继续运行，失败和关闭不丢检查点。
const Store=preload("res://scripts/survival/session_store.gd")
class VoiceProbe extends "res://scripts/voice/voice_test.gd":
	var dispatches:=0
	func _try_autonomy() -> void:dispatches+=1
class SessionProbe extends "res://scripts/survival/session_controller.gd":
	var saved_count:=0
	func _message(text: String, error: bool=false) -> void:
		super._message(text,error)
		if text.begins_with("已保存"):
			saved_count+=1
			if quitting:
				assert(not host.survival.enabled and not host.get_parent().get_node("Player").is_physics_processing())
				host._process(0)
				assert(host.dispatches==0,"保存中关闭不能重新发起判断")

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(90).timeout.connect(func():push_error("async session test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=VoiceProbe.new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	voice.session_manager.queue_free()
	var session:=SessionProbe.new();session.host=voice;voice.add_child(session);voice.session_manager=session
	session.path="user://sessions/async_%d.json"%Time.get_ticks_usec()
	# 尚未持有暂停时的退出失败不能套用默认的“恢复”状态。
	voice.survival.enabled=false;scene.get_node("Player").set_physics_process(false)
	voice.survival.ready_for_actions=false
	await session.quit_game()
	assert(not session.is_locked() and not voice.survival.enabled and not scene.get_node("Player").is_physics_processing())
	voice.survival.ready_for_actions=true;voice.survival.enabled=true;scene.get_node("Player").set_physics_process(true)
	var id:="person_003"
	var large:="完整历史正文".repeat(700000)
	voice.store.people[id].known_facts.append(large)
	var original:={"id":"async_checkpoint_order","speaker":"player","kind":"speech_intent","text":"继续原任务"}
	voice.store.hear(id,original)
	voice.store.working_tasks[id]={"request":original,"state":"awaiting_judgement","action_event_id":original.id,"progress":[]}
	var result:={"done":false,"error":"not returned"}
	(func():result.error=await session.save_game();result.done=true).call()
	assert(session.busy and session.is_locked() and voice.menu.session_status.text.begins_with("正在保存"))
	assert((await session.save_game()).contains("已有存取"))
	assert((await session.load_game()).contains("已有存取"))
	var frames:=0
	while not result.done:
		assert(session.is_locked())
		voice._process(0)
		assert(voice.dispatches==0)
		frames+=1;await process_frame
	assert(result.error.is_empty() and frames>2 and not session.is_locked())
	var checked:=Store.read(session.path,voice.survival)
	assert(checked.ok,str(checked.get("error")))
	assert(checked.data.people[id].known_facts.back()==large,"不能为加快存档裁剪正文")
	assert(checked.data.memory.records==checked.data.world.records)
	assert(checked.data.continuity.requests.filter(func(event):return event.kind=="session_checkpoint").size()==1)
	checked.clear()
	var digest:=FileAccess.get_sha256(session.path)
	assert(DirAccess.make_dir_absolute(session.path+".tmp")==OK)
	# 真正临时文件打开失败；关闭请求须收到本次失败，不能悄悄再试或退出。
	session.save_game()
	await session.quit_game()
	assert(not session.is_locked() and not session.quitting and session.saved_count==1)
	assert(FileAccess.get_sha256(session.path)==digest and voice.menu.session_status.text=="无法写入临时存档")
	assert(DirAccess.remove_absolute(session.path+".tmp")==OK)
	print("SESSION_ASYNC_SAVE_PASSED frames=",frames," complete_history busy_save_load_rejected failure_keeps_original pending_quit_failure_unlocks unowned_pause_unchanged")
	# 成功时复用同一次检查点。若重复保存，saved_count 会变成3。
	session.save_game()
	assert(session.busy)
	root.tree_exiting.connect(func():
		assert(session.saved_count==2 and voice.dispatches==0)
		assert(FileAccess.file_exists(session.path) and not FileAccess.file_exists(session.path+".tmp"))
		print("SESSION_ASYNC_QUIT_PASSED current_save_joined_once no_new_decisions complete_file"))
	await session.quit_game()
