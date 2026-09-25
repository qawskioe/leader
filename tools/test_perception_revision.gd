extends SceneTree
class Memory extends RefCounted:
	var records:={"person":{}}
	func note_observation(_id: String, _entry: Dictionary) -> void:pass
	func put(id: String, kind: String, key: String, data: Dictionary, _importance: float) -> void:
		records[id][kind+"/"+key.sha256_text()]={"data":data.duplicate(true)}
class Store extends RefCounted:
	var memory=Memory.new()
class Sim extends Node:
	var store=Store.new()
func _initialize() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	var sim:=Sim.new()
	var perception=preload("res://scripts/survival/perception.gd").new()
	perception.sim=sim;perception.memories={"person":{}};perception.revisions={"person":0}
	perception._record("person","bag","water_bag",Vector3.ZERO,true,{"water":1})
	var revision: int=perception.revisions.person
	for n in 20:
		perception._record("person","bag","water_bag",Vector3(0.01 if n%2==0 else -0.01,0,0),true,{"water":1})
	assert(perception.revisions.person==revision,"刚体细微抖动不能反复触发新一轮模型判断")
	assert(is_equal_approx(float(perception.memories.person.bag.position[0]),-0.01),"精确观察仍须实时更新")
	perception.revision_positions.clear() # 模拟载入已有观察后第一次建立调度锚点
	perception._record("person","bag","water_bag",Vector3(0.15,0,0),true,{"water":1})
	perception._record("person","bag","water_bag",Vector3(0.3,0,0),true,{"water":1})
	assert(perception.revisions.person==revision+1,"累积移动不能因每帧变化小而被永久忽略")
	perception._record("person","bag","water_bag",Vector3(0.3,0,0),true,{"water":0})
	assert(perception.revisions.person==revision+2,"物资变化仍须立即触发")
	perception.reset()
	print("PERCEPTION_REVISION_PASSED exact_geometry_without_jitter_retrigger")
	sim.free();quit()
