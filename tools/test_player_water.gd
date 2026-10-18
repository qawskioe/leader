extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
class TestRig extends Node3D:
	var active:=true
	var focused:=true
	var hands=preload("res://scripts/vr/hand_interaction.gd").new()
func _initialize() -> void: run.call_deferred()
func press(sim: Node, action: String, seconds: float) -> void:
	Input.action_press(action);sim.gathering._player_input(seconds)
func release(sim: Node, action: String) -> void:
	Input.action_release(action);sim.gathering._player_input(0)

func run() -> void:
	create_timer(20).timeout.connect(func():push_error("玩家取水夹具超时");quit(1))
	# 无界面夹具验证交互入口与世界状态；真实F/Q/G另在正常游戏中验证。
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store:=Store.new();assert(store.initialize().is_empty())
	var sim:=Sim.new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	sim.gathering.set_physics_process(false)
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false);player.set_process(false)
	# Headless不能捕获鼠标；合成聚焦仅打开正常动作门，实际桌面输入另做游玩验证。
	var rig:=TestRig.new();player.add_child(rig);player.vr=rig;rig.hands.sim=sim
	var camera: Camera3D=player.get_node("Eyes")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var at: Vector3=sim.water.bags["1"].root.global_position
	player.global_position=at+Vector3(0,0,1);camera.look_at(at)
	press(sim,"player_interact",.4)
	assert(sim.water.held("player")=="","按键初始检查不能拿取物品")
	release(sim,"player_interact")
	press(sim,"player_interact",.81)
	assert(sim.water.held("player")=="1")
	release(sim,"player_interact")
	camera.rotation=Vector3.ZERO
	await physics_frame;await physics_frame
	var held_local: Vector3=camera.to_local(sim.water.bags["1"].root.global_position)
	if held_local.z>=-0.5:
		push_error("桌面手持水袋没有位于摄像机前方："+str(held_local));quit(1);return
	camera.rotation.x=-0.6
	await physics_frame;await physics_frame
	assert(camera.to_local(sim.water.bags["1"].root.global_position).distance_to(held_local)<0.001,"俯仰后手持水袋仍应保持在视野中")
	player.global_position=sim.water.SOURCE+Vector3(0,0.1,1);camera.look_at(sim.water.SOURCE)
	press(sim,"player_interact",.4)
	assert(sim.water.bags["1"].contents.count==0 and sim.water.drawn==0)
	# 离开原目标取消，返回后必须重新完整计时。
	camera.rotation=Vector3.ZERO;sim.gathering._player_input(.4)
	assert(sim.water.drawn==0)
	camera.look_at(sim.water.SOURCE);sim.gathering._player_input(.4)
	assert(sim.water.drawn==0)
	sim.gathering._player_input(.41)
	assert(sim.water.bags["1"].contents.count==3)
	release(sim,"player_interact")
	press(sim,"player_drink",.4)
	assert(sim.water.bags["1"].contents.count==3 and sim.water.consumed==0)
	sim.gathering.cancel_player_action();sim.gathering._player_input(1)
	assert(sim.water.consumed==0,"存档或失焦中断后，仍按住不能继续结算")
	release(sim,"player_drink")
	press(sim,"player_drink",.81)
	sim.gathering._player_input(2)
	assert(sim.water.consumed==1,"同次按住只能消费一次")
	release(sim,"player_drink")
	assert(sim.water.bags["1"].contents.count==2)
	assert(sim.water.drop("player"))
	assert(sim.water.held("player")=="" and sim.water.bags["1"].contents.count==2)
	assert(sim.water.drawn==3 and sim.water.consumed==1)
	# 合成VR聚焦/失焦验证同一计时入口，不冒充实体手柄验证。
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	press(sim,"player_interact",.4)
	assert(sim.water.consumed==1)
	rig.focused=false;sim.gathering._player_input(1)
	assert(sim.water.consumed==1)
	rig.focused=true;release(sim,"player_interact")
	press(sim,"player_interact",.81)
	assert(sim.water.consumed==2 and sim.water.drawn==4)
	release(sim,"player_interact")
	rig.focused=false;sim.gathering._player_input(0)
	rig.focused=true;press(sim,"player_drink",.81)
	assert(sim.water.consumed==3,"失焦期间已无按键，恢复后第一次新的按住必须可执行")
	release(sim,"player_drink")
	# 视线选中不等于伸手可达：F提示和Q入口都必须遵守同一世界接触规则。
	player.global_position=sim.water.SOURCE+Vector3(0,.1,1.7);camera.look_at(sim.water.SOURCE)
	var distant_target: String=sim.water.player_target()
	assert(distant_target=="water/drink/source","夹具须复现看得到但够不到的水源")
	assert(not sim.life_world.access_source("player","water_source").ok)
	assert(not sim.water.player_blocked(distant_target).is_empty(),"够不到水源时不能提示可开始喝水")
	assert(sim.water.player_target(true).is_empty())
	var consumed_before: int=sim.water.consumed
	press(sim,"player_interact",.81)
	assert(sim.water.consumed==consumed_before)
	release(sim,"player_interact")
	player.global_position=sim.water.SOURCE+Vector3(0,.1,1);camera.look_at(sim.water.SOURCE)
	assert(sim.water.player_blocked(sim.water.player_target()).is_empty())
	press(sim,"player_interact",.81)
	assert(sim.water.consumed==consumed_before+1,"靠近以后同一正常入口应恢复计时消费")
	release(sim,"player_interact")
	player.vr=null
	print("PLAYER_WATER_PASSED timed_pickup_fill_drink_single_commit_aim_cancel_checkpoint_cancel_synthetic_vr_focus")
	scene.queue_free();await create_timer(0.2).timeout;quit()
