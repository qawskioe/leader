extends SceneTree
## 只验证玩家视口信息，未启动正式世界、人物模型或语音服务。
class Sim extends Node:
	var scene: Node3D
	var actors: Dictionary={}
	var gathering: Dictionary={"baskets":{},"resources":{},"loose_food":{}}
	var water: Dictionary={"bags":{}}
	var life_world: Dictionary={"supplies":{}}
class Host extends Node:
	var survival: Node
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(5).timeout.connect(func():push_error("可见资源点回归超时");quit(1))
	var world:=Node3D.new();root.add_child(world)
	var player:=CharacterBody3D.new();player.name="Player";world.add_child(player)
	var eye:=Camera3D.new();eye.name="Eyes";player.add_child(eye);eye.position.y=1.6;eye.current=true;eye.fov=75
	var sim:=Sim.new();world.add_child(sim);sim.scene=world
	var host:=Host.new();world.add_child(host);host.survival=sim
	var bridge:=preload("res://scripts/player_control.gd").new();host.add_child(bridge);bridge.set_process(false)
	var source:=Marker3D.new();world.add_child(source);source.position=Vector3(0,0,-4)
	sim.life_world.supplies["private_internal_source"]={"material":"water","anchor":source,"offset":Vector3(0,.03,0)}
	var food:=RigidBody3D.new();food.freeze=true;world.add_child(food);food.position=Vector3(.4,.25,-2.3)
	var mesh:=MeshInstance3D.new();mesh.mesh=SphereMesh.new();food.add_child(mesh)
	sim.gathering.loose_food["private_internal_food"]={"body":food,"visual":mesh}
	var fruit:=MeshInstance3D.new();fruit.mesh=SphereMesh.new();world.add_child(fruit);fruit.position=Vector3(-.5,1,-2)
	var fruit_body:=StaticBody3D.new();fruit.add_child(fruit_body)
	sim.gathering.resources["private_fruit"]={"available":true,"mesh":fruit,"body":fruit_body}
	sim.life_world.supplies["fruit/private_fruit"]={"material":"food","anchor":fruit,"offset":Vector3.ZERO}
	await physics_frame
	var visible: Array=bridge.visible_interactables()
	var names: Array=visible.map(func(item: Dictionary):return item.name)
	assert("水源" in names and "散落食物" in names,"实际视口内的资源点与掉落物必须可读")
	assert(names.count("可采果实")==1 and not "储食处" in names,"果实来源不能重复列为储食处")
	for item in visible:
		assert(item.size()==4 and item.has("name") and item.has("distance_m") and item.has("screen_x") and item.has("screen_y"),"不暴露内部ID、库存、绝对坐标")
	sim.gathering.resources.private_fruit.available=false;fruit.hide()
	var depleted: Array=bridge.visible_interactables().map(func(item: Dictionary):return item.name)
	assert(not "可采果实" in depleted and not "储食处" in depleted,"已摘取的果实不能经资源登记重新暴露")
	var wall:=StaticBody3D.new();world.add_child(wall);wall.position=Vector3(0,1.6,-1);wall.collision_layer=7
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(10,5,.3);shape.shape=box;wall.add_child(shape)
	await physics_frame;await physics_frame
	assert(bridge.visible_interactables().is_empty(),"墙后的资源点与掉落物不能被桥接全知暴露")
	wall.queue_free();await physics_frame
	source.position.z=4;food.position.z=3
	assert(bridge.visible_interactables().is_empty(),"玩家身后的物体不可列为当前所见")
	print("PLAYER_VISIBLE_SOURCES_PASSED supplies_loose_food_fruit_availability_no_false_storage_occlusion_frustum_public_fields; real_model_calls=0")
	world.queue_free();await process_frame;quit()
