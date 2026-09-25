"""记录静音；仅响应游戏中本次按住说话的显式请求，解除 Oculus 输入静音。"""
import ctypes
import json
from pathlib import Path
import sys
import time
import warnings

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'runtime/audio_diag'))
warnings.filterwarnings('ignore', category=UserWarning)


def speech_request(endpoint, request, now_ms):
    result = {'id': request.get('id'), 'ok': False}
    if request.get('action') != 'unmute_for_speech' or not 0 <= now_ms-request.get('unix_ms', 0) < 2000:
        return result
    endpoint.SetMute(0, None)
    result['ok'] = not bool(endpoint.GetMute())
    return result


def main(pid):
    from pycaw.pycaw import AudioUtilities
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return
    path = ROOT / f'runtime/vr_audio_windows_{pid}.jsonl'
    last = None
    heartbeat = 0
    endpoint = None
    handled = None
    request_path = ROOT / f'runtime/vr_audio_request_{pid}.json'
    ack_path = ROOT / f'runtime/vr_audio_ack_{pid}.json'
    try:
        while True:
            code = ctypes.c_ulong()
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value != 259:
                break
            try:
                if endpoint is None:
                    endpoint = next(d.EndpointVolume for d in AudioUtilities.GetAllDevices()
                                    if d.FriendlyName == 'Headset Microphone (Oculus Virtual Audio Device)')
                state = {'muted': bool(endpoint.GetMute()), 'volume': round(endpoint.GetMasterVolumeLevelScalar(), 3)}
                if request_path.exists():
                    try:
                        request = json.loads(request_path.read_text(encoding='utf-8'))
                        if request.get('id') != handled:
                            ack = speech_request(endpoint, request, round(time.time()*1000))
                            temporary = ack_path.with_suffix('.tmp')
                            temporary.write_text(json.dumps(ack), encoding='utf-8')
                            temporary.replace(ack_path)
                            handled = request.get('id')
                            with path.open('a', encoding='utf-8') as file:
                                file.write(json.dumps({'unix_ms': round(time.time()*1000), 'kind': 'speech_unmute_request', **ack})+'\n')
                    except (OSError, ValueError):
                        pass  # 请求文件正被原子更替/写入时，下次轮询重读。
            except Exception as exc:
                state = {'error': type(exc).__name__}
                endpoint = None
            now = time.monotonic()
            if state != last or now - heartbeat >= 10:
                with path.open('a', encoding='utf-8') as file:
                    file.write(json.dumps({'unix_ms': round(time.time()*1000), 'kind': 'windows_microphone',
                                           'changed': state != last, **state}) + '\n')
                last = state
                heartbeat = now
            time.sleep(0.05 if endpoint is not None else 2)
    finally:
        kernel.CloseHandle(handle)


if __name__ == '__main__':
    main(int(sys.argv[1]))
