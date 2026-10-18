extends CharacterBody3D
## 第一人称移动、视角与跌落恢复；物品仍由采集系统管理。

const WALK_SPEED := 3.2
const RUN_SPEED := 5.5
const LOOK_SENSITIVITY := 0.0022
const SPAWN := Vector3(0.0, 0.5, 8.4)
const GroundMotion=preload("res://scripts/survival/ground_motion.gd")
const MouseMode=preload("res://scripts/player_mouse_mode.gd")
var camera: Camera3D
const FALL_LIMIT:=-8.0
var last_safe_position:=SPAWN
var collision_shape: CollisionShape3D
var recovery_failed:=false
var vr: Node3D

func is_vr_active() -> bool:
	return is_instance_valid(vr) and vr.active

func restore_desktop_view() -> void:
	if is_vr_active():return
	# VR 的跟踪姿态可相对身体带任意偏航/滚转；PC鼠标则以身体偏航、Eyes俯仰工作。
	# 保留观看方向，将水平朝向归到身体，避免从VR存档恢复后W横着走、篮子偏到视野外。
	var forward: Vector3=-camera.global_basis.z.normalized()
	var horizontal:=Vector3(forward.x,0,forward.z)
	if horizontal.length_squared()<.0001:
		horizontal=-global_basis.z;horizontal.y=0
	horizontal=horizontal.normalized()
	global_rotation=Vector3(0,atan2(-horizontal.x,-horizontal.z),0)
	camera.rotation=Vector3(clampf(asin(clampf(forward.y,-1,1)),-1.35,1.35),0,0)


func _ready() -> void:
	for binding in {"player_forward":KEY_W,"player_back":KEY_S,"player_left":KEY_A,"player_right":KEY_D,"player_run":KEY_SHIFT,"player_interact":KEY_F,"player_drink":KEY_Q}:
		if not InputMap.has_action(binding):InputMap.add_action(binding)
		var event:=InputEventKey.new();event.physical_keycode={"player_forward":KEY_W,"player_back":KEY_S,"player_left":KEY_A,"player_right":KEY_D,"player_run":KEY_SHIFT,"player_interact":KEY_F,"player_drink":KEY_Q}[binding]
		if not InputMap.action_has_event(binding,event):InputMap.action_add_event(binding,event)
	collision_mask = 7  # 场景碰撞为 1，成员碰撞为 2。
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.72
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.87
	add_child(collider)
	collision_shape=collider
	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.position.y = 1.66
	camera.fov = 82.0
	camera.near = 0.05
	camera.far = 120.0
	add_child(camera)
	camera.current = true
	if OS.get_cmdline_user_args().has("--vr"):
		vr = preload("res://scripts/vr/player_rig.gd").new()
		add_child(vr)
	floor_snap_length = 0.28
	if not is_vr_active() and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--capture"):
		MouseMode.set_mode(self,Input.MOUSE_MODE_CAPTURED)


func _mouse_dialog_open() -> bool:
	var voice:=get_parent().get_node_or_null("VoiceTest")
	if voice==null: return false
	if voice.menu.is_open(): return true
	for caption in voice.captions.values():
		if caption.expanded: return true
	return false

func _input(event: InputEvent) -> void:
	if is_vr_active(): return
	# 捕获鼠标时必须先于 Control 处理视角，否则头顶卡片会吞掉移动。
	if event is InputEventMouseMotion and MouseMode.is_captured(self) and not _mouse_dialog_open():
		rotate_y(-event.relative.x*LOOK_SENSITIVITY)
		camera.rotation.x=clampf(camera.rotation.x-event.relative.y*LOOK_SENSITIVITY,-1.35,1.35)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			var voice:=get_parent().get_node_or_null("VoiceTest")
			if voice!=null and voice.menu.is_open(): voice.menu.close()
			elif _mouse_dialog_open():
				for caption in voice.captions.values():
					if caption.expanded: caption.set_expanded(false)
			else:
				MouseMode.set_mode(self,Input.MOUSE_MODE_VISIBLE if MouseMode.is_captured(self) else Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_R:
			if global_position.y<FALL_LIMIT:
				_recover_from_fall()
				get_viewport().set_input_as_handled()
				return
			if _mouse_dialog_open(): return
			var voice:=get_parent().get_node_or_null("VoiceTest")
			if voice!=null and (voice.survival.gathering.basket_for("player")!="" or voice.survival.gathering.hands.has("player")): return
			position = SPAWN
			velocity = Vector3.ZERO
			rotation = Vector3.ZERO
			camera.rotation = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if is_vr_active(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _mouse_dialog_open():
		MouseMode.set_mode(self,Input.MOUSE_MODE_CAPTURED)

func _notification(what: int) -> void:
	if is_vr_active(): return
	if MouseMode.is_automated(self):return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		MouseMode.set_mode(self,Input.MOUSE_MODE_VISIBLE)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(camera):
		if not _mouse_dialog_open(): MouseMode.set_mode(self,Input.MOUSE_MODE_CAPTURED)

func _ground_below(at: Vector3) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.5,at-Vector3.UP*1.0,1,[get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<GroundMotion.MIN_FLOOR_Y: return {}
	if str(hit.collider.get_parent().name) not in ["Solid_CaveFloor","Solid_EntryFloor","Solid_OutdoorGround","Solid_EntryRamp"]: return {}
	return hit

func _safe_standing_point(at: Vector3) -> Variant:
	var hit:=_ground_below(at)
	if hit.is_empty(): return null
	var destination: Vector3=hit.position+Vector3.UP*0.06
	# 保留脚下完整支撑，避免将悬崖边沿记成恢复点。
	for offset in [Vector3(0.35,0,0),Vector3(-0.35,0,0),Vector3(0,0,0.35),Vector3(0,0,-0.35)]:
		var edge:=_ground_below(destination+offset)
		if edge.is_empty() or absf(edge.position.y-hit.position.y)>GroundMotion.STEP_HEIGHT: return null
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=collision_shape.shape
	query.transform=Transform3D(Basis.IDENTITY,destination+collision_shape.position)
	query.collision_mask=3; query.exclude=[get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return null
	return destination

func _recover_from_fall() -> void:
	var destination: Variant=null
	for anchor in [last_safe_position,SPAWN]:
		for offset in [Vector3.ZERO,Vector3(0.8,0,0),Vector3(-0.8,0,0),Vector3(0,0,0.8),Vector3(0,0,-0.8),Vector3(1.6,0,0),Vector3(-1.6,0,0)]:
			destination=_safe_standing_point(anchor+offset)
			if destination!=null: break
		if destination!=null: break
	if destination==null:
		if not recovery_failed: push_error("跌落恢复失败：最近落脚点与据点附近均无安全位置")
		recovery_failed=true
		return
	var previous:=global_position
	global_position=destination
	velocity=Vector3.ZERO
	last_safe_position=destination
	recovery_failed=false
	# 不重置采集系统，手中物品继续跟随玩家，数量及来源不变。
	var voice:=get_parent().get_node_or_null("VoiceTest")
	if voice!=null: voice.log_event({"type":"player_recovered","message":"跌出场景，已返回最近安全地面；携带物品保留","from":str(previous),"to":str(destination)})
	else: print("PLAYER_RECOVERED ",previous," -> ",destination)


func _process(_delta: float) -> void:
	if is_vr_active(): vr.sync_head()

func _physics_process(delta: float) -> void:
	if is_vr_active():
		vr.align_body()
		vr.sync_head()
	if global_position.y<FALL_LIMIT:
		_recover_from_fall()
		return
	var axis := Vector2.ZERO
	if not is_vr_active() and MouseMode.is_captured(self):
		axis = Vector2(
			float(Input.is_action_pressed("player_right")) - float(Input.is_action_pressed("player_left")),
			float(Input.is_action_pressed("player_back")) - float(Input.is_action_pressed("player_forward"))
		).normalized()
	var direction := global_basis * Vector3(axis.x, 0, axis.y)
	if is_vr_active(): direction = vr.movement()
	var speed := 1.8 if is_vr_active() else (RUN_SPEED if Input.is_action_pressed("player_run") else WALK_SPEED)
	var voice:=get_parent().get_node_or_null("VoiceTest")
	if voice!=null and is_instance_valid(voice.survival.gathering) and voice.survival.gathering.basket_for("player")!="": speed=WALK_SPEED*0.7
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0
	GroundMotion.move(self,delta)
	if is_on_floor():
		var safe: Variant=_safe_standing_point(global_position)
		if safe!=null: last_safe_position=safe
