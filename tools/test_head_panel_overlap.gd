extends SceneTree
## 真实面板投影的拥挤回归，不启动人物模型、录音或正式世界。
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("head panel overlap timeout");quit(1))
	root.size=Vector2i(1280,800)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.position.y=1.65;camera.current=true;camera.fov=75
	var panels: Dictionary={}
	for id in ["moon","flower","distant"]:
		var panel=load("res://scripts/voice/head_panel.gd").new();world.add_child(panel);panels[id]=panel
	panels.moon.position=Vector3(0,2.05,-2.5)
	panels.flower.position=Vector3(.12,2.05,-2.65)
	panels.distant.position=Vector3(1.8,2.05,-2.4)
	panels.moon.update_content("月亮","已听见 · 已作出回应\n正在验证方法","先学好，等你要求再演示。")
	panels.flower.update_content("小花 · 听见","已听见 · 已作出回应","",true,false)
	panels.distant.update_content("石头","正在休息","",true,false)
	for frame in 4:await process_frame
	var origins: Dictionary={}
	for id in panels:origins[id]={"position":panels[id].position,"pixel_size":panels[id].sprite.pixel_size}
	assert(panels.moon.screen_rect(camera).intersects(panels.flower.screen_rect(camera)),"必须复现邻人卡片重叠")
	await capture("offline_head_overlap_before.png")
	var selected:=apply_layout(panels,camera,"moon")
	assert("moon" in selected and "distant" in selected and not "flower" in selected)
	assert(not panels.flower.sprite.visible and panels.flower.visible,"隐藏绘制不能阻止视线选择")
	await capture("offline_head_overlap_after.png")
	selected=apply_layout(panels,camera,"flower")
	assert("flower" in selected and not "moon" in selected,"转向邻人后其详情仍可成为主卡片")
	panels.moon.position.x=-1.8
	selected=apply_layout(panels,camera,"flower")
	assert("moon" in selected and "flower" in selected,"不再重叠时恢复面板")
	panels.moon.position=origins.moon.position
	for id in panels:
		assert(panels[id].position==origins[id].position and panels[id].sprite.pixel_size==origins[id].pixel_size)
	print("HEAD_PANEL_OVERLAP_PASSED actual_projection_focus_priority_switch_restore_fixed_world_pose; model_calls=0")
	world.queue_free();await process_frame;quit()
func apply_layout(panels: Dictionary,camera: Camera3D,focus: String) -> PackedStringArray:
	var entries: Array[Dictionary]=[]
	for id in panels:entries.append({"id":id,"priority":0 if id==focus else 2,"distance":camera.global_position.distance_squared_to(panels[id].global_position),"rectangle":panels[id].screen_rect(camera)})
	var selected:=Voice.visible_head_panels(entries)
	for id in panels:panels[id].sprite.visible=id in selected
	for left in selected:
		for right in selected:
			if left!=right:assert(not panels[left].screen_rect(camera).intersects(panels[right].screen_rect(camera)))
	return selected
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://services/text-gateway/runtime/player-control/"+name)==OK)
