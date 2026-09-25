extends Node
## 仅负责水面、炉火等环境表现，不改变水量、食物或人物状态。

var hearth_light: OmniLight3D
var elapsed := 0.0


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene := get_parent()
	for mesh in scene.get_node("Cave").find_children("Solid_*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	for mesh in scene.get_node("Outdoor").find_children("Solid_*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("Solid_BoundaryRidge_") or mesh.name == "Solid_CaveHillShell":
			var tint := (mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			tint.albedo_color = Color(0.62, 0.70, 0.58)
			mesh.material_override = tint
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var water := ShaderMaterial.new()
	water.shader = preload("res://scripts/shaders/world_water.gdshader")
	for label in ["WaterPool", "Cenote_water"]:
		var surface := scene.find_child(label, true, false) as MeshInstance3D
		assert(surface != null, "地图缺少水面：" + label)
		surface.material_override = water
	var fire := ShaderMaterial.new()
	fire.shader = preload("res://scripts/shaders/hearth_flame.gdshader")
	for flame in scene.get_node("Cave").find_children("Flame_*", "MeshInstance3D", true, false):
		flame.material_override = fire
	for index in range(200, 203):
		var proxy := scene.get_node("Outdoor").find_child("Solid_Trunk_" + str(index), true, false) as MeshInstance3D
		assert(proxy != null, "地图缺少果树碰撞代理")
		proxy.visible = false
	hearth_light = scene.get_node("HearthGlow") as OmniLight3D
	var sparks := CPUParticles3D.new()
	sparks.name = "HearthSparks"
	sparks.position = Vector3(-4.7, 0.48, 3.2)
	sparks.amount = 20
	sparks.lifetime = 2.4
	sparks.direction = Vector3.UP
	sparks.spread = 22.0
	sparks.gravity = Vector3(0, 0.06, 0)
	sparks.initial_velocity_min = 0.25
	sparks.initial_velocity_max = 0.7
	var particle := SphereMesh.new()
	particle.radius = 0.012
	particle.height = 0.024
	particle.radial_segments = 4
	particle.rings = 2
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.39, 0.07)
	particle.material = glow
	sparks.mesh = particle
	scene.add_child(sparks)


func _process(delta: float) -> void:
	if is_instance_valid(hearth_light):
		elapsed += delta
		hearth_light.light_energy = 0.86 + 0.06 * sin(elapsed * 4.7) + 0.03 * sin(elapsed * 10.3)
