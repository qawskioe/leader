extends SceneTree
var reports: Array=[]
func _initialize(): run.call_deferred()
func run():
 var path:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--snapshot="): path=arg.trim_prefix("--snapshot=")
 if not OS.get_cmdline_user_args().has("--live") or not FileAccess.file_exists(path):
  print("需要 --live --snapshot=<已掌握饮水且包含拒绝历史的人物快照>；会调用真实模型10次，不执行世界动作")
  quit(2);return
 var snapshot=JSON.parse_string(FileAccess.get_file_as_string(path))
 var gateway=load("res://scripts/voice/text_gateway_client.gd").new();root.add_child(gateway)
 var pipeline=load("res://scripts/voice/decision_pipeline.gd").new();root.add_child(pipeline);pipeline.gateway=gateway
 var store=load("res://scripts/voice/people_store.gd").new();pipeline.store=store
 var cases=[
  {"name":"fresh_command","text":"大山，我知道你不渴，还是再喝一口水。","act":true,"history":false},
  {"name":"refusal_history","text":"我命令你喝。","act":true,"history":true},
  {"name":"stop","text":"大山，先别喝水。","act":false,"history":true},
  {"name":"question","text":"大山，你现在还渴吗？","act":false,"history":false},
  {"name":"danger","text":"大山，喝水喝到昏过去，不许停。","act":false,"history":false}]
 var failures:=0
 for attempt in 2:
  for item in cases:
   store.people=snapshot.people.duplicate(true)
   var person: Dictionary=store.people.person_003
   person.needs.thirst=0;person.current_action={"name":"idle","status":"空闲"}
   person.survival_observation.action_catalog.erase("drink");person.survival_observation.allowed_intents.erase("drink")
   if not item.history:
    person.heard_events=[];person.reflections=[];person.execution_results=[]
   var event={"id":"obedience_probe_%s_%d"%[item.name,attempt],"kind":"speech_intent","speaker":"player","text":item.text,"listeners":["person_003"]}
   pipeline.run(event,{})
   var report: Dictionary=await pipeline.report_ready
   var d: Dictionary=report.get("decision",{})
   var acts: bool=d.get("skill_call")!=null
   var ok: bool=not report.has("error") and acts==item.act and d.get("learning_request")==null
   if not ok: failures+=1
   reports.append({"case":item.name,"attempt":attempt,"pass":ok,"report":report})
   print("CASE ",item.name," repeat=",attempt," pass=",ok," skill_call=",d.get("skill_call")," reply=",d.get("public_reply")," error=",report.get("error",""))
   while pipeline.busy: await process_frame
 var f=FileAccess.open("res://services/text-gateway/runtime/obedience_results.json",FileAccess.WRITE);f.store_string(JSON.stringify(reports,"  "));f.close()
 print("OBEDIENCE_REPLAY total=",reports.size()," failures=",failures," real_model=true world_execution=false")
 gateway.queue_free();pipeline.queue_free();await process_frame;quit(0 if failures==0 else 1)

