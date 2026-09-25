extends SceneTree
const Store = preload("res://scripts/voice/people_store.gd")
const Cloud = preload("res://scripts/voice/cloud_client.gd")
const Pipeline = preload("res://scripts/voice/decision_pipeline.gd")
const Mic = preload("res://scripts/voice/microphone.gd")
const Voice = preload("res://scripts/voice/voice_test.gd")

class FakeCloud extends Node:
	var calls: Array = []
	var mode := "normal"
	var active := 0
	var max_active := 0
	func exchange(payload: Dictionary) -> Dictionary:
		calls.append(payload.duplicate(true))
		active += 1
		max_active = maxi(max_active,active)
		await get_tree().process_frame
		active -= 1
		if mode == "network":
			return {"ok":false,"error":"测试网络失败"}
		if mode == "malformed":
			return {"ok":true,"text":"不是 JSON"}
		var content: Dictionary = JSON.parse_string(payload.prompt.split("\n")[-1])
		var me: Dictionary = content.self
		var decision := {"intent":"none","recipient_id":"","capability_gap":null,"private_interpretation":"模拟结果，仅检验传输：" + me.name,"speech_act":"statement","addressed_person":"","speech_style":"neutral","public_reply":"收到","routing_reason":"模拟关系冲突升级"}
		decision.conversation={"addressees":["all"],"participation":"reply","reason":"传输测试夹具"}
		return {"ok":true,"text":JSON.stringify(decision),"elapsed_ms":1,"usage":{"total_tokens":10}}

var reports: Array = []
var completions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST_FAILED " + message)
		quit(1)
		assert(condition,message)

func _run() -> void:
	var store := Store.new()
	check(store.initialize().is_empty(),"人物数据加载")
	check(store.people.size()==4,"四个不同的稳定人物 ID")
	var actions: Dictionary = {}
	for id in store.people:
		actions[id] = store.people[id].current_action.duplicate(true)
	check(Voice.listeners_for(Vector3.ZERO,{"near":Vector3(1,0,0),"edge":Vector3(2,0,0),"far":Vector3(3,0,0)},2.0)==["near","edge"],"听众距离边界")
	check(Mic.radius_for(-40,-40,-15)==2 and Mic.radius_for(-15,-40,-15)==20,"音量传播范围")
	var silence := PackedFloat32Array()
	silence.resize(48000)
	check(not Mic.analyze(silence,48000,-48).ok,"空录音不能送往云端")
	var signal_audio := PackedFloat32Array()
	for i in 48000:
		signal_audio.append(sin(float(i)*TAU*440/48000)*0.1)
	var audio_info := Mic.analyze(signal_audio,48000,-48)
	check(audio_info.ok and absf(audio_info.db+23.01)<0.2,"电平计算")
	var wav := Mic.encode_wav(signal_audio,48000)
	check(wav.size()==32044 and wav.decode_u32(24)==16000 and wav.decode_u16(22)==1,"16kHz 单声道 WAV")
	var asr := Cloud.asr_payload("asr",wav)
	check(asr.messages[0].content[0].input_audio.data.begins_with("data:audio/wav;base64,"),"语音请求协议")
	check(not Cloud.parse_response('{"choices":[]}').ok,"拒绝空云端响应")
	check(not Cloud.parse_response('{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}').ok,"拒绝截断输出")
	check(not Cloud.validate_decision('{}').ok,"拒绝缺失决策字段")
	check(not Cloud.validate_decision('{"intent":"none","recipient_id":"","capability_gap":null,"private_interpretation":"a","speech_act":"statement","addressed_person":"","speech_style":"neutral","public_reply":"b","routing_reason":"c","requires_deep":true}').ok,"拒绝已移除的路由字段")
	var client := FakeCloud.new()
	root.add_child(client)
	var pipeline := Pipeline.new()
	pipeline.store = store
	pipeline.gateway = client
	root.add_child(pipeline)
	pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	pipeline.completed.connect(func(): completions += 1)
	var config: Dictionary = {}
	var event := {"id":"test-gift","kind":"observed_test","text":"四人共同目击玩家赠给石头食物","listeners":store.people.keys()}
	pipeline.run(event,config)
	await pipeline.completed
	check(reports.size()==4 and client.calls.size()==4,"四个听众各调用一次，不再二次路由判断")
	check(client.max_active<=2,"并发上限")
	for payload in client.calls:
		var context: Dictionary = JSON.parse_string(payload.prompt.split("\n")[-1])
		check(context.keys().size()<=4 and context.has("self") and context.has("current_event"),"上下文只包含一个角色和本轮事件")
		check(context.current_event.id==event.id and not context.current_event.has("listeners"),"本轮事件必须准确且不泄露其他听众")
		var id: String = context.self.id
		check(context.self.known_facts==store.people[id].known_facts,"角色事实未混入他人信息")
		check(not context.self.heard_events[0].has("listeners"),"角色不自动知道其他听众")
	for id in store.people:
		check(store.people[id].heard_events.size()==1 and store.people[id].reflections.size()==1,"每个听众有记录和主观反应")
		check(store.people[id].current_action==actions[id],"输出计划没有改变实际行动")
		check(not store.people[id].has("pending_plans"),"不再把说明文字存成执行计划")
	var count_before := client.calls.size()
	pipeline.run({"id":"empty","listeners":[]},config)
	await process_frame
	check(client.calls.size()==count_before,"无听众不调用模型")
	for mode in ["network","malformed"]:
		client.mode = mode
		reports.clear()
		pipeline.run({"id":mode,"kind":"speech_intent","text":"测试","listeners":["person_001"]},config)
		await pipeline.completed
		check(reports.size()==1 and reports[0].has("error"),"失败明确输出："+mode)
		check(store.people.person_001.reflections.size()==1,"失败没有生成虚假反应")
	check(store.people.person_001.heard_events.size()==3,"模型失败仍保留听闻")
	var saved := store.save_snapshot("res://work/test_people_snapshot.json")
	check(saved==OK,"人物快照可保存")
	check(completions==4,"每个事件只完成一次")
	var result := {"result":"passed","mock_only":true,"checks":["hearing_boundary","silence","wav","provider_format","private_context","independent_listeners","single_daily_call","concurrency","no_execution","network_and_schema_failures","snapshot"],"real_cloud_tested":false,"physical_microphone_tested":false}
	var file := FileAccess.open("res://work/voice_test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("VOICE_TEST_PASSED ",JSON.stringify(result))
	pipeline.queue_free()
	client.queue_free()
	await process_frame
	quit(0)
