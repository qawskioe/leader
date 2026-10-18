extends SceneTree
const Luau=preload("res://scripts/skills/luau_contract.gd")
var folders: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func write_job(job: String, definition: Dictionary, corrupt: bool=false) -> void:
	var folder:="res://services/skill-runtime/runtime/jobs/"+job
	assert(not DirAccess.dir_exists_absolute(folder),"夹具不得覆盖已有任务")
	assert(DirAccess.make_dir_recursive_absolute(folder)==OK);folders.append(folder)
	var raw:=JSON.stringify(definition)
	var receipt:={"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":"bad" if corrupt else raw.sha256_text()}
	var request:={"goal_id":definition.id,"character_context":{"id":"person_001"},"revision":{},"creation":{"goal":"恢复已验证方法，不执行动作","player_event":{"id":"fixture_recover","kind":"speech_intent","speaker":"player","text":"恢复已验证方法，暂不演示"}}}
	if definition.has("revision_of"):request.revision={"ref":definition.revision_of,"player_event":request.creation.player_event};request.creation={}
	for name in ["status.json","build_request.json","package.json"]:
		var value: Dictionary={"state":"ready","model":"fixture"} if name=="status.json" else request if name=="build_request.json" else {"definition":definition,"receipt":receipt}
		var file:=FileAccess.open(folder+"/"+name,FileAccess.WRITE);assert(file!=null);file.store_string(JSON.stringify(value));file.close()
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("verified recovery timeout");quit(1))
	var job:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-learning-job="):job=arg.trim_prefix("--resume-learning-job=")
	assert(not job.is_empty(),"需要唯一的恢复夹具任务编号")
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	voice.session_manager.path="user://sessions/recovery_%d.json"%Time.get_ticks_usec()
	while not voice.survival.ready_for_actions:await physics_frame
	var library: RefCounted=voice.skills.library
	var definition:={"id":"recovery_fixture","name":"恢复夹具","description":"仅验证任务恢复合同","parameters":{},"program_json":JSON.stringify(Luau.make_program("return function(args,context) return {ok=true,code='fixture'} end",[]))}
	write_job(job,definition)
	var inventory: int=voice.survival.storage_food
	await voice.session_manager.startup()
	assert(not voice.session_manager.load_failed,voice.menu.session_status.text)
	assert(voice.menu.session_status.text.begins_with("已恢复并保存已验证技能"))
	var restored:=""
	for entry in library.describe("person_001"):
		if entry.id==definition.id:restored=entry.ref
	assert(not restored.is_empty() and voice.skills.active.is_empty() and voice.survival.storage_food==inventory)
	var saved:=preload("res://scripts/survival/session_store.gd").read(voice.session_manager.path,voice.survival)
	assert(saved.ok and saved.library.resolve("person_001",restored).id==definition.id,"新版本必须进入统一存档")
	var size: int=library.owners.person_001.size()
	assert(voice.skills.recover_verified_job(job).already_loaded and library.owners.person_001.size()==size)
	assert(not voice.skills.recover_verified_job("../package").ok)
	var conflict:=definition.duplicate(true);conflict.revision_of="wrong@parent"
	write_job(job+"1",conflict)
	assert(not voice.skills.recover_verified_job(job+"1").ok and library.owners.person_001.size()==size)
	var invalid:=definition.duplicate(true);invalid.id="invalid_receipt"
	write_job(job+"2",invalid,true)
	assert(voice.skills.recover_verified_job(job+"2").ok)
	var rejected: Dictionary=await voice.skills.learning_finished
	assert(not rejected.ok and library.owners.person_001.size()==size and voice.survival.storage_food==inventory)
	# 将本测试创建的任务归档到扫描范围外，避免夹具进入正式人物的草稿目录。
	var archive:="res://services/skill-runtime/runtime/recovery-test-archive"
	assert(DirAccess.make_dir_recursive_absolute(archive)==OK)
	for folder in folders:assert(DirAccess.rename_absolute(folder,archive+"/"+folder.get_file())==OK)
	print("VERIFIED_JOB_RECOVERY_PASSED startup_checkpoint_idempotent_conflict_receipt_no_actions")
	assert((await voice.mic.stop_for_shutdown()).is_empty())
	scene.queue_free();await process_frame;quit()
