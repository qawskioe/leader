extends SceneTree
class Simulation extends Node:
	var store: RefCounted
func _initialize() -> void:
	var path:="res://services/luau-runtime/runtime/rejoin_%d.json"%Time.get_ticks_usec()
	var first=preload("res://scripts/voice/people_store.gd").new();assert(first.initialize("res://data/people.json",path,true).is_empty())
	first.hear("person_003",{"id":"persisted_speech","speaker":"player","text":"把木块留给小花"})
	first.remember("person_003","persisted_speech",{"private_interpretation":"记住这次安排","public_reply":"好"})
	first.memory.put("person_003","landmark","old_tree",{"id":"old_tree","kind":"landmark","position":[40,0,60],"available":true,"visible_now":true,"observed_at_seconds":0,"source":"上次亲眼看见","extra":{}},0.6)
	assert(first.memory.save().is_empty())
	var second=preload("res://scripts/voice/people_store.gd").new();assert(second.initialize("res://data/people.json",path).is_empty())
	assert(second.people.person_003.heard_events.size()==1 and second.people.person_003.reflections.size()==1)
	assert(second.people.person_002.heard_events.is_empty())
	var sim:=Simulation.new();sim.store=second
	var perception=preload("res://scripts/survival/perception.gd").new();perception.sim=sim;perception.seed_arrival(second.people.keys())
	assert(perception.memories.person_003.has("old_tree") and not perception.memories.person_003.old_tree.visible_now)
	assert(not perception.memories.person_003.has("arrival_path"),"读旧档不能重新灌入未保存的开场路线")
	second.memory.advance(800*second.memory.policy.day_seconds);second.refresh_memory_views()
	perception.seed_arrival(second.people.keys())
	assert(not perception.memories.person_003.has("old_tree") and second.people.person_003.heard_events.is_empty())
	sim.free()
	print("MEMORY_REJOIN_PASSED restore_private_history_and_stale_landmarks_no_resurrection")
	quit()
