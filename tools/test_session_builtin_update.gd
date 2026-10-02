extends SceneTree
const Luau=preload("res://scripts/skills/luau_contract.gd")
func _initialize() -> void:run.call_deferred()
func change(library: RefCounted, id: String, source: String) -> String:
	var old:=""
	for entry in library.describe("person_002"):
		if entry.id==id:old=entry.ref;break
	assert(not old.is_empty())
	var definition: Dictionary=library.definitions[old].duplicate(true)
	definition.revision_of=old;definition.description="保存前的测试版本"
	if id=="eat":
		definition.parameters={};definition.parameter_kinds={};definition.dependencies={}
		definition.program_json=JSON.stringify(Luau.make_program("return function(args,context) return {ok=false,code='fixture_old'} end",[]))
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok,str(registered))
	assert(library.revise("person_002",old,registered.ref,source).is_empty())
	return registered.ref
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("builtin restore timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	voice.session_manager.path="user://sessions/builtin_update_%d.json"%Time.get_ticks_usec()
	while not voice.survival.ready_for_actions:await physics_frame
	var old:=change(voice.skills.library,"eat","初始生活技能：旧工程版本")
	var taught:=change(voice.skills.library,"look_toward","玩家教导")
	assert((await voice.session_manager.save_game()).is_empty())
	assert((await voice.session_manager.load_game()).is_empty())
	var updated:=""
	for entry in voice.skills.library.describe("person_002"):
		if entry.id=="eat":updated=entry.ref
	assert(updated!="" and updated!=old and voice.skills.library.definitions[updated].parameters.has("source"))
	assert(not voice.skills.library.resolve("person_002",taught).is_empty(),"工程升级不能覆盖玩家修订")
	print("SESSION_BUILTIN_UPDATE_PASSED shipped_updated_taught_retained")
	scene.queue_free();await process_frame;quit()
