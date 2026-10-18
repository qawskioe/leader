extends RefCounted
## 跨步仍使用完整人物碰撞体扫掠；只允许抬脚，不跳过墙体或头顶碰撞。
const STEP_HEIGHT:=0.30
const MIN_FLOOR_Y:=0.85
const BODY_RADIUS:=0.30
const BODY_HEIGHT:=1.70

static func try_step(body: CharacterBody3D, motion: Vector3) -> bool:
	if not body.is_on_floor() or motion.length_squared()<0.000001: return false
	var start:=body.global_transform
	var landing:=step_destination(body,start,motion)
	if landing.is_empty():return false
	body.global_position=landing.position
	body.velocity.y=0
	body.apply_floor_snap()
	return true

static func step_destination(body: CharacterBody3D, start: Transform3D, motion: Vector3) -> Dictionary:
	# 真实跨步与路径预判使用同一碰撞、净空和台面规则；查询不移动人物。
	var wall:=KinematicCollision3D.new()
	if not body.test_move(start,motion,wall): return {}
	if wall.get_normal().y>=MIN_FLOOR_Y: return {}
	var up:=Vector3.UP*STEP_HEIGHT
	if body.test_move(start,up): return {}
	var raised:=start
	raised.origin+=up
	if body.test_move(raised,motion): return {}
	raised.origin+=motion
	# 胶囊底部接触台阶棱边时，碰撞法线是斜的，不代表台面陡峭。
	# 向前探测脚即将踏上的台面，再用完整胶囊扫掠验证抬升空间。
	var probe:=raised.origin+motion.normalized()*(BODY_RADIUS+0.02)
	probe.y=start.origin.y+STEP_HEIGHT+0.01
	var query:=PhysicsRayQueryParameters3D.create(probe,probe-Vector3.UP*(STEP_HEIGHT+0.04),body.collision_mask,[body.get_rid()])
	var landing:=body.get_world_3d().direct_space_state.intersect_ray(query)
	if landing.is_empty() or landing.normal.y<MIN_FLOOR_Y: return {}
	# 成员、篮子不能当台阶；地形必须是静态场景碰撞。
	var support: Object=landing.collider
	if not support is StaticBody3D or support.collision_layer!=1: return {}
	var destination:=start.origin+motion
	destination.y=landing.position.y+0.001
	var rise:=destination.y-start.origin.y
	if rise<0.005 or rise>STEP_HEIGHT: return {}
	var lifted:=start
	lifted.origin.y=destination.y
	if body.test_move(lifted,motion): return {}
	return {"position":destination}

static func path_clear(body: CharacterBody3D, target: Vector3) -> bool:
	var at:=body.global_transform
	var horizontal:=target-at.origin
	horizontal.y=0
	var distance:=horizontal.length()
	if distance<0.001:return true
	var direction:=horizontal/distance
	var floor_y:=cos(body.floor_max_angle)
	# 单次长扫掠只返回最早接触；按短段贴地前进，地面接触后继续检查。
	# 终点高度不能替代沿途可跨越的高度，累计缓坡也不能当成高台阶。
	for index in ceili(distance/0.20):
		var segment:=direction*minf(.20,distance-index*.20)
		var origin:=at
		at.origin+=Vector3.UP*.04
		var remaining:=segment
		var resolved:=false
		for slide in body.max_slides:
			var query:=PhysicsTestMotionParameters3D.new()
			query.from=at;query.motion=remaining;query.margin=.005
			var collision:=PhysicsTestMotionResult3D.new()
			if not PhysicsServer3D.body_test_motion(body.get_rid(),query,collision):
				at.origin+=remaining;resolved=true;break
			var normal:=collision.get_collision_normal(0)
			if normal.y<floor_y:
				# 试走回执可能先包含引擎推出重叠的位移，要求的运动却还完全没开始。
				# 把复位与本段步进分开，再从复位后的虚拟身体完整重查；不移动真实身体。
				# 不能把“尚有接触”直接当作退路封死，也不能因复位成功就放行穿过阻挡。
				var recovery:=collision.get_travel()-(remaining-collision.get_remainder())
				if recovery.length_squared()>.00000001:
					at.origin+=recovery
					origin.origin+=recovery
					continue
				var step:=step_destination(body,origin,segment)
				if not step.is_empty():
					at.origin=step.position;resolved=true;break
				# 不能跨步的侧面接触仍可沿碰撞面滑动，真实move_and_slide也会这样做。
				# 扫掠、落脚与最终距离继续核验，不能把一次擦碰等同于整条路线封死。
			at.origin+=collision.get_travel()
			remaining=collision.get_remainder().slide(normal)
			if remaining.length_squared()<.000001:resolved=true;break
		if not resolved:return false
		# 完整身体向下扫掠确认落脚，预判不能跳过缺口。
		var down:=PhysicsTestMotionParameters3D.new()
		down.from=at;down.from.origin+=Vector3.UP*.04
		down.motion=Vector3.DOWN*(STEP_HEIGHT+.08);down.margin=.005
		var floor_hit:=PhysicsTestMotionResult3D.new()
		if not PhysicsServer3D.body_test_motion(body.get_rid(),down,floor_hit):return false
		if floor_hit.get_collision_normal(0).y<floor_y:return false
		at.origin=down.from.origin+floor_hit.get_travel()
	var error:=target-at.origin;error.y=0
	return error.length()<=.20

static func move(body: CharacterBody3D, delta: float) -> void:
	var horizontal:=Vector3(body.velocity.x,0,body.velocity.z)
	if try_step(body,horizontal*delta):
		# 本帧的水平位移已由扫掠完成，不能再走一次。
		body.velocity.x=0
		body.velocity.z=0
		body.move_and_slide()
		body.velocity.x=horizontal.x
		body.velocity.z=horizontal.z
	else:
		body.move_and_slide()
