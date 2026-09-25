extends SceneTree
const Contents=preload("res://scripts/survival/container_contents.gd")
func _initialize() -> void:
	for material in ["water","food"]:
		var source:=Contents.new(material,4)
		var target:=Contents.new(material,2)
		var unit:={"origin":{"collector_id":"person_002","resource_id":"original"}}
		assert(source.add(unit).ok and source.add({"origin":{"resource_id":"second"}}).ok)
		assert(source.transfer_to(target,1).ok)
		assert(source.count==1 and target.count==1 and target.items[0].origin==unit.origin)
		assert(is_same(target.items[0],unit),"转移同一份内容物，不复制来源或生成替代品")
		var before: String=JSON.stringify([source.items,target.items])
		assert(not source.transfer_to(target,3).ok)
		assert(not source.transfer_to(target,0).ok and not source.transfer_to(source,1).ok)
		assert(JSON.stringify([source.items,target.items])==before,"失败不能部分扣除")
		assert(target.add({}).ok)
		assert(not source.transfer_to(target,1).ok and not target.add({}).ok)
		assert(source.count+target.count==3)
		assert(target.take().item==unit and target.count==1)
		assert(not target.take(5).ok and target.count==1)
		var other:=Contents.new("stone",4)
		assert(not source.transfer_to(other,1).ok and other.count==0)
	print("CONTAINER_CONTENTS_PASSED conservation_capacity_identity_atomic_failure")
	quit()
