extends SceneTree
func _initialize():
	var harness=preload("res://tools/test_luau_candidate.gd")
	for query in ["perceive","walk_options","recall_locations","observe","body_point","contact_point","inspect_contents","inspect_body","surface","check_placement","plan_grasp"]:
		assert(not harness.needs_action_frame(query))
	for action in ["approach","look_toward","pose","pose_bones","reach_point","grasp","release","take_unit","put_unit","new_unknown_operation"]:
		assert(harness.needs_action_frame(action),"动作和未知操作必须保留画面")
	print("REVIEW_CAPTURE_POLICY_PASSED queries_numeric_actions_visual_unknown_visual")
	quit()
