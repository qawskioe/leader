extends Node
## 只在隔离回放中模拟参与者的行为前提，不能作为候选的世界操作。
const GroundMotion=preload("res://scripts/survival/ground_motion.gd")
const Player=preload("res://scripts/first_person_controller.gd")
var sim: Node
var actor_id: String
var record: Callable
var modes: Dictionary={}
var distances: Dictionary={}
var sampled_at: Dictionary={}
var samples: Array=[]
var handover_answers: Dictionary={}
var trails: Dictionary={}
var trail_samples: Dictionary={}

func configure(world: Node, actor: String, behaviors: Array, recorder: Callable) -> void:
	sim=world;actor_id=actor;record=recorder
	reset(behaviors)

func _body(id: String) -> CharacterBody3D:
	return sim.scene.get_node("Player") if id=="player" else sim.actors[id].body

func reset(behaviors: Array) -> void:
	for id in modes:_body(id).velocity=Vector3.ZERO
	modes.clear();distances.clear();sampled_at.clear();samples.clear();handover_answers.clear();trails.clear();trail_samples.clear()
	for item in behaviors:set_behavior(item.person,item.behavior,"independent_plan")

func set_handover_answer(id: String, answer: String) -> void:
	assert(id!=actor_id and sim.actors.has(id) and answer in ["accept","decline"],"隔离递交回复仅用于其他NPC")
	handover_answers[id]=answer
	record.call({"type":"participant_fixture_consent_policy","person":id,"answer":answer,"source":"isolated_condition","note":"隔离接收判断替身，不代表真实人物决定"})

func handover_answer(id: String) -> String:
	# baseline沿用已明确的接受替身；额外场景可设置拒绝，结果仍经真实respond结算。
	return handover_answers.get(id,"accept")

func set_behavior(id: String, behavior: String, source: String="isolated_condition") -> void:
	assert(id!=actor_id and behavior in ["stay","follow_actor"],"参与者行为合同无效")
	var body:=_body(id)
	body.set_physics_process(false)
	body.velocity=Vector3.ZERO
	modes[id]=behavior
	if not trails.has(id):
		repositioned(id)
	if not distances.has(id):distances[id]=0.0
	sampled_at[id]=float(distances[id])
	record.call({"type":"participant_fixture_policy","person":id,"behavior":behavior,"source":source,"note":"隔离行为测试替身，不代表真实人物决定"})

func repositioned(id: String) -> void:
	if id==actor_id:
		# 宿主明确布置受检者时，旧路线不再代表连续行走；各替身从新现场重建。
		for participant in modes:repositioned(participant)
		return
	if not modes.has(id):return
	var point: Vector3=sim.actors[actor_id].body.global_position
	var trail: Array[Vector3]=[point]
	trails[id]=trail;trail_samples[id]=point

func _physics_process(delta: float) -> void:
	if not is_instance_valid(sim):return
	var lead: CharacterBody3D=sim.actors[actor_id].body
	for id in modes:
		var trail: Array[Vector3]=trails[id]
		# 只记录受检人物已经实际走过的轨迹，不替他选路、不向候选提供轨迹。
		if lead.global_position.distance_to(trail_samples[id])>=0.35:
			trail.append(lead.global_position);trail_samples[id]=lead.global_position
		if modes[id]!="follow_actor":continue
		var body:=_body(id)
		while trail.size()>1 and _horizontal(trail[0]-body.global_position).length()<0.18:trail.pop_front()
		var direction:=_horizontal(trail[0]-body.global_position)
		var remaining:=direction.length()
		for index in range(1,trail.size()):remaining+=_horizontal(trail[index]-trail[index-1]).length()
		var ray:=PhysicsRayQueryParameters3D.create(body.global_position+Vector3.UP*1.6,lead.global_position+Vector3.UP*1.2,1,[body.get_rid(),lead.get_rid()])
		var visible:=body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		# 拐弯后直线距离近不代表已会合；遮挡时沿真实旧轨迹接近，仍保留碰撞。
		var gap:=2.4 if visible else 1.0
		var speed: float=Player.WALK_SPEED*(0.7 if sim.gathering.basket_for(id)!="" else 1.0)
		speed=minf(speed,minf(direction.length(),maxf(0,remaining-gap))/maxf(delta,0.0001))
		var velocity:=direction.normalized()*speed
		body.velocity.x=velocity.x;body.velocity.z=velocity.z
		body.velocity.y=0 if body.is_on_floor() else body.velocity.y-9.8*delta
		var before:=body.global_position
		GroundMotion.move(body,delta)
		distances[id]+=before.distance_to(body.global_position)
		if float(distances[id])-float(sampled_at[id])>=0.5:
			sampled_at[id]=float(distances[id])
			var event:={"type":"participant_fixture_move","person":id,"position":[body.global_position.x,body.global_position.y,body.global_position.z],"distance_walked":distances[id],"distance_to_actor":body.global_position.distance_to(lead.global_position)}
			if samples.size()<64:samples.append(event.duplicate(true))
			record.call(event)

func _horizontal(direction: Vector3) -> Vector3:
	direction.y=0;return direction

func evidence() -> Dictionary:
	return {"behaviors":modes.duplicate(),"handover_answers":handover_answers.duplicate(),"distance_walked":distances.duplicate(),"samples":samples.duplicate(true),"source":"隔离参与者测试替身，不是正式玩家或模型行为"}
