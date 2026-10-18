extends SceneTree
class Known extends RefCounted:
	func known(_person: String,key: String) -> Dictionary:return {"position":[0,0,0]} if key=="landmark" else {}
class Gathering extends Node:
	func basket_for(_person: String) -> String:return ""
class World extends Node:
	var scene: Node3D
	var actors: Dictionary
	var perception=Known.new()
	var gathering: Node
func body(at: Vector3) -> CharacterBody3D:
	var value:=CharacterBody3D.new();value.position=at;value.collision_layer=2;value.collision_mask=7
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;shape.shape=capsule;value.add_child(shape)
	return value
func reference_positions() -> void:
	# 物理地面+已知旧参考点，未创建目标本体，布置本身不能证明目标存在。
	var scene:=Node3D.new();root.add_child(scene)
	var floor:=StaticBody3D.new();scene.add_child(floor);floor.position.y=-.2
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.4,20);collider.shape=box;floor.add_child(collider)
	var actor:=body(Vector3(0,.92,-5));scene.add_child(actor)
	var player:=body(Vector3(0,.92,-6));player.name="Player";scene.add_child(player)
	var sim:=World.new();scene.add_child(sim);sim.scene=scene;sim.actors={"subject":{"body":actor}};sim.gathering=Gathering.new();sim.add_child(sim.gathering)
	await physics_frame;await physics_frame
	var participants=preload("res://scripts/skills/verification_participants.gd").new();scene.add_child(participants)
	participants.configure(sim,"subject",[{"person":"player","behavior":"stay"}],func(_event: Dictionary):pass)
	participants.trails.player.append(Vector3(5,.92,5))
	var snapshot:={"people":{"subject":{"position":[0,.92,-5],"rotation":[0,0,0]}}}
	var conditions: Array=[{"kind":"reference_distance","person":"subject","reference":"landmark","distance_m":1.5,"bearing_degrees":0},{"kind":"reference_distance","person":"player","reference":"landmark","distance_m":3,"bearing_degrees":90}]
	var result: Dictionary=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,conditions,participants)
	assert(result.ok and result.preparation.size()==2)
	assert(absf(Vector2(actor.position.x,actor.position.z).length()-1.5)<.01 and absf(Vector2(player.position.x,player.position.z).length()-3)<.01,"按同一已知点真实布置不同距离")
	assert(absf(actor.position.x)<.01 and absf(player.position.z)<.01,"必须保持指定相对方位")
	assert(participants.trails.player.size()==1 and participants.trails.player[0]==actor.position,"搬动受检本人不能伪造连续跟随轨迹")
	await physics_frame;await physics_frame
	# 第二组必须使用第一项移动后的真实碰撞位置，不能被上一组旧人物位置阻挡。
	var opposite: Array=[{"kind":"reference_distance","person":"subject","reference":"landmark","distance_m":3,"bearing_degrees":0},{"kind":"reference_distance","person":"player","reference":"landmark","distance_m":1.5,"bearing_degrees":0}]
	participants.set_behavior("player","follow_actor")
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,opposite,participants)
	if not result.ok:
		var transforms: Array=[]
		for moved in [actor,player]:
			var physical: Transform3D=PhysicsServer3D.body_get_state(moved.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			transforms.append({"node":str(moved.global_position),"physics":str(physical.origin)})
		push_error(JSON.stringify({"preparation":result,"transforms":transforms}))
	assert(result.ok,"同批次后续布置必须使用已移动人物的碰撞体")
	assert(participants.is_physics_processing() and participants.modes.player=="follow_actor","布置等待期间暂停跟随，结束后恢复")
	assert(absf(Vector2(actor.position.x,actor.position.z).length()-3)<.01 and absf(Vector2(player.position.x,player.position.z).length()-1.5)<.01)
	for moved in [actor,player]:
		var physical: Transform3D=PhysicsServer3D.body_get_state(moved.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		assert(physical.is_equal_approx(moved.global_transform),"布置完成后的逻辑位置和碰撞体必须一致")
	var stopped:=player.position
	participants.set_physics_process(false)
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"reference_distance","person":"player","reference":"unknown","distance_m":3,"bearing_degrees":90}],participants)
	assert(not result.ok and player.position==stopped)
	assert(not participants.is_physics_processing(),"失败返回也必须保留原暂停状态")
	floor.collision_layer=0;await physics_frame;await physics_frame
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[conditions[1]],participants)
	assert(not result.ok and player.position==stopped,"没有支撑时必须拒绝，不能替换方位或移动参与者")
	scene.queue_free();await process_frame
func _initialize():run.call_deferred()
func run():
	create_timer(20).timeout.connect(func():push_error("verification conditions timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false;scene.get_node("Player").set_physics_process(false)
	var id:="person_003";var body: Node3D=sim.actors[id].body
	body.global_position=sim.STORAGE+Vector3(0,.05,-.8);body.rotation.y=0
	var basket: Dictionary=sim.gathering.baskets["1"];basket.root.global_position=body.global_position+Vector3(.4,.4,.5)
	assert(sim.gathering.pickup(id,"1"));sim.perception.observe(id)
	for index in 2:
		assert(sim.life_world.take_unit(id,"storage").ok)
		assert(sim.life_world.put_unit(id,"basket/1").ok)
	var original: int=sim.eaten
	var snapshot: Dictionary=preload("res://scripts/skills/verification_snapshot.gd").capture(sim,id)
	var result: Dictionary=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,id,snapshot,[{"kind":"consume_to_quantity","object":"basket/1","quantity":0}])
	assert(result.ok and result.preparation.size()==2 and sim.eaten==original+2 and basket.contents.count==0,"隔离条件复用真实食物消耗，不只适用水袋")
	var refused: Dictionary=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,id,snapshot,[{"kind":"consume_to_quantity","object":"basket/1","quantity":1}])
	assert(not refused.ok and basket.contents.count==0,"测试条件不能补造已消耗物资")
	scene.queue_free();await process_frame
	await reference_positions()
	print("VERIFICATION_CONDITIONS_PASSED shared_food_consumption_origin_no_creation_reference_distance_bearing_support_actor_rebase")
	quit()
