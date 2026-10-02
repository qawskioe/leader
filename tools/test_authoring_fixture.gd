extends SceneTree
## 只准备隔离编写夹具，不伪称正常游玩，也不调用云端模型。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var actor: Dictionary=sim.actors.person_003
	actor.body.global_position=sim.water.SOURCE+Vector3(0,0.6,-0.65);actor.body.rotation.y=0
	for frame in 30:await physics_frame
	store.people.person_003.needs.thirst=80
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/authoring_fixture_"+str(Time.get_ticks_usec())+".json").is_empty());assert(controller.library.install_builtins().is_empty())
	var owned: Dictionary={};var drink:=""
	for entry in controller.library.owners.person_003:
		owned[entry.ref]=controller.library.definitions[entry.ref]
		if owned[entry.ref].id=="drink":drink=entry.ref
	var folder:="res://services/skill-runtime/runtime/jobs/job_migration_fixture"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))==OK)
	var context: Dictionary=sim.space.prepare_context("person_003",store.context_for("person_003"),sim.space.capture("person_003"))
	context.interaction_rules={"mode":"simplified","range_m":1.6}
	var request:={"goal_id":"observe_then_drink","revision":{},"creation":{"goal":"先观察当前周围，再喝一口水，身体动作必须实际发生","player_event":{"id":"migration_fixture","kind":"speech_intent","speaker":"player","text":"大山，学会先观察周围，再喝一口水"}},"owned_skills":owned,"character_context":context,"world_operations":preload("res://scripts/skills/luau_contract.gd").OPERATIONS,"verification_snapshot":preload("res://scripts/skills/verification_snapshot.gd").capture(sim,"person_003")}
	var program:=preload("res://scripts/skills/luau_contract.gd").make_program('return function(args, context) local seen=world.request("perceive",{}) if not seen.ok then return seen end return skills.call("drink",{},context) end',["perceive"])
	var definition:={"id":request.goal_id,"name":"观察后喝水","description":"观察当前周围再喝水","parameters":{},"parameter_kinds":{},"dependencies":{"drink":drink},"program_json":JSON.stringify(program)}
	for key in {"build_request.json":request,"candidate_definition.json":definition,"candidate.json":program,"test_arguments.json":{}}:
		var file:=FileAccess.open(folder+"/"+key,FileAccess.WRITE);file.store_string(JSON.stringify({"build_request.json":request,"candidate_definition.json":definition,"candidate.json":program,"test_arguments.json":{}}[key]));file.close()
	print("AUTHORING_FIXTURE_READY snapshot_dependencies_personal_context")
	scene.queue_free();await create_timer(0.2).timeout;quit()
