extends SceneTree
class Controller extends "res://scripts/skills/controller.gd":
	var ended:=""
	func _end_learning(id: String, _ok: bool, message: String, _ref: String="") -> void:
		ended=message;learning.erase(id)
func _initialize() -> void:
	var controller:=Controller.new()
	var job:="job_timeout_fixture_"+str(Time.get_ticks_usec())
	var folder:="res://services/skill-runtime/runtime/jobs/"+job
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))==OK)
	controller.learning={"person_002":{"job":job,"started":Time.get_ticks_msec()-int((controller.build_policy.budget_seconds+controller.build_policy.host_grace_seconds)*1000)-1}}
	controller._process(1.0)
	assert(controller.learning.is_empty() and controller.ended.contains("超时"))
	assert(FileAccess.get_file_as_string(folder+"/cancelled")=="host_timeout","宿主超时必须通知后台禁止迟到发布")
	controller.free()
	print("LEARNING_TIMEOUT_PASSED shared_budget_and_worker_cancellation")
	quit()
