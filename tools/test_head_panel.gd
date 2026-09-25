extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var panel=load("res://scripts/voice/head_panel.gd").new();root.add_child(panel)
 var image=Image.create(800,600,false,Image.FORMAT_RGB8)
 panel.update_content("大山","正在进行独立动作验证，验证失败将保留旧版本。正在学习动作。".repeat(5),"这是一段需要换行的公开台词。".repeat(15))
 await process_frame;await process_frame
 var box=panel.view.get_child(0).get_child(0)
 var bottom:=0.0
 for child in box.get_children():
  if not child.visible:continue
  assert(child.position.y>=bottom,"面板内容重叠")
  bottom=child.position.y+child.size.y
 assert(bottom<=panel.view.size.y,"内容超出面板: "+str(bottom))
 assert(is_equal_approx(panel.sprite.pixel_size,0.002) and panel.scale==Vector3.ONE)
 panel.update_content("大山","闲置状态","",true)
 await process_frame;await process_frame
 assert(panel.view.size.x<300 and not panel.status.visible and panel.title.text=="大山")
 panel.update_content("大山","正在说话","我听到了",false)
 await process_frame;await process_frame
 assert(panel.view.size.x==720 and panel.speech.visible and panel.status.visible)
 print("HEAD_PANEL_PASSED bottom=",bottom," fixed_world_size=true")
 panel.queue_free();await process_frame;quit()
