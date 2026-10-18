extends SceneTree
## 只验证听闻位置，不启动正式场景、模型或语音服务。
const Perception=preload("res://scripts/survival/perception.gd")
class Memory extends RefCounted:
	var entries: Dictionary={}
	func note_observation(id: String, entry: Dictionary) -> void:entries[id]=entry.duplicate(true)
	func put(_id: String, _kind: String, _key: String, _entry: Dictionary, _importance: float) -> void:pass
class Store extends RefCounted:
	var memory=Memory.new()
class Sim extends Node:
	var store=Store.new()
	var actors: Dictionary={}
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	var sim:=Sim.new();root.add_child(sim)
	var body:=Node3D.new();sim.add_child(body);sim.actors["listener"]={"body":body}
	var perception:=Perception.new();perception.sim=sim;perception.memories={"listener":{}}
	# 正式游玩：真人声在身后0.58米，旧的两米全局网格却把声源放到身前。
	body.position=Vector3(19.139866,-.755016,63.596916)
	var source:=Vector3(19.128798,.921978,63.014706)
	assert(perception.hear_voice("listener","player","near_voice",source,20))
	var heard: Dictionary=perception.known("listener","person/player")
	var at:=Vector3(heard.position[0],heard.position[1],heard.position[2])
	var truth:=source-Vector3.UP*1.6-body.position;truth.y=0
	var estimate:=at-body.position;estimate.y=0
	assert(truth.angle_to(estimate)<deg_to_rad(10),"近距离声源不能被全局取整翻到人物背面")
	assert(not heard.visible_now and heard.extra.is_empty() and heard.heard_at_seconds==20,"听闻不是目视，也不暴露物品和实时状态")
	var near_error: float=heard.position_error_per_axis_m
	assert(near_error>0 and near_error<.3,"近距听觉位置仍有误差，但不能一律粗化两米")
	# 在地图各处听同样的相对声音，方向与相对估计应一致。
	var local:=at-body.position
	body.position+=Vector3(40,3,-31);source+=Vector3(40,3,-31)
	assert(perception.hear_voice("listener","player","translated_voice",source,21))
	heard=perception.known("listener","person/player")
	at=Vector3(heard.position[0],heard.position[1],heard.position[2])
	assert((at-body.position).distance_to(local)<.0001,"听觉估计不能依赖地图原点或全局网格边界")
	for distance in [.2,.6,1.5,6.0,30.0]:
		for angle in [-2.8,-1.3,-.2,.7,2.1]:
			var offset: Vector3=Vector3(sin(angle),0,cos(angle))*distance
			assert(perception.hear_voice("listener","player","direction_sweep",body.position+offset+Vector3.UP*1.6,22))
			heard=perception.known("listener","person/player")
			at=Vector3(heard.position[0],heard.position[1],heard.position[2])
			assert(offset.angle_to(at-body.position)<deg_to_rad(10),"各方位听闻都必须保留声源方向")
	assert(heard.position_error_per_axis_m>near_error,"远处声源保留更粗的位置误差")
	assert(not perception.hear_voice("listener","player","old_voice",Vector3.ZERO,19),"迟到声音不能覆盖新线索")
	print("HEARING_DIRECTION_PASSED near_bearing_translation_range_uncertainty_no_visual_leak_old_voice; real_model_calls=0")
	sim.free();quit()
