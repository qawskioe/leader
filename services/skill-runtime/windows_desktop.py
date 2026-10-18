"""Render Windows tests on a private desktop without switching the user's desktop."""
import ctypes
from ctypes import wintypes
import msvcrt
import os
from pathlib import Path
import subprocess
import time
import uuid


class StartupInfo(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('reserved', wintypes.LPWSTR),
                ('desktop', wintypes.LPWSTR), ('title', wintypes.LPWSTR),
                ('x', wintypes.DWORD), ('y', wintypes.DWORD),
                ('width', wintypes.DWORD), ('height', wintypes.DWORD),
                ('chars_x', wintypes.DWORD), ('chars_y', wintypes.DWORD),
                ('fill', wintypes.DWORD), ('flags', wintypes.DWORD),
                ('show', wintypes.WORD), ('reserved_size', wintypes.WORD),
                ('reserved_bytes', ctypes.POINTER(ctypes.c_byte)),
                ('stdin', wintypes.HANDLE), ('stdout', wintypes.HANDLE),
                ('stderr', wintypes.HANDLE)]


class ProcessInfo(ctypes.Structure):
    _fields_ = [('process', wintypes.HANDLE), ('thread', wintypes.HANDLE),
                ('pid', wintypes.DWORD), ('thread_id', wintypes.DWORD)]


class DesktopProcess:
    def __init__(self, kernel, info, args):
        self.kernel = kernel
        self.handle = info.process
        self.pid = info.pid
        self.args = args
        self.returncode = None

    def poll(self):
        if self.returncode is not None:
            return self.returncode
        result = self.kernel.WaitForSingleObject(self.handle, 0)
        if result == 0x102:
            return None
        if result != 0:
            raise ctypes.WinError(ctypes.get_last_error())
        code = wintypes.DWORD()
        if not self.kernel.GetExitCodeProcess(self.handle, ctypes.byref(code)):
            raise ctypes.WinError(ctypes.get_last_error())
        self.returncode = code.value
        return self.returncode

    def wait(self, timeout=None):
        deadline = time.monotonic() + timeout if timeout is not None else None
        while self.poll() is None:
            if deadline is not None and time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired(self.args, timeout)
            time.sleep(.02)
        return self.returncode

    def close_handle(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


class PrivateDesktop:
    def __init__(self):
        self.user = ctypes.WinDLL('user32', use_last_error=True)
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.name = 'LeaderBackground_' + uuid.uuid4().hex
        self.user.CreateDesktopW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR,
                                            ctypes.c_void_p, wintypes.DWORD,
                                            wintypes.DWORD, ctypes.c_void_p]
        self.user.CreateDesktopW.restype = wintypes.HANDLE
        self.user.CloseDesktop.argtypes = [wintypes.HANDLE]
        self.kernel.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR,
                                              ctypes.c_void_p, ctypes.c_void_p,
                                              wintypes.BOOL, wintypes.DWORD,
                                              ctypes.c_void_p, wintypes.LPCWSTR,
                                              ctypes.POINTER(StartupInfo),
                                              ctypes.POINTER(ProcessInfo)]
        self.kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        self.kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.handle = None

    def __enter__(self):
        # No DESKTOP_SWITCHDESKTOP permission, SetThreadDesktop or SwitchDesktop.
        self.handle = self.user.CreateDesktopW(self.name, None, None, 0, 0x00FF, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        return self

    def __exit__(self, *_):
        if self.handle:
            if not self.user.CloseDesktop(self.handle):
                raise ctypes.WinError(ctypes.get_last_error())
            self.handle = None

    def start(self, args, stdout, stderr, cwd=None):
        if not self.handle:
            raise RuntimeError('Private desktop is not open')
        handles = list({msvcrt.get_osfhandle(stream.fileno()) for stream in [stdout, stderr]})
        inherited = {handle: os.get_handle_inheritable(handle) for handle in handles}
        startup = StartupInfo()
        startup.cb = ctypes.sizeof(startup)
        startup.desktop = 'WinSta0\\' + self.name
        startup.flags = 0x00000100  # STARTF_USESTDHANDLES; no focus or show requests.
        startup.stdout = msvcrt.get_osfhandle(stdout.fileno())
        startup.stderr = msvcrt.get_osfhandle(stderr.fileno())
        info = ProcessInfo()
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline([str(arg) for arg in args]))
        try:
            for handle in handles:
                os.set_handle_inheritable(handle, True)
            started = self.kernel.CreateProcessW(str(Path(args[0]).resolve()), command,
                                                None, None, True, 0x08000000,
                                                None, str(cwd) if cwd else None,
                                                ctypes.byref(startup), ctypes.byref(info))
            if not started:
                raise ctypes.WinError(ctypes.get_last_error())
        finally:
            for handle, value in inherited.items():
                os.set_handle_inheritable(handle, value)
        self.kernel.CloseHandle(info.thread)
        return DesktopProcess(self.kernel, info, args)

    def request_close(self, process, window_class=None):
        callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        self.user.EnumDesktopWindows.argtypes = [wintypes.HANDLE, callback_type, wintypes.LPARAM]
        self.user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        self.user.IsWindowVisible.argtypes = [wintypes.HWND]
        self.user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
        self.user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
        found = []

        @callback_type
        def visit(hwnd, _):
            owner = wintypes.DWORD()
            self.user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            name = ctypes.create_unicode_buffer(128)
            if owner.value == process.pid:
                self.user.GetClassNameW(hwnd, name, 128)
            # Godot's Engine window can render while hidden; its class identifies the quit entry.
            matches = name.value.casefold() == window_class.casefold() if window_class else bool(self.user.IsWindowVisible(hwnd))
            if owner.value == process.pid and matches:
                if not self.user.PostMessageW(hwnd, 0x0010, 0, 0):
                    return False
                found.append(int(hwnd))
            return True

        if not self.user.EnumDesktopWindows(self.handle, visit, 0) and not found:
            raise ctypes.WinError(ctypes.get_last_error())
        return found
