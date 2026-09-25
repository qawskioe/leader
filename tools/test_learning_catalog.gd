extends SceneTree
const Catalog=preload("res://scripts/skills/learning_catalog.gd")

func _initialize() -> void:
	var folder:="user://draft_catalog_probe_%d"%Time.get_ticks_usec()
	for spec in [["own","person_002","bag_raise_demo","failed",true],
		["other","person_003","private_method","failed",true],
		["ready","person_002","already_done","ready",true],
		["empty","person_002","no_source","failed",false]]:
		var path:=folder+"/job_"+str(spec[0])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		_write(path+"/status.json",{"state":spec[3],"message":"验收未完成"})
		_write(path+"/build_request.json",{"goal_id":spec[2],"verification_snapshot":{"person_id":spec[1]},"creation":{"goal":"举袋示意"}})
		if spec[4]: _write(path+"/candidate_definition.json",{})
	var result:=Catalog.scan(["person_002"],folder)
	assert(result.person_002.size()==1)
	assert(result.person_002[0].goal_id=="bag_raise_demo")
	assert(not result.person_002[0].has("source"))
	var controller=preload("res://scripts/skills/controller.gd").new()
	controller.store=preload("res://scripts/voice/people_store.gd").new()
	assert(controller.store.initialize("res://data/people.json",folder+"/memory.json",true).is_empty())
	controller.learning_drafts=result
	controller.sync_person("person_002")
	assert(controller.store.context_for("person_002").learning_drafts.size()==1)
	assert(controller.store.context_for("person_002").available_skills.is_empty(),"草稿不是已掌握技能")
	assert(controller.library.initialize(folder+"/library.json",controller.store.people).is_empty())
	assert(controller.library.install_builtins().is_empty())
	controller.learning_drafts.person_002.append({"goal_id":"take_object","goal":"旧拿取草稿"})
	controller.sync_person("person_002")
	assert(not controller.store.context_for("person_002").available_skills.is_empty())
	assert(controller.store.context_for("person_002").learning_drafts.size()==1,"已经掌握的技能不再作为新学习草稿展示")
	controller.free()
	for name in DirAccess.get_directories_at(folder):
		var path:=folder.path_join(name)
		for file in DirAccess.get_files_at(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("LEARNING_CATALOG_PASSED own_failed_only, no_grant, context_visible; real_model_calls=0")
	quit()

func _write(path: String, value: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value));file.close()
