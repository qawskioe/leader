extends Node
## 绑定单个人物；脚本只能传物品 ID，不能取得节点或全局场景权限。
var sim: Node
var person_id: String
var _owned:=false
var _motion: Dictionary={}
var motion_timeout:=90.0
const BodyState=preload("res://scripts/skills/body_state.gd")
var body_state: RefCounted

func _result(ok: bool, code: String, message: String="") -> Dictionary:
	return {"ok":ok,"code":code,"message":message}

func acquire() -> Dictionary:
	if not is_instance_valid(sim) or not sim.ready_for_actions or not sim.enabled or not sim.actors.has(person_id): return _result(false,"not_ready")
	if _owned or sim.actors[person_id].stage!="idle": return _result(false,"actor_busy")
	_owned=true
	var body: Node3D=sim.actors[person_id].body
	if body.has_meta("body_state"):body_state=body.get_meta("body_state")
	else:
		body_state=BodyState.new();body_state.initialize(sim.actors[person_id],person_id);body.set_meta("body_state",body_state)
	sim.actors[person_id]["skill_owner"]=get_instance_id()
	sim.actors[person_id].stage="skill_wait"
	sim.skill_motion_result.connect(_on_motion)
	return _result(true,"acquired")

func _on_motion(id: String, result: Dictionary) -> void:
	if id==person_id: _motion=result

func finish() -> Dictionary:
	_release_body()
	return {"ok":true,"restored":false,"message":"交互结束，恢复待机"}

func _release_body() -> void:
	if not _owned:return
	_owned=false
	if not is_instance_valid(sim):return
	if sim.skill_motion_result.is_connected(_on_motion):sim.skill_motion_result.disconnect(_on_motion)
	var actor: Dictionary=sim.actors[person_id]
	if actor.get("skill_owner")!=get_instance_id():return
	actor.erase("motion_guard");actor.erase("keep_motion_heading");actor.erase("motion_stop_distance");actor.erase("motion_contacts");actor.erase("skill_owner")
	actor.stage="idle";actor.path=PackedVector3Array();actor.body.velocity=Vector3.ZERO
	sim._animation(actor,"Idle");sim._sync(person_id)

func cancel() -> void: _release_body()
