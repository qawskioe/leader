extends SceneTree
static func completed_goal(before: Vector3, after: Vector3, reference: Vector3, held: String, idle: bool, errors: bool, verified: bool) -> bool:
	# 5厘米仅用于排除物理抖动；模型自行决定具体方向和距离。
	return idle and not errors and verified and held.is_empty() and Vector2(after.x-reference.x,after.z-reference.z).length()>Vector2(before.x-reference.x,before.z-reference.z).length()+0.05
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	var audit=preload("res://tools/test_release_physics.gd").AuditObjects.new()
	voice.skills.add_child(audit);voice.skills.world_objects=audit
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/fuzzy_%d.json"%Time.get_ticks_usec())
	voice.config.tts_enabled=false
	var refs: Dictionary={}
	for entry in voice.skills.library.describe("person_003"): refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	for goal in ["take_object","place_object"]:
		var args: Dictionary={"object":"wood_block"}
		if goal=="place_object": args.target=ground_target(voice.survival,"person_003")
		assert(voice.skills.invoke("person_003","setup_"+goal,{"ref":refs[goal],"arguments":args}).ok)
		var result: Dictionary=await voice.skills.finished
		if not result.success:
			print("FUZZY_SETUP_FAILED ",result);scene.queue_free();await create_timer(0.2).timeout;quit(1);return
	var before: Vector3=voice.skills.world_objects.objects.wood_block.body.global_position
	var reference: Vector3=voice.survival.actors.person_003.body.global_position
	var executions: Array=[];voice.skills.finished.connect(func(r): executions.append(r))
	var reports: Array=[];voice.pipeline.report_ready.connect(func(r): reports.append(r))
	voice.busy=true;voice._allow_execution=true;voice._decisions_done=false;voice._event_started=Time.get_ticks_msec();voice._job_config=voice.config.duplicate(true)
	var text:="大山，刚才放在你脚边的木块，放远一点。"
	voice._start_pipeline({"id":"fuzzy_player","kind":"speech_intent","speaker":"player","text":text,"listeners":["person_003"],"spatial_segments":[{"text":text,"focus_hint":"person_003","audience":{"person_003":{"angle_degrees":0,"distance_m":1.2}}}]},voice._job_config)
	var deadline:=Time.get_ticks_msec()+75000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not voice.busy and voice.skills.active.is_empty() and voice.autonomy.requests.is_empty(): break
	var results: Array=[]
	for report in reports: results.append({"event":report.event_id,"error":report.get("error"),"decision":report.get("decision")})
	var after: Vector3=voice.skills.world_objects.objects.wood_block.body.global_position
	var idle: bool=not voice.busy and voice.skills.active.is_empty() and voice.autonomy.requests.is_empty()
	var errors: bool=reports.is_empty() or reports.any(func(r): return r.has("error"))
	var verified: bool=not executions.is_empty() and executions[-1].get("success",false) and executions[-1].get("goal_verified",false) and executions[-1].get("runtime",{}).get("returned",{}).get("code")=="placed"
	var passed:=completed_goal(before,after,reference,voice.skills.world_objects.objects.wood_block.holder,idle,errors,verified)
	var file:=FileAccess.open("res://services/luau-runtime/runtime/fuzzy_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"physics_samples":audit.samples,"passed":passed,"idle":idle,"verified":verified,"executions":executions,"reports":results,"before":str(before),"after":str(after),"held":voice.skills.world_objects.objects.wood_block.holder,"pending":voice.autonomy.requests.size()},"  "));file.close()
	print("FUZZY_RESULT reports=",reports.size()," pending=",voice.autonomy.requests.size()," before=",before," after=",after)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)

func ground_target(sim: Node, id: String) -> Dictionary:
	var observation: Dictionary=sim.space.capture(id)
	return {"observation_id":observation.id,"position":observation.near_field.landmarks["surface/person/"+id].position}
