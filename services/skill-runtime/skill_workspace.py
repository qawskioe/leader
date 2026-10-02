"""模型技能工程：工具代理限制文件范围，Git记录基线和每次受检代码。"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
from evidence_index import EvidenceIndex


def dump(value):
    return json.dumps(value,ensure_ascii=False,indent=2)


class Workspace:
    editable={'source.luau','skill.json'}

    def __init__(self,folder,request,baseline,sdk,evidence,draft):
        self.root=folder/'workspace'
        self.root.mkdir(exist_ok=False)
        self.files=set()
        self.test_count=0
        self.approved=None
        self.export('source.luau',baseline.pop('source',''),raw=True)
        self.export('skill.json',baseline)
        self.export('reference/sdk.md',sdk,raw=True)
        self.export('reference/principles.md',Path(__file__).with_name('authoring_principles.md').read_text(encoding='utf-8'),raw=True)
        self.evidence_index=EvidenceIndex(self.export)
        self.export('reference/task.json',self.evidence_index.pack({'goal_id':request['goal_id'],'creation':request.get('creation',{}),'revision':{k:v for k,v in request.get('revision',{}).items() if k!='definition'},'world_operations':request['world_operations']}))
        self.export('reference/evidence.json',self.evidence_index.pack(evidence))
        self.export('reference/previous_failure.json',self.evidence_index.pack({k:v for k,v in draft.items() if k not in ('source','candidate_output')}))
        for key,value in request['character_context'].items():
            # 文件名来自宿主合同，不来自模型路径。
            if not key.replace('_','').isalnum():raise ValueError('invalid context section')
            self.export('reference/context/'+key+'.json',self.evidence_index.pack(value,key))
        owned=[]
        for index,(ref,definition) in enumerate(request['owned_skills'].items()):
            prefix=f'reference/owned/{index}'
            program=json.loads(definition['program_json'])
            self.export(prefix+'.luau',program['source'],raw=True)
            self.export(prefix+'.json',{k:v for k,v in definition.items() if k!='program_json'})
            owned.append({'ref':ref,'name':definition['name'],'description':definition['description'],'source':prefix+'.luau','definition':prefix+'.json'})
        self.export('reference/owned/index.json',owned)
        (self.root/'.hooks').mkdir()
        (self.root/'.template').mkdir()
        self.git('init','--template=.template','.')
        self.git('add','--','source.luau','skill.json')
        self.git('commit','-m','技能开发基线','--allow-empty')
        self.base=self.git('rev-parse','HEAD').strip()

    def export(self,name,value,raw=False):
        p=self.root/name
        if not p.resolve().is_relative_to(self.root.resolve()):raise ValueError('导出路径越界')
        p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(value if raw else dump(value),encoding='utf-8')
        self.files.add(name)

    def path(self,name,write=False):
        if not isinstance(name,str) or name not in (self.editable if write else self.files):
            raise ValueError('文件不在本次技能工程的可写/可读目录中')
        p=self.root/name
        if p.is_symlink() or not p.resolve().is_relative_to(self.root.resolve()):raise ValueError('文件路径越界')
        return p

    def git(self,*args):
        env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull,GIT_TERMINAL_PROMPT='0',GIT_ALLOW_PROTOCOL='')
        result=subprocess.run(['git','-c','core.hooksPath='+str((self.root/'.hooks').resolve()),'-c','commit.gpgsign=false','-c','core.autocrlf=false','-c','user.name=Leader Skill','-c','user.email=skill@localhost',*args],cwd=self.root,env=env,capture_output=True,text=True,encoding='utf-8',timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        if result.returncode:raise ValueError('Git操作失败：'+result.stderr[:600])
        return result.stdout

    def output(self):
        if any(self.path(name).stat().st_size>60000 for name in self.editable):raise ValueError('技能文件超过60000字节')
        value=json.loads(self.path('skill.json').read_text(encoding='utf-8'))
        if not isinstance(value,dict) or 'source' in value:raise ValueError('skill.json只放声明，源码在source.luau')
        return dict(value,source=self.path('source.luau').read_text(encoding='utf-8'))

    def digest(self):
        return hashlib.sha256(json.dumps(self.output(),ensure_ascii=False,sort_keys=True).encode()).hexdigest()

    def checkpoint(self,label):
        self.git('add','--','source.luau','skill.json')
        self.git('commit','--allow-empty','-m',label)
        return self.git('rev-parse','HEAD').strip()
