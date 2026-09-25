"""验证解压到项目根的公开资源包，不下载或执行外部程序。"""
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'asset-pack-manifest.json').read_text(encoding='utf-8'))
errors=[]
for entry in manifest['files']:
    path=root/entry['path']
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:
        errors.append(entry['path'])
if errors:raise SystemExit('资源缺失或摘要不符：\n'+'\n'.join(errors))
print('ASSET_PACK_VERIFIED',len(manifest['files']))
