extends Node
## 仅--player-control启用的本机操作入口：键鼠、当前输入框与玩家画面，无世界状态修改。
const ROOT:="res://services/text-gateway/runtime/player-control/"
var active:=false
var elapsed:=0.0
var virtual_mouse_mode: int=Input.MOUSE_MODE_VISIBLE
func _ready() -> void:
	name="PlayerControl"
	virtual_mouse_mode=Input.mouse_mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
func _process(delta: float) -> void:
	elapsed+=delta
	if active or elapsed<0.1:return
	elapsed=0
	if not FileAccess.file_exists(ROOT+"command.json"):return
	var command: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"command.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT+"command.json"))
	active=true
	perform(command)
func key_event(code: int, down: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=down
	Input.parse_input_event(e)
	var actions:={KEY_W:"player_forward",KEY_S:"player_back",KEY_A:"player_left",KEY_D:"player_right",KEY_SHIFT:"player_run",KEY_F:"player_interact"}
	if actions.has(code):
		if down:Input.action_press(actions[code])
		else:Input.action_release(actions[code])
func perform(command: Variant) -> void:
	var error:=""
	# 后台测试保留虚拟窗口的捕获/菜单状态；操作仍经正常Input事件与玩家控制器。
	if not DisplayServer.window_is_focused():Input.mouse_mode=virtual_mouse_mode
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
				var button: String=command.get("button","")
				if not buttons.has(button): error="unknown mouse button"
				else:
					var down:=InputEventMouseButton.new();down.button_index=buttons[button];down.pressed=true
					down.position=get_viewport().get_visible_rect().size*0.5;Input.parse_input_event(down)
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
		if ready[0]: result=get_viewport().get_texture().get_image().save_png(ROOT+"frame.png")
	var f:=FileAccess.open(ROOT+"result.json",FileAccess.WRITE)
	var focused:=get_viewport().gui_get_focus_owner()
	var hint: Label=get_parent().survival.gathering.interaction_hint
	var input_notice:=""
	if focused is LineEdit:
		for sibling in focused.get_parent().get_children():
			if sibling is Label and sibling.is_visible_in_tree():input_notice=sibling.text;break
	# 仅回报这次操作时玩家自己经历的位移，不暴露地图坐标或视野外目标。
	var movement: Vector3=start_view.inverse()*(player.global_position-start_position)
	var response:={"id":command.get("id","") if command is Dictionary else "","error":error,"visible_interactables":visible_interactables() if result==OK else [],"interaction_hint":hint.text if result==OK and is_instance_valid(hint) and hint.is_visible_in_tree() else "","capture_error":result,"frame":"frame.png" if result==OK else "","focus":focused.get_class() if focused else "","input_text":focused.text if focused is LineEdit else "","input_notice":input_notice,"movement":{"distance_m":snappedf(movement.length(),0.01),"right_m":snappedf(movement.x,0.01),"up_m":snappedf(movement.y,0.01),"forward_m":snappedf(-movement.z,0.01)}}
	f.store_string(JSON.stringify(response));f.close()
	var history:=FileAccess.open(ROOT+"input_history.jsonl",FileAccess.READ_WRITE if FileAccess.file_exists(ROOT+"input_history.jsonl") else FileAccess.WRITE)
	assert(history!=null,"无法记录玩家操作验收证据")
	history.seek_end();history.store_line(JSON.stringify({"time":Time.get_datetime_string_from_system(),"command":command,"result":response}));history.close()
	virtual_mouse_mode=Input.mouse_mode
	if not DisplayServer.window_is_focused():Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	active=false

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
		candidates.append({"name":str(sim.store.people[id].name),"at":sim.actors[id].body.global_position+Vector3(0,1.1,0),"rid":sim.actors[id].body.get_rid(),"range":12.0})
	for item in sim.gathering.resources.values():
		if item.available: candidates.append({"name":"可采果实","at":item.mesh.global_position,"rid":item.body.get_rid(),"range":3.0})
	var seen: Array=[]
	for item in candidates:
		var distance: float=camera.global_position.distance_to(item.at)
		if distance>item.range or not camera.is_position_in_frustum(item.at): continue
		var excluded: Array[RID]=[player.get_rid()]
		if item.rid.is_valid(): excluded.append(item.rid)
		var query:=PhysicsRayQueryParameters3D.create(camera.global_position,item.at,7,excluded)
		if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		var screen: Vector2=camera.unproject_position(item.at)/get_viewport().get_visible_rect().size
		seen.append({"name":item.name,"distance_m":snappedf(distance,0.1),"screen_x":snappedf(screen.x,0.01),"screen_y":snappedf(screen.y,0.01)})
	seen.sort_custom(func(a,b):return a.distance_m<b.distance_m)
	return seen.slice(0,8)
