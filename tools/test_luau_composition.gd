extends SceneTree
const Library=preload("res://scripts/skills/library.gd")
const Contract=preload("res://scripts/skills/luau_contract.gd")
const Linker=preload("res://scripts/skills/luau_linker.gd")
class World extends Node:
	var owned:=false
	var requests: Array=[]
	var acquisitions:=0
	var fail:=false
	func acquire() -> Dictionary: owned=true;acquisitions+=1;return {"ok":true}
	func finish() -> void: owned=false
	func cancel() -> void: owned=false
	func request(operation: String, args: Dictionary) -> Dictionary:
		await get_tree().create_timer(0.03).timeout
		if not owned: return {"ok":false,"code":"cancelled"}
		requests.append({"operation":operation,"arguments":args})
		return {"ok":not fail,"code":"world_rejected" if fail else "observed","version":args.get("version",0)}
var library:=Library.new()
func add(id: String, source: String, parameters: Dictionary, capabilities: Array, dependencies: Dictionary={}) -> String:
	var definition:={"id":id,"name":id,"description":"隔离测试技能","parameters":parameters,"program_json":JSON.stringify(Contract.make_program(source,capabilities)),"dependencies":dependencies}
	var raw:=JSON.stringify(definition)
	var result:=library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(result.ok,JSON.stringify(result))
	return result.ref
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(25).timeout.connect(func():push_error("composition_timeout");quit(1))
	var path:="user://skills/composition_"+str(Time.get_ticks_usec())+".json"
	assert(library.initialize(path,{"person":{},"other":{}}).is_empty())
	var leaf:=add("leaf",'return function(args, context) return world.request("observe",{object=args.object,version=1}) end',{"object":"目标"},["observe"])
	var parent:=add("parent",'return function(args, context) local a=skills.call("first",args,context) if not a.ok then return a end return skills.call("again",args,context) end',{"object":"目标"},[],{"first":leaf,"again":leaf})
	assert(library.grant("person",parent,"测试批准").is_empty())
	assert(not library.execution_context("person",parent).ok,"未掌握依赖不能调用")
	assert(not library.describe("person")[0].callable,"目录应说明已有组合缺少可用依赖，不能等执行才告诉模型")
	assert(library.grant("person",leaf,"测试批准").is_empty())
	assert(not library.execution_context("other",parent).ok,"不能使用别人的掌握记录")
	var linked:=library.execution_context("person",parent)
	assert(linked.ok)
	assert(library.describe("person")[0].callable and library.describe("person")[0].has("object_requirement"),"组合应继承依赖的物品交互条件")
	var program: Dictionary=JSON.parse_string(library.definitions[parent].program_json)
	var service=preload("res://scripts/skills/luau_service.gd").new();root.add_child(service)
	var runtime=preload("res://scripts/skills/luau_library_runtime.gd").new();runtime.service=service;root.add_child(runtime)
	var world:=World.new();root.add_child(world)
	var result: Dictionary=await runtime.run(program,{"object":"stone"},world,linked.context)
	assert(result.status=="completed" and result.returned.version==1,JSON.stringify(result))
	assert(world.requests.size()==2 and world.acquisitions==1,"重复子技能共享一次身体占用，不能开启第二个世界行动")
	var outer:=add("outer",'return function(args, context) return skills.call("inner",args,context) end',{"object":"目标"},[],{"inner":parent})
	assert(library.grant("person",outer,"测试批准").is_empty())
	world.requests.clear()
	result=await runtime.run(JSON.parse_string(library.definitions[outer].program_json),{"object":"stone"},world,library.execution_context("person",outer).context)
	assert(result.returned.version==1 and world.requests.size()==2,"嵌套组合的世界等待必须贯通全部调用层")
	world.requests.clear();world.fail=true
	result=await runtime.run(program,{"object":"stone"},world,linked.context)
	assert(result.status=="completed" and not result.returned.ok and world.requests.size()==1,"真实失败能由父技能处理，不自动执行下一步")
	world.fail=false;world.requests.clear()
	create_timer(0.01).timeout.connect(runtime.cancel)
	result=await runtime.run(program,{"object":"stone"},world,linked.context)
	assert(result.status=="cancelled")
	await create_timer(0.08).timeout
	assert(world.requests.is_empty() and not world.owned,"取消使后续子调用失效")
	# 子技能修订不暗中改变旧复合技能所引用的版本。
	var new_definition: Dictionary=library.definitions[leaf].duplicate(true)
	new_definition.revision_of=leaf
	new_definition.program_json=JSON.stringify(Contract.make_program('return function(args, context) return world.request("observe",{object=args.object,version=2}) end',["observe"]))
	var raw:=JSON.stringify(new_definition)
	var registered:=library.register_verified(new_definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and library.revise("person",leaf,registered.ref,"修订").is_empty())
	linked=library.execution_context("person",parent)
	result=await runtime.run(program,{"object":"stone"},world,linked.context)
	assert(result.returned.version==1,"旧复合技能必须继续使用固定依赖，不能偷偷升级")
	var newer:=add("new_parent",'return function(args, context) return skills.call("new",args,context) end',{"object":"目标"},[],{"new":registered.ref})
	assert(library.grant("person",newer,"测试批准").is_empty())
	result=await runtime.run(JSON.parse_string(library.definitions[newer].program_json),{"object":"stone"},world,library.execution_context("person",newer).context)
	assert(result.returned.version==2)
	# 非声明依赖、缺参、未授权世界操作都明确失败，不产生额外世界效果。
	for body in ['return skills.call("missing",args,context)','return skills.call("first",{},context)','return world.request("release",{object=args.object})']:
		var bad:=add("bad_"+str(body.hash()).replace("-","n"),'return function(args, context) '+body+' end',{"object":"目标"},[],{"first":leaf})
		assert(library.grant("person",bad,"测试批准").is_empty())
		world.requests.clear()
		result=await runtime.run(JSON.parse_string(library.definitions[bad].program_json),{"object":"stone"},world,library.execution_context("person",bad).context)
		assert(result.status=="error" and world.requests.is_empty(),JSON.stringify(result))
	var cycle: Dictionary=linked.context.duplicate(true);cycle.definitions[leaf].dependencies={"back":parent}
	assert(not Linker.link(program,cycle).ok)
	var missing: Dictionary=linked.context.duplicate(true);missing.definitions.erase(leaf)
	assert(not Linker.link(program,missing).ok)
	var loop:=add("loop",'return function() while true do end end',{},[])
	var bounded:=add("bounded",'return function(args, context) return skills.call("loop",{},context) end',{},[],{"loop":loop})
	assert(library.grant("person",loop,"测试批准").is_empty() and library.grant("person",bounded,"测试批准").is_empty())
	result=await runtime.run(JSON.parse_string(library.definitions[bounded].program_json),{},world,library.execution_context("person",bounded).context)
	assert(result.status=="error" and "compute_budget" in result.code,"子技能也受同一次调用的计算预算限制")
	var reloaded:=Library.new();assert(reloaded.initialize(path,{"person":{},"other":{}}).is_empty())
	assert(reloaded.execution_context("person",parent).ok,"保存重读后固定依赖仍有效")
	assert(library.learn_from("other","person",parent,"实际复合教学测试").is_empty())
	assert(library.execution_context("other",parent).ok,"学习复合方法应同时获得其固定依赖索引")
	assert(library.describe("other").size()==1,"依赖只随复合方法学习，不混入独立技能菜单")
	print("LUAU_COMPOSITION_PASSED async_dependencies_ownership_failure_cancel_version_permissions")
	runtime.queue_free();world.queue_free();service.queue_free();await process_frame;quit()
