extends SceneTree
class QuietVoice extends "res://scripts/voice/voice_test.gd":
 func log_event(_record: Dictionary) -> void:pass
 func _resume_waited_result(_report: Dictionary) -> void:pass
 func _pump_speech() -> void:pass
class Skills extends Node:
 var calls:=0
 func request_learning(_id, _event, _request):calls+=1;return {"ok":true}
 func request_revision(_id, _event, _request):calls+=1;return {"ok":true}
 func invoke(_id, _event, _request):calls+=1;return {"ok":false,"error":"unexpected call"}
func _initialize():
 create_timer(15).timeout.connect(func():push_error("execution gate timeout");quit(1))
 var voice:=QuietVoice.new()
 assert(voice.store.initialize("res://data/people.json","user://execution_gate_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var skills:=Skills.new();voice.add_child(skills);voice.skills=skills
 var person:="person_001"
 var event:={"id":"gate","speaker":"player","kind":"speech_intent","text":"学习方法"}
 voice.store.hear(person,event)
 voice._allow_execution=true;voice.config={"actions_enabled":false};voice._job_config={"actions_enabled":true,"tts_enabled":true}
 for field in ["revision_request","learning_request","skill_call"]:
  var decision:={"intent":"none","public_reply":"","capability_gap":null,"task_handling":{"state":"execute"}}
  decision[field]={"ref":"skill_1","arguments":{},"goal_id":"new_method","goal":"新方法","feedback":"修订方法"}
  voice._on_report({"person_id":person,"event_id":event.id,"decision":decision})
 assert(skills.calls==0,"当前关闭行动后，未结束的判断也不能提交世界操作")
 # 模拟语音回调延迟到关闭开关之后，再进入学习启动函数。
 voice._begin_self_learning(person,event.id,{"learning_request":{"goal_id":"new_method","goal":"新方法"}})
 voice._begin_revision(person,event.id,{"ref":"skill_1","feedback":"修订方法"})
 assert(skills.calls==0,"延迟回调不能越过当前行动开关")
 voice.config.actions_enabled=true;voice._job_config.actions_enabled=false
 voice._begin_self_learning(person,event.id,{"learning_request":{"goal_id":"new_method","goal":"新方法"}})
 assert(skills.calls==0,"最初只有对话权限的轮次不能因开关后来打开而执行")
 voice._job_config.actions_enabled=true;voice._allow_execution=false
 voice._begin_revision(person,event.id,{"ref":"skill_1","feedback":"修订方法"})
 assert(skills.calls==0,"测试轮次权限独立有效")
 voice._allow_execution=true
 voice._begin_self_learning(person,event.id,{"learning_request":{"goal_id":"new_method","goal":"新方法"}})
 voice._begin_revision(person,event.id,{"ref":"skill_1","feedback":"修订方法"})
 assert(skills.calls==2,"正常获准的学习和修订仍可启动")
 voice.free();print("EXECUTION_GATE_PASSED report_delayed_callback_live_switch_round_permission");quit()
