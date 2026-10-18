extends SceneTree
func _initialize() -> void:
	var object_offers=load("res://scripts/survival/handover.gd").new()
	var player_offers=load("res://scripts/survival/gathering.gd").new()
	for driver in [object_offers,player_offers]:
		var offers: Dictionary=driver.pending if driver==object_offers else driver.offers
		var recipient_field:="recipient" if driver==object_offers else "target"
		# 已排队接近到期，此时开始判断必须获得完整判断时限。
		offers.test={recipient_field:"person_002","expires":Time.get_ticks_msec()+100,"decision_started":false}
		assert(not driver.begin_receiver_decision("test","wrong_person"))
		assert(driver.begin_receiver_decision("test","person_002"))
		var deadline: int=offers.test.expires
		assert(deadline-Time.get_ticks_msec()>119000 and offers.test.decision_started)
		assert(driver.begin_receiver_decision("test","person_002") and offers.test.expires==deadline,"重复派发不能无限续期")
		offers.test.expires=Time.get_ticks_msec()-1
		assert(not driver.begin_receiver_decision("test","person_002"),"迟到判断不能复活已过期递物")
		assert(not driver.begin_receiver_decision("missing","person_002"))
	print("OFFER_WAIT_PHASES_PASSED receiver_bound_start_budget_idempotent_expired_not_revived")
	object_offers.free();player_offers.free();quit()
