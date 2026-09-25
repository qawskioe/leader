extends SceneTree
const Autonomy=preload("res://scripts/survival/autonomy.gd")
const Tasks=preload("res://scripts/survival/help_tasks.gd")
const Voice=preload("res://scripts/voice/voice_test.gd")
class OfflinePipeline extends Node:
	func run(_event: Dictionary, _job: Dictionary) -> void: pass
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scheduler:=Autonomy.new()
	var people:={"a":{"needs":{"hunger":85},"survival_observation":{"storage_food_seen":0}}}
	var actors:={"a":{"stage":"idle"}}
	var first:=scheduler.next_event(8,people,actors)
	assert(first.trigger.reason=="need_initial")
	var retry:=scheduler.next_event(98,people,actors)
	assert(retry.trigger.reason=="need_retry" and retry.trigger.elapsed_seconds==90 and retry.source_event_id==first.id)
	people.a.survival_observation.storage_food_seen=1
	var changed:=scheduler.next_event(120,people,actors)
	assert(changed.trigger.reason=="need_changed" and changed.trigger.changes.storage_food_seen.after==1)
	var tasks:=Tasks.new()
	var aid:={"request_id":"request","requester_id":"person_002","helper_id":"person_004","request_text":"能帮我拿些食物吗？"}
	tasks.accept(aid,"person_004",0,"request")
	tasks.result({"person_id":"person_004","source_event_id":"request","success":false,"intent":"fetch_food","message":"路线受阻，未拿到食物","assistance":aid},10)
	var next:=tasks.next_event(12,{"person_004":{"stage":"idle"}})
	assert(next.trigger.reason=="help_result" and next.source_event_id=="request")
	assert(tasks.next_event(103,{"person_004":{"stage":"idle"}}).trigger.reason=="help_retry")
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	voice.name="VoiceTest"
	scene.add_child(voice)
	voice.config.local_only=true; voice.config.autonomy_enabled=false
	voice.survival.enabled=false
	voice.pipeline.queue_free()
	voice.pipeline=OfflinePipeline.new()
	voice.add_child(voice.pipeline)
	while not voice.survival.ready_for_actions: await physics_frame
	voice.menu.close()
	var request:={"id":"request","kind":"social_request","speaker":"person_002","text":"能帮我拿些食物吗？","listeners":["person_004"]}
	voice._start_pipeline(request,{})
	var caption: Node=voice.captions.person_004
	assert(caption.turn_heading.text=="回应小花的请求" and caption.turn_cause.text.contains(request.text))
	voice._start_pipeline(next,{})
	assert(caption.turn_heading.text=="继续处理小花的求助" and caption.turn_cause.text.contains("路线受阻"))
	assert(caption.turn_purpose.text.contains(aid.request_text))
	var heading: String=caption.turn_heading.text
	voice.log_event({"type":"action_result","result":{"person_id":"person_004","source_event_id":"request","success":true,"message":"旧轮次结果"}})
	assert(caption.turn_heading.text==heading and not caption.public_state.contains("旧轮次"))
	var tree: Tree=caption.details
	var current: TreeItem=tree.turns[next.id]
	var card: TreeItem=current.get_child(1)
	var origin: TreeItem=card.get_first_child()
	assert(origin.get_text(0)=="本轮来由")
	var source: TreeItem=origin.get_child(3)
	assert(source.get_metadata(0)=="request")
	source.select(0); tree.item_activated.emit()
	assert(tree.get_selected()==tree.turns.request)
	# 不开启云端；实际窗口检查头顶的来由是否能直接读到。
	var player: CharacterBody3D=scene.get_node("Player")
	player.set_physics_process(false)
	player.position=Vector3(0,0.3,8)
	scene.get_node("People/Person04").position=Vector3(0,0.1,3.8)
	player.camera.look_at(Vector3(0,1.6,3.8))
	for id in voice.captions:
		if id!="person_004":
			voice.captions[id].set_process(false)
			voice.captions[id].bubble.hide(); voice.captions[id].leader_line.hide()
	if DisplayServer.get_name()!="headless":
		for frame in 6: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/turn_context.png")
	print("TURN_CONTEXT_PASSED: initial, retry, changed, help_result, help_retry, source_navigation, stale_event_guard; cloud_calls=0")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
