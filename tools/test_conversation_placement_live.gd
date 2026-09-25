extends SceneTree
var reports: Array=[]
var executions: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/conversation_%d.json"%Time.get_ticks_usec())
	voice.config.tts_enabled=false
	voice.pipeline.report_ready.connect(func(r): reports.append(r))
	voice.skills.finished.connect(func(r): executions.append(r))
	# 复现用户已听到的错误断言，下一句必须获得这段现场，而不是否认说过。
	voice.store.hear("person_003",{"id":"earlier","speaker":"player","text":"你知道你背后有什么吗？"})
	voice.store.remember("person_003","earlier",{"private_interpretation":"我猜背后是洞壁","public_reply":"我背后刚才看就是洞壁和黑暗。"})
	voice.store.mark_reply("person_003","earlier","已播放完成；附近成员听闻另行记录")
	await say(voice,"correction","你刚刚不是才跟我说你知道背后是什么吗？")
	await say(voice,"placement","算了，无所谓，拿起石块，放到水池的外面。")
	var object: Dictionary=voice.skills.world_objects.objects.stone_tool
	var mesh:=scene.find_child("Cenote_water",true,false) as MeshInstance3D
	# 水面网格外轮廓可能埋在地形下，实际岸线取水面与地面的相交处。
	var at: Vector3=object.body.global_position
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2,1,[object.body.get_rid()]))
	var outside:=not hit.is_empty()
	if outside:
		var start: Vector3=mesh.to_local(hit.position+Vector3.UP*2)
		var finish: Vector3=mesh.to_local(hit.position)
		var triangles: PackedVector3Array=mesh.mesh.get_faces()
		for index in range(0,triangles.size(),3):
			if Geometry3D.segment_intersects_triangle(start,finish,triangles[index],triangles[index+1],triangles[index+2])!=null: outside=false;break
	var passed: bool=object.holder.is_empty() and outside and executions.any(func(r):return r.success and r.get("runtime",{}).get("returned",{}).get("code")=="placed")
	var file:=FileAccess.open("res://services/luau-runtime/runtime/conversation_placement_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"outside":outside,"held":object.holder,"reports":reports,"executions":executions},"  "));file.close()
	print("CONVERSATION_PLACEMENT_LIVE_", "PASSED" if passed else "FAILED")
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
func say(voice: Node, id: String, text: String) -> void:
	voice.busy=true;voice._allow_execution=true;voice._decisions_done=false;voice._event_started=Time.get_ticks_msec();voice._job_config=voice.config.duplicate(true)
	voice._start_pipeline({"id":id,"kind":"speech_intent","speaker":"player","text":text,"listeners":["person_003"],"spatial_segments":[{"text":text,"focus_hint":"person_003","audience":{"person_003":{"angle_degrees":0,"distance_m":1.2}}}]},voice._job_config)
	var deadline:=Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not voice.busy and voice.skills.active.is_empty() and voice.autonomy.requests.is_empty():return
	assert(false,"真实模型任务超时")
