extends SceneTree
## 用固定外部依赖结果执行真实采集源码，只测试“零产出不能声称采集完成”。
class World extends Node:
 func acquire() -> Dictionary:return {"ok":true}
 func finish() -> void:pass
 func cancel() -> void:pass
func _initialize():run.call_deferred()
func run():
 create_timer(15).timeout.connect(func():push_error("gather result timeout");quit(1))
 var service=load("res://scripts/skills/luau_service.gd").new();root.add_child(service)
 var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;root.add_child(runtime)
 var api:=World.new();root.add_child(api)
 var code:="""return function(args,context)
 local world={request=function(op)
  if op=="inspect_contents" then return {ok=true,quantity=0,capacity=4} end
  return {near={held_objects={{id="basket"}}},known={basket={kind="basket"}}}
 end}
 local skills={call=function(name)
  if name=="store" then return {ok=true,quantity=args.quantity,target="storage"} end
  return {ok=true,object="grove"}
 end}
 local method=(function()
 %s
 end)()
 return method(args,context)
end"""%FileAccess.get_file_as_string("res://data/skills/gather_food.luau")
 for count in [0,2]:
  var result: Dictionary=await runtime.run(code,{"quantity":count},{},api,[])
  assert(result.status=="completed")
  assert(result.returned.ok==(count>0))
  if count==0:assert(result.returned.code=="no_food_collected")
 print("GATHER_EMPTY_RESULT_PASSED zero_rejected_nonzero_preserved")
 quit()
