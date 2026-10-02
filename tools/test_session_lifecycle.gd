extends SceneTree
## 两个独立Godot进程使用正式菜单入口存取；本测试用独立存档、无云端调用。
var voice: Node
func _initialize():run.call_deferred()
func run():
 create_timer(90).timeout.connect(func():push_error("session lifecycle timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
 voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
 voice.session_manager.path="user://sessions/acceptance_cross_process.json"
 while not voice.survival.ready_for_actions:await physics_frame
 var sim: Node=voice.survival
 var id:="person_003";var actor: Dictionary=sim.actors[id]
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
  assert(sim.storage_food==2 and sim.gathering.hands.has(id))
  if "--write-running" in OS.get_cmdline_user_args():
   assert(voice.store.people[id].execution_results[-1].cancelled)
   assert(voice.store.people[id].execution_results[-1].message.contains("动作已停止"))
  print("SESSION_LIFECYCLE_WRITE_PASSED menu_save_pending_task_food")
 elif "--read" in OS.get_cmdline_user_args() or "--startup" in OS.get_cmdline_user_args():
  assert(sim.storage_food==3 and not sim.gathering.hands.has(id),"新进程最初使用场景默认状态")
  if "--startup" in OS.get_cmdline_user_args():
   await voice.session_manager.startup()
  else:
   var clicked: Button=voice.menu.find_child("Session_load",true,false)
   assert(clicked!=null);clicked.pressed.emit()
  while voice.session_manager.busy:await process_frame
  assert(voice.menu.session_status.text.begins_with("已恢复"),voice.menu.session_status.text)
  assert(sim.storage_food==2 and sim.gathering.hands.has(id),"恢复不能补回已拿出的食物")
  assert(voice.store.working_tasks[id].request.id=="persisted_order")
  assert(voice.store.working_tasks[id].state=="interrupted_save" and actor.stage=="idle")
  var queued: Array=voice.autonomy.requests.filter(func(e):return id in e.listeners and e.get("original_event",{}).get("id")=="persisted_order")
  assert(queued.size()==1 and queued[0].kind=="session_restored","未完成任务只排队判断一次，不重放动作")
  assert(voice.skills.active.is_empty() and not voice.busy)
  assert(voice._task_was_cancelled(id,{"id":"earlier_cancelled"}))
  assert(voice._task_was_cancelled(id,{"id":"earlier_replaced"}))
  print("SESSION_LIFECYCLE_READ_PASSED new_process_no_duplicate_food_task_requeued_not_executed")
 elif "--scenario-isolation" in OS.get_cmdline_user_args():
  var previous_path: String=voice.session_manager.path
  var previous_content:=FileAccess.get_file_as_string(previous_path)
  await voice.session_manager.startup("gather-scenario")
  assert(voice.session_manager.path=="user://sessions/fixture_gather-scenario.json")
  assert(sim.storage_food==0 and not voice.session_manager.is_locked())
  assert(FileAccess.get_file_as_string(previous_path)==previous_content,"初始化测试情境不得改写原存档")
  print("SESSION_SCENARIO_ISOLATION_PASSED fresh_fixture_separate_path")
 else:push_error("需指定生命周期测试模式");quit(1);return
 scene.queue_free();await create_timer(0.2).timeout;quit()
