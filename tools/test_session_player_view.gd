extends SceneTree
## 离线跨模式恢复：PC视线和走路共用水平朝向，VR继续保留跟踪姿态。
const Session=preload("res://scripts/survival/session_store.gd")
class TrackedRig extends Node3D:
	var active:=true

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(30).timeout.connect(func():push_error("session player view timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var library=load("res://scripts/skills/library.gd").new()
	assert(library.initialize("user://view_library_%d.json"%Time.get_ticks_usec(),store.people).is_empty())
	assert(library.install_builtins().is_empty())
	var player: Node3D=scene.get_node("Player")
	player.set_physics_process(false);player.set_process(false)
	var camera: Camera3D=player.get_node("Eyes")
	for eyes in [Vector3(-.03697814,1.6499517,.06234035),Vector3(.3,-2.1,-.2),Vector3(-.3,0,0)]:
		player.rotation=Vector3(0,-2.4223304,0);camera.rotation=eyes
		var forward: Vector3=-camera.global_basis.z
		var horizontal:=Vector3(forward.x,0,forward.z).normalized()
		var position: Vector3=player.global_position
		var path:="user://sessions/view_%d.json"%Time.get_ticks_usec()
		assert((await Session.save(path,sim,library,self)).is_empty())
		var checked:=Session.read(path,sim);assert(checked.ok,str(checked.get("error")))
		Session.restore(sim,library,checked);player.set_physics_process(false)
		var dot: float=(-player.global_basis.z).dot(horizontal)
		if dot<.9999 or not camera.rotation.y==0 or not camera.rotation.z==0:
			push_error("PC前进方向偏离恢复视线：alignment=%f eyes=%s"%[dot,str(camera.rotation)])
			quit(1);return
		assert((-camera.global_basis.z).is_equal_approx(forward),"归一化应保留原观看方向")
		assert(player.global_position.is_equal_approx(position),"恢复视角不能挪动玩家")
	# 当前入口为VR时，保留原跟踪姿态，不按PC鼠标规则改写。
	var rig:=TrackedRig.new();player.add_child(rig);player.vr=rig
	player.rotation=Vector3(0,.7,0);camera.rotation=Vector3(.2,1.6,.1)
	var before: Vector3=camera.rotation
	var path:="user://sessions/vr_view_%d.json"%Time.get_ticks_usec()
	assert((await Session.save(path,sim,library,self)).is_empty())
	var checked:=Session.read(path,sim);assert(checked.ok)
	Session.restore(sim,library,checked);player.set_physics_process(false)
	assert(camera.rotation.is_equal_approx(before) and is_equal_approx(player.rotation.y,.7))
	player.vr=null
	print("SESSION_PLAYER_VIEW_PASSED tracked_to_pc_forward_pitch_position_desktop_no_change_vr_pose_preserved")
	scene.queue_free();await process_frame;quit()
