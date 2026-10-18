"""启动本机网关，再打开 Godot 游戏；不打开网页，不录制麦克风。"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
sys.path.insert(0, str(ROOT.parent))
from godot_path import resolve_godot

def launch(args):
    if '--tts' in args and '--no-tts' in args:
        raise ValueError('--tts 与 --no-tts 不能同时使用')
    no_tts = '--no-tts' in args or ('--player-control' in args and '--tts' not in args)
    GODOT = Path(resolve_godot())
    subprocess.run([sys.executable,str(ROOT/'manage.py'),'start'],check=True)
    if not no_tts:
        subprocess.run([sys.executable,str(ROOT.parent/'gemini-tts/manage.py'),'start'],check=True)
    xr_args = ['--xr-mode','on','--rendering-method','gl_compatibility'] if '--vr' in args else []
    user_args = [x for x in args if x in ('--vr','--gather-scenario','--help-scenario','--luau-playtest','--player-control','--tts','--no-tts')]
    if no_tts and '--no-tts' not in user_args:
        user_args.append('--no-tts')
    user_args += [x for x in args if x.startswith('--skill-library=')]
    user_args += [x for x in args if x.startswith('--skill-review-job=')]
    user_args += [x for x in args if x.startswith('--resume-learning-job=')]
    with (ROOT/'runtime/godot.log').open('ab') as log:
        subprocess.Popen([str(GODOT),'--path',str(PROJECT)]+xr_args+(['--']+user_args if user_args else []),cwd=PROJECT,
                         stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)


if __name__ == '__main__':
    launch(sys.argv[1:])
