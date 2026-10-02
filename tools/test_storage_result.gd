extends SceneTree
## 实际存储源码：已入库不能被无关的松手失败覆盖。
class World extends Node:
 func acquire() -> Dictionary:return {"ok":true}
 func finish() -> void:pass
 func cancel() -> void:pass
func _initialize():run.call_deferred()
func run():
 create_timer(15).timeout.connect(func():push_error("storage result timeout");quit(1))
 var service=load("res://scripts/skills/luau_service.gd").new();root.add_child(service)
 var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;root.add_child(runtime)
 var api:=World.new();root.add_child(api)
 var code:="""return function(args,context)
 local remaining=2 local stored=0 local releases=0
 local world={request=function(op)
  if op=="perceive" then return {near={held_objects={{id="basket"}}},held_unit={}} end
  if op=="inspect_contents" then return {ok=true,quantity=remaining} end
  if op=="take_unit" then remaining-=1 return {ok=true} end
  if op=="put_unit" then stored+=1 return {ok=true} end
  if op=="release" then releases+=1 return {ok=false,code="release_overlapping"} end
  return {ok=false,code="unexpected_operation"}
 end}
 local skills={call=function() return {ok=true,object="storage"} end}
 local method=(function() %s end)()
 local r=method({container="basket"},context)
 return {ok=r.ok,quantity=r.quantity,stored=stored,releases=releases}
end"""%FileAccess.get_file_as_string("res://data/skills/store_food.luau")
 var result: Dictionary=await runtime.run(code,{},{},api,[])
 assert(result.status=="completed" and result.returned.ok)
 assert(result.returned.stored==2 and result.returned.quantity==2 and result.returned.releases==0)
 print("STORAGE_RESULT_PASSED real_quantity_no_unrequested_release")
 quit()
