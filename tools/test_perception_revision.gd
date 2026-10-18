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
	var scene: Node3D
	var actors: Dictionary={}
	var STORAGE:=Vector3(100,0,100)
	var storage_food:=0
	var water: Node
	var gathering:={"baskets":{},"resources":{}}
class Contents extends RefCounted:
	var count:=1
	func describe() -> Array:return [{"count":count}]
class VisiblePerception extends "res://scripts/survival/perception.gd":
	var visible_points: Array[Vector3]=[]
	func sees(_id: String, at: Vector3, _target: RID=RID()) -> bool:
		return visible_points.any(func(point):return point.distance_to(at)<0.001)
func _initialize() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	record_checks()
	observe_checks.call_deferred()

func record_checks() -> void:
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
	sim.free()

func observe_checks() -> void:
	var scene:=Node3D.new();root.add_child(scene)
	var sim:=Sim.new();scene.add_child(sim);sim.scene=scene
	var observer:=CharacterBody3D.new();scene.add_child(observer)
	var player:=CharacterBody3D.new();player.name="Player";scene.add_child(player)
	sim.actors={"person":{"body":observer}}
	var basket:=RigidBody3D.new();basket.freeze=true;basket.position=Vector3(0,0,3);scene.add_child(basket)
	var contents:=Contents.new()
	var objects=preload("res://scripts/skills/world_objects.gd").new();scene.add_child(objects)
	objects.register_object("basket/1",basket,Vector3(-0.39,0.67,0))
	objects.objects["basket/1"].kind="basket"
	objects.objects["basket/1"].extra=func():return {"food_count":contents.count,"contents":contents.describe()}
	sim.gathering.baskets["1"]={"root":basket,"body":basket,"holder":"","contents":contents}
	var perception:=VisiblePerception.new();perception.sim=sim;perception.world_objects=objects
	perception.memories={"person":{}};perception.revisions={"person":0}
	await physics_frame
	var grip: Vector3=objects.grip_position("basket/1")
	var centre: Vector3=basket.global_position+Vector3.UP*0.4
	perception.visible_points=[grip,centre]
	perception.observe("person")
	var revision: int=perception.revisions.person
	for n in 20:perception.observe("person")
	assert(perception.revisions.person==revision,"同一静止篮子不能被两条观察链重复写成新变化")
	var scheduler=preload("res://scripts/survival/autonomy.gd").new()
	var people:={"person":{"needs":{"hunger":85},"survival_observation":{"knowledge_revision":revision}}}
	var actors:={"person":{"stage":"idle"}}
	assert(not scheduler.next_event(8,people,actors).is_empty())
	for now in [28,48,68,88]:
		perception.observe("person");people.person.survival_observation.knowledge_revision=perception.revisions.person
		assert(scheduler.next_event(now,people,actors).is_empty(),"静止物品不能每20秒催发一次无变化需求判断")
	assert(scheduler.next_event(98,people,actors).trigger.reason=="need_retry","仍保留90秒真实需求复查")
	assert(perception.known("person","basket/1").position==[grip.x,grip.y,grip.z])
	assert(perception.known("person","basket/1").extra.has("holder"),"保留通用物品和库存属性")
	contents.count=2;perception.observe("person")
	assert(perception.revisions.person==revision+1,"库存变化只触发一次")
	perception.observe("person");assert(perception.revisions.person==revision+1)
	for point in [grip,centre]:
		perception.visible_points=[point];perception.observe("person")
		assert(perception.known("person","basket/1").visible_now,"篮体或握持点独立可见时都能识别")
	perception.visible_points=[];perception.observe("person")
	assert(not perception.known("person","basket/1").visible_now)
	var attachment:=func():return Transform3D(Basis.IDENTITY,Vector3(0,0,3))
	assert(objects.attach_to("basket/1","person","Hand.R",attachment).ok);perception.observe("person")
	assert(perception.known("person","basket/1").visible_now and perception.known("person","basket/1").available,"本人持物不因离开视线消失")
	assert(objects.transfer_attachment("basket/1","person","other","Hand.R",attachment).ok)
	perception.visible_points=[grip];perception.observe("person")
	assert(not perception.known("person","basket/1").available,"他人手中物品不能误判为空闲")
	print("PERCEPTION_REVISION_PASSED exact_geometry_single_basket_observation_stock_visibility_holder_no_retrigger")
	scene.queue_free();await process_frame;quit()
