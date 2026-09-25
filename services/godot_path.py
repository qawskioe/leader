"""所有启动与隔离验证共用引擎路径；机器配置保留在忽略目录。"""
import os
import shutil
from pathlib import Path


def resolve_godot():
    configured = os.environ.get('LEADER_GODOT')
    path_file = Path(__file__).resolve().parent / 'text-gateway/runtime/godot-path.txt'
    if not configured and path_file.is_file():
        configured = path_file.read_text(encoding='utf-8').strip()
    if configured:
        if not Path(configured).is_file():
            raise FileNotFoundError('LEADER_GODOT 或 godot-path.txt 指向的引擎不存在')
        return configured
    for name in ('godot', 'godot4'):
        found = shutil.which(name)
        if found:
            return found
    raise FileNotFoundError('请设置 LEADER_GODOT 为 Godot 4.6.2 可执行文件的完整路径')
