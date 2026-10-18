extends Node
## 常驻进程；所有管道读写在专属线程，主线程只收取完整消息。
signal message_received(message: Dictionary)
var worker:=Thread.new()
var lock:=Mutex.new()
var outgoing: Array[PackedByteArray]=[]
var incoming: Array[Dictionary]=[]
var stopping:=false
var process_id:=-1
var pipes: Dictionary={}
var service_ready:=false
var expected: Dictionary={}
var active: Dictionary={}
var max_dispatch_ms:=0.0
const EXE="res://services/luau-runtime/runtime/build/leader-skill-service.exe"
const TRANSPORT_CHUNK_BYTES:=1024
const MAX_MESSAGE_BYTES:=1048576

func start() -> String:
	if process_id>0: return ""
	if not FileAccess.file_exists(EXE): return "请先构建 services/luau-runtime/build.py"
	pipes=OS.execute_with_pipe(ProjectSettings.globalize_path(EXE),PackedStringArray(),false)
	if pipes.is_empty(): return "无法启动Luau执行服务"
	process_id=pipes.pid;stopping=false
	worker.start(_io)
	return ""

func send(value: Dictionary) -> String:
	assert(process_id>0)
	var bytes:=(JSON.stringify(value)+"\n").to_utf8_buffer()
	# 外部上下文和世界回执有大小边界；拒绝前不登记调用，避免留下永远等不到的回执。
	if bytes.size()>MAX_MESSAGE_BYTES:return "transport_message_too_large"
	var id: String=value.get("id","")
	if value.op=="start": active[id]=true
	if value.op in ["start","resume","cancel"]: expected[id]=Time.get_ticks_msec()
	lock.lock();outgoing.append(bytes);lock.unlock()
	return ""

func _io() -> void:
	var stream: FileAccess=pipes.stdio
	var errors: FileAccess=pipes.stderr
	var buffer:=PackedByteArray()
	var last_poll:=Time.get_ticks_msec()
	var writes: Array=[]
	var sending:=PackedByteArray()
	var offset:=0
	var chunk_sequence:=0
	var sending_id:=""
	var awaiting_ack:=false
	while true:
		var progressed:=false
		lock.lock();var stop:=stopping;writes.append_array(outgoing);outgoing.clear();lock.unlock()
		if stop: break
		if not OS.is_process_running(process_id):
			lock.lock();incoming.append({"type":"service_lost"});lock.unlock();break
		if sending.is_empty() and not writes.is_empty():
			sending=writes.pop_front();offset=0;chunk_sequence=0
			sending_id=str(JSON.parse_string(sending.get_string_from_utf8()).get("id",""))
		if not sending.is_empty() and not awaiting_ack:
			# Hex后每块约2KiB，仍逐块确认，不一次写入整个大观察包。
			var stop_at:=mini(offset+TRANSPORT_CHUNK_BYTES,sending.size())
			stream.store_string(JSON.stringify({"op":"transport_chunk","sequence":chunk_sequence,"hex":sending.slice(offset,stop_at).hex_encode(),"last":stop_at==sending.size()})+"\n")
			offset=stop_at;awaiting_ack=true;progressed=true
		if sending.is_empty() and Time.get_ticks_msec()-last_poll>500:
			stream.store_string('{"op":"poll"}\n');last_poll=Time.get_ticks_msec()
		var available:=mini(stream.get_length(),1048576)
		if available>0:
			buffer.append_array(stream.get_buffer(available));progressed=true
		if errors.get_length()>0: errors.get_buffer(mini(errors.get_length(),65536)) # 不让stderr填满；不把原生输出当协议。
		var end:=buffer.find(10)
		while end>=0:
			var parser:=JSON.new()
			if parser.parse(buffer.slice(0,end).get_string_from_utf8())==OK and parser.data is Dictionary:
				if parser.data.get("type")=="transport_ack":
					if int(parser.data.sequence)==chunk_sequence:
						awaiting_ack=false;chunk_sequence+=1
						# 分块确认是实际通信进展；不能把正常传输大上下文误判成服务无回应。
						lock.lock();incoming.append({"type":"transport_progress","id":sending_id});lock.unlock()
						if offset>=sending.size(): sending=PackedByteArray()
				else:
					lock.lock();incoming.append(parser.data);lock.unlock()
			buffer=buffer.slice(end+1);end=buffer.find(10)
		if buffer.size()>1048576:
			lock.lock();incoming.append({"type":"service_lost"});lock.unlock();break
		# 有数据或确认到达就继续收发；只有空闲轮次让出线程，避免每个小块固定等待。
		if not progressed: OS.delay_msec(1)

func _process(_delta: float) -> void:
	var started:=Time.get_ticks_usec()
	lock.lock();var events:=incoming.duplicate();incoming.clear();lock.unlock()
	for event in events:
		if event.type=="transport_progress":
			if expected.has(event.id): expected[event.id]=Time.get_ticks_msec()
			continue
		if event.type=="ready": service_ready=true
		if event.type=="service_lost": _lost("执行服务退出");return
		var id: String=event.get("id","")
		expected.erase(id)
		if event.type in ["completed","failed","cancelled"]: active.erase(id)
		message_received.emit(event)
	for id in expected:
		if Time.get_ticks_msec()-expected[id]>2000:
			_lost("执行服务无回应，已中止，未重放动作");return
	max_dispatch_ms=maxf(max_dispatch_ms,(Time.get_ticks_usec()-started)/1000.0)

func _lost(reason: String) -> void:
	var ids:=active.keys();close()
	for id in ids: message_received.emit({"type":"failed","id":id,"error":reason})

func close() -> void:
	lock.lock();stopping=true;lock.unlock()
	if process_id>0 and OS.is_process_running(process_id): OS.kill(process_id)
	if worker.is_started(): worker.wait_to_finish()
	for key in ["stdio","stderr"]:
		if pipes.has(key): pipes[key].close()
	pipes.clear();expected.clear();active.clear();process_id=-1;service_ready=false

func _exit_tree() -> void: close()
