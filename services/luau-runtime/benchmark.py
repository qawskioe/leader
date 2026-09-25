"""四个并发请求的本地往返基线，不含Godot帧调度/模型/世界动作时间。"""
import json
import time
from test_service import Client

client=Client()
durations=[]
source='return function(args) return {value=args.value*2} end'
try:
    for batch in range(101):
        starts={}
        for actor in range(4):
            ident=f'{batch}_{actor}';starts[ident]=time.perf_counter()
            client.process.stdin.write(json.dumps({'op':'start','id':ident,'source':source,'capabilities':[], 'arguments':{'value':actor},'context':{}})+'\n')
        client.process.stdin.flush()
        for _ in range(4):
            result=client.messages.get(timeout=5)
            assert result['type']=='completed',result
            if batch:durations.append((time.perf_counter()-starts[result['id']])*1000)
    values=sorted(durations)
    print(json.dumps({'samples':len(values),'concurrency':4,'p50_ms':values[len(values)//2],'p95_ms':values[int(len(values)*.95)],'max_ms':max(values),'includes':'pipe + VM creation + cached code execution; excludes Godot frame dispatch'},indent=2))
finally:client.close()
