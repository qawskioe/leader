extends SceneTree
var moving: Dictionary={}
func _initialize() -> void: run.call_deferred()
func walk(api: Node, target: Dictionary) -> void:
	moving=await api.request("approach",{"object":target,"distance":0.45})
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/motion_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var sim: Node=voice.survival
	var snapshot: Dictionary=sim.space.capture("person_003")
	var point: Dictionary={}
	for sample in snapshot.near_field.ground_samples:
		if sample.probe.x==0 and sample.probe.z==2.25 and sample.state=="visible_surface": point=sample.position
	assert(not point.is_empty())
	var target: Dictionary={"observation_id":snapshot.id,"position":point}
	var actor: Node3D=sim.actors.person_003.body
	var initial:=actor.global_position
	var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=voice.skills.world_objects;scene.add_child(api)
	assert(api.acquire().ok)
	walk(api,target)
	for frame in 4: await physics_frame
	# 目标观察后路上出现障碍：验证碰撞停止，不调用全图绕行。
	var wall:=StaticBody3D.new();scene.add_child(wall)
	wall.global_position=initial+Vector3(0,0.8,1.0)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(3,2,0.1);collision.shape=box;wall.add_child(collision)
	var deadline:=Time.get_ticks_msec()+12000
	var side_drift:=0.0
	while moving.is_empty() and Time.get_ticks_msec()<deadline:
		await physics_frame;side_drift=maxf(side_drift,absf(actor.global_position.x-initial.x))
	assert(not moving.is_empty() and not moving.ok,"障碍应导致失败，不是默默绕路")
	assert(side_drift<0.1,"不能自行选择绕行路径")
	api.finish()
	print("EGOCENTRIC_MOTION_PASSED collision_stops_selected_segment_no_automatic_detour")
	scene.queue_free();await create_timer(0.2).timeout;quit()
