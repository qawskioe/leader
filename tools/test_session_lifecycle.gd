extends SceneTree
## 两个独立Godot进程使用正式菜单入口存取；本测试用独立存档、无云端调用。
var voice: Node
class DelayedGateway extends Node:
 func exchange(_payload: Dictionary) -> Dictionary:
  await get_tree().create_timer(.4).timeout
  return {"ok":false,"error":"independent notification fixture"}
func _initialize():run.call_deferred()
func run():
 create_timer(90).timeout.connect(func():push_error("session lifecycle timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
 voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
 voice.session_manager.path="user://sessions/acceptance_cross_process.json"
 if "--independent-write" in OS.get_cmdline_user_args() or "--independent-read" in OS.get_cmdline_user_args():voice.session_manager.path="user://sessions/acceptance_internal_notifications.json"
 while not voice.survival.ready_for_actions:await physics_frame
 var sim: Node=voice.survival
 var id:="person_003";var actor: Dictionary=sim.actors[id]
 var cache_scope: String=voice.pipeline.context_cache_scope()
 if "--write" in OS.get_cmdline_user_args() or "--write-running" in OS.get_cmdline_user_args() or "--quit-save" in OS.get_cmdline_user_args():
  actor.body.global_position=sim.STORAGE+Vector3(0,.06,-.8);actor.body.rotation.y=0
  for frame in 10:await physics_frame
  sim.perception.observe(id)
  assert(sim.life_world.take_unit(id,"storage").ok)
  var original:={"id":"persisted_order","speaker":"player","kind":"speech_intent","text":"把手中的食物带给小花"}
  voice.store.hear(id,original)
  voice.store.working_tasks[id]={"request":original,"state":"action_submitted","action_event_id":original.id,"progress":[]}
  if "--write-running" in OS.get_cmdline_user_args():
   var ref:=""
   for skill in voice.skills.library.describe(id):
    if skill.id=="bring_to_mouth":ref=skill.ref
   assert(not ref.is_empty())
   assert(voice.skills.invoke(id,original.id,{"ref":ref,"arguments":{}}).ok)
   var until:=Time.get_ticks_msec()+10000
   while voice.skills.active.has(id) and voice.skills.active[id].runner._pending_operations==0 and Time.get_ticks_msec()<until:await process_frame
   assert(voice.skills.active.has(id) and voice.skills.active[id].runner._pending_operations>0,"必须在计时消费执行中保存")
  voice._cancelled_player_tasks[id+"/earlier_cancelled"]=true
  voice.store.superseded_tasks[id+"/earlier_replaced"]=original.id
  if "--quit-save" in OS.get_cmdline_user_args():
   print("SESSION_QUIT_SAVE_REQUESTED")
   voice._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
   return
  var clicked: Button=voice.menu.find_child("Session_save",true,false)
  assert(clicked!=null);clicked.pressed.emit()
  while voice.session_manager.busy:await process_frame
  assert(FileAccess.file_exists(voice.session_manager.path))
  assert(voice.menu.session_status.text.begins_with("已保存"),voice.menu.session_status.text)
  assert(voice.pipeline.context_cache_scope()==cache_scope,"正常保存没有撤掉记忆，不需要切换缓存域")
  assert(sim.storage_food==2 and sim.gathering.hands.has(id))
  if "--write-running" in OS.get_cmdline_user_args():
   assert(voice.store.people[id].execution_results[-1].cancelled)
   assert(voice.store.people[id].execution_results[-1].message.contains("动作已停止"))
  print("SESSION_LIFECYCLE_WRITE_PASSED menu_save_pending_task_food")
 elif "--read" in OS.get_cmdline_user_args() or "--startup" in OS.get_cmdline_user_args():
  assert(sim.storage_food==3 and not sim.gathering.hands.has(id),"新进程最初使用场景默认状态")
  voice.captions[id].show_execution_result({"success":true,"intent":"rest","message":"读档前夹具结果"})
  assert(not voice.captions[id].execution_text.is_empty())
  if "--startup" in OS.get_cmdline_user_args():
   await voice.session_manager.startup()
  else:
   var clicked: Button=voice.menu.find_child("Session_load",true,false)
   assert(clicked!=null);clicked.pressed.emit()
  while voice.session_manager.busy:await process_frame
  assert(voice.menu.session_status.text.begins_with("已恢复"),voice.menu.session_status.text)
  assert(voice.pipeline.context_cache_scope()!=cache_scope,"实际读档必须阻止复用已回滚的经历基准")
  assert(sim.storage_food==2 and sim.gathering.hands.has(id),"恢复不能补回已拿出的食物")
  assert(voice.store.working_tasks[id].request.id=="persisted_order")
  assert(voice.store.working_tasks[id].state=="interrupted_save" and actor.stage=="idle")
  var queued: Array=voice.autonomy.requests.filter(func(e):return id in e.listeners and e.get("original_event",{}).get("id")=="persisted_order")
  assert(queued.size()==1 and queued[0].kind=="session_restored","未完成任务只排队判断一次，不重放动作")
  assert(voice.skills.active.is_empty() and not voice.busy)
  assert(voice.captions[id].execution_text.is_empty(),"读档不能把旧世界执行结果继续显示成当前反馈")
  assert(voice._task_was_cancelled(id,{"id":"earlier_cancelled"}))
  assert(voice._task_was_cancelled(id,{"id":"earlier_replaced"}))
  print("SESSION_LIFECYCLE_READ_PASSED new_process_no_duplicate_food_task_requeued_not_executed")
 elif "--deferred-failure" in OS.get_cmdline_user_args():
  voice.set_process(false)
  var original:={"id":"deferred_order","speaker":"player","kind":"speech_intent","text":"把原袋还给我"}
  voice.store.hear(id,original)
  voice.store.working_tasks[id]={"request":original,"state":"awaiting_judgement","action_event_id":"take_bag","progress":[]}
  var deferred:={"event":{"id":"pending_result","speaker":"world","kind":"task_observation_changed","listeners":[id],"original_event":original,"text":"重新看见请求者"},"task_bound":true,"request_id":original.id,"action_event_id":"take_bag"}
  voice._deferred_judgments.append(deferred)
  voice.busy=true;actor.stage="fixture_not_stopped"
  var failed: String=await voice.session_manager.save_game()
  assert(failed.contains("人物仍在执行") and not voice.session_manager.is_locked())
  assert(not voice.busy and voice._deferred_judgments==[deferred],"保存失败不能卡住判断或丢掉延期任务触发")
  actor.stage="idle"
  assert((await voice.session_manager.save_game()).is_empty())
  var queued: Array=voice.autonomy.requests.filter(func(e):return e.get("original_event",{}).get("id")==original.id)
  assert(queued.size()==1 and queued[0].kind=="session_checkpoint")
  assert(voice._deferred_judgments.is_empty(),"恢复触发已经建立，不再重复旧确认")
  print("SESSION_DEFERRED_FAILURE_PASSED observation_failure_preserves_trigger_unlocks_success_checkpoint_once")
 elif "--independent-write" in OS.get_cmdline_user_args() or "--independent-read" in OS.get_cmdline_user_args():
  voice.set_process(false);voice.config.local_only=false
  var fake:=DelayedGateway.new();voice.add_child(fake);voice.pipeline.gateway=fake
  var requests_path: String=voice.session_manager.path
  var wanted: Array=["checkpoint_need","checkpoint_benefit","checkpoint_benefit_second","checkpoint_independent_question"]
  if "--independent-write" in OS.get_cmdline_user_args():
   var need:={"id":wanted[0],"speaker":"body","kind":"need_changed","listeners":[id],"text":"隔离身体需求通知"}
   var benefit:={"id":wanted[1],"speaker":"world","kind":"assistance_completed","listeners":[id],"text":"隔离已发生受益通知，仅验证触发持久化","result":{"person_id":id,"material":"food"},"assistance":{"giver_id":"person_002","recipient_id":id}}
   var second: Dictionary=benefit.duplicate(true);second.id=wanted[2];second.assistance.giver_id="person_001"
   var original:={"id":"checkpoint_active_order","speaker":"player","kind":"speech_intent","text":"未完成的明确请求"}
   voice.store.hear(id,original)
   voice.store.working_tasks[id]={"request":original,"action_event_id":"task_action","state":"awaiting_judgement","progress":[]}
   voice.store.independent_actions[id+"/body_independent"]=true
   var question:={"id":wanted[3],"speaker":"world","kind":"information_unanswered","listeners":[id],"original_event":original,"source_event_id":"body_independent","text":"独立身体轮次的询问超时"}
   assert(voice.autonomy.offer_request(need,voice._autonomy_clock));voice.autonomy.requests.clear()
   voice.store.hear(id,need);voice._deferred_judgments.append(voice._deferred_judgment(need))
   voice.store.hear(id,second);voice._deferred_judgments.append(voice._deferred_judgment(second))
   voice.store.hear(id,question);voice._deferred_judgments.append(voice._deferred_judgment(question))
   assert(voice.autonomy.offer_request(benefit,voice._autonomy_clock));voice.autonomy.requests.clear()
   voice.busy=true;voice._job_config=voice.config.duplicate(true);voice._start_pipeline(benefit,voice._job_config)
   actor.stage="fixture_unstopped"
   var failed: String=await voice.session_manager.save_game()
   assert(not failed.is_empty() and not voice.session_manager.is_locked())
   assert(voice._deferred_judgments.is_empty() and voice.autonomy.requests.size()==4,"失败存取须保留已延期和仍在途独立通知，各一次")
   actor.stage="idle"
   var blocker:="user://sessions/internal_block_%d"%Time.get_ticks_usec()
   var file:=FileAccess.open(blocker,FileAccess.WRITE);file.store_string("fixture parent file");file.close()
   voice.session_manager.path=blocker+"/child.json"
   assert(not (await voice.session_manager.save_game()).is_empty(),"真实文件父路径冲突必须写入失败")
   print("INDEPENDENT_CHECKPOINT_COUNT pending=",voice.autonomy.requests.size()," locked=",voice.session_manager.is_locked())
   if voice.autonomy.requests.size()!=5 or voice.session_manager.is_locked():
    push_error("任务检查点误删带原请求的独立通知");quit(1);return
   voice.session_manager.path=blocker
   var before: Array=voice.autonomy.requests.duplicate(true)
   assert(not (await voice.session_manager.load_game()).is_empty() and voice.autonomy.requests==before,"坏存档校验不能丢当前通知")
   voice.session_manager.path=requests_path
   assert((await voice.session_manager.save_game()).is_empty())
   var saved: Dictionary=preload("res://scripts/survival/session_store.gd").read(requests_path,sim)
   if not saved.ok or saved.data.continuity.requests.size()!=5:
    push_error("独立通知检查点校验失败："+str(saved.get("error","通知数量错误")));quit(1);return
   for event in saved.data.continuity.requests:
    assert((event.id in wanted or event.kind=="session_checkpoint") and not event.has("task_bound") and not event.has("request_id"),"存档队列只含原始事件，不发送延期控制包装")
   DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
   print("SESSION_INDEPENDENT_WRITE_PASSED inflight_deferred_seen_preserved_quiesce_write_bad_load_failures_exactly_once")
  else:
   var future:={"id":"future_not_saved","speaker":"body","kind":"need_changed","listeners":[id],"text":"当前世界中尚未保存的通知"}
   voice.store.hear(id,future);voice._deferred_judgments.append(voice._deferred_judgment(future))
   assert((await voice.session_manager.load_game()).is_empty())
   if not voice._deferred_judgments.is_empty() or voice.autonomy.requests.size()!=5:
    push_error("读档丢失同文本但不同来源的已接受通知，或混入未来通知");quit(1);return
   var reports: Array=[];voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report.event_id))
   for event in voice.autonomy.requests:assert(event.id in wanted or event.kind=="session_restored")
   assert(not voice.config.autonomy_enabled,"关闭新自主判断也须恢复已有待办")
   var restored_id: String=voice.autonomy.requests.filter(func(event):return event.kind=="session_restored")[0].id
   # 已排队的恢复事件与身体通知先合并；此网关故意失败，原身体随后仍须独立恢复。
   for index in 5:
    assert(voice._resume_deferred_judgment())
    await create_timer(.5).timeout
   assert(reports.size()==5 and reports.count(restored_id)==1)
   for event_id in wanted:assert(reports.count(event_id)==1)
   assert(not voice._resume_deferred_judgment() and voice.autonomy.requests.is_empty())
   assert(sim.storage_food==3 and voice.skills.active.is_empty(),"恢复判断不重放世界结算")
   print("SESSION_INDEPENDENT_READ_PASSED new_process_original_events_only_no_future_autonomy_off_resume_once_no_settlement")
  await create_timer(.5).timeout
 elif "--audio-close-failure" in OS.get_cmdline_user_args():
  voice.set_process(false)
  sim.enabled=true
  var player: Node=scene.get_node("Player");player.set_physics_process(true)
  # 仅夹具持有额外强引用，强制真实释放条件超时，不假造关闭结果。
  var retained: AudioStream=voice.mic.player.stream
  var probe:={"guarded":false}
  (func():
   assert(voice.mic._closing_input)
   voice.mic.prepare_continuous_input();voice.mic.start()
   assert(voice.mic.player.stream==null and not voice.mic.recording)
   assert(not await voice.mic.recover_connection("Default"))
   probe.guarded=true
  ).call_deferred()
  await voice.session_manager.quit_game(false)
  assert(probe.guarded and not voice.session_manager.is_locked())
  assert(sim.enabled and player.is_physics_processing(),"关闭失败不能留下暂停世界或冻结玩家")
  assert(voice.menu.is_open() and voice.menu.session_status.text.contains("收音资源尚未释放"))
  assert(not voice.mic._closing_input and voice.mic.continuous_input and voice.mic.player.stream!=null)
  retained=null
  assert((await voice.mic.stop_for_shutdown()).is_empty(),"释放额外引用后须能收束新旧两份资源")
  print("SESSION_AUDIO_CLOSE_FAILURE_PASSED closing_blocks_rewarm_record_reconnect_timeout_unlocks_world_player_retry_releases")
 elif "--scenario-isolation" in OS.get_cmdline_user_args():
  var previous_path: String=voice.session_manager.path
  var previous_content:=FileAccess.get_file_as_string(previous_path)
  await voice.session_manager.startup("gather-scenario")
  assert(voice.session_manager.path=="user://sessions/fixture_gather-scenario.json")
  assert(sim.storage_food==0 and not voice.session_manager.is_locked())
  assert(FileAccess.get_file_as_string(previous_path)==previous_content,"初始化测试情境不得改写原存档")
  print("SESSION_SCENARIO_ISOLATION_PASSED fresh_fixture_separate_path")
 else:push_error("需指定生命周期测试模式");quit(1);return
 assert((await voice.mic.stop_for_shutdown()).is_empty())
 scene.queue_free();await create_timer(0.2).timeout;quit()
