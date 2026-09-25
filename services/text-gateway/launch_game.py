"""启动本机网关，再打开 Godot 游戏；不打开网页，不录制麦克风。"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
sys.path.insert(0, str(ROOT.parent))
from godot_path import resolve_godot

if __name__ == '__main__':
    GODOT = Path(resolve_godot())
    subprocess.run([sys.executable,str(ROOT/'manage.py'),'start'],check=True)
    if '--no-tts' not in sys.argv[1:]:
        subprocess.run([sys.executable,str(ROOT.parent/'gemini-tts/manage.py'),'start'],check=True)
    xr_args = ['--xr-mode','on','--rendering-method','gl_compatibility'] if '--vr' in sys.argv[1:] else []
    user_args = [x for x in sys.argv[1:] if x in ('--vr','--gather-scenario','--help-scenario','--luau-playtest','--player-control')]
    user_args += [x for x in sys.argv[1:] if x.startswith('--skill-library=')]
    user_args += [x for x in sys.argv[1:] if x.startswith('--skill-review-job=')]
    user_args += [x for x in sys.argv[1:] if x.startswith('--resume-learning-job=')]
    with (ROOT/'runtime/godot.log').open('ab') as log:
        subprocess.Popen([str(GODOT),'--path',str(PROJECT)]+xr_args+(['--']+user_args if user_args else []),cwd=PROJECT,
                         stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
