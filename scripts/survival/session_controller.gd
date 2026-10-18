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
var _paused:=false
var _save_operation: Dictionary={}

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
		host.pipeline.reset_context_cache()
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
	if not load_failed:
		var recovery_error:=await _recover_requested_job()
		if not recovery_error.is_empty():
			load_failed=true;host.survival.enabled=false;host.get_parent().get_node("Player").set_physics_process(false);host.menu.open();_message(recovery_error+"；原存档保留。",true)
	booting=false

func _recover_requested_job() -> String:
	var jobs: Array[String]=[]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-learning-job="):jobs.append(argument.trim_prefix("--resume-learning-job="))
	if jobs.is_empty():return ""
	if jobs.size()!=1:return "一次启动只能恢复一个已验证任务"
	var job: String=jobs[0]
	var reports: Array[Dictionary]=[]
	var collect:=func(result: Dictionary):
		if result.job==job:reports.append(result)
	host.skills.learning_finished.connect(collect)
	var accepted: Dictionary=host.skills.recover_verified_job(job)
	if not accepted.ok:
		host.skills.learning_finished.disconnect(collect);return accepted.error
	if accepted.already_loaded:
		host.skills.learning_finished.disconnect(collect);_message("该任务的技能版本已经加载，无需重复恢复。");return ""
	while reports.is_empty() and host.skills.learning.has(accepted.person_id):await get_tree().process_frame
	host.skills.learning_finished.disconnect(collect)
	if reports.is_empty():return "恢复任务没有产生加载结果"
	if not reports[0].ok:return reports[0].message
	# 在启动锁仍有效、人物尚未重新行动时保存技能与世界同一检查点。
	var error:=await save_game()
	if not error.is_empty():return "技能恢复后保存检查点失败："+error
	_message("已恢复并保存已验证技能；未执行现场动作。")
	return ""

func _quiesce() -> String:
	if not _paused:
		_was_enabled=host.survival.enabled;_player_processing=host.get_parent().get_node("Player").is_physics_processing()
		_paused=true
	host._allow_execution=false;host._input_generation+=1
	host._checkpoint_internal_notifications()
	host.mic.cancel();host._pending_inputs.clear();host.pipeline.cancel();host.tts.cancel()
	# 存取失败也必须释放已撤销的判断；延期通知保留到恢复触发建立之后。
	host.busy=false;host._decisions_done=false
	host._speech_queue.clear()
	if is_instance_valid(host._active_speech_output):host._active_speech_output._fail("存档操作中断播放")
	host.survival.enabled=false
	host.survival.gathering.cancel_player_action()
	host.get_parent().get_node("Player").set_physics_process(false)
	for key in host.survival.gathering.offers.keys():host.survival.gathering._cancel_offer(key,"存档中断递物，物品仍在手中")
	host.survival.handover.cancel_giver("player")
	host.social_learning.reset()
	host.skills.checkpoint_stop()
	var deadline:=Time.get_ticks_msec()+5000
	while not host.skills.active.is_empty() or host._speech_busy:
		if Time.get_ticks_msec()>deadline:return "执行器尚未停止，未进行存取"
		await get_tree().physics_frame
	for actor in host.survival.actors.values():
		if actor.stage!="idle":return "人物仍在执行行动，未进行存取"
	var memory_error: String=await host.store.memory.flush_pending(get_tree())
	if not memory_error.is_empty():return memory_error
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
			if id in queued.listeners and queued.get("original_event",{}).get("id","")==original.id and host._notification_has_task(queued):host.autonomy.requests.remove_at(index)
		task.state="interrupted_save"
		var event:={"id":host._new_id(),"kind":"session_restored" if restored else "session_checkpoint","speaker":"world","listeners":[id],"source_event_id":original.id,"original_event":original.duplicate(true),"text":("存档恢复" if restored else "保存检查点")+"：执行中的步骤已停止，已发生的世界变化保留。"}
		host.store.hear(id,event);host.autonomy.offer_request(event,host._autonomy_clock)
		for index in range(host._deferred_judgments.size()-1,-1,-1):
			var deferred: Dictionary=host._deferred_judgments[index]
			if id in deferred.event.listeners and deferred.request_id==original.id:host._deferred_judgments.remove_at(index)
	host.store.memory.dirty=true

func _release_pause() -> void:
	if _paused and not quitting:
		host.survival.enabled=_was_enabled and not load_failed
		host.get_parent().get_node("Player").set_physics_process(_player_processing and not load_failed)
		_paused=false
	busy=false

func save_game() -> String:
	if busy:return "已有存取操作正在进行"
	if load_failed:return "当前存档加载失败，禁止用初始化现场覆盖原存档"
	if not host.survival.ready_for_actions:return "世界尚未就绪"
	busy=true
	var operation:={"error":"存档尚未完成"}
	_save_operation=operation
	_message("正在保存世界、人物与技能……")
	await get_tree().process_frame
	var error:=await _quiesce()
	if error.is_empty():
		_resume_tasks()
		error=await Store.save(path,host.survival,host.skills.library,get_tree(),_continuity())
	operation.error=error
	_release_pause()
	_message("已保存世界、人物与技能；执行中的步骤已停止。" if error.is_empty() else error,not error.is_empty())
	_save_operation={}
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
	host.pipeline.reset_context_cache()
	Store.restore(host.survival,host.skills.library,checked)
	# 存档保留人物修订的版本；未自行修改的工程内置技能按当前实现升级。
	error=host.skills.library.install_builtins()
	if not error.is_empty():
		load_failed=true;_release_pause();return "恢复世界后更新内置技能失败："+error
	host._pending_inputs.clear();host._deferred_judgments.clear();host._round_events.clear()
	host._cancelled_player_tasks=continuity.cancelled_tasks.duplicate(true);host._execution_feedback.clear();host._execution_feedback.append_array(continuity.execution_feedback)
	host._completed_assistance=continuity.completed_assistance.duplicate(true);host._social_requests=continuity.social_requests.duplicate(true)
	host._autonomy_clock=float(continuity.autonomy_clock);host.autonomy.reset(host._autonomy_clock)
	# 队列已经接受过这些事件；恢复原始ID，不能再按相同文本去重而丢掉不同来源的通知。
	host.autonomy.requests.assign(continuity.requests.duplicate(true))
	for event in host.autonomy.requests:
		host.autonomy.seen.append(event.id)
		if host.autonomy.seen.size()>256:host.autonomy.seen.pop_front()
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
	if quitting:return
	# 普通保存会恢复调度；退出保存必须一直锁到进程结束，避免又启动云端判断。
	quitting=true
	# 异步保存期间仍能收到关闭窗口事件。等待同一次保存结果，不丢请求或重复写盘。
	var pending_save:=_save_operation
	while busy:await get_tree().process_frame
	if save and not pending_save.is_empty() and not pending_save.error.is_empty():
		quitting=false;_release_pause();host.menu.open();_message(pending_save.error,true);return
	var bridge: Node=host.get_node_or_null("PlayerControl")
	if bridge!=null:
		var bridge_error: String=await bridge.stop_for_shutdown()
		if not bridge_error.is_empty():
			bridge.resume_after_shutdown_failure();quitting=false
			if _paused:_release_pause()
			host.menu.open();_message(bridge_error,true);return
	if save and pending_save.is_empty():
		var error:=await save_game()
		if not error.is_empty():
			if bridge!=null:bridge.resume_after_shutdown_failure()
			quitting=false;_release_pause();host.menu.open();_message(error,true);return
	elif not save:
		busy=true
		var error:=await _quiesce()
		if not error.is_empty():
			if bridge!=null:bridge.resume_after_shutdown_failure()
			quitting=false;_release_pause();host.menu.open();_message(error,true);return
	var audio_error: String=await host.mic.stop_for_shutdown()
	if not audio_error.is_empty():
		host.mic.prepare_continuous_input()
		if bridge!=null:bridge.resume_after_shutdown_failure()
		quitting=false;_release_pause();host.menu.open();_message(audio_error,true);return
	get_tree().quit()
