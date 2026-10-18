extends SceneTree
## 隔离UI/任务边界；结果是夹具，不改正式存档，不调用人物模型或TTS。
const Voice=preload("res://scripts/voice/voice_test.gd")
var voice: Node
var caption: Node

func _initialize() -> void:run.call_deferred()

func check(value: bool, message: String) -> bool:
	if value:return true
	push_error(message);quit(1);return false

func result(event_id: String, success: bool, cancelled: bool=false) -> Dictionary:
	return {"person_id":"person_004","source_event_id":event_id,"intent":"skill","skill_name":"递交物品","success":success,"cancelled":cancelled,"message":"仅用于执行经历的详细诊断","world_facts":[],"runtime":{}}

func run() -> void:
	root.size=Vector2i(960,540)
	create_timer(35).timeout.connect(func():push_error("immediate feedback timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	voice=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.local_only=true;voice.config.tts_enabled=false;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	voice.survival.enabled=false;voice.menu.close();caption=voice.captions.person_004
	var player: Node3D=scene.get_node("Player")
	player.global_position=caption.global_position+Vector3(0,0,2.4);player.rotation.y=0
	await physics_frame
	var request:={"id":"feedback_request","speaker":"player","kind":"speech_intent","listeners":["person_004"],"text":"把物品交给我"}
	voice._round_events[request.id]=request
	voice.store.working_tasks.person_004={"request":request,"action_event_id":request.id,"progress":[],"state":"execute"}
	voice.busy=true;voice._speech_order=["person_004"];voice._reports_received.clear()
	var emitted_at:=Time.get_ticks_msec()
	voice.skills.finished.emit(result(request.id,true))
	caption._process(0)
	var visible_after_ms:=Time.get_ticks_msec()-emitted_at
	if not check(visible_after_ms<1000,"实际执行回执到首帧显示超过1秒"):return
	print("FEEDBACK_VISIBLE_AFTER_MS ",visible_after_ms)
	print("FEEDBACK_BEFORE_MODEL ",caption.head_panel.status.text.left(100))
	if not check(caption.head_panel.status.visible and caption.head_panel.status.text.contains("实际结果"),"模型尚未返回时实际执行结果没有成为可读状态"):return
	if not check(voice.execution_note.visible and voice.execution_note.text.contains("实际结果"),"头顶超出视口时仍须有可读的屏幕结果"):return
	if not check(caption.public_text.is_empty() and not caption.speaking,"程序结果不能伪造人物台词"):return
	if not check(voice.store.working_tasks.person_004.state=="awaiting_judgement","操作结束不能直接判定原请求完成"):return
	if not check(not caption.head_panel.status.text.contains("详细诊断"),"执行技术诊断不能直接成为玩家反馈"):return
	var given:=result("feedback_given",true)
	given.world_facts=[{"kind":"given","material":"water","recipient_id":"player","quantity":2}]
	voice.skills.finished.emit(given);caption._process(0)
	if not check(caption.head_panel.status.text.contains("交给玩家水2份"),"真实资源回执须保留具体数量与接收者"):return
	voice.skills.finished.emit(result("feedback_cancelled",false,true));caption._process(0)
	if not check(caption.head_panel.status.text.contains("已中断"),"取消结果须立即区分于成功"):return
	voice.skills.finished.emit(result("feedback_failed",false));caption._process(0)
	if not check(caption.head_panel.status.text.contains("未完成"),"失败不能显示为任务完成"):return
	var waiting:=result("feedback_waiting_player",false)
	waiting.runtime={"status":"completed","returned":{"code":"waiting_for_player","completed":false}}
	voice.skills.finished.emit(waiting);caption._process(0)
	if not check(voice.execution_note.text.contains("未完成") and not voice.execution_note.text.contains("受阻"),"等待玩家没有发生失败世界操作，不能推断为受阻"):return
	# 空容器没有物资数量事实；反馈仍须保留宿主实际交接及失败原因。
	var failed:=result("feedback_occupied",false)
	failed.runtime={"returned":{"ok":false,"message":"技能自报的内部诊断"},"trace":[{"operation":"handover","result":{"ok":false,"code":"recipient_occupied","message":"接收者没有可用的接物手，需先腾出手；未发生交付"}}]}
	voice.skills.finished.emit(failed);caption._process(0)
	if not check(voice.execution_note.text.contains("先腾出手") and not voice.execution_note.text.contains("技能自报"),"真实交付失败原因被丢弃，或技能自报被当成事实"):return
	var hint: Label=voice.survival.gathering.interaction_hint
	await process_frame;hint.show()
	voice.execution_note.position=Vector2(12,root.size.y-80)
	voice._position_execution_note()
	print("FEEDBACK_FOOTER_LAYOUT ",JSON.stringify({"hint_visible":hint.is_visible_in_tree(),"note_bottom":voice.execution_note.get_global_rect().end.y,"hint_top":hint.get_global_rect().position.y}))
	if not check(voice.execution_note.get_global_rect().end.y+8<=hint.get_global_rect().position.y,"长结果提示侵入了底部交互区域"):return
	var empty:=result("feedback_empty_container",true)
	empty.runtime={"trace":[{"operation":"handover","result":{"ok":true,"code":"transferred","object":"basket/1","recipient_id":"player"}}]}
	empty.feedback_details=voice.skills.execution_feedback_details(empty)
	voice.skills.finished.emit(empty);caption._process(0)
	if not check(voice.execution_note.text.contains("篮子") and voice.execution_note.text.contains("交给玩家"),"空容器交接缺少实际物品及接收者"):return
	if not check(not voice.store.people.person_004.execution_results[-1].has("feedback_details"),"玩家显示摘要不能重复进入人物记忆"):return
	var private_failure:=result("feedback_private_failure",false)
	private_failure.runtime={"trace":[{"operation":"recall_locations","result":{"ok":false,"message":"本人私下线索"}}]}
	voice.skills.finished.emit(private_failure);caption._process(0)
	if not check(not voice.execution_note.text.contains("私下线索"),"感知或回忆诊断不能当成公开执行结果"):return
	var recovered:=result("feedback_recovered_failure",false)
	recovered.runtime={"trace":[{"operation":"approach","result":{"ok":false,"message":"已绕开的旧障碍"}},{"operation":"approach","result":{"ok":true,"message":"已经走到"}}]}
	voice.skills.finished.emit(recovered);caption._process(0)
	if not check(not voice.execution_note.text.contains("旧障碍"),"已恢复的旧失败不能冒充当前受阻原因"):return
	caption.execution_until=0;caption._process(0)
	if not check(not caption.head_panel.status.text.contains("实际结果"),"过期结果不能永久伪装成当前状态"):return
	voice.skills.finished.emit(result("feedback_reset",true));caption.reset_display();caption._process(0)
	voice._position_execution_note()
	if not check(not caption.head_panel.status.text.contains("实际结果"),"读档/重置显示不能残留另一现场的结果"):return
	if not check(not voice.execution_note.visible,"读档/重置不能残留屏幕结果"):return
	var ordinary:=result("feedback_ordinary",true);ordinary.intent="rest";ordinary.message="已停下，保留手中物品"
	voice.survival.action_result.emit(ordinary);caption._process(0)
	if not check(caption.head_panel.status.text.contains(ordinary.message),"基础动作信号也须进入同一反馈入口"):return
	voice._execution_note_until=0;caption.visible=false
	voice.skills.finished.emit(result("feedback_unseen",true));voice._position_execution_note()
	if not check(not voice.execution_note.visible,"看不到的人物结果不能成为全知屏幕提示"):return
	if not check(voice._reports_received.is_empty(),"本夹具未取得模型决定"):return
	print("IMMEDIATE_EXECUTION_FEEDBACK_PASSED pending_model_visible_result_no_fabricated_speech_task_not_completed_cancel_failure_expiry; cloud_calls=0")
	voice.busy=false;assert((await voice.mic.stop_for_shutdown()).is_empty());scene.queue_free();await create_timer(0.2).timeout;quit()
