extends SceneTree
func _initialize(): run.call_deferred()
func run():
 create_timer(30).timeout.connect(func():push_error("person details timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
 await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/tests/person_details_%s.json"%Time.get_ticks_usec())
 voice.config.local_only=true;voice.config.tts_enabled=false
 var card=voice.captions.person_003
 var camera=scene.get_viewport().get_camera_3d()
 var target=card.global_position+Vector3(0,1.65,0)
 camera.global_position=target+Vector3(0,0,2.5);camera.look_at(target)
 await process_frame;await process_frame
 assert(card.head_panel.visible and not card.bubble.visible)
 var key=InputEventKey.new();key.physical_keycode=KEY_E;key.pressed=true
 print("INPUT_PROBE mode=",Input.mouse_mode," panel=",card.head_panel.visible," menu=",voice.menu.is_open()," sight=",voice._clear_sight(camera.global_position,target)," dot=",(-camera.global_basis.z).dot((target-camera.global_position).normalized()))
 card._input(key)
 await process_frame;await process_frame
 assert(card.expanded and card.bubble.visible,"E不能被隐藏的旧卡片拦截")
 assert(card.head_panel.visible,"展开详情仍保留头顶概要")
 assert(card.bubble.position.x<=8 or card.bubble.position.x>=get_root().size.x/2,"详情不应居中")
 card._input(key)
 await process_frame
 assert(not card.expanded and not card.bubble.visible)
 print("PERSON_DETAILS_PASSED E_open_close, separate_summary, side_details")
 scene.queue_free();await create_timer(0.2).timeout;quit()
