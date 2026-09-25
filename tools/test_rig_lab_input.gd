extends SceneTree
func _initialize():call_deferred("run")
func run():
 var lab=load("res://scenes/rig_lab.tscn").instantiate();root.add_child(lab)
 for i in 10:await process_frame
 var target: Node3D=lab.rig.targets["Hand.L"]
 var before:=target.global_position
 var screen: Vector2=lab.camera.unproject_position(before)
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=screen
 Input.parse_input_event(press);await process_frame
 assert(lab.dragging and lab.selected=="Hand.L")
 var move:=InputEventMouseMotion.new();move.position=screen+Vector2(40,20);move.relative=Vector2(40,20);move.button_mask=MOUSE_BUTTON_MASK_LEFT
 Input.parse_input_event(move);await process_frame
 assert(target.global_position.distance_to(before)>.04,"拖动必须改变目标")
 press.pressed=false;press.position=move.position;Input.parse_input_event(press);await process_frame
 assert(not lab.dragging)
 var orientation:=target.quaternion
 var key:=InputEventKey.new();key.keycode=KEY_E;key.pressed=true;Input.parse_input_event(key);await process_frame
 assert(not target.quaternion.is_equal_approx(orientation),"旋转末端目标")
 var depth:=target.global_position
 var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.shift_pressed=true;Input.parse_input_event(wheel);await process_frame
 assert(target.global_position.distance_to(depth)>.05,"深度拖动")
 key.keycode=KEY_2;Input.parse_input_event(key);await process_frame
 assert(lab.rig.targets["Hand.L"].global_position.is_equal_approx(Vector3(.22,.28,.3)))
 key.keycode=KEY_R;Input.parse_input_event(key);await process_frame
 assert(target.global_position.is_equal_approx(before),"复位目标")
 print("RIG_LAB_INPUT_PASSED mouse_drag, release, orientation, depth, preset, reset; model_calls=0")
 lab.free();quit()
