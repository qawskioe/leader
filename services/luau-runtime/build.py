"""固定依赖版本构建本地执行器，依赖和产物仅写入忽略的runtime目录。"""
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request

ROOT=Path(__file__).resolve().parent

def main():
    spec=json.loads((ROOT/'dependencies.json').read_text(encoding='utf-8'))
    repo=ROOT/'runtime/luau'
    if not repo.exists():
        subprocess.run(['git','clone',spec['luau_repository'],str(repo)],check=True)
    subprocess.run(['git','-C',str(repo),'checkout','--detach',spec['luau_commit']],check=True)
    header=ROOT/'runtime/include/nlohmann/json.hpp'
    header.parent.mkdir(parents=True,exist_ok=True)
    if not header.exists():
        with urllib.request.urlopen(spec['json_header'],timeout=30) as response:
            header.write_bytes(response.read())
    if hashlib.sha256(header.read_bytes()).hexdigest()!=spec['json_sha256']:
        raise RuntimeError('JSON依赖摘要不匹配，停止构建')
    subprocess.run(['cmake','-S',str(ROOT),'-B',str(ROOT/'runtime/build'),'-G','Ninja','-DCMAKE_BUILD_TYPE=Release'],check=True)
    subprocess.run(['cmake','--build',str(ROOT/'runtime/build'),'--target','leader-skill-service','-j','4'],check=True)

if __name__=='__main__': main()
