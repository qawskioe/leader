import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

if os.name == 'nt':
    from windows_desktop import PrivateDesktop


@unittest.skipUnless(os.name == 'nt', 'native Windows desktop check')
class WindowsDesktopTests(unittest.TestCase):
    def test_private_window_focus_and_normal_close_preserve_user_desktop(self):
        self.check_window(False)

    def test_hidden_window_has_a_normal_close_entry(self):
        self.check_window(True)

    def check_window(self, hidden):
        code = '''
import ctypes,json,os,sys,time
from ctypes import wintypes
from pathlib import Path
u=ctypes.WinDLL('user32',use_last_error=True)
k=ctypes.WinDLL('kernel32',use_last_error=True)
u.GetThreadDesktop.argtypes=[wintypes.DWORD];u.GetThreadDesktop.restype=wintypes.HANDLE
u.GetUserObjectInformationW.argtypes=[wintypes.HANDLE,ctypes.c_int,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD)]
name=ctypes.create_unicode_buffer(256);needed=wintypes.DWORD()
assert u.GetUserObjectInformationW(u.GetThreadDesktop(k.GetCurrentThreadId()),2,name,ctypes.sizeof(name),ctypes.byref(needed))
assert name.value==sys.argv[1], 'Refuse focus check outside the private desktop'
u.CreateWindowExW.restype=wintypes.HWND
u.CreateWindowExW.argtypes=[wintypes.DWORD,wintypes.LPCWSTR,wintypes.LPCWSTR,wintypes.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,wintypes.HWND,wintypes.HMENU,wintypes.HINSTANCE,ctypes.c_void_p]
u.SetForegroundWindow.argtypes=[wintypes.HWND];u.IsWindow.argtypes=[wintypes.HWND]
h=u.CreateWindowExW(0,'STATIC','Leader isolated fixture',0x00CF0000 | (0 if sys.argv[3]=='hidden' else 0x10000000),10,10,160,100,None,None,None,None)
assert h
u.GetClassNameW.argtypes=[wintypes.HWND,wintypes.LPWSTR,ctypes.c_int]
window_class=ctypes.create_unicode_buffer(128);u.GetClassNameW(h,window_class,128)
u.SetForegroundWindow(h)
Path(sys.argv[2]).write_text(json.dumps({'desktop':name.value,'pid':os.getpid(),'class':window_class.value}))
deadline=time.monotonic()+10
while u.IsWindow(h):
    assert time.monotonic()<deadline, 'Normal close was not delivered'
    msg=wintypes.MSG()
    while u.PeekMessageW(ctypes.byref(msg),None,0,0,1):
        u.TranslateMessage(ctypes.byref(msg));u.DispatchMessageW(ctypes.byref(msg))
    time.sleep(.01)
print('PRIVATE_DESKTOP_NORMAL_CLOSE_PASSED',flush=True)
'''
        user = ctypes.WinDLL('user32', use_last_error=True)
        user.GetForegroundWindow.restype = wintypes.HWND
        user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryFile() as output:
            ready = Path(folder) / 'ready.json'
            with PrivateDesktop() as desktop:
                python = getattr(sys, '_base_executable', sys.executable)
                process = desktop.start([python, '-u', '-c', code, desktop.name, str(ready), 'hidden' if hidden else 'visible'], output, output)
                try:
                    until = time.monotonic() + 5
                    samples = 0
                    while not ready.exists() and time.monotonic() < until and process.poll() is None:
                        owner = wintypes.DWORD()
                        user.GetWindowThreadProcessId(user.GetForegroundWindow(), ctypes.byref(owner))
                        self.assertNotEqual(owner.value, process.pid)
                        samples += 1
                        time.sleep(.01)
                    self.assertTrue(ready.exists(), 'Fixture must confirm the private desktop before focus checks')
                    self.assertEqual(json.loads(ready.read_text())['desktop'], desktop.name)
                    self.assertGreater(samples, 0)
                    self.assertGreater(len(desktop.request_close(process, window_class='STATIC' if hidden else None)), 0, json.loads(ready.read_text()))
                    self.assertEqual(process.wait(timeout=5), 0)
                    output.seek(0)
                    self.assertIn(b'PRIVATE_DESKTOP_NORMAL_CLOSE_PASSED', output.read())
                finally:
                    if process.poll() is None:
                        subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                                       capture_output=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
                        process.wait(timeout=5)
                    process.close_handle()


if __name__ == '__main__':
    unittest.main()
