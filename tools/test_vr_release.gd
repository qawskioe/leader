extends SceneTree
## 离线控制器夹具：复现实体测试的持物位置，不代替头显视觉与手柄验收。
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
class TestRig extends Node3D:
	var active:=true
	var focused:=true
	var hands=preload("res://scripts/vr/hand_interaction.gd").new()
	var left:=XRController3D.new()
	var right:=XRController3D.new()
	func _ready() -> void:
		add_child(left);add_child(right)

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(25).timeout.connect(func():push_error("VR release fixture timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=Store.new();assert(store.initialize().is_empty())
	var sim=Sim.new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player=scene.get_node("Player")
	player.set_physics_process(false);player.set_process(false)
	player.global_position=Vector3(2.48816061019897,-0.0523804388940334,6.80009508132935)
	var rig:=TestRig.new();player.add_child(rig);player.vr=rig;rig.hands.sim=sim
	var bag: Dictionary=sim.water.bags["1"]
	var clear_pose: Vector3=player.global_position+Vector3(.8,1.1,0)
	bag.root.global_position=clear_pose;rig.right.global_position=clear_pose
	assert(rig.hands.grab("right",clear_pose).begins_with("已拿起"))
	rig.right.global_position=Vector3(2.68394160270691,1.02270758152008,6.69047451019287)
	await physics_frame;await physics_frame
	var raw_contacts: Array=sim.world_objects.pose_contacts("water_bag/1",Transform3D(Basis.IDENTITY,rig.right.global_position))
	assert("person" in raw_contacts,"夹具必须复现自然屈肘姿态与简化身体重叠")
	assert(sim.world_objects.release_contacts("water_bag/1").is_empty(),"持物槽应自行避开身体，不能要求现实手臂伸直")
	assert(not bag.label.visible,"VR持物数量必须进入操作提示，不留下重叠的物品标签")
	var message: String=rig.hands.release("right",rig.right.global_position)
	assert(message=="已放下",message)
	assert(sim.water.held("player")=="" and not rig.hands.held.has("right"))
	await physics_frame
	assert(bag.label.visible,"放下后物品标签应恢复")
	# 自然屈肘可放下，不等于可以在地面/墙内开启刚体。
	assert(sim.water.pickup("player","1"))
	rig.hands.reconcile()
	rig.right.global_position=player.global_position+Vector3(.85,-.2,0)
	await physics_frame;await physics_frame
	message=rig.hands.release("right",rig.right.global_position)
	assert(message.contains("地面或墙壁") and not message.contains("果实"),message)
	assert(rig.hands.last_release_result.code=="release_overlapping")
	assert(sim.water.held("player")=="1" and rig.hands.held.has("right"))
	rig.right.global_position=clear_pose
	assert(rig.hands.release("right",clear_pose)=="已放下")
	assert(sim.water.held("player")=="" and not rig.hands.held.has("right"))
	assert(not bag.root.freeze and bag.root.collision_layer==4 and bag.root.collision_mask==7)
	# 读档或他人递交只恢复世界持有关系时，手柄视图必须自行恢复。
	assert(sim.water.pickup("player","1"))
	rig.hands.held.clear();rig.hands.reconcile()
	assert(rig.hands.held.right=={"kind":"water","key":"1"})
	rig.hands.reconcile();assert(rig.hands.held.size()==1)
	assert(rig.hands.release("right",clear_pose)=="已放下")
	var before: Vector3=bag.root.global_position
	for index in 35:await physics_frame
	assert(bag.root.global_position.y<before.y-.1,"松开后必须恢复真实自由落体")
	var left_pose: Vector3=player.global_position+Vector3(-.8,1.1,0)
	bag.root.global_position=left_pose;rig.left.global_position=left_pose
	assert(rig.hands.grab("left",left_pose).begins_with("已拿起"))
	if bag.hand!="Hand.L":push_error("左手握住水袋却占用世界右手槽");quit(1);return
	assert(sim.world_objects.held.get("player/Hand.L")=="water_bag/1")
	rig.hands.reconcile();assert(rig.hands.held.left.kind=="water")
	assert(rig.hands.release("left",left_pose)=="已放下")
	var failure: String=rig.hands.release_failure("water",{"ok":false,"code":"release_overlapping","contacts":{"environment":true}})
	assert(failure.contains("水袋") and failure.contains("地面或墙壁") and not failure.contains("篮子"))
	player.vr=null
	print("VR_RELEASE_PASSED relaxed_hand_body_clearance_environment_guard_single_label_restored_binding_dynamic_fall")
	scene.queue_free();await create_timer(.1).timeout;quit()
