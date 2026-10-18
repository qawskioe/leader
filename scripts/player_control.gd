extends Node
## 仅--player-control启用的本机操作入口：键鼠、当前输入框与玩家画面，无世界状态修改。
const ROOT:="res://services/text-gateway/runtime/player-control/"
const MouseMode=preload("res://scripts/player_mouse_mode.gd")
var ipc_root:=ROOT
var active:=false
var _stopping:=false
var elapsed:=0.0
var virtual_mouse_mode: int=Input.MOUSE_MODE_CAPTURED
func _ready() -> void:
	name="PlayerControl"
	add_to_group(MouseMode.AUTOMATION_GROUP)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ipc_root))
	# 上一进程退出期间未接收的输入不能在新世界启动后重放。
	if FileAccess.file_exists(ipc_root+"command.json"):
		assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(ipc_root+"command.json"))==OK)
func _process(delta: float) -> void:
	if _stopping:return
	elapsed+=delta
	if active or elapsed<0.1:return
	elapsed=0
	if not FileAccess.file_exists(ipc_root+"command.json"):return
	var command: Variant=JSON.parse_string(FileAccess.get_file_as_string(ipc_root+"command.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ipc_root+"command.json"))
	active=true
	perform(command)

func stop_for_shutdown() -> String:
	# perform及回执发布都会等帧；SceneTree退出前必须让它们真正返回。
	_stopping=true;set_process(false)
	var deadline:=Time.get_ticks_msec()+5000
	while active:
		if Time.get_ticks_msec()>=deadline:return "玩家输入桥尚未结束，已保留应用"
		await get_tree().process_frame
	return ""

func resume_after_shutdown_failure() -> void:
	_stopping=false;set_process(true)
func key_event(code: int, down: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=down
	Input.parse_input_event(e)
	var actions:={KEY_W:"player_forward",KEY_S:"player_back",KEY_A:"player_left",KEY_D:"player_right",KEY_SHIFT:"player_run",KEY_F:"player_interact",KEY_Q:"player_drink"}
	if actions.has(code):
		if down:Input.action_press(actions[code])
		else:Input.action_release(actions[code])
func perform(command: Variant) -> void:
	var error:=""
	# 正常Input事件读取共享逻辑状态，取景和注入均不触碰系统鼠标。
	var player: Node3D=get_parent().survival.scene.get_node("Player")
	var start_position: Vector3=player.global_position
	var start_view: Basis=player.get_node("Eyes").global_basis
	if not command is Dictionary:error="invalid command"
	else:
		match command.get("type"):
			"key":
				var code:=OS.find_keycode_from_string(str(command.get("key","")))
				if code==0:error="unknown key"
				else:
					key_event(code,true)
					await get_tree().create_timer(clampf(float(command.get("seconds",0.08)),0.04,3.0)).timeout
					key_event(code,false)
			"look":
				var e:=InputEventMouseMotion.new();e.relative=Vector2(float(command.get("x",0)),float(command.get("y",0)));Input.parse_input_event(e)
			"type":
				var focused:=get_viewport().gui_get_focus_owner()
				if focused is LineEdit:focused.insert_text_at_caret(str(command.get("text","")))
				else:error="No focused text input"
			"mouse":
				var buttons:={"left":MOUSE_BUTTON_LEFT,"right":MOUSE_BUTTON_RIGHT}
				var button: Variant=command.get("button","")
				var bounds:=get_viewport().get_visible_rect()
				var position:=bounds.size*0.5
				if command.has("x") or command.has("y"):
					if not (command.get("x") is float or command.get("x") is int) or not (command.get("y") is float or command.get("y") is int):
						error="mouse position requires numeric x and y"
					else:
						position=Vector2(float(command.x),float(command.y))
						if not is_finite(position.x) or not is_finite(position.y) or not bounds.has_point(position):error="mouse position outside viewport"
				if not button is String or not buttons.has(button): error="unknown mouse button"
				if error.is_empty():
					var down:=InputEventMouseButton.new();down.button_index=buttons[button];down.pressed=true
					down.position=position;down.global_position=position;Input.parse_input_event(down)
					await get_tree().process_frame
					var up:=down.duplicate() as InputEventMouseButton;up.pressed=false;Input.parse_input_event(up)
			"capture":pass
			_:error="unsupported input"
	await get_tree().process_frame
	var result:=ERR_UNAVAILABLE
	if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED:
		# 最小化或渲染暂停时可能永远没有frame_post_draw；输入结果不能等截图才确认。
		var ready: Array[bool]=[false]
		var drawn:=func(): ready[0]=true
		RenderingServer.frame_post_draw.connect(drawn,CONNECT_ONE_SHOT)
		var deadline:=Time.get_ticks_msec()+500
		while not ready[0] and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		if RenderingServer.frame_post_draw.is_connected(drawn): RenderingServer.frame_post_draw.disconnect(drawn)
		if ready[0]: result=get_viewport().get_texture().get_image().save_png(ipc_root+"frame.png")
	var focused:=get_viewport().gui_get_focus_owner()
	var hint: Label=get_parent().survival.gathering.interaction_hint
	var input_notice:=""
	if focused is LineEdit:
		for sibling in focused.get_parent().get_children():
			if sibling is Label and sibling.is_visible_in_tree():input_notice=sibling.text;break
	# 仅回报这次操作时玩家自己经历的位移，不暴露地图坐标或视野外目标。
	var movement: Vector3=start_view.inverse()*(player.global_position-start_position)
	var response:={"id":command.get("id","") if command is Dictionary else "","error":error,"visible_interactables":visible_interactables() if result==OK else [],"interaction_hint":hint.text if result==OK and is_instance_valid(hint) and hint.is_visible_in_tree() else "","capture_error":result,"frame":"frame.png" if result==OK else "","focus":focused.get_class() if focused else "","input_text":focused.text if focused is LineEdit else "","input_notice":input_notice,"native_mouse_mode":Input.mouse_mode,"logical_mouse_mode":virtual_mouse_mode,"movement":{"distance_m":snappedf(movement.length(),0.01),"right_m":snappedf(movement.x,0.01),"up_m":snappedf(movement.y,0.01),"forward_m":snappedf(-movement.z,0.01)}}
	var publish_error: Error=await publish_response(ipc_root+"result.json",response)
	assert(publish_error==OK,"无法发布玩家输入回执")
	var history:=FileAccess.open(ipc_root+"input_history.jsonl",FileAccess.READ_WRITE if FileAccess.file_exists(ipc_root+"input_history.jsonl") else FileAccess.WRITE)
	assert(history!=null,"无法记录玩家操作验收证据")
	history.seek_end();history.store_line(JSON.stringify({"time":Time.get_datetime_string_from_system(),"command":command,"result":response}));history.close()
	active=false

static func publish_response(path: String, response: Dictionary) -> Error:
	# 先写完再发布，轮询读者不能看到WRITE刚清空的文件或部分JSON。
	# Windows的DirAccess替换会短暂移除旧目标；客户端只等待同一id，不重发输入。
	var staged:=path+".tmp"
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(response))
	var error:=file.get_error();file.close()
	if error!=OK:return error
	# Windows读者短暂打开旧回执时可能拒绝删除；只重试发布，不执行输入。
	var deadline:=Time.get_ticks_msec()+500
	while true:
		error=DirAccess.rename_absolute(staged,path)
		if error==OK:return OK
		if Time.get_ticks_msec()>=deadline:return error
		await (Engine.get_main_loop() as SceneTree).process_frame
	return error

func visible_interactables() -> Array:
	# 仅回读当前玩家视野；不返回遮挡后物体、库存、角色私下状态或全局坐标。
	var sim: Node=get_parent().survival
	var player: Node3D=sim.scene.get_node("Player")
	var camera: Camera3D=player.get_node("Eyes")
	var candidates: Array=[]
	for key in sim.gathering.baskets:
		var basket: Dictionary=sim.gathering.baskets[key]
		candidates.append({"name":"编织篮子","at":basket.root.global_position+Vector3(0,0.35,0),"rid":basket.body.get_rid(),"range":8.0})
		if basket.holder in ["","player"] and basket.root.to_local(camera.global_position).y>=0.52:
			for item in basket.contents.items:
				candidates.append({"name":"篮内果实","at":item.visual.global_position,"rid":basket.body.get_rid(),"range":3.0})
	for key in sim.water.bags:
		var bag: Dictionary=sim.water.bags[key]
		if bag.holder!="player": candidates.append({"name":"水袋","at":bag.root.global_position,"rid":bag.body.get_rid(),"range":5.0})
	for id in sim.actors:
		var body: CharacterBody3D=sim.actors[id].body
		candidates.append({"name":str(sim.store.people[id].name),"at":body.global_position+Vector3(0,1.2,0),"visible_points":[body.global_position+Vector3(0,1.2,0),body.global_position+Vector3(0,1.6,0)],"rid":body.get_rid(),"range":12.0})
	for item in sim.gathering.resources.values():
		if item.available: candidates.append({"name":"可采果实","at":item.mesh.global_position,"rid":item.body.get_rid(),"range":3.0})
	for item in sim.gathering.loose_food.values():
		candidates.append({"name":"散落食物","at":item.visual.global_position,"rid":item.body.get_rid(),"range":3.0})
	# 资源点复用世界登记的实际锚点；下方统一执行玩家视野/遮挡检查，不返回库存或隐藏位置。
	var source_names:={"water":"水源"}
	for source_key in sim.life_world.supplies:
		# 果实已按实际可采状态列出；其登记锚点在摘取后仍保留，不能再次当作资源点。
		if str(source_key).begins_with("fruit/"): continue
		var source: Dictionary=sim.life_world.supplies[source_key]
		candidates.append({"name":source_names.get(source.material,"资源点"),"at":source.anchor.to_global(source.offset),"rid":RID(),"range":8.0})
	var seen: Array=[]
	for item in candidates:
		var excluded: Array[RID]=[player.get_rid()]
		if item.rid.is_valid(): excluded.append(item.rid)
		# 胸或头有一点完整通过范围、视锥和射线才可报告，屏幕位置使用该可见点。
		# 不能把一个点的视锥与另一个点的无遮挡条件拼接成“可见”。
		for at: Vector3 in item.get("visible_points",[item.at]):
			var distance: float=camera.global_position.distance_to(at)
			if distance>item.range or not camera.is_position_in_frustum(at): continue
			var query:=PhysicsRayQueryParameters3D.create(camera.global_position,at,7,excluded)
			if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
			var screen: Vector2=camera.unproject_position(at)/get_viewport().get_visible_rect().size
			seen.append({"name":item.name,"distance_m":snappedf(distance,0.1),"screen_x":snappedf(screen.x,0.01),"screen_y":snappedf(screen.y,0.01)})
			break
	seen.sort_custom(func(a,b):return a.distance_m<b.distance_m)
	return seen.slice(0,12)
