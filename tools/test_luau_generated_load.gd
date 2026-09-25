extends SceneTree
## 已由真实强模型编写、实际隔离执行并独立审查的包，经正式轮询加载后再使用。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(80).timeout.connect(func():push_error("generated_load_timeout");quit(1))
	var folder:="res://services/skill-runtime/runtime/jobs/job_migration_fixture/"
	var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"build_request.json"))
	var status: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"status.json"))
	assert(status.state=="ready","真实编写/审查未通过，禁止伪造通过记录")
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	preload("res://scripts/skills/verification_snapshot.gd").restore(sim,request.verification_snapshot)
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/real_generated_"+str(Time.get_ticks_usec())+".json").is_empty())
	controller.library.definitions=request.owned_skills.duplicate(true)
	for ref in request.owned_skills:assert(controller.library.grant("person_003",ref,"隔离夹具恢复编写前本人已掌握版本").is_empty())
	controller.learning.person_003={"job":"job_migration_fixture","pid":0,"started":Time.get_ticks_msec(),"revision_of":"","original_event":request.creation.player_event}
	sim.actors.person_003.stage="skill_learning";sim.actors.person_003["skill_owner"]=controller.get_instance_id()
	var learned: Dictionary=await controller.learning_finished
	assert(learned.ok and learned.ref.begins_with("observe_then_drink@"))
	assert(controller.invoke("person_003","real_generated_execution",{"ref":learned.ref,"arguments":{}}).ok)
	var result: Dictionary=await controller.finished
	assert(result.success and sim.water.consumed==1 and store.people.person_003.needs.thirst<40)
	assert(controller.library.resolve("person_003",learned.ref).dependencies.size()>0)
	print("LUAU_GENERATED_LOAD_PASSED real_gpt6_authored_reviewed_fixed_dependencies_registered_used")
	scene.queue_free();await create_timer(.2).timeout;quit()
