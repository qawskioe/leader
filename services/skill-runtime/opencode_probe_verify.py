"""Windows宿主验证探针工作区产物；不授予正常游戏人物技能。"""
import json,re,sys
from pathlib import Path
from luau_builder import candidate,verify_existing,write,ROOT
job=sys.argv[1]
if not re.fullmatch(r'job_opencode_probe_[0-9]+',job):raise SystemExit(2)
folder=ROOT/'services/skill-runtime/runtime/jobs'/job
request=json.loads((folder/'build_request.json').read_text(encoding='utf-8'))
try:
    definition,program,args=candidate(json.loads((folder/'proposal.json').read_text(encoding='utf-8')),request)
    for name,value in [('candidate_definition.json',definition),('candidate.json',program),('test_arguments.json',args)]:
        (folder/name).write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
    (folder/'source.luau').write_text(program['source'],encoding='utf-8')
    raise SystemExit(verify_existing(folder))
except (ValueError,KeyError,TypeError) as error:
    write(folder,{'state':'failed','message':str(error)});raise SystemExit(1)
