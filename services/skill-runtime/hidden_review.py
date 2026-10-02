"""Windows 隐藏父窗口：Godot 子窗口从创建起就不能抢占游戏前台。"""
import ctypes
import os
import subprocess
import time
from contextlib import contextmanager
from ctypes import wintypes


@contextmanager
def hidden_parent():
    if os.name != 'nt':
        yield []
        return
    user = ctypes.WinDLL('user32', use_last_error=True)
    create = user.CreateWindowExW
    create.restype = wintypes.HWND
    create.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR,
                       wintypes.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                       ctypes.c_int, wintypes.HWND, wintypes.HMENU,
                       wintypes.HINSTANCE, wintypes.LPVOID]
    user.DestroyWindow.argtypes = [wintypes.HWND]
    # 不设置 WS_VISIBLE；使用系统窗口类，不创建额外桌面或捕获其他窗口。
    handle = create(0x08000000, 'STATIC', 'Leader hidden review host',
                    0x80000000, 0, 0, 800, 600, None, None, None, None)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        yield ['--wid', str(handle)]
    finally:
        user.DestroyWindow(handle)


def run_hidden(args, timeout=65):
    with hidden_parent() as window_args:
        with subprocess.Popen(args[:1]+window_args+args[1:], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace',
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
            deadline=time.monotonic()+timeout
            try:
                while True:
                    if os.name=='nt':
                        user=ctypes.windll.user32
                        message=wintypes.MSG()
                        while user.PeekMessageW(ctypes.byref(message),None,0,0,1):
                            user.TranslateMessage(ctypes.byref(message))
                            user.DispatchMessageW(ctypes.byref(message))
                    if time.monotonic()>=deadline:
                        raise subprocess.TimeoutExpired(args,timeout)
                    try:
                        stdout,stderr=process.communicate(timeout=0.05)
                        return subprocess.CompletedProcess(args,process.returncode,stdout,stderr)
                    except subprocess.TimeoutExpired:
                        pass
            except BaseException as error:
                # Windows控制台启动器会派生Godot子进程；只杀启动器会留下持有输出管道的子进程。
                if os.name=='nt':
                    subprocess.run(['taskkill.exe','/PID',str(process.pid),'/T','/F'],capture_output=True,timeout=10,creationflags=subprocess.CREATE_NO_WINDOW)
                else:process.kill()
                stdout,stderr=process.communicate(timeout=10)
                if isinstance(error,subprocess.TimeoutExpired):
                    error.output=stdout;error.stderr=stderr
                raise
