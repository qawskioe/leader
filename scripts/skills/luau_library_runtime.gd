extends Node
## 技能库的调用适配器；代码执行委托常驻Luau服务。
var service: Node
var runner: Node
var context: Dictionary={}
func is_starting() -> bool:
	return is_instance_valid(runner) and runner.is_starting()
func _ready() -> void:
	runner=preload("res://scripts/skills/luau_runtime.gd").new();runner.service=service;add_child(runner)
func run(program: Dictionary, arguments: Dictionary, adapter: Node, linked: Dictionary={}) -> Dictionary:
	var executable:=preload("res://scripts/skills/luau_linker.gd").link(program,linked)
	if not executable.ok: return {"status":"error","code":executable.error}
	return await runner.run(executable.source,arguments,context,adapter,executable.capabilities)
func cancel() -> void:
	if is_instance_valid(runner): runner.cancel()
