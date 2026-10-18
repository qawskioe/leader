extends "res://tools/test_luau_candidate.gd"
## 真实Luau调用在取出物资后取消；下次调用保留同请求事实和同一手中物资。
const Candidate=preload("res://tools/test_luau_candidate.gd")
var partial: Array=[]
func _initialize() -> void:run.call_deferred()
func record_partial(event: Dictionary) -> void:partial.append(event.duplicate(true))
func run() -> void:
	create_timer(25).timeout.connect(func():push_error("verification cancellation timeout");quit(1))
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store: RefCounted=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim: Node=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	scene.get_node("Player").set_physics_process(false)
	var person:="person_003"
	var actor: Dictionary=sim.actors[person]
	actor.body.global_position=sim.STORAGE+Vector3(0,.05,-.8);actor.body.rotation.y=0
	var basket: Dictionary=sim.gathering.baskets["1"]
	basket.root.global_position=actor.body.global_position+Vector3(.4,.4,.5)
	assert(sim.gathering.pickup(person,"1") and basket.contents.count==0)
	verification_snapshot=Snapshot.capture(sim,person)
	var source:="""return function(arguments, context)
    local seen=world.request("perceive",{})
    if not seen.ok then return seen end
    if seen.held_unit.material~="food" then
        local access=world.request("access_source",{source="storage"})
        if not access.ok then return access end
        local taken=world.request("take_unit",{source="storage"})
        if not taken.ok then return taken end
    end
    return world.request("put_unit",{target="basket/1"})
end"""
	var program: Dictionary=preload("res://scripts/skills/luau_contract.gd").make_program(source,["perceive","access_source","take_unit","put_unit"])
	var service: Node=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	replay_runtime=load("res://scripts/skills/luau_library_runtime.gd").new();replay_runtime.service=service;scene.add_child(replay_runtime)
	var step_facts: Array=[]
	sim.life_world.fact.connect(func(event: Dictionary):step_facts.append(event.duplicate(true)))
	var adapter: Node=Candidate.ObservedWorld.new();adapter.sim=sim;adapter.person_id=person;adapter.objects=sim.world_objects;adapter.observer=self;scene.add_child(adapter)
	adapter.cancel_after_operation={"operation":"take_unit","occurrence":1}
	actor.event_id="fixture_cancel_order/call/0"
	replay_runtime.context={"task_execution":Journal.context(person,"fixture_cancel_order",[])}
	var cancelled: Dictionary=await replay_runtime.run(program,{},adapter)
	assert(cancelled.status=="cancelled" and adapter.cancellation_checkpoint.operation=="take_unit" and adapter.cancellation_checkpoint.after_result.ok)
	var retained: Dictionary=Snapshot.evidence(sim,person)
	assert(retained.hand_unit.material=="food" and retained.containers["basket/1"].quantity==0)
	assert(step_facts.size()==1 and step_facts[0].kind=="taken")
	var progress: Array=[{"person_id":person,"source_event_id":actor.event_id,"skill_ref":"fixture@cancel","runtime":cancelled,"world_facts":step_facts.duplicate(true)}]
	var context: Dictionary=Journal.context(person,"fixture_cancel_order",progress)
	assert(context.calls.size()==1 and context.calls[0].status=="cancelled" and context.calls[0].facts.size()==1)
	adapter.queue_free();await process_frame
	step_facts.clear();actor.event_id="fixture_cancel_order/call/1"
	adapter=Candidate.ObservedWorld.new();adapter.sim=sim;adapter.person_id=person;adapter.objects=sim.world_objects;adapter.observer=self;scene.add_child(adapter)
	replay_runtime.context={"task_execution":context}
	var resumed: Dictionary=await replay_runtime.run(program,{},adapter)
	assert(resumed.status=="completed" and resumed.returned.ok and basket.contents.count==1)
	assert(step_facts.size()==1 and step_facts[0].kind=="stored","续办不能重新取出一份食物")
	assert(Snapshot.evidence(sim,person).hand_unit.is_empty())
	print("VERIFICATION_CANCELLATION_PASSED real_cancel_retained_unit_same_request_no_retake")
	scene.queue_free();await process_frame;quit()
