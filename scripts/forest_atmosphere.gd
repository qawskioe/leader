extends Node
## 室外渐变大气：依据相机位置混合，洞内继续沿用原有照明。

var environment: Environment
var sun: DirectionalLight3D
var camera: Camera3D
var indoor_ambient: Color
var indoor_energy: float
var indoor_sun_color: Color
var indoor_sun_energy: float
var indoor_sun_rotation: Vector3


func _ready() -> void:
	# 父节点在 _ready 中创建环境和玩家相机，延后一轮取得这些已初始化对象。
	_setup.call_deferred()


func _setup() -> void:
	var scene := get_parent()
	var worlds := scene.find_children("*", "WorldEnvironment", false, false)
	assert(worlds.size() == 1, "森林要求主场景提供唯一 WorldEnvironment")
	environment = (worlds[0] as WorldEnvironment).environment
	sun = scene.get_node("OutdoorSun") as DirectionalLight3D
	camera = scene.get_node("Player").camera
	for proxy in scene.get_node("Outdoor").find_children("Solid_ForestTrunk_*", "MeshInstance3D", true, false):
		proxy.visible = false
	# 近处保留叶片轮廓，远处切换共享简化网格。切换不依赖固定预览相机。
	for tree in scene.get_node("Outdoor").find_children("WoodlandTree_*", "MeshInstance3D", true, false):
		tree.visibility_range_end = 28.0
		tree.visibility_range_end_margin = 3.0
	for tree in scene.get_node("Outdoor").find_children("DistantTree_*", "MeshInstance3D", true, false):
		tree.visible = true
		tree.visibility_range_begin = 28.0
		tree.visibility_range_begin_margin = 3.0
	indoor_ambient = environment.ambient_light_color
	indoor_energy = environment.ambient_light_energy
	indoor_sun_color = sun.light_color
	indoor_sun_energy = sun.light_energy
	indoor_sun_rotation = sun.rotation
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	environment.fog_light_color = Color(0.57, 0.65, 0.64)
	environment.fog_sun_scatter = 0.18
	environment.fog_sky_affect = 0.25
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = Color(0.30, 0.44, 0.59)
	sky_material.sky_horizon_color = Color(0.76, 0.78, 0.73)
	_update_atmosphere()


func _process(_delta: float) -> void:
	if is_instance_valid(camera) and environment != null:
		_update_atmosphere()


func _update_atmosphere() -> void:
	var outside := smoothstep(16.0, 24.0, camera.global_position.z)
	environment.ambient_light_color = indoor_ambient.lerp(Color(0.48, 0.56, 0.65), outside)
	environment.ambient_light_energy = lerpf(indoor_energy, 0.28, outside)
	environment.fog_enabled = outside > 0.01
	environment.fog_density = 0.0025 * outside
	sun.light_color = indoor_sun_color.lerp(Color(1.0, 0.84, 0.61), outside)
	sun.light_energy = lerpf(indoor_sun_energy, 1.1, outside)
	sun.rotation = Vector3(
		lerp_angle(indoor_sun_rotation.x, deg_to_rad(-27.0), outside),
		lerp_angle(indoor_sun_rotation.y, deg_to_rad(-35.0), outside), 0.0)
