extends SceneTree
## 执行真实通用技能源码，固定感知输入复现粗略方位跳变；不是正常游玩。
class World extends Node:
 func acquire() -> Dictionary:return {"ok":true}
 func finish() -> void:pass
 func cancel() -> void:pass
func _initialize():run.call_deferred()
func run():
 create_timer(20).timeout.connect(func():push_error("navigation regression timeout");quit(1))
 var service=load("res://scripts/skills/luau_service.gd").new();root.add_child(service)
 var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;root.add_child(runtime)
 var api:=World.new();root.add_child(api)
 var code:="""return function(args,context)
 local turns=0 local moves=0
 local world={request=function(op,params)
  if op=="recall_locations" then return {ok=true,locations={}} end
  if op=="look_toward" then turns+=1 return {ok=true} end
  if op=="approach" then moves+=1 return {ok=true} end
  local position=moves>0 and {x=0,y=0,z=0.5} or {x=turns%%2==0 and 10 or -10,y=0,z=10}
  local visible=args.visible and {target={kind="basket",position={x=0,y=0,z=0.5},available=true}} or {}
  return {ok=true,observation_id="test",known={target={kind="basket",approx_position=position}},
   near={landmarks=visible,held_objects={},ground_samples={{state="visible_surface",path_clear=true,slope_degrees=0,position={x=0,y=0,z=3}}}},
   odometry={position={x=0,z=0},right={x=1,z=0},forward={x=0,z=1}}}
 end}
 local method=(function() %s end)()
 local r=method({object="target",distance=1},context)
 return {ok=r.ok,code=r.code,turns=turns,moves=moves}
end"""%FileAccess.get_file_as_string("res://data/skills/go_to_known.luau")
 for visible in [false,true]:
  var result: Dictionary=await runtime.run(code,{"visible":visible},{},api,[])
  print("NAV_RESULT ",visible," ",JSON.stringify(result.get("returned",{})))
  assert(result.status=="completed" and result.returned.ok,"粗略方位不能导致原地反复转向")
  assert(result.returned.moves==(0 if visible else 1),"当前可见位置必须优先于旧记忆")
 # 观察到的平缓地面可实际试走；未确认的预判不能冒充禁止移动。
 var slope_code:="""return function(args,context)
 local moves=0
 local world={request=function(op,params)
  if op=="recall_locations" or op=="look_toward" then return {ok=true,locations={}} end
  if op=="approach" then moves+=1 return {ok=true} end
  return {ok=true,observation_id="slope_fixture",known={target={position={x=0,y=0,z=moves>0 and 0.5 or 10}}},
   near={landmarks={},held_objects={},ground_samples={{state="visible_surface",path_clear=args.clear,slope_degrees=args.slope,position={x=0,y=1,z=3}}}},
   odometry={position={x=0,z=0},right={x=1,z=0},forward={x=0,z=1}}}
 end}
 local method=(function() %s end)()
 local r=method({object="target",distance=1},context)
 return {ok=r.ok,code=r.code,moves=moves}
end"""%FileAccess.get_file_as_string("res://data/skills/go_to_known.luau")
 for sample in [{"clear":true,"slope":18.5},{"clear":true,"slope":50.0},{"clear":false,"slope":18.5}]:
  var outcome: Dictionary=await runtime.run(slope_code,sample,{},api,[])
  var can_walk: bool=sample.slope<35
  if outcome.status!="completed" or outcome.returned.ok!=can_walk or outcome.returned.moves!=(1 if can_walk else 0):
   push_error("平缓可见地面须由实际运动判断，不能用未确认预判拒绝："+JSON.stringify(outcome.get("returned",{})));quit(1);return
 var selection_code:="""return function(args,context)
 local moves=0 local selected_x=-1
 local world={request=function(op,params)
  if op=="recall_locations" or op=="look_toward" then return {ok=true,locations={}} end
  if op=="approach" then moves+=1 selected_x=params.object.position.x return {ok=args.succeeds,code=args.succeeds and "arrived" or "movement_failed"} end
  local samples={{state=args.unknown and "unknown" or "visible_surface",path_clear=false,slope_degrees=0,position={x=0,y=0,z=3}}}
  if args.confirmed then samples[2]={state="visible_surface",path_clear=true,slope_degrees=0,position={x=1,y=0,z=1.5}} end
  return {ok=true,observation_id="selection_fixture",known={target={position={x=0,y=0,z=moves>0 and args.succeeds and 0.5 or 5}}},
   near={landmarks={},held_objects={},ground_samples=samples},
   odometry={position={x=0,z=0},right={x=1,z=0},forward={x=0,z=1}}}
 end}
 local method=(function() %s end)()
 local r=method({object="target",distance=1},context)
 return {ok=r.ok,code=r.code,moves=moves,selected_x=selected_x}
end"""%FileAccess.get_file_as_string("res://data/skills/go_to_known.luau")
 for case in [{"confirmed":true,"succeeds":true},{"confirmed":false,"succeeds":true},{"confirmed":false,"succeeds":false},{"unknown":true,"succeeds":true}]:
  var selected: Dictionary=await runtime.run(selection_code,case,{},api,[])
  assert(selected.status=="completed",str(selected))
  var outcome: Dictionary=selected.returned
  if case.get("unknown",false):assert(not outcome.ok and outcome.moves==0 and outcome.code=="no_visible_step","未观察地面不能试走")
  elif not case.succeeds:assert(not outcome.ok and outcome.moves==6 and outcome.code=="no_route_progress","真实失败须有界停止，不能冒充成功")
  else:assert(outcome.ok and outcome.moves==1 and outcome.selected_x==(1 if case.confirmed else 0),"确认路径优先，未确认可见地面仍可试走")
 var find_code:="""return function(args,context)
 local world={request=function(op)
  if op=="recall_locations" then return {ok=true,locations={}} end
  return {known={old={kind="basket",position={x=1,y=0,z=0},available=true}},near={landmarks={fresh={kind="basket",position={x=2,y=0,z=0},available=true},old={kind="basket",position={x=1,y=0,z=0},available=false}}}}
 end}
 local method=(function() %s end)()
 return method({kind="basket"},context)
end"""%FileAccess.get_file_as_string("res://data/skills/find_resource.luau")
 var found: Dictionary=await runtime.run(find_code,{},{},api,[])
 assert(found.status=="completed" and found.returned.object=="fresh","可见不可用状态必须覆盖旧记忆，并纳入新看到的候选")
 var locate_code:="""return function(args,context)
 local at="" local visits={}
 local world={request=function(op)
  if op=="recall_locations" or op=="look_toward" then return {ok=true,locations={}} end
  local visible=at=="other" and args.exists and {other={kind="basket",position={x=0,y=0,z=1.4},available=true}} or {}
  return {ok=true,observation_id="test",known={stale={kind="basket",position={x=1,y=0,z=0}},other={kind="basket",position={x=4,y=0,z=0}}},near={landmarks=visible}}
 end}
 local skills={call=function(alias,p) at=p.object visits[#visits+1]=at return {ok=false,code="no_visible_step"} end}
 local method=(function() %s end)()
 local r=method({kind="basket"},context)
 r.visits=#visits
 return r
end"""%FileAccess.get_file_as_string("res://data/skills/locate_resource.luau")
 for exists in [true,false]:
  var located: Dictionary=await runtime.run(locate_code,{"exists":exists},{},api,[])
  assert(located.status=="completed" and located.returned.ok==exists)
  assert(located.returned.visits==2,"过时线索只能检查一次，然后检查另一条线索")
  if exists:assert(located.returned.object=="other")
  else:assert(located.returned.code=="no_observed_resource","未实际看见不能返回找到")
 print("NAVIGATION_MEMORY_PASSED coarse_bearing_progress_current_observation_priority_confirmed_first_bounded_trials")
 quit()
