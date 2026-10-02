extends Node
## 游戏存档入口。暂停异步输入并收束执行后保存；读取只恢复事实，不重放技能。
const Store=preload("res://scripts/survival/session_store.gd")
var host: Node
var path:="user://sessions/current.json"
var busy:=false
var booting:=false
var load_failed:=false
var quitting:=false
var _was_enabled:=true
var _player_processing:=true

func is_locked() -> bool:return busy or booting or load_failed or quitting

func _message(text: String, error: bool=false) -> void:
	host.log_event({"type":"error" if error else "session_state","message":text})
	if is_instance_valid(host.menu):host.menu.session_status.text=text

func startup(scenario: String="") -> void:
	booting=true
	# 显式测试情境每次重建，不能与正式存档恢复并发，也不能覆盖正式进度。
	if not scenario.is_empty():path="user://sessions/fixture_"+scenario+".json"
	while not host.survival.ready_for_actions:await get_tree().physics_frame
	if not scenario.is_empty():
		match scenario:
			"luau-playtest":await host._prepare_luau_playtest()
			"gather-scenario":host.reset_gather_scenario()
			"help-scenario":host.reset_help_scenario()
			_:assert(false,"未知启动情境")
	elif FileAccess.file_exists(path):
		var error: String=await load_game()
		if not error.is_empty():
			load_failed=true;host.survival.enabled=false;host.get_parent().get_node("Player").set_physics_process(false);host.menu.open();_message(error+"；已暂停，原存档保留。",true)
	else:
		await host._record_scene_restart()
	booting=false

func _quiesce() -> String:
	_was_enabled=host.survival.enabled;_player_processing=host.get_parent().get_node("Player").is_physics_processing()
	host._allow_execution=false;host._input_generation+=1
	host.mic.cancel();host._pending_captures.clear();host.pipeline.cancel();host.tts.cancel()
	host._speech_queue.clear()
	if is_instance_valid(host._active_speech_output):host._active_speech_output._fail("存档操作中断播放")
	host.survival.enabled=false
	host.get_parent().get_node("Player").set_physics_process(false)
	for key in host.survival.gathering.offers.keys():host.survival.gathering._cancel_offer(key,"存档中断递物，物品仍在手中")
	host.survival.handover.cancel_giver("player")
	host._player_offers.clear()
	host.social_learning.reset()
	host.skills.checkpoint_stop()
	var deadline:=Time.get_ticks_msec()+5000
	while not host.skills.active.is_empty() or host._speech_busy:
		if Time.get_ticks_msec()>deadline:return "执行器尚未停止，未进行存取"
		await get_tree().physics_frame
	for actor in host.survival.actors.values():
		if actor.stage!="idle":return "人物仍在执行行动，未进行存取"
	host.busy=false;host._decisions_done=false
	return ""

func _continuity() -> Dictionary:
	return {"autonomy_clock":host._autonomy_clock,"cancelled_tasks":host._cancelled_player_tasks.duplicate(true),"superseded_tasks":host.store.superseded_tasks.duplicate(true),"independent_actions":host.store.independent_actions.duplicate(true),"requests":host.autonomy.requests.duplicate(true),"execution_feedback":host._execution_feedback.duplicate(true),"completed_assistance":host._completed_assistance.duplicate(true),"social_requests":host._social_requests.duplicate(true),"help_tasks":host.help_tasks.tasks.duplicate(true),"help_promises":host.help_tasks.promises.duplicate(true),"information_pending":host.information_waits.pending.duplicate(true),"information_checks":host.information_waits.checks.duplicate(true)}

func _resume_tasks(restored: bool=false) -> void:
	for id in host.store.working_tasks:
		var task: Dictionary=host.store.working_tasks[id]
		if task.get("state","") in ["completed","cancelled","refused","paused_budget"]:continue
		var original: Dictionary=task.request
		if original.is_empty():continue
		# 保存前已停止了执行协程。以新的恢复事件续办原请求，绝不重放保存前的调用参数。
		for index in range(host.autonomy.requests.size()-1,-1,-1):
			var queued: Dictionary=host.autonomy.requests[index]
			if id in queued.listeners and queued.get("original_event",{}).get("id","")==original.id:host.autonomy.requests.remove_at(index)
		task.state="interrupted_save"
		var event:={"id":host._new_id(),"kind":"session_restored" if restored else "session_checkpoint","speaker":"world","listeners":[id],"source_event_id":original.id,"original_event":original.duplicate(true),"text":("存档恢复" if restored else "保存检查点")+"：执行中的步骤已停止，已发生的世界变化保留。"}
		host.store.hear(id,event);host.autonomy.offer_request(event,host._autonomy_clock)
	host.store.memory.dirty=true

func _release_pause() -> void:
	host.survival.enabled=_was_enabled and not load_failed
	host.get_parent().get_node("Player").set_physics_process(_player_processing and not load_failed)
	busy=false

func save_game() -> String:
	if busy:return "已有存取操作正在进行"
	if load_failed:return "当前存档加载失败，禁止用初始化现场覆盖原存档"
	if not host.survival.ready_for_actions:return "世界尚未就绪"
	busy=true
	var error:=await _quiesce()
	if error.is_empty():
		_resume_tasks()
		error=Store.save(path,host.survival,host.skills.library,_continuity())
	_release_pause()
	_message("已保存世界、人物与技能；执行中的步骤已停止。" if error.is_empty() else error,not error.is_empty())
	return error

func load_game() -> String:
	if busy:return "已有存取操作正在进行"
	if not host.survival.ready_for_actions:return "世界尚未就绪"
	# 先校验完整文件；坏存档不取消当前现场的动作，也不半途替换数据。
	var checked:=Store.read(path,host.survival)
	if not checked.ok:return checked.error
	var continuity: Dictionary=checked.data.get("continuity",{})
	var error:=_validate_continuity(continuity)
	if not error.is_empty():return error
	busy=true
	error=await _quiesce()
	if not error.is_empty():_release_pause();return error
	Store.restore(host.survival,host.skills.library,checked)
	# 存档保留人物修订的版本；未自行修改的工程内置技能按当前实现升级。
	error=host.skills.library.install_builtins()
	if not error.is_empty():
		load_failed=true;_release_pause();return "恢复世界后更新内置技能失败："+error
	host._player_offers.clear();host._round_events.clear()
	host._cancelled_player_tasks=continuity.cancelled_tasks.duplicate(true);host._execution_feedback.clear();host._execution_feedback.append_array(continuity.execution_feedback)
	host._completed_assistance=continuity.completed_assistance.duplicate(true);host._social_requests=continuity.social_requests.duplicate(true)
	host._autonomy_clock=float(continuity.autonomy_clock);host.autonomy.reset(host._autonomy_clock)
	for event in continuity.requests:host.autonomy.offer_request(event,host._autonomy_clock)
	host.help_tasks.tasks=continuity.help_tasks.duplicate(true);host.help_tasks.promises=continuity.help_promises.duplicate(true)
	host.information_waits.pending=continuity.information_pending.duplicate(true);host.information_waits.checks=continuity.information_checks.duplicate(true)
	host.store.independent_actions=continuity.independent_actions.duplicate(true);host.store.superseded_tasks=continuity.superseded_tasks.duplicate(true)
	for id in host.store.people:
		host.skills.sync_person(id);host.captions[id].reset_display()
	host.social_learning.load_knowledge()
	_resume_tasks(true)
	if load_failed:_was_enabled=true;_player_processing=true
	load_failed=false
	_release_pause();_message("已恢复存档；未完成任务将依据恢复后的现场继续判断。")
	return ""

func _validate_continuity(data: Dictionary) -> String:
	if not (data.get("autonomy_clock") is float or data.get("autonomy_clock") is int) or not is_finite(data.autonomy_clock) or data.autonomy_clock<0:return "存档缺少有效游戏时钟"
	for key in ["requests","execution_feedback"]:
		if not data.get(key) is Array:return "存档续办队列损坏"
	for event in data.requests:
		if not event is Dictionary or not event.get("id") is String or not event.get("listeners") is Array or event.listeners.is_empty() or not event.get("speaker") is String or not event.get("text") is String:return "存档续办事件损坏"
		for id in event.listeners:
			if not host.store.people.has(id):return "存档续办人物无效"
	for result in data.execution_feedback:
		if not result is Dictionary or not host.store.people.has(result.get("person_id","")) or not result.get("food_origin") is Dictionary or result.get("material") not in ["food","water"]:return "存档受益反馈损坏"
	for key in ["cancelled_tasks","superseded_tasks","independent_actions","completed_assistance","social_requests","help_tasks","help_promises","information_pending","information_checks"]:
		if not data.get(key) is Dictionary:return "存档协作状态损坏"
	return ""

func quit_game(save: bool=true) -> void:
	if busy or quitting:return
	# 普通保存会恢复调度；退出保存必须一直锁到进程结束，避免又启动云端判断。
	quitting=true
	if save:
		var error:=await save_game()
		if not error.is_empty():quitting=false;host.menu.open();_message(error,true);return
	else:
		busy=true
		await _quiesce()
	get_tree().quit()
