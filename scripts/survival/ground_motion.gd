extends RefCounted
## 跨步仍使用完整人物碰撞体扫掠；只允许抬脚，不跳过墙体或头顶碰撞。
const STEP_HEIGHT:=0.30
const MIN_FLOOR_Y:=0.85
const BODY_RADIUS:=0.30
const BODY_HEIGHT:=1.70

static func try_step(body: CharacterBody3D, motion: Vector3) -> bool:
	if not body.is_on_floor() or motion.length_squared()<0.000001: return false
	var start:=body.global_transform
	var wall:=KinematicCollision3D.new()
	if not body.test_move(start,motion,wall): return false
	if wall.get_normal().y>=MIN_FLOOR_Y: return false
	var up:=Vector3.UP*STEP_HEIGHT
	if body.test_move(start,up): return false
	var raised:=start
	raised.origin+=up
	if body.test_move(raised,motion): return false
	raised.origin+=motion
	# 胶囊底部接触台阶棱边时，碰撞法线是斜的，不代表台面陡峭。
	# 向前探测脚即将踏上的台面，再用完整胶囊扫掠验证抬升空间。
	var probe:=raised.origin+motion.normalized()*(BODY_RADIUS+0.02)
	probe.y=start.origin.y+STEP_HEIGHT+0.01
	var query:=PhysicsRayQueryParameters3D.create(probe,probe-Vector3.UP*(STEP_HEIGHT+0.04),body.collision_mask,[body.get_rid()])
	var landing:=body.get_world_3d().direct_space_state.intersect_ray(query)
	if landing.is_empty() or landing.normal.y<MIN_FLOOR_Y: return false
	# 成员、篮子不能当台阶；地形必须是静态场景碰撞。
	var support: Object=landing.collider
	if not support is StaticBody3D or support.collision_layer!=1: return false
	var destination:=start.origin+motion
	destination.y=landing.position.y+0.001
	var rise:=destination.y-start.origin.y
	if rise<0.005 or rise>STEP_HEIGHT: return false
	var lifted:=start
	lifted.origin.y=destination.y
	if body.test_move(lifted,motion): return false
	body.global_position=destination
	body.velocity.y=0
	body.apply_floor_snap()
	return true

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
