extends SceneTree
## 候选代码只在此独立世界运行；可同时生成后台审查关键帧。
var folder: String
var motion: String
var review_camera: Camera3D
var framing_objects: Array[String]=[]
var view: SubViewport
var frames: Array=[]
var all_frames: Array=[]
var capture_serial:=0
var samples: Array=[]
var capturing:=false
var recording:=false
var start_ms:=0
var last_frame:=0
var label: Label
var stage:="准备"
var facts: Array=[]
var consent_fixture: Array=[]
var trace_log: FileAccess
var operation_serial:=0
const Snapshot=preload("res://scripts/skills/verification_snapshot.gd")
var api: Node
class ObservedWorld extends "res://scripts/skills/luau_world_adapter.gd":
	var observer: SceneTree
	func finish() -> Dictionary:
		await observer.capture("宿主结束清理：开始连续恢复待机")
		var result: Dictionary=await super.finish()
		await observer.capture("宿主结束清理：恢复完成")
		return result
	func request(operation: String, args: Dictionary) -> Dictionary:
		observer.operation_serial+=1
		var serial: int=observer.operation_serial
		var started:=Time.get_ticks_msec()
		observer.record_partial({"type":"operation_started","request_id":serial,"operation":operation,"arguments":args})
		if observer.needs_action_frame(operation):await observer.capture(operation+" 开始")
		var result: Dictionary=await super.request(operation,args)
		observer.record_partial({"type":"operation_finished","request_id":serial,"step":{"operation":operation,"arguments":args,"result":result,"elapsed_ms":Time.get_ticks_msec()-started}})
		if observer.needs_action_frame(operation):await observer.capture(operation+" / "+str(result.get("code",result.get("ok"))))
		return result
static func needs_action_frame(operation: String) -> bool:
	# 查询的完整数值轨迹仍逐条保存；不为读取同一现场重复阻塞渲染两帧。
	# 未知操作按会改变世界处理，不能因漏列新能力而丢掉动作证据。
	return operation not in ["perceive","walk_options","recall_locations","observe","body_point","contact_point","inspect_contents","inspect_body","surface","check_placement","plan_grasp"]

func record_partial(event: Dictionary) -> void:
	# 超时/进程被终止前逐条落盘，不能只在整段技能返回后才保存失败证据。
	if trace_log==null:return
	event["time_ms"]=Time.get_ticks_msec()-start_ms
	trace_log.store_line(JSON.stringify(event));trace_log.flush()

func _initialize() -> void: run.call_deferred()
func _process(_delta: float) -> bool:
	if recording and is_instance_valid(api) and api.body_state!=null:
		if not capturing and Time.get_ticks_msec()-last_frame>600: capture.call_deferred(stage)
	return false
static func retain_history(history: Array) -> Array:
	if history.size()<64:return history
	var retained: Array=[]
	for index in range(0,history.size(),2):retained.append(history[index])
	return retained

func capture(title: String) -> void:
	if not recording or view==null: return
	while capturing: await process_frame
	if not recording or not is_instance_valid(label):return
	# 长技能不能耗尽前段额度后丢掉真正执行与结束证据；稀疏保留早期帧，再继续记录。
	frames=retain_history(frames)
	capturing=true;stage=title
	if is_instance_valid(review_camera) and is_instance_valid(api):
		# 镜头随真实角色与本次交互物移动；固定在起点会把走近的身体裁掉。
		var actor_at: Vector3=api.sim.actors[api.person_id].body.global_position
		var low:=actor_at+Vector3(-0.7,-0.2,-0.7)
		var high:=actor_at+Vector3(0.7,2.1,0.7)
		for id in framing_objects:
			if not api.objects.objects.has(id):continue
			var at: Vector3=api.objects.objects[id].body.global_position
			if at.distance_to(actor_at)>6:continue
			low=low.min(at-Vector3.ONE*0.6);high=high.max(at+Vector3.ONE*0.6)
		var center: Vector3=(low+high)*0.5
		var radius: float=(high-low).length()*0.5
		review_camera.global_position=center+Vector3(-1,0.65,1).normalized()*radius/sin(deg_to_rad(review_camera.fov*0.5))*1.1
		review_camera.look_at(center)
	label.text="%.2fs · %s"%[(Time.get_ticks_msec()-start_ms)/1000.0,title]
	await process_frame;await RenderingServer.frame_post_draw
	var file:="frame_%04d.jpg"%capture_serial
	capture_serial+=1
	assert(view.get_texture().get_image().save_jpg(motion+"/"+file,0.85)==OK)
	frames.append({"file":file,"stage":title,"time_ms":Time.get_ticks_msec()-start_ms})
	all_frames.append(frames[-1])
	var manifest:=FileAccess.open(folder+"/preview.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"file":motion.get_file()+"/"+file,"stage":title,"time_ms":Time.get_ticks_msec()-start_ms}));manifest.close()
	last_frame=Time.get_ticks_msec();capturing=false
func run() -> void:
	var job:="";var motion_dir:="motion_luau"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skill-job="): job=arg.trim_prefix("--skill-job=")
		if arg.begins_with("--motion-dir="): motion_dir=arg.trim_prefix("--motion-dir=")
	if not job.is_valid_identifier() or not motion_dir.is_valid_identifier(): quit(2);return
	folder="res://services/skill-runtime/runtime/jobs/"+job;motion=folder+"/"+motion_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(motion))
	trace_log=FileAccess.open(motion+"/partial_trace.jsonl",FileAccess.WRITE)
	assert(trace_log!=null,"无法保存独立验证执行证据")
	create_timer(155).timeout.connect(func():push_error("独立验证超过预算");quit(1))
	var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/build_request.json"))
	var person: String=request.verification_snapshot.person_id
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/candidate_definition.json"))
	var program: Dictionary=JSON.parse_string(definition.program_json)
	if not preload("res://scripts/skills/luau_contract.gd").valid(program): quit(2);return
	var parent: Node=root
	if DisplayServer.get_name()!="headless":
		root.unfocusable=true;view=SubViewport.new();view.size=Vector2i(800,600);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);parent=view
	var scene=load("res://scenes/initial_base.tscn").instantiate();parent.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var actor: Dictionary=sim.actors[person]
	var objects: Node=sim.world_objects
	if request.verification_snapshot.objects.has("wood_block") or request.verification_snapshot.objects.has("stone_tool"):
		preload("res://scripts/skills/luau_playtest.gd").populate(sim,objects,person)
	Snapshot.restore(sim,request.verification_snapshot)
	for frame in 5:await physics_frame
	api=ObservedWorld.new();api.sim=sim;api.person_id=person;api.objects=objects;api.observer=self;scene.add_child(api)
	sim.perception.observe(person)
	sim.life_world.fact.connect(func(event: Dictionary):
		facts.append(event.duplicate(true));record_partial({"type":"world_fact","fact":event.duplicate(true)}))
	sim.handover.offered.connect(func(event: Dictionary):
		consent_fixture.append({"event_id":event.id,"recipient":event.listeners[0],"answer":"accept","source":"隔离接收测试替身，非真实模型决定"})
		sim.handover.respond.call_deferred(event.id,event.listeners[0],true))
	if view!=null:
		for mesh in actor.body.find_children("*","VisualInstance3D",true,false): mesh.layers=2
		for object in objects.objects.values():
			for mesh in object.body.find_children("*","VisualInstance3D",true,false): mesh.layers=2
		for light in scene.find_children("*","Light3D",true,false): light.visible=false
		var camera:=Camera3D.new();review_camera=camera;camera.cull_mask=2;camera.fov=45;scene.add_child(camera)
		camera.global_position=actor.body.global_position+Vector3(-2.2,1.5,2.2);camera.look_at(actor.body.global_position+Vector3(0,1,0));camera.current=true
		var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(0.15,0.17,0.19);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=0.9;camera.environment=environment
		var light:=OmniLight3D.new();light.light_cull_mask=2;light.omni_range=6;light.light_energy=1.3;scene.add_child(light);light.global_position=camera.global_position
		var canvas:=CanvasLayer.new();scene.add_child(canvas);label=Label.new();label.position=Vector2(15,15);label.add_theme_font_size_override("font_size",22);canvas.add_child(label)
	var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime=load("res://scripts/skills/luau_library_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
	var library=preload("res://scripts/skills/library.gd").new()
	library.path=folder+"/verification_library.json";library.definitions=request.owned_skills.duplicate(true);library.owners={person:[]}
	for ref in library.definitions:library.owners[person].append({"ref":ref,"source":"隔离快照中已掌握"})
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	if not registered.ok:push_error(registered.error);quit(1);return
	assert(library.grant(person,registered.ref,"候选仅限隔离进程").is_empty())
	var linked: Dictionary=library.execution_context(person,registered.ref)
	if not linked.ok:push_error(linked.error);quit(1);return
	var observation: Dictionary=sim.space.capture(person)
	runtime.context=sim.space.prepare_context(person,store.context_for(person),observation)
	api.observation_id=observation.id
	var arguments: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/test_arguments.json"))
	for key in arguments:
		if arguments[key] is String and objects.objects.has(arguments[key]):framing_objects.append(arguments[key])
		if arguments[key] is Dictionary and arguments[key].has("observation_id"):arguments[key].observation_id=observation.id
		if not library.valid_argument(arguments[key],definition.get("parameter_kinds",{}).get(key,"reference")):
			push_error("验证参数无效："+key);quit(1);return
	var before:=Snapshot.evidence(sim,person)
	start_ms=Time.get_ticks_msec();recording=view!=null
	await capture("执行前")
	var outcome: Dictionary=await runtime.run(program,arguments,api,linked.context)
	await capture("执行后")
	recording=false
	while capturing:await process_frame
	# 保留实际执行结束现场，便于后续针对失败环节修订；不伪造成功或覆盖原输入快照。
	var snapshot_file:=FileAccess.open(motion+"/final_snapshot.json",FileAccess.WRITE)
	assert(snapshot_file!=null,"无法保存验证结束现场")
	snapshot_file.store_string(JSON.stringify(Snapshot.capture(sim,person)));snapshot_file.close()
	var returned: Dictionary=outcome.get("returned",{}) if outcome.get("returned") is Dictionary else {}
	var failures: Array=[]
	if outcome.status!="completed" or not returned.get("ok",false):failures.append("技能实际执行未完成")
	if outcome.get("trace",[]).is_empty():failures.append("没有世界交互证据，不能只返回成功")
	var file:=FileAccess.open(motion+"/motion.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"faults":[],"frames":frames,"all_frames":all_frames,"samples":samples,"result":{"before":before,"after":Snapshot.evidence(sim,person),"facts":facts,"consent_fixture":consent_fixture,"runtime":outcome,"arguments":arguments,"failures":failures},"note":"宿主隔离回放当前实体状态。passed仅表示代码完成，不代表满足玩家目标；必须由独立审查结合原话、前后事实与操作证据批准。隔离NPC接受递物使用明确的测试替身；不证明实际人物会同意。真实场景仍由接收者模型决定。"}));file.close()
	print("LUAU_CANDIDATE_RESULT failures=",failures," frames=",frames.size())
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if failures.is_empty() else 1)
