extends SceneTree
## 仅渲染字幕与头顶卡片；不实例化人物决策、收音、TTS或正式世界。
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void:run.call_deferred()
func capture(path: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
func run() -> void:
	create_timer(25).timeout.connect(func():push_error("字幕排版回归超时");quit(1))
	root.title="Leader · 离线字幕排版"
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,1.65,0);camera.current=true;camera.fov=75
	var head:=preload("res://scripts/voice/head_panel.gd").new();world.add_child(head);head.position=Vector3(-.7,2.6,-2.5)
	head.update_content("月亮","正在学习带路方法\n等待独立验证","请跟着我。\n看不见你，我会等。\n你跟上以后，我再走。\n一起到达果树林再停。")
	var layer:=CanvasLayer.new();root.add_child(layer)
	var note:=Label.new();layer.add_child(note);note.position=Vector2(12,12);note.size=Vector2(550,72)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.max_lines_visible=3
	note.text="你说：请继续学习完整带路，掉队就等我，跟上后再走。\n听众：月亮";note.tooltip_text=note.text
	var original_text:=note.text;var original_pixel_size: float=head.sprite.pixel_size
	var directory:="res://services/text-gateway/runtime/player-control/"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))==OK)
	for size in [Vector2i(1280,800),Vector2i(800,600)]:
		root.size=size;note.position=Vector2(12,12)
		for frame in 4:await process_frame
		var bounds: Rect2=head.screen_rect(camera)
		assert(bounds.has_area() and bounds.intersects(note.get_global_rect()),"须复现原先字幕遮挡卡片的排版")
		await capture(directory+"offline_note_before_%d.png"%size.x)
		var obstacles: Array[Rect2]=[bounds]
		note.position=Voice.transcript_position(note.position,note.size,Vector2(size),obstacles)
		assert(not bounds.grow(8).intersects(note.get_global_rect()),"字幕仍挡住卡片")
		var visible:=Rect2(Vector2.ZERO,Vector2(size))
		assert(visible.encloses(note.get_global_rect()),"字幕不能移出视口")
		assert(Voice.transcript_position(note.position,note.size,Vector2(size),obstacles)==note.position,"无新遮挡时位置必须稳定")
		assert(note.text==original_text and head.sprite.pixel_size==original_pixel_size,"不得缩放头顶卡片或删除玩家台词")
		await capture(directory+"offline_note_after_%d.png"%size.x)
		print("PLAYER_NOTE_LAYOUT_CASE ",size," note=",note.get_global_rect()," card=",bounds)
	head.position.z=2.5
	assert(not head.screen_rect(camera).has_area(),"身后卡片不占据屏幕")
	note.hide()
	print("PLAYER_NOTE_LAYOUT_PASSED projected_head, avoidance, stable_corner, viewport_bounds, text_and_scale_preserved, behind_camera; real_model_calls=0")
	world.queue_free();layer.queue_free();await process_frame;quit()
