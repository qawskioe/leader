extends SceneTree
## 离线验证：替身跟随保留碰撞，暂停/续行不会传送或接管受检人物。
const Participants=preload("res://scripts/skills/verification_participants.gd")
const Motion=preload("res://scripts/survival/ground_motion.gd")
class Basket extends Node:
	func basket_for(_id: String) -> String:return ""
class World extends Node:
	var scene: Node3D
	var actors: Dictionary
	var gathering: Node
func _initialize() -> void:run.call_deferred()
func body(at: Vector3) -> CharacterBody3D:
	var result:=CharacterBody3D.new();result.position=at
	var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.3;capsule.height=1.8
	collider.shape=capsule;result.add_child(collider)
	return result
func box(at: Vector3, size: Vector3) -> StaticBody3D:
	var result:=StaticBody3D.new();result.position=at
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size
	collider.shape=shape;result.add_child(collider)
	return result
func walk(lead: CharacterBody3D,to: Vector3) -> void:
	for frame in 220:
		await physics_frame
		var offset:=to-lead.position;offset.y=0
		if offset.length()<=.08:lead.velocity=Vector3.ZERO;return
		lead.velocity=offset.normalized()*minf(1.5,offset.length()*60)
		lead.velocity.y=0 if lead.is_on_floor() else -2
		Motion.move(lead,1.0/60)
	assert(false,"受检角色的隔离拐弯路线必须实际走通")
func corner_follow() -> void:
	var scene:=Node3D.new();root.add_child(scene)
	scene.add_child(box(Vector3(0,-.2,0),Vector3(30,.4,30)))
	scene.add_child(box(Vector3(0,1.5,-3),Vector3(6,3,.3)))
	var player:=body(Vector3(-2,.92,-.8));player.name="Player";scene.add_child(player)
	var lead:=body(Vector3(-2,.92,-2));scene.add_child(lead)
	var sim:=World.new();sim.scene=scene;sim.actors={"subject":{"body":lead}};sim.gathering=Basket.new();scene.add_child(sim);sim.add_child(sim.gathering)
	var helper:=Participants.new();scene.add_child(helper)
	helper.configure(sim,"subject",[{"person":"player","behavior":"follow_actor"}],func(_event: Dictionary):pass)
	await walk(lead,Vector3(-3.9,.92,-2));await walk(lead,Vector3(-3.9,.92,-4.2));await walk(lead,Vector3(-2,.92,-4.2))
	for frame in 100:await physics_frame
	var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(lead.position+Vector3.UP*1.6,player.position+Vector3.UP*1.2,1,[lead.get_rid(),player.get_rid()]))
	assert(hit.is_empty() and player.position.z<-3.2,"不能在墙另一侧因直线距离已近就停下，须沿实际路线恢复视线")
	assert(player.position.distance_to(lead.position)<=2.7 and lead.position.distance_to(Vector3(-2,lead.position.y,-4.2))<.1,"保持距离且不得替受检人物移动")
	# 同一回放中显式重新布置到近处时，不能追先前未消费的远处轨迹。
	helper.set_behavior("player","stay")
	await walk(lead,Vector3(-7,lead.position.y,-4.2))
	var prepared:=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",{"player":{"position":[player.position.x,player.position.y,player.position.z]}},[{"kind":"participant_distance","person":"player","distance_m":2}],helper)
	assert(prepared.ok)
	helper.set_behavior("player","follow_actor")
	var placed:=player.position
	for frame in 30:await physics_frame
	assert(Vector2(player.position.x-placed.x,player.position.z-placed.z).length()<.01,"已靠近时不能反向追旧轨迹")
	helper.reset([])
	assert(helper.trails.is_empty() and helper.trail_samples.is_empty(),"恢复快照时必须清除旧轨迹")
	scene.queue_free();await physics_frame
func run() -> void:
	var scene:=Node3D.new();root.add_child(scene)
	scene.add_child(box(Vector3(0,-0.2,0),Vector3(30,0.4,30)))
	var wall:=box(Vector3(0,1.5,-4),Vector3(20,3,0.3));scene.add_child(wall)
	var player:=body(Vector3(0,0.92,0));player.name="Player";scene.add_child(player)
	var lead:=body(Vector3(0,0.92,-6));scene.add_child(lead)
	var sim:=World.new();sim.scene=scene;sim.actors={"subject":{"body":lead}};sim.gathering=Basket.new();scene.add_child(sim);sim.add_child(sim.gathering)
	var records: Array=[]
	var helper:=Participants.new();scene.add_child(helper)
	helper.configure(sim,"subject",[{"person":"player","behavior":"follow_actor"}],func(event: Dictionary):records.append(event))
	for frame in 130:await physics_frame
	assert(player.position.z>-3.6,"测试替身不能穿过墙壁")
	assert(player.position.z<-2.5,"跟随应发生真实移动")
	wall.queue_free();await physics_frame
	for frame in 70:await physics_frame
	assert(player.position.distance_to(lead.position)<2.6 and player.position.distance_to(lead.position)>2.1,"跟随保留实际距离")
	helper.set_behavior("player","stay")
	var stopped:=player.position;lead.position.z=-10
	for frame in 60:await physics_frame
	assert(player.position.distance_to(stopped)<0.01,"停留阶段不再移动")
	helper.set_behavior("player","follow_actor")
	for frame in 110:await physics_frame
	assert(player.position.z<-7.3,"恢复后从实际位置继续")
	assert(lead.position==Vector3(0,0.92,-10),"替身不能替候选移动受检角色")
	assert(records.any(func(event):return event.type=="participant_fixture_move"))
	assert(float(helper.evidence().distance_walked.player)>6)
	helper.reset([]);stopped=player.position
	for frame in 20:await physics_frame
	assert(player.position.distance_to(stopped)<0.01)
	# 旧高度在新地面中：距离前提必须找真实站立点，而不是生成一个地下参与者。
	scene.add_child(box(Vector3(8,0.4,0),Vector3(6,0.8,6)))
	lead.position=Vector3(4,.92,0);await physics_frame
	var snapshot:={"player":{"position":[9,.92,0]}}
	var result:=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_distance","person":"player","distance_m":3}])
	assert(result.ok and player.position.y>1.65,"测试参与者必须站在抬高后的地面上")
	assert(absf(Vector2(player.position.x-lead.position.x,player.position.z-lead.position.z).length()-3)<.01,"实际距离符合测试前提")
	stopped=player.position;lead.position=Vector3(50,.92,0)
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_distance","person":"player","distance_m":3}])
	assert(not result.ok and player.position==stopped,"没有站立点时明确失败，不假造可配合前提")
	lead.position=Vector3(0,.92,-6)
	wall=box(Vector3(0,1.5,-4),Vector3(20,3,.3));scene.add_child(wall);await physics_frame
	snapshot.player.position=[0,.92,0]
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_occluded","person":"player","distance_m":6}])
	assert(result.ok and preload("res://scripts/skills/verification_conditions.gd")._occluded(lead,player,player.global_position),"实际墙体遮挡，不能修改可见性布尔值")
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_occluded","person":"player"}])
	assert(result.ok and preload("res://scripts/skills/verification_conditions.gd")._occluded(lead,player,player.global_position),"范围搜索仍须找到实际遮挡及完整身体站立点")
	var range_distance:=Vector2(player.position.x-lead.position.x,player.position.z-lead.position.z).length()
	assert(range_distance>=.99 and range_distance<=8.01)
	wall.queue_free();await physics_frame;stopped=player.position
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_occluded","person":"player","distance_m":3}])
	assert(not result.ok and player.position==stopped,"没有遮挡时必须拒绝测试前提")
	result=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,"subject",snapshot,[{"kind":"participant_occluded","person":"player"}])
	assert(not result.ok and player.position==stopped,"范围搜索不能捏造遮挡或在失败时移动参与者")
	scene.queue_free();await physics_frame
	await corner_follow()
	print("VERIFICATION_PARTICIPANTS_PASSED collision, real_movement, stay, resume, actor_not_controlled, clear, supported_distance_condition, actual_occlusion, actual_corner_trajectory_and_visibility; real_model_calls=0")
	quit()
