extends SceneTree
## 关闭 TTS 后，仍按交流顺序交付公开文字与求助；不访问真实模型或语音服务。
const Voice=preload("res://scripts/voice/voice_test.gd")

class ForbiddenTTS extends Node:
	signal audio_chunk(packet: Dictionary)
	var calls:=0
	func cancel() -> void:pass
	func speak(_text: String,_style: String,_voice: String) -> Dictionary:
		calls+=1
		return {"ok":false,"error":"文字测试不应调用 TTS"}

func _initialize() -> void:run.call_deferred()

func run() -> void:
	assert(not Voice.tts_at_launch(true,PackedStringArray(["--no-tts"]),false),"启动参数必须覆盖旧的已保存有声设置")
	assert(not Voice.tts_at_launch(true,PackedStringArray(["--player-control"]),false),"自动游玩默认不合成语音")
	assert(not Voice.tts_at_launch(true,PackedStringArray(),true),"无画面测试默认不合成语音")
	assert(Voice.tts_at_launch(false,PackedStringArray(["--tts"]),true),"明确试听可以开启")
	assert(not Voice.tts_at_launch(false,PackedStringArray(),false),"普通启动保留用户的关闭设置")
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	scene.add_child(voice)
	voice.set_process(false)
	voice.store.memory.path="user://voice_tests/tts_disabled_fixture_memory.json"
	voice.survival.enabled=false
	voice.config.tts_enabled=false
	voice.config.autonomy_enabled=true
	voice.config.actions_enabled=false
	voice.tts.queue_free()
	var forbidden:=ForbiddenTTS.new()
	voice.add_child(forbidden)
	voice.tts=forbidden
	voice.busy=true
	voice._event_started=Time.get_ticks_msec()
	voice._job_config={"tts_enabled":true,"actions_enabled":false} # 关闭前发出的旧请求快照。
	voice._speech_order=["person_003","person_001"]
	var request:={"intent":"none","private_interpretation":"PRIVATE_SENTINEL_OFF","public_reply":"小花，你记得篮子在哪里吗？","speech_style":"疑惑","speech_act":"request","request_kind":"information","addressed_person":"person_002","routing_reason":"离线情报询问夹具"}
	voice.store.hear("person_001",{"id":"text_request","kind":"player_speech","speaker":"player","text":"问小花篮子在哪","listeners":["person_001"]})
	voice.store.remember("person_001","text_request",request)
	voice._on_report({"event_id":"text_request","person_id":"person_001","person_name":"石头","calls":[],"decision":request})
	assert(voice._public_dialogue.is_empty(),"后问者先返回时，文字交流也不能越过前序人物")
	var earlier:={"intent":"none","private_interpretation":"PRIVATE_SENTINEL_OFF","public_reply":"我在这里。","speech_style":"平静","speech_act":"statement","routing_reason":"离线顺序夹具"}
	voice.store.hear("person_003",{"id":"text_earlier","kind":"player_speech","speaker":"player","text":"你在哪里","listeners":["person_003"]})
	voice.store.remember("person_003","text_earlier",earlier)
	voice._on_report({"event_id":"text_earlier","person_id":"person_003","person_name":"大山","calls":[],"decision":earlier})
	voice._on_completed()
	var deadline:=Time.get_ticks_msec()+2000
	while voice.busy and Time.get_ticks_msec()<deadline:await process_frame
	assert(not voice.busy,"文字模式无需等待语音生成即可完成本轮")
	assert(forbidden.calls==0,"当前关闭开关必须挡住旧快照中的 TTS 开启状态")
	assert(voice.captions.person_001.public_text==request.public_reply,"关闭 TTS 后头顶仍显示公开台词")
	assert(voice.store.people.person_001.reflections[0].public_reply_status=="已用文字呈现；未生成语音")
	assert(voice._public_dialogue.size()==2 and voice._public_dialogue[0].speaker=="大山" and voice._public_dialogue[1].speaker=="石头","按相同顺序记录玩家收到的公开交流")
	assert(voice.store.people.person_002.heard_events.back().text==request.public_reply,"附近成员仍收到公开交流")
	assert(not JSON.stringify(voice.store.people.person_002.heard_events).contains("PRIVATE_SENTINEL_OFF"),"文字模式仍隔离私下理解")
	assert(voice.autonomy.requests.any(func(event: Dictionary):return event.kind=="information_request" and event.speaker=="person_001" and event.listeners==["person_002"]),"文字模式保留人物间的情报询问")
	print("TTS_DISABLED_PASSED: launch_override, stale_config_gate, captions, ordered_dialogue, nearby_information_request; tts_calls=0; model_calls=0")
	scene.queue_free()
	await create_timer(0.2).timeout
	quit()
