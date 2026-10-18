extends SceneTree
## 控制器夹具验证真实果实落地与再次拿取；不代替实体手柄手感验收。
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
class TestRig extends Node3D:
	var active:=true
	var focused:=true
	var hands=preload("res://scripts/vr/hand_interaction.gd").new()
	var left:=XRController3D.new()
	var right:=XRController3D.new()
	func _ready() -> void:add_child(left);add_child(right)

func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("VR loose food fixture timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=Store.new();assert(store.initialize().is_empty())
	var sim=Sim.new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var player=scene.get_node("Player");player.set_physics_process(false);player.set_process(false)
	var rig:=TestRig.new();player.add_child(rig);player.vr=rig;rig.hands.sim=sim
	var resource_key: String=sim.gathering.resources.keys()[0]
	var fruit: Dictionary=sim.gathering.resources[resource_key]
	player.global_position=fruit.mesh.global_position+Vector3(0,-.7,.6)
	var basket: Dictionary=sim.gathering.baskets["1"]
	basket.root.global_position=player.global_position+Vector3(-.7,.7,0)
	rig.left.global_position=basket.root.to_global(Vector3(-.34,.4,0))
	assert(rig.hands.grab("left",rig.left.global_position).begins_with("已拿起"))
	rig.right.global_position=fruit.mesh.global_position
	assert(rig.hands.grab("right",rig.right.global_position).begins_with("已拿起"))
	assert(sim.gathering.harvested==1)
	var visual: MeshInstance3D=sim.gathering.hands.player.visual
	var origin: Dictionary=sim.gathering.hands.player.origin.duplicate(true)
	# 本项只验证持物/落地，不把树冠附近的可达性混进测试；使用已有松手夹具的空处。
	player.global_position=Vector3(2.48816061019897,-0.0523804388940334,6.80009508132935)
	rig.left.global_position=player.global_position+Vector3(-.8,1.4,0)
	rig.right.global_position=player.global_position+Vector3(.8,1.1,0)
	await physics_frame;await physics_frame
	var at: Vector3=visual.global_position
	var message: String=rig.hands.release("right",rig.right.global_position)
	if message!="已放下":
		var shape:=visual.mesh.create_convex_shape()
		var points:=shape.points
		for index in points.size():points[index]=visual.global_basis*(points[index]-visual.get_aabb().get_center())
		shape.points=points
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=7
		query.transform=Transform3D(Basis.IDENTITY,visual.to_global(visual.get_aabb().get_center()))
		var contacts: Array=[]
		for hit in scene.get_world_3d().direct_space_state.intersect_shape(query,8):contacts.append(str(hit.collider.name))
		print(JSON.stringify({"visual_position":str(visual.global_position),"hand_position":str(rig.right.global_position),"bounds":str(visual.get_aabb()),"contacts":contacts}))
		push_error("空处松开果实未落地："+message);quit(1);return
	assert(not rig.hands.held.has("right") and not sim.gathering.hands.has("player"))
	assert(sim.gathering.loose_food.size()==1 and sim.gathering.harvested==1)
	var loose_key: String=sim.gathering.loose_food.keys()[0]
	var loose: Dictionary=sim.gathering.loose_food[loose_key]
	assert(loose.visual==visual and loose.origin==origin)
	for index in 20:await physics_frame
	assert(loose.body.global_position.y<at.y-.05,"松手必须恢复真实重力")
	rig.right.global_position=loose.visual.global_position
	assert(rig.hands.candidate(rig.right.global_position)[0]=="loose")
	message=rig.hands.grab("right",rig.right.global_position)
	if not message.begins_with("已拿起"):
		var query:=PhysicsRayQueryParameters3D.create(player.global_position+Vector3(0,1.2,0),loose.body.global_position,1,[player.get_rid()])
		for record in sim.gathering.baskets.values():query.exclude.append(record.body.get_rid())
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
		print(JSON.stringify({"free_hand":sim.gathering.free_unit_hand("player"),"reachable":sim.gathering._reachable("player",loose.body.global_position),"loose_position":str(loose.body.global_position),"eye_position":str(query.from),"blocker":"" if hit.is_empty() else str(hit.collider.name)}))
		push_error("落地果实不能再拿起："+message);quit(1);return
	assert(sim.gathering.loose_food.is_empty() and sim.gathering.hands.player.visual==visual)
	assert(sim.gathering.hands.player.origin==origin and rig.hands.held.right.kind=="fruit")
	assert(sim.gathering.harvested==1 and not fruit.available,"再拿取不能重生或重复采摘")
	rig.right.global_position=player.global_position+Vector3(.8,.08,0)
	await physics_frame;await physics_frame
	message=rig.hands.release("right",rig.right.global_position)
	assert(message.begins_with("未放下"),"与地面重叠时仍须拒绝释放")
	assert(rig.hands.held.has("right") and sim.gathering.hands.has("player") and sim.gathering.loose_food.is_empty())
	rig.right.global_position=player.global_position+Vector3(.8,1.1,0)
	await physics_frame;await physics_frame
	assert(rig.hands.release("right",basket.root.to_global(Vector3(0,.25,0)))=="已装篮")
	assert(basket.contents.items.size()==1 and basket.contents.items[0].origin==origin)
	assert(not rig.hands.held.has("right") and not sim.gathering.hands.has("player"))
	# 世界递交/恢复可直接产生手中物资；控制器视图不能只承认经grab取得的物品。
	assert(sim.gathering.take_from_basket("player","1",0))
	assert(sim.gathering.hands.player.hand=="Hand.R")
	rig.hands.reconcile()
	if not rig.hands.held.has("right"):
		push_error("已有世界持物未恢复到VR手部视图");quit(1);return
	assert(rig.hands.held.right.kind=="fruit")
	assert(sim.gathering.hands.player.origin==origin)
	await physics_frame;await physics_frame
	assert(rig.hands.release("right",rig.right.global_position)=="已放下")
	assert(sim.gathering.loose_food.size()==1 and not sim.gathering.hands.has("player"))
	rig.hands.reconcile();assert(not rig.hands.held.has("right"))
	player.vr=null
	print("VR_LOOSE_FOOD_PASSED empty_space_release_dynamic_fall_regrab_same_item_origin_no_duplicate_environment_guard_store_restored_unit_binding")
	scene.queue_free();await create_timer(.1).timeout;quit()
