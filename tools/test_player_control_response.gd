extends SceneTree
const Bridge=preload("res://scripts/player_control.gd")
var stopped:=false
var path: String
func _initialize() -> void:run.call_deferred()
func packet(sequence: int) -> Dictionary:
	return {"id":str(sequence),"sequence":sequence,"padding":str(sequence).repeat(32768)}
func read_concurrently() -> Dictionary:
	var samples:=0
	var invalid:=0
	var malformed:=0
	while not stopped:
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null:continue # Windows替换期间短暂不存在不等于收到回执。
		var text:=file.get_as_text();file.close()
		var parser:=JSON.new()
		if parser.parse(text)!=OK or not parser.data is Dictionary:
			invalid+=1
			malformed+=1
		else:
			var data: Dictionary=parser.data
			var sequence:=int(data.get("sequence",-1))
			if data.get("id")!=str(sequence) or data.get("padding")!=str(sequence).repeat(32768):invalid+=1
		samples+=1
	return {"samples":samples,"invalid":invalid,"malformed":malformed}
func run() -> void:
	path="user://player_control_response_%d.json"%Time.get_ticks_usec()
	assert(await Bridge.publish_response(path,packet(0))==OK)
	var initial: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(initial.id=="0" and int(initial.sequence)==0 and initial.padding=="0".repeat(32768))
	var reader:=Thread.new();assert(reader.start(read_concurrently)==OK)
	var failed:=false
	for sequence in range(1,101):
		if await Bridge.publish_response(path,packet(sequence))!=OK:failed=true;break
		await process_frame
	stopped=true
	var result: Dictionary=reader.wait_to_finish()
	print("PLAYER_CONTROL_RESPONSE_RESULT ",JSON.stringify(result))
	if failed or result.samples==0 or result.invalid>0:
		push_error("玩家输入回执不能向并发读者提供空或部分JSON")
		quit(1);return
	print("PLAYER_CONTROL_RESPONSE_PASSED complete_receipts_concurrent_reader")
	quit()
