extends SceneTree
## 离线真实射线：局部身体可见不能误判掉队，全遮挡和视野边界不得放行。
const Perception=preload("res://scripts/survival/perception.gd")
const Conditions=preload("res://scripts/skills/verification_conditions.gd")
class Memory extends RefCounted:
	var records:={"observer":{}}
	func note_observation(_id: String,_entry: Dictionary) -> void:pass
class Store extends RefCounted:
	var memory=Memory.new()
	var people:={"peer":{"name":"同伴"}}
class Sim extends Node:
	var scene: Node3D
	var actors: Dictionary
	var store=Store.new()
	var STORAGE:=Vector3(100,0,100)
	var water: Node
	var gathering:={"baskets":{},"resources":{}}
var scene: Node3D
var observer: CharacterBody3D
var player: CharacterBody3D
var peer: CharacterBody3D
var perception: RefCounted
var wall: StaticBody3D
var wall_shape: BoxShape3D
func _initialize() -> void:run.call_deferred()
func body(at: Vector3) -> CharacterBody3D:
	var value:=CharacterBody3D.new();value.position=at;scene.add_child(value);return value
func visible(expected: bool) -> void:
	perception.observe("observer")
	for key in ["person/player","person/peer"]:
		assert(perception.known("observer",key).get("visible_now",false)==expected,"玩家与NPC必须使用相同的完整可见性规则："+key)
func barrier(at: Vector3,size: Vector3) -> void:
	wall.position=at;wall_shape.size=size
	await physics_frame;await physics_frame
func run() -> void:
	create_timer(10).timeout.connect(func():push_error("person visibility timeout");quit(1))
	scene=Node3D.new();root.add_child(scene)
	observer=body(Vector3.ZERO);player=body(Vector3(0,0,3));player.name="Player";peer=body(Vector3(.3,0,3))
	var sim:=Sim.new();scene.add_child(sim);sim.scene=scene;sim.actors={"observer":{"body":observer},"peer":{"body":peer}}
	perception=Perception.new();perception.sim=sim;perception.memories={"observer":{}}
	wall=StaticBody3D.new();scene.add_child(wall)
	var collider:=CollisionShape3D.new();wall_shape=BoxShape3D.new();collider.shape=wall_shape;wall.add_child(collider)
	await barrier(Vector3(0,.75,1.5),Vector3(3,1.5,.2))
	assert(not perception.sees("observer",player.position+Vector3.UP*1.2) and perception.sees("observer",player.position+Vector3.UP*1.6),"复现胸挡头露")
	visible(true)
	assert(not Conditions._occluded(observer,player,player.position),"头露时不能生成完全遮挡的隔离前提")
	await barrier(Vector3(0,1.6,1.5),Vector3(3,.2,.2))
	assert(perception.sees("observer",player.position+Vector3.UP*1.2) and not perception.sees("observer",player.position+Vector3.UP*1.6),"反向验证胸露头挡")
	visible(true)
	var remembered_player: Dictionary=perception.known("observer","person/player")
	var remembered_peer: Dictionary=perception.known("observer","person/peer")
	player.position.x+=.2;peer.position.x+=.2;perception.clock=10
	await barrier(Vector3(0,1.1,1.5),Vector3(3,2.2,.2))
	visible(false)
	assert(Conditions._occluded(observer,player,player.position))
	for pair in [["person/player",remembered_player],["person/peer",remembered_peer]]:
		var stale: Dictionary=perception.known("observer",pair[0])
		assert(stale.position==pair[1].position and stale.observed_at_seconds==pair[1].observed_at_seconds,"完全不可见不能刷新旧位置或时间")
	wall.collision_layer=0;await physics_frame;await physics_frame
	observer.rotation.y=PI;visible(false)
	observer.rotation.y=0;player.position=Vector3(0,0,11);peer.position=Vector3(.3,0,11)
	await physics_frame;visible(false)
	# 一个点射线畅通但视角不合格，另一个点在视角内却被挡；不得拼接两点的条件。
	player.position=Vector3(.05,0,.05);peer.position=Vector3(-.05,0,.05);wall.collision_layer=1
	await barrier(Vector3(0,1.6,.025),Vector3(.2,.08,.01))
	assert(not perception.sees("observer",player.position+Vector3.UP*1.2) and not perception.sees("observer",player.position+Vector3.UP*1.6))
	assert(not Conditions._occluded(observer,player,player.position),"视野不合格不能冒充实际全遮挡")
	visible(false)
	print("PERSON_VISIBILITY_PASSED head_or_chest_complete_rays_full_occlusion_fov_range_stale_memory_fixture_contract; cloud_calls=0")
	scene.queue_free();await process_frame;quit()
