extends Node
## 绑定单个人物；脚本只能传物品 ID，不能取得节点或全局场景权限。
var sim: Node
var person_id: String
var _owned:=false
var _motion: Dictionary={}
var motion_timeout:=90.0
const BodyMotor=preload("res://scripts/skills/body_motor.gd")
var motor: RefCounted

func _result(ok: bool, code: String, message: String="") -> Dictionary:
	return {"ok":ok,"code":code,"message":message}

func acquire() -> Dictionary:
	if not is_instance_valid(sim) or not sim.ready_for_actions or not sim.enabled or not sim.actors.has(person_id): return _result(false,"not_ready")
	if _owned or sim.actors[person_id].stage!="idle": return _result(false,"actor_busy")
	_owned=true
	motor=BodyMotor.new();motor.initialize(sim.actors[person_id],person_id)
	sim.actors[person_id]["skill_owner"]=get_instance_id()
	sim.actors[person_id].stage="skill_wait"
	sim.skill_motion_result.connect(_on_motion)
	return _result(true,"acquired")

func _on_motion(id: String, result: Dictionary) -> void:
	if id==person_id: _motion=result

func finish() -> Dictionary:
	var restored: bool=_owned and motor!=null and motor.changed and sim.enabled
	var started:=Time.get_ticks_msec()
	if restored:await _restore_idle(1.2)
	_release_body(restored)
	return {"ok":true,"restored":restored,"elapsed_ms":Time.get_ticks_msec()-started,"message":"宿主结束清理：连续恢复待机姿态"}

func _restore_idle(duration: float) -> void:
	# rest并非Idle动画姿态；恢复到rest再播放Idle会让双手瞬间跳动。
	motor.start()
	var initial: Dictionary=motor.bone_snapshot()
	var actor: Dictionary=sim.actors[person_id]
	sim._animation(actor,"Idle")
	actor.animation.advance(0)
	var target: Dictionary=motor.bone_snapshot()
	actor.animation.stop(true)
	_apply_idle_blend(initial,target,0.0)
	var elapsed:=0.0
	while elapsed<duration:
		await get_tree().process_frame
		if not _owned:return
		if not sim.enabled:continue
		elapsed+=get_process_delta_time()
		_apply_idle_blend(initial,target,smoothstep(0,1,minf(1,elapsed/duration)))

func _apply_idle_blend(initial: Dictionary, target: Dictionary, weight: float) -> void:
	for bone in target:
		var index: int=motor.skeleton.find_bone(bone)
		motor.skeleton.set_bone_pose_rotation(index,initial[bone].rotation.slerp(target[bone].rotation,weight))
		motor.skeleton.set_bone_pose_position(index,initial[bone].position.lerp(target[bone].position,weight))

func _release_body(idle_ready: bool=false) -> void:
	if not _owned: return
	_owned=false
	if not is_instance_valid(sim): return
	if sim.skill_motion_result.is_connected(_on_motion): sim.skill_motion_result.disconnect(_on_motion)
	var actor: Dictionary=sim.actors[person_id]
	if actor.get("skill_owner")!=get_instance_id(): return
	if motor!=null:
		if idle_ready:motor.clear_water()
		else:motor.reset()
	actor.erase("skill_owner");actor.stage="idle";actor.path=PackedVector3Array();actor.body.velocity=Vector3.ZERO
	if idle_ready:
		actor.animation.play("Idle")
		actor.animation.advance(0)
	else:sim._animation(actor,"Idle")
	sim._sync(person_id)

func cancel() -> void: _release_body()

func operate(operation: String, args: Array) -> Dictionary:
	if not _owned or sim.actors[person_id].get("skill_owner")!=get_instance_id(): return _result(false,"not_owned")
	if operation=="inspect_body": return {"ok":true,"body":BodyMotor.describe(motor.skeleton)}
	if operation in ["pose_bones","pose","relax"]: return await _body_operation(operation,args)
	return _result(false,"unsupported_operation")

func _body_operation(operation: String, args: Array) -> Dictionary:
	var pose: Dictionary={}
	var duration: Variant=0.0
	if operation=="pose_bones":
		if not motor.validate_bones(args[0]) or not BodyMotor.seconds(args[1]): return _result(false,"invalid_bone_pose","骨骼名称、有限XYZ数值或时长无效")
		pose=args[0];duration=args[1]
	elif operation=="pose":
		if not motor.validate_pose(args[0]) or not BodyMotor.seconds(args[1]): return _result(false,"invalid_pose")
		pose=args[0];duration=args[1]
	elif operation=="relax":
		if not BodyMotor.seconds(args[0]): return _result(false,"invalid_duration")
		duration=args[0]
		for index in motor.skeleton.get_bone_count():
			pose[motor.skeleton.get_bone_name(index)]={"rotation":{"x":0.0,"y":0.0,"z":0.0},"position":{"x":0.0,"y":0.0,"z":0.0}}
	motor.start()
	var initial: Dictionary=motor.snapshot()
	if operation in ["pose_bones","relax"]: initial=motor.bone_snapshot()
	var elapsed:=0.0
	var started_ms:=Time.get_ticks_msec()
	var last_step:=0.0
	while elapsed<float(duration):
		await get_tree().process_frame
		if not _owned: return _result(false,"cancelled")
		if not sim.enabled: continue
		last_step=get_process_delta_time()
		elapsed+=last_step
		var weight:=smoothstep(0.0,1.0,minf(1.0,elapsed/float(duration)))
		if operation in ["pose_bones","relax"]: motor.apply_bones(pose,initial,weight)
		else: motor.apply_pose(pose,initial,weight)
	var result:=_result(true,"pose_held","保持当前骨骼姿态，指定时间已实际经过") if operation=="pose_bones" and pose.is_empty() else _result(true,"body_moved","骨骼动作已执行")
	result["timing"]={"requested_seconds":duration,"simulated_elapsed_seconds":elapsed,"last_step_seconds":last_step,"wall_elapsed_ms":Time.get_ticks_msec()-started_ms}
	return result
