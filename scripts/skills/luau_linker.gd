extends RefCounted
## 链接已经验证且人物已掌握的固定版本，仍交给官方Luau编译器执行。
## 整次调用共享VM、身体和权限并集；子技能不是另一个安全隔离单元。
const Contract=preload("res://scripts/skills/luau_contract.gd")

static func link(program: Dictionary, bundle: Dictionary) -> Dictionary:
	if not Contract.valid(program): return {"ok":false,"error":"invalid_luau_program"}
	if bundle.is_empty(): return {"ok":true,"source":program.source,"capabilities":program.capabilities}
	var definitions: Dictionary=bundle.get("definitions",{})
	var root: String=bundle.get("root","")
	if definitions.size()>32 or not definitions.has(root) or definitions[root].get("program")!=program:
		return {"ok":false,"error":"invalid_linked_root"}
	var ordered: Array[String]=[]
	var error:=_visit(root,definitions,[],ordered)
	if error!="": return {"ok":false,"error":error}
	if ordered.size()!=definitions.size(): return {"ok":false,"error":"unreachable_dependency"}
	var capabilities: Array=[]
	var lines: PackedStringArray=["local implementations = {}"]
	# 参数检查和别名绑定属于调用合同，不解释技能语法，也不替角色选择后续动作。
	lines.append("""local function dependencies_api(entries)
    return table.freeze({call=function(alias, args, context)
        local entry=entries[alias]
        if not entry then error("undeclared_skill_dependency") end
        if type(args)~="table" then error("skill_arguments_must_be_table") end
        local count=0
        for key in pairs(args) do
            if not entry.parameters[key] then error("unknown_skill_argument") end
            count+=1
        end
        if count~=entry.count then error("missing_skill_argument") end
        return entry.invoke(args, context)
    end})
end""")
	for ref in ordered:
		var definition: Dictionary=definitions[ref]
		for operation in definition.program.capabilities:
			if operation not in capabilities: capabilities.append(operation)
		var entries: PackedStringArray=[]
		for alias in definition.dependencies:
			var child: String=definition.dependencies[alias]
			var parameters: PackedStringArray=[]
			for key in definitions[child].parameters: parameters.append("[%s]=true"%JSON.stringify(key))
			entries.append("[%s]={invoke=implementations[%s],parameters={%s},count=%d}"%[JSON.stringify(alias),JSON.stringify(child),",".join(parameters),parameters.size()])
		lines.append("implementations[%s]=(function(skills)\n%s\nend)(dependencies_api({%s}))"%[JSON.stringify(ref),definition.program.source,",".join(entries)])
		lines.append('assert(type(implementations[%s])=="function", "source_must_return_function")'%JSON.stringify(ref))
	lines.append("table.freeze(implementations)\nreturn implementations[%s]"%JSON.stringify(root))
	var source: String="\n".join(lines)
	if source.to_utf8_buffer().size()>65536: return {"ok":false,"error":"linked_source_too_large"}
	return {"ok":true,"source":source,"capabilities":capabilities}

static func _visit(ref: String, definitions: Dictionary, ancestors: Array, ordered: Array[String]) -> String:
	if ref in ancestors or ancestors.size()>=8: return "cyclic_or_deep_skill_dependency"
	if not definitions.has(ref): return "missing_skill_dependency"
	if ref in ordered: return ""
	var definition: Dictionary=definitions[ref]
	if not Contract.valid(definition.get("program")) or not definition.get("parameters") is Dictionary or not definition.get("dependencies") is Dictionary:
		return "invalid_skill_dependency"
	var next:=ancestors.duplicate();next.append(ref)
	for child in definition.dependencies.values():
		if not child is String: return "invalid_skill_dependency"
		var error:=_visit(child,definitions,next,ordered)
		if error!="": return error
	ordered.append(ref)
	return ""
