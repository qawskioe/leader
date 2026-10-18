extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("Luau registered fixture timeout");quit(1))
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
	var baseline: Dictionary=preload("res://scripts/skills/verification_snapshot.gd").capture(voice.survival,"person_003")
	for goal in ["take_object","release_object"]:
		replay.decision.skill_call.ref=refs.take_object # 原始决策重放，测试库使用当前内置版本
		var call: Dictionary=replay.decision.skill_call if goal=="take_object" else {"ref":refs[goal],"arguments":{"object":"wood_block"}}
		var submitted: Dictionary=voice.skills.invoke("person_003","fixture_"+goal,call)
		assert(submitted.ok,JSON.stringify(submitted))
		var result: Dictionary=await voice.skills.finished
		assert(result.success and not result.has("goal_verified"),JSON.stringify(result))
		assert(voice.skills.world_objects.objects.wood_block.holder==("person_003" if goal=="take_object" else ""),"实际归属独立于技能名称")
		var knowledge: Dictionary=voice.survival.perception.known("person_003","wood_block")
		assert(knowledge.extra.holder==("person_003" if goal=="take_object" else ""),"人物必须知道实际持有状态")
	# 回到相同夹具现场再比较；上次松手后的物理落点不能当作改名差异。
	preload("res://scripts/skills/verification_snapshot.gd").restore(voice.survival,baseline)
	await physics_frame;await physics_frame
	# 完全相同的世界操作改名后，归属回执和执行摘要仍相同。
	for goal in ["take_object","release_object"]:
		var alias: Dictionary=voice.skills.library.definitions[refs[goal]].duplicate(true)
		alias.id="renamed_"+goal;alias.name="改名验证";alias.erase("revision_of")
		var alias_raw:=JSON.stringify(alias)
		var registered_alias: Dictionary=voice.skills.library.register_verified(alias,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":alias_raw,"definition_sha256":alias_raw.sha256_text()})
		assert(registered_alias.ok and voice.skills.library.grant("person_003",registered_alias.ref,"测试夹具：相同方法改名").is_empty())
		assert(voice.skills.invoke("person_003","alias_"+goal,{"ref":registered_alias.ref,"arguments":{"object":"wood_block"}}).ok)
		var alias_result: Dictionary=await voice.skills.finished
		var holder: String="person_003" if goal=="take_object" else ""
		assert(alias_result.success and voice.skills.world_objects.objects.wood_block.holder==holder)
		var operation: String="grasp" if goal=="take_object" else "release"
		assert(alias_result.runtime.phase_summary.any(func(phase):return phase.operation==operation and phase.ok and phase.holder==holder),"任意名字的方法共用世界归属回执")
	# 方法自报ok只能证明代码结束，不能凭名字或返回值捏造世界变化。
	var no_op:={"id":"give_object","name":"无世界操作的夹具","description":"仅测试方法返回值与真实世界证据的区别","parameters":{},"program_json":JSON.stringify(preload("res://scripts/skills/luau_contract.gd").make_program("return function(args,context) return {ok=true,code='claimed_success'} end",[]))}
	var no_op_raw:=JSON.stringify(no_op)
	var no_op_registered: Dictionary=voice.skills.library.register_verified(no_op,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":no_op_raw,"definition_sha256":no_op_raw.sha256_text()})
	assert(no_op_registered.ok and voice.skills.library.grant("person_003",no_op_registered.ref,"测试夹具：空方法").is_empty())
	assert(voice.skills.invoke("person_003","no_op",{"ref":no_op_registered.ref,"arguments":{}}).ok)
	var no_op_result: Dictionary=await voice.skills.finished
	assert(no_op_result.success and no_op_result.world_facts.is_empty() and no_op_result.runtime.phase_summary.is_empty())
	assert(not no_op_result.has("goal_verified") and not no_op_result.message.contains("世界状态验证通过"))
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
	var frame: Dictionary=voice.survival.space.capture("person_003")
	var distant:={"observation_id":frame.id,"position":{"x":-50.0,"y":0.0,"z":-10.0}}
	assert(voice.skills.invoke("person_003","far_look",{"ref":refs.look_toward,"arguments":{"target":distant}}).ok,"通用执行入口允许远处参照物，操作自身决定距离限制")
	var turned: Dictionary=await voice.skills.finished
	assert(turned.success,JSON.stringify(turned))
	assert(not voice.survival.space.resolve("person_003",distant).ok,"近距解析不会被通用入口放宽")
	print("LUAU_REGISTERED_PASSED decision_replay_real_world_renamed_methods_receipts_no_op_per_person_revision_far_look")
	scene.queue_free();await create_timer(0.2).timeout;quit()
