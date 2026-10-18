extends SceneTree
## 离线物理夹具：输入桥只报告当前玩家确实看见的人物部位。
const Bridge=preload("res://scripts/player_control.gd")
class Sim extends Node:
	var scene: Node3D
	var actors: Dictionary
	var store:={"people":{"peer":{"name":"同伴"}}}
	var gathering:={"baskets":{},"resources":{},"loose_food":{}}
	var water:={"bags":{}}
	var life_world:={"supplies":{}}
class Host extends Node:
	var survival: Sim
var scene: Node3D
var bridge: Node
var camera: Camera3D
var peer: CharacterBody3D
var wall: StaticBody3D
var wall_shape: BoxShape3D
func _initialize() -> void:run.call_deferred()
func barrier(at: Vector3,size: Vector3) -> void:
	wall.position=at;wall_shape.size=size
	await physics_frame;await physics_frame
func seen(expected: bool) -> Dictionary:
	var items: Array=bridge.visible_interactables()
	assert(items.size()==int(expected),"当前可见人物应出现一次；胸口被挡而头部可见时不能跟丢")
	if expected:
		assert(items[0].name=="同伴")
		assert(items[0].keys().size()==4,"输入桥只回报名称、距离和屏幕位置")
		return items[0]
	return {}
func run() -> void:
	create_timer(10).timeout.connect(func():push_error("player visibility timeout");quit(1))
	scene=Node3D.new();root.add_child(scene)
	var player:=CharacterBody3D.new();player.name="Player";scene.add_child(player)
	camera=Camera3D.new();camera.name="Eyes";camera.position.y=1.6;player.add_child(camera);camera.current=true
	peer=CharacterBody3D.new();peer.position=Vector3(0,0,-3);scene.add_child(peer)
	var sim:=Sim.new();scene.add_child(sim);sim.scene=scene;sim.actors={"peer":{"body":peer}}
	var host:=Host.new();host.survival=sim;scene.add_child(host)
	bridge=Bridge.new();bridge.ipc_root="user://player_control_visibility_fixture/";host.add_child(bridge);bridge.set_process(false)
	wall=StaticBody3D.new();scene.add_child(wall)
	var collider:=CollisionShape3D.new();wall_shape=BoxShape3D.new();collider.shape=wall_shape;wall.add_child(collider)
	await barrier(Vector3(0,.75,-1.5),Vector3(3,1.5,.2))
	var head: Dictionary=seen(true)
	var head_screen: Vector2=camera.unproject_position(peer.position+Vector3.UP*1.6)/root.get_visible_rect().size
	assert(absf(head.screen_y-head_screen.y)<.011,"回报的屏幕点必须是实际可见的头部")
	await barrier(Vector3(0,1.6,-1.5),Vector3(3,.2,.2))
	var chest: Dictionary=seen(true)
	assert(chest.screen_y>head.screen_y,"头部被挡时改用当前可见的胸口")
	await barrier(Vector3(0,1.1,-1.5),Vector3(3,2.2,.2));seen(false)
	wall.collision_layer=0;await physics_frame;await physics_frame
	seen(true)
	peer.position.z=-13;await physics_frame;seen(false)
	peer.position.z=3;await physics_frame;seen(false)
	print("PLAYER_CONTROL_VISIBILITY_PASSED head_visible_chest_occluded_chest_visible_head_occluded_full_occlusion_range_frustum_no_hidden_fields; cloud_calls=0")
	scene.queue_free();await process_frame;quit()
