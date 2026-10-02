extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Controller=preload("res://scripts/skills/controller.gd")
func _initialize():
 var store=Store.new();var path:="user://autonomous_revision_%d.json"%Time.get_ticks_usec()
 assert(store.initialize("res://data/people.json",path,true).is_empty())
 var result:={"person_id":"person_002","source_event_id":"need_one","skill_ref":"eat@old","success":false,"message":"接触失败","runtime":{"returned":{"ok":false,"code":"hand_not_in_contact","distance_m":0.29},"trace":[{"operation":"reach_point","arguments":{"world_position":{"x":999}},"result":{"ok":false,"code":"hand_not_in_contact","distance_m":0.29,"contact_limit_m":0.20}}]}}
 result.runtime.trace.push_front({"operation":"pose_bones","arguments":{"seconds":2.0},"elapsed_ms":2005,"result":{"ok":true,"timing":{"requested_seconds":2.0,"simulated_elapsed_seconds":2.005}}})
 store.record_execution(result)
 assert(store.execution_evidence("person_002","eat@old").size()==1,"刚发生的失败不能被长期记忆检索漏掉")
 assert(store.execution_evidence("person_002","other@old").is_empty())
 var turns: Array=store.working_context("person_002").recent_turns
 assert(turns.size()==1 and turns[0].event.kind=="skill_execution")
 assert(turns[0].event.result.feedback.distance_m==0.29)
 assert(turns[0].event.result.failed_attempts[0].operation=="reach_point")
 assert(turns[0].event.result.execution_summary.phases.size()==2)
 assert(turns[0].event.result.execution_summary.phases[0].timing.simulated_elapsed_seconds==2.005,"此前真实停顿不能因末步返回而丢失")
 assert(not JSON.stringify(turns).contains("world_position") and not JSON.stringify(turns).contains("runtime"))
 assert(store.working_context("person_001").recent_turns.is_empty())
 store.record_execution(result);assert(store.working_context("person_002").recent_turns.size()==1)
 var event:={"kind":"skill_progress","result":result}
 assert(Controller.revision_event_error(event,"eat@old").is_empty())
 assert(not Controller.revision_event_error(event,"other@old").is_empty())
 event.result.success=true;assert(Controller.revision_event_error(event,"eat@old").is_empty(),"执行成功不等于满足语义目标，不能禁止基于结果修订")
 event.result.success=false;event.result.cancelled=true;assert(not Controller.revision_event_error(event,"eat@old").is_empty())
 assert(not Controller.revision_event_error({"kind":"skill_progress","learning_failed":true},"eat@old").is_empty())
 assert(not Controller.revision_event_error({"kind":"skill_revised"},"eat@old").is_empty())
 var continuation:={"kind":"skill_progress","original_event":{"id":"teaching","speaker":"player","kind":"speech_intent","text":"先停下探索，修订采果方法"},"result":{"intent":"rest","success":true}}
 assert(Controller.revision_event_error(continuation,"gather@old").is_empty(),"停止旧动作后仍可续办玩家的修订请求")
 continuation.result={"skill_ref":"look@old","success":true}
 assert(Controller.revision_event_error(continuation,"gather@old").is_empty(),"准备步骤不应替代原请求的修订依据")
 continuation.result.cancelled=true
 assert(not Controller.revision_event_error(continuation,"gather@old").is_empty(),"取消回执不能因携带旧请求而启动修订")
 continuation.result.erase("cancelled");continuation.learning_failed=true
 assert(not Controller.revision_event_error(continuation,"gather@old").is_empty(),"学习失败不得自动循环")
 continuation.erase("learning_failed");continuation.original_event={"speaker":"body"}
 assert(not Controller.revision_event_error(continuation,"gather@old").is_empty(),"身体需求下仍须匹配本人同版本执行证据")
 var space=preload("res://scripts/skills/egocentric_space.gd")
 var long_trace: Array=[{"operation":"grasp","result":{"ok":true,"code":"grasped","object":"water_bag/1"}}]
 for n in 40:long_trace.append({"operation":"look_toward","result":{"ok":true,"code":"looked_toward"}})
 var outcome={"runtime":{"phase_summary":space.execution_phases(long_trace),"trace":long_trace.slice(-32)}}
 var wrapped={"result":outcome};space.sanitize_event(wrapped)
 assert(wrapped.result.execution_summary.complete_action_history)
 assert(wrapped.result.execution_summary.phases.size()==41)
 assert(wrapped.result.execution_summary.phases[0].object=="water_bag/1","尾部重复转向不能抹掉先前拿取成功")
 # 移动/旋转后的局部坐标、过时参考与摘要保留必须同时成立。
 var frame:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(100,2,200))
 var grip: Vector3=frame*Vector3(0,0.5,1)
 var known:={"storage":{"position":[100,2,200],"visible_now":false,"source":"此前亲眼看到","observed_at_seconds":12},"far":{"position":[1000,2,200]},"water_bag/1":{"position":[101,2.5,200]}}
 var receipt: Dictionary=space.release_location("water_bag/1",grip,frame,"release_frame",known,10)
 assert(is_equal_approx(receipt.grip_position.z,1) and is_equal_approx(receipt.grip_position.y,0.5))
 assert(receipt.known_references.size()==1 and not receipt.known_references.storage.reference_visible_at_release)
 assert(is_equal_approx(receipt.known_references.storage.horizontal_distance_m,1))
 assert(receipt.known_references.storage.observed_at_seconds==12)
 assert(not receipt.known_references.has("unknown_object"))
 var release_event:={"result":{"runtime":{"returned":{"ok":true},"trace":[{"operation":"release","result":{"ok":true,"release_location":receipt}}]}}}
 space.sanitize_event(release_event)
 assert(release_event.result.execution_summary.phases[0].release_location==receipt)
 assert(not JSON.stringify(release_event).contains('"x":100'),"摘要不能泄漏绝对世界坐标")
 print("AUTONOMOUS_REVISION_PASSED private_short_term_evidence_failure_gate_no_completion_loop")
 quit()
