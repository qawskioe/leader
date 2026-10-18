extends SceneTree
class Containers extends RefCounted:
	var containers: Dictionary={}
class World extends Node:
	var content_interaction:=Containers.new()
func _initialize() -> void:
	var sim:=World.new()
	var basket:=Node3D.new();basket.set_meta("display_name","篮子")
	var storage:=Node3D.new();storage.set_meta("display_name","储食处")
	var bag:=Node3D.new();bag.set_meta("display_name","水袋")
	sim.content_interaction.containers={"crate_42":{"record":{"root":basket}},"storage":{"record":{"root":storage}},"bag":{"record":{"root":bag}}}
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim
	controller.store=load("res://scripts/voice/people_store.gd").new();controller.store.people={"recipient":{"name":"小花"}}
	var facts: Array=[]
	for i in 2:
		facts.append({"kind":"taken","material":"food","quantity":1,"source":"resource"})
		facts.append({"kind":"stored","material":"food","quantity":1,"target":"crate_42"})
	for i in 2:
		facts.append({"kind":"taken","material":"food","quantity":1,"source":"crate_42"})
		facts.append({"kind":"stored","material":"food","quantity":1,"target":"storage"})
	var summary: String=controller.effect_summary(facts)
	assert(summary=="从资源点取得食物2份、存入篮子食物2份、从篮子取出食物2份、存入储食处食物2份",summary)
	assert(not summary.contains("4份"),"中转两次不能显示为新增四份")
	var social: String=controller.effect_summary([{"kind":"given","material":"food","quantity":1,"recipient_id":"recipient"},{"kind":"consumed","material":"food","quantity":1},{"kind":"filled","material":"water","quantity":3,"target":"bag"}])
	assert(social=="交给小花食物1份、消耗食物1份、装入水袋水3份",social)
	print("EFFECT_SUMMARY_PASSED acquisition_container_moves_storage_consent_consumption_water")
	controller.free();sim.free();basket.free();storage.free();bag.free();quit()
