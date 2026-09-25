extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/test_registered_%d.json"%Time.get_ticks_usec())
	var refs: Dictionary={}
	for entry in voice.skills.library.describe("person_003"):
		refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	assert(refs.has("take_object") and refs.has("release_object"))
	var legacy:={"id":"old","name":"旧格式","description":"不能通过新库","parameters":{},"program_json":JSON.stringify({"format":"leader-skill-1","body":[]})}
	assert(not voice.skills.library._valid_definition(legacy),"正式技能库不能接受旧格式")
	var replay: Dictionary=preload("res://scripts/voice/cloud_client.gd").validate_decision(FileAccess.get_file_as_string("res://tools/fixtures/silent_take_decision.json"),true,true)
	assert(replay.ok,JSON.stringify(replay))
	assert(replay.decision.public_reply.is_empty() and replay.decision.skill_call.arguments.object=="wood_block")
	var invalid: Dictionary=replay.decision.duplicate(true)
	invalid.conversation.participation="listen";invalid.public_reply="我来回答";invalid.speech_style="平静"
	assert(not preload("res://scripts/voice/cloud_client.gd").validate_decision(JSON.stringify(invalid),true,true).ok)
	invalid.conversation.participation="interject";invalid.public_reply=""
	assert(not preload("res://scripts/voice/cloud_client.gd").validate_decision(JSON.stringify(invalid),true,true).ok)
	for goal in ["take_object","release_object"]:
		replay.decision.skill_call.ref=refs.take_object # 原始决策重放，测试库使用当前内置版本
		var call: Dictionary=replay.decision.skill_call if goal=="take_object" else {"ref":refs[goal],"arguments":{"object":"wood_block"}}
		var submitted: Dictionary=voice.skills.invoke("person_003","fixture_"+goal,call)
		assert(submitted.ok,JSON.stringify(submitted))
		var result: Dictionary=await voice.skills.finished
		assert(result.success and result.goal_verified,JSON.stringify(result))
		var knowledge: Dictionary=voice.survival.perception.known("person_003","wood_block")
		assert(knowledge.extra.holder==("person_003" if goal=="take_object" else ""),"人物必须知道实际持有状态")
	var remembered: Dictionary=voice.survival.perception.known("person_003","wood_block")
	var actor: Node3D=voice.survival.actors.person_003.body
	actor.global_position+=Vector3(0,0,30)
	voice.skills.world_objects.objects.wood_block.body.global_position+=Vector3(5,0,0)
	voice.survival.perception.observe("person_003")
	var unseen: Dictionary=voice.survival.perception.known("person_003","wood_block")
	assert(not unseen.visible_now and unseen.position==remembered.position,"未看见物品移动时不能灌入新位置")
	var old_ref: String=refs.take_object
	var next: Dictionary=voice.skills.library.definitions[old_ref].duplicate(true)
	next.revision_of=old_ref;next.description="修订夹具：保持实际拿取效果"
	var raw:=JSON.stringify(next)
	var registered: Dictionary=voice.skills.library.register_verified(next,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok)
	assert(voice.skills.library.revise("person_003",old_ref,registered.ref,"离线版本替换验证").is_empty())
	assert(voice.skills.library.describe("person_001")[0].ref!=registered.ref)
	assert(voice.skills.library.install_builtins().is_empty())
	var present:=false
	for entry in voice.skills.library.describe("person_003"):
		if entry.ref==registered.ref: present=true
	assert(present,"初始化内置技能不能覆盖个人修订")
	print("LUAU_REGISTERED_PASSED original_rejected_decision_replay, real_controller_call, two_builtins, authoritative_results, per_person_revision")
	scene.queue_free();await create_timer(0.2).timeout;quit()
