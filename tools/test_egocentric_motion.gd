extends SceneTree
var moving: Dictionary={}
func _initialize() -> void: run.call_deferred()
func walk(api: Node, target: Dictionary) -> void:
	moving=await api.request("approach",{"object":target,"distance":0.45})
func run() -> void:
	create_timer(25).timeout.connect(func():push_error("egocentric motion journal timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/motion_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var sim: Node=voice.survival
	var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=voice.skills.world_objects;scene.add_child(api)
	assert(api.acquire().ok)
	var snapshot: Dictionary=await api.request("perceive",{})
	var point: Dictionary={}
	for sample in snapshot.near.ground_samples:
		if sample.probe.x==0 and sample.probe.z==2.25 and sample.state=="visible_surface": point=sample.position
	assert(not point.is_empty())
	var target: Dictionary={"observation_id":snapshot.observation_id,"position":point}
	var actor: Node3D=sim.actors.person_003.body
	var initial:=actor.global_position
	# 后续有别的观察，仍须按移动实际使用的旧观察号关联证据。
	var newer: Dictionary=await api.request("perceive",{})
	walk(api,target)
	for frame in 4: await physics_frame
	# 目标观察后路上出现障碍：验证碰撞停止，不调用全图绕行。
	var wall:=StaticBody3D.new();scene.add_child(wall)
	wall.global_position=initial+Vector3(0,0.8,1.0)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(3,2,0.1);collision.shape=box;wall.add_child(collision)
	var deadline:=Time.get_ticks_msec()+12000
	var side_drift:=0.0
	while moving.is_empty() and Time.get_ticks_msec()<deadline:
		await physics_frame;side_drift=maxf(side_drift,absf(actor.global_position.x-initial.x))
	assert(not moving.is_empty() and not moving.ok,"障碍应导致失败，不是默默绕路")
	assert(side_drift<0.1,"不能自行选择绕行路径")
	var trace: Array=[{"operation":"perceive","result":snapshot},{"operation":"perceive","result":newer},{"operation":"approach","arguments":{"object":target},"result":moving}]
	# 合成无位移尾部摘要，只检验超过控制器32条截断后的历史保留。
	for index in 40:trace.append({"operation":"look_toward","result":{"ok":true,"code":"turned"}})
	var runtime:={"status":"completed","trace":trace,"returned":{"ok":true,"movements":[{"ok":true,"code":"伪造成功"}]}}
	var journal=preload("res://scripts/skills/execution_journal.gd")
	var actual: Dictionary=journal.execution_evidence({"target":"water_source","note":"private_parameter"},{"target":"reference","note":"text"},runtime)
	var movement: Dictionary=actual.movement_history.entries[0]
	assert(actual.movement_history.complete and movement.evidence_complete and not movement.ok and movement.code==moving.code)
	assert(movement.observation_id==snapshot.observation_id and not movement.observation_immediately_preceded,"不能误用最近观察")
	assert(movement.standing_position==moving.standing_position and movement.requested_target==target)
	assert(movement.references.has("water_source") and not movement.references.has("private_parameter"),"只保存已验证reference关联的本人知识")
	assert(not movement.has("ground_samples") and not movement.has("returned"),"方法自报与完整取景不能混作真实路线")
	var record:={"person_id":"person_003","source_event_id":"motion","runtime":runtime,"message":"运动证据"}
	record.merge(actual)
	var event:={"result":record};preload("res://scripts/skills/egocentric_space.gd").sanitize_event(event)
	var restored: Dictionary=JSON.parse_string(JSON.stringify(event.result))
	var context: Dictionary=journal.context("person_003","request",[restored])
	var restored_standing: Dictionary=context.calls[0].movements[0].standing_position
	var error_m:=0.0
	for axis in ["x","y","z"]:error_m=maxf(error_m,absf(restored_standing.position[axis]-moving.standing_position.position[axis]))
	print("JOURNAL_RESTORE_DIAGNOSTIC ",JSON.stringify({"target":context.calls[0].arguments.target,"observation_id_retained":restored_standing.observation_id==moving.standing_position.observation_id,"max_position_error_m":error_m}))
	assert(context.calls[0].arguments.target=="water_source" and restored_standing.observation_id==moving.standing_position.observation_id and error_m<0.000001,"摘要裁剪及JSON存取不能丢失旧失败运动")
	context.calls[0].movements[0].ok=true
	assert(not journal.context("person_003","request",[restored]).calls[0].movements[0].ok,"上下文修改不得回写历史")
	var cancelled:=runtime.duplicate(true);cancelled.status="cancelled"
	assert(not journal.execution_evidence({"target":"water_source"},{},cancelled).movement_history.complete,"取消不能声称覆盖最后部分位移")
	var missing:=runtime.duplicate(true);missing.trace=trace.slice(1)
	var unavailable: Dictionary=journal.execution_evidence({"target":"water_source"},{},missing).movement_history
	assert(not unavailable.complete and not unavailable.entries[0].evidence_complete and not unavailable.entries[0].has("standing_position"),"缺少来源帧不得拼接另一个观察或伪造站位")
	var direct_trace: Array=[trace[2]]
	var retained: Dictionary=api.argument_motion_frames(direct_trace)
	assert(retained.has(snapshot.observation_id) and not retained[snapshot.observation_id].has("near"))
	var direct: Dictionary=journal.execution_evidence({"target":"water_source"},{},{"status":"completed","trace":direct_trace,"argument_frames":retained}).movement_history
	assert(direct.complete and direct.entries[0].evidence_complete)
	assert(direct.entries[0].observation_source=="retained_argument_frame" and not direct.entries[0].observation_immediately_preceded)
	assert(direct.entries[0].references.is_empty() and direct.entries[0].standing_position==moving.standing_position,"旧帧只能补运动证据，不能补造旧视野")
	var both:=runtime.duplicate(true);both["argument_frames"]=retained.duplicate(true)
	both.argument_frames[snapshot.observation_id].request_odometry.position.x=99999
	var preferred: Dictionary=journal.execution_evidence({"target":"water_source"},{},both).movement_history.entries[0]
	assert(preferred.observation_source=="execution_query" and preferred.request_odometry==snapshot.request_odometry and preferred.references.has("water_source"),"完整观察优先，不得被参数帧覆盖")
	var wrong:=direct_trace.duplicate(true);wrong[0].result.standing_position.observation_id=newer.observation_id
	assert(not journal.execution_evidence({},{},{"status":"completed","trace":wrong,"argument_frames":retained}).movement_history.entries[0].evidence_complete,"坐标帧与站位不匹配不能补全")
	for other in ["person_003","person_002"]:
		var unleased: Dictionary=sim.space.capture(other)
		assert(api.argument_motion_frames([{"operation":"approach","arguments":{"object":{"observation_id":unleased.id,"position":point}}}]).is_empty(),"未租用或他人帧不可导出")
	assert(api.argument_motion_frames([]).is_empty())
	var invalid:=target.duplicate(true);invalid["ground_samples"]={"forged":"不得进入历史"}
	var rejected: Dictionary=journal.execution_evidence({},{},{"status":"completed","trace":[{"operation":"approach","arguments":{"object":invalid},"result":{"ok":false,"code":"invalid_target"}}]}).movement_history.entries[0]
	assert(rejected.requested_target.is_empty() and not rejected.evidence_complete,"被世界拒绝的额外字段不能进入运动历史")
	await api.finish()
	# 不显式绑定请求的接口复用必须从当前站位起算，不能拿旧观察作独立请求起点。
	actor.rotation.y+=PI/2
	assert(api.acquire().ok)
	var independent: Dictionary=await api.request("perceive",{})
	assert(independent.request_odometry.request_id!=snapshot.request_odometry.request_id)
	assert(Vector2(independent.request_odometry.position.x,independent.request_odometry.position.z).length()<.1)
	await api.finish()
	print("EGOCENTRIC_MOTION_PASSED collision_stops_selected_segment_no_automatic_detour; movement_journal_old_frame_real_failure_saved_without_trace_self_report_cancel_missing_frame")
	scene.queue_free();await create_timer(0.2).timeout;quit()
