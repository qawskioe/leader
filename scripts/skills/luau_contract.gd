extends RefCounted
## 共享的Luau包边界；权限属于宿主，源码不能自行扩大。
const FORMAT="leader-luau-1"
const OPERATIONS=["look_toward","surface","move_held","check_placement","pose","observe","reach","reach_with_body","plan_grasp","grasp","release","pose_bones","inspect_body","relax","approach","handover","inspect_contents","transfer_contents","perceive","recall_locations","contact_point","reach_point","body_point","take_unit","put_unit","consume_unit","fill_container","give_unit","change_grip","consume_contents","walk_options"]
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
