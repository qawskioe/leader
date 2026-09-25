extends SceneTree
const Test=preload("res://tools/test_fuzzy_placement.gd")
func _initialize() -> void:
	assert(Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,1),Vector3.ZERO,"",true,false,true))
	assert(not Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,1),Vector3.ZERO,"person_003",true,false,true))
	assert(not Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,1),Vector3.ZERO,"",false,false,true))
	assert(not Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,1),Vector3.ZERO,"",true,false,false))
	assert(not Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,0.3),Vector3.ZERO,"",true,false,true))
	assert(not Test.completed_goal(Vector3(0,0,0.3),Vector3(0,0,1),Vector3.ZERO,"",true,true,true))
	print("FUZZY_OUTCOME_PASSED success_and_five_failure_modes");quit()
