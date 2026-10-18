extends RefCounted
## 共享的Luau包边界；权限属于宿主，源码不能自行扩大。
const FORMAT="leader-luau-1"
const OPERATIONS=["access_source","look_toward","surface","move_held","check_placement","check_settled","observe","grasp","release","approach","handover","inspect_contents","transfer_contents","perceive","recall_locations","take_unit","put_unit","consume_unit","fill_container","give_unit","change_grip","consume_contents","walk_options"]
static func valid(program: Variant) -> bool:
	if not program is Dictionary or program.get("format")!=FORMAT: return false
	if not program.get("source") is String or program.source.is_empty() or program.source.to_utf8_buffer().size()>60000: return false
	if program.get("source_sha256")!=program.source.sha256_text(): return false
	if not program.get("capabilities") is Array or program.capabilities.size()>OPERATIONS.size(): return false
	var seen: Array=[]
	for op in program.capabilities:
		if op not in OPERATIONS or op in seen: return false
		seen.append(op)
	return true

static func make_program(source: String, capabilities: Array) -> Dictionary:
	return {"format":FORMAT,"source":source,"source_sha256":source.sha256_text(),"capabilities":capabilities}

## 日常判断和技能编写共用同一操作目录；这是身体能力边界，不是世界位置情报。
static func authoring_context() -> Dictionary:
	return {"available":true,"language":"Luau","operations":OPERATIONS.duplicate(),
		"rule":"已有技能是可直接调用的方法；operations是强模型编写新方法时可组合的世界操作，不可作为skill_call直接调用。没有现成方法不等于世界缺能力。",
		"interaction_rules":"普通生活使用近距、可见性、归属、库存与操作时间：grasp直接建立固定连接；move_held检查选定表面，若仅自己挡住落点，按碰撞外框在操作范围内调整站位后重新校验；其他实体阻挡仍返回失败，不改变落点或碰撞。take_unit/put_unit/consume_unit等直接按世界条件结算。release恢复物理，不自动产生投掷速度。",
		"learning_boundary":"目标可由这些操作或已有技能表达时，可提交learning_request；强模型负责具体方法与参数，隔离验证后才加载。只有必要的世界效果不能表达时才报告capability_gap；路径受阻、材料不足和动作失败分别按实际原因处理。"}
