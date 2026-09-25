extends Node3D
## 独立离线控制实验台；不启动人物决策、语音或生存模拟。
var rig: Node3D
var camera: Camera3D
var hud: Label
var markers: Dictionary={}
var selected:="Hand.L"
var dragging:=false
var plane: Plane
var offset:=Vector3.ZERO
var orbit:=false
var yaw:=0.55
var pitch:=0.12
var radius:=3.6
var clock:=0.0
var capture_at:=-1.0
var capture_path:=""
var preset:=1

func _ready() -> void:
 DisplayServer.window_set_title("Leader · IK 控制实验台（离线）")
 var environment:=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("202834")
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.65;add_child(environment)
 var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-45,-35,0);key.light_energy=1.5;key.shadow_enabled=true;add_child(key)
 var fill:=OmniLight3D.new();fill.position=Vector3(-2,2,2);fill.light_energy=1.2;fill.omni_range=6;add_child(fill)
 var floor:=MeshInstance3D.new();var mesh:=PlaneMesh.new();mesh.size=Vector2(6,6);floor.mesh=mesh
 var material:=StandardMaterial3D.new();material.albedo_color=Color("465064");floor.material_override=material;add_child(floor)
 var model=load("res://assets/characters/person_v2_02.glb").instantiate();add_child(model)
 var skeleton: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
 for animation in model.find_children("*","AnimationPlayer",true,false):animation.stop()
 rig=load("res://scripts/rig/target_rig.gd").new();add_child(rig);rig.initialize(skeleton)
 camera=Camera3D.new();camera.fov=48;add_child(camera);_camera()
 var controls: Dictionary=rig.targets.duplicate();controls["Hips"]=rig.pelvis
 for name in rig.poles:controls["Pole/"+name]=rig.poles[name]
 for name in controls:
  var sphere:=MeshInstance3D.new();var shape:=SphereMesh.new();shape.radius=0.035 if str(name).begins_with("Pole/") else 0.045;shape.height=shape.radius*2;sphere.mesh=shape
  var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("8da1b5") if str(name).begins_with("Pole/") else Color("ffcb56") if str(name).begins_with("Hand") else Color("79cdff") if str(name).begins_with("Foot") else Color("c090ff")
  sphere.material_override=mat;controls[name].add_child(sphere)
  var label:=Label3D.new();label.text={"Hand.L":"左手","Hand.R":"右手","Foot.L":"左脚","Foot.R":"右脚","Hips":"骨盆"}.get(name,"弯曲方向")
  label.position.y=.08;label.font_size=24;label.pixel_size=.002;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;controls[name].add_child(label)
  markers[name]=controls[name]
 var canvas:=CanvasLayer.new();add_child(canvas)
 hud=Label.new();hud.position=Vector2(16,16);hud.add_theme_font_size_override("font_size",18);hud.add_theme_color_override("font_shadow_color",Color.BLACK);hud.add_theme_constant_override("shadow_offset_x",1);hud.add_theme_constant_override("shadow_offset_y",1);canvas.add_child(hud)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--rig-preset="):preset=int(arg.get_slice("=",1))
  if arg.begins_with("--rig-capture="):capture_path=arg.get_slice("=",1);capture_at=3.0
 apply_preset(preset)

func _camera() -> void:
 camera.position=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*radius+Vector3(0,.9,0)
 camera.look_at(Vector3(0,.9,0))

func apply_preset(value: int) -> void:
 preset=value;rig.reset_targets()
 if value==2:
  rig.targets["Hand.L"].global_position=Vector3(.22,.28,.30)
  rig.targets["Hand.R"].global_position=Vector3(-.22,.28,.30)
 elif value==3:
  rig.targets["Hand.L"].global_position=Vector3(.22,1.25,.38)
  rig.targets["Hand.R"].global_position=Vector3(-.22,1.25,.38)
 elif value==4:rig.targets["Hand.L"].global_position=Vector3(1.4,1.25,.4)

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_RIGHT:orbit=event.pressed
  if event.button_index==MOUSE_BUTTON_LEFT:
   dragging=false
   if event.pressed:
    var best:=24.0
    for name in markers:
     if camera.is_position_behind(markers[name].global_position):continue
     var distance:=camera.unproject_position(markers[name].global_position).distance_to(event.position)
     if distance<best:best=distance;selected=name;dragging=true
    if dragging:
     if selected=="Hips":rig.auto_posture=false
     var point: Vector3=markers[selected].global_position
     plane=Plane(camera.global_basis.z,point)
     var hit: Variant=plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
     offset=point-hit if hit is Vector3 else Vector3.ZERO
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   var amount:=.06 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.06
   if event.shift_pressed:markers[selected].global_position-=camera.global_basis.z*amount
   else:radius=clampf(radius-amount*3,1.8,6);_camera()
 elif event is InputEventMouseMotion:
  if dragging:
   var hit: Variant=plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
   if hit is Vector3:markers[selected].global_position=hit+offset
  elif orbit:yaw-=event.relative.x*.006;pitch=clampf(pitch+event.relative.y*.004,-.2,.8);_camera()
 elif event is InputEventKey and event.pressed and not event.echo:
  if event.keycode>=KEY_1 and event.keycode<=KEY_4:apply_preset(event.keycode-KEY_0)
  if event.keycode==KEY_R:rig.auto_posture=true;apply_preset(1)
  if event.keycode==KEY_A:rig.auto_posture=not rig.auto_posture
  if event.keycode in [KEY_Q,KEY_E,KEY_Z,KEY_C] and rig.targets.has(selected):
   markers[selected].rotate_object_local(Vector3.UP if event.keycode in [KEY_Q,KEY_E] else Vector3.FORWARD,deg_to_rad(-10 if event.keycode in [KEY_Q,KEY_Z] else 10))

func _process(delta: float) -> void:
 clock+=delta
 if hud==null:return
 var lines: PackedStringArray=["角色 IK 实验台 · 无模型调用", "左键拖控制点｜右键旋转视角｜滚轮缩放｜Shift+滚轮调目标深度", "Q/E 转末端朝向 · Z/C 转末端倾斜｜A 自动下蹲｜R 复位", "1 站立 · 2 低处伸手 · 3 胸前举手 · 4 够不到", "当前："+selected+"　自动下蹲："+("开" if rig.auto_posture else "关")]
 for name in rig.sample:
  var data: Dictionary=rig.sample[name]
  lines.append("%s：误差 %.1f cm · 弯曲 %.0f° %s"%[name,data.error_m*100,data.bend_degrees,"【目标超出范围】" if data.limited else ""])
 lines.append("黄色：手腕目标　蓝色：脚踝目标　紫色：骨盆　灰色：肘/膝弯曲方向")
 lines.append("当前为运动学控制；未实现全身碰撞、动态平衡或手指抓握。")
 for name in markers:
  for child in markers[name].get_children():
   if child is Label3D:child.visible=name==selected
 hud.text="\n".join(lines)
 if capture_at>0 and clock>=capture_at:
  capture_at=-1;await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png(capture_path)
  print("RIG_CAPTURE ",capture_path)
  if "--rig-exit" in OS.get_cmdline_user_args():get_tree().quit()
