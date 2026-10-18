"""Isolated rendered replay, with owned process-tree cancellation."""
import os
import signal
import subprocess
import tempfile
import time


class ReviewCancelled(subprocess.SubprocessError):
    def __init__(self):
        super().__init__('独立回放已取消')
        self.output='';self.stderr=''


def run_hidden(args, timeout=65, cancelled=None):
    if cancelled is not None and cancelled():raise ReviewCancelled()
    if os.name=='nt':return _run_windows(args,timeout,cancelled)
    with subprocess.Popen(args, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace',
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
                              start_new_session=os.name!='nt') as process:
            deadline=time.monotonic()+timeout
            try:
                while True:
                    if cancelled is not None and cancelled():raise ReviewCancelled()
                    if time.monotonic()>=deadline:
                        raise subprocess.TimeoutExpired(args,timeout)
                    try:
                        stdout,stderr=process.communicate(timeout=0.05)
                        return subprocess.CompletedProcess(args,process.returncode,stdout,stderr)
                    except subprocess.TimeoutExpired:
                        pass
            except BaseException as error:
                # Windows控制台启动器会派生Godot子进程；只杀启动器会留下持有输出管道的子进程。
                # 子进程可能仍持有输出管道；只结束本次创建的独立进程组。
                try:os.killpg(process.pid,signal.SIGKILL)
                except ProcessLookupError:pass
                stdout,stderr=process.communicate(timeout=10)
                if isinstance(error,(subprocess.TimeoutExpired,ReviewCancelled)):
                    error.output=stdout;error.stderr=stderr
                raise


def _run_windows(args, timeout, cancelled):
    from windows_desktop import PrivateDesktop
    # Files retain partial output after cancellation without waiting on inherited pipes.
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        with PrivateDesktop() as desktop:
            process=desktop.start(args,output,errors)
            try:
                deadline=time.monotonic()+timeout
                while process.poll() is None:
                    if cancelled is not None and cancelled():raise ReviewCancelled()
                    if time.monotonic()>=deadline:raise subprocess.TimeoutExpired(args,timeout)
                    time.sleep(.05)
                output.seek(0);errors.seek(0)
                return subprocess.CompletedProcess(args,process.returncode,
                        output.read().decode('utf-8',errors='replace'),errors.read().decode('utf-8',errors='replace'))
            except BaseException as error:
                if process.poll() is None:
                    subprocess.run(['taskkill.exe','/PID',str(process.pid),'/T','/F'],
                                   capture_output=True,timeout=10,creationflags=subprocess.CREATE_NO_WINDOW)
                process.wait(timeout=10)
                output.seek(0);errors.seek(0)
                if isinstance(error,(subprocess.TimeoutExpired,ReviewCancelled)):
                    error.output=output.read().decode('utf-8',errors='replace')
                    error.stderr=errors.read().decode('utf-8',errors='replace')
                raise
            finally:
                process.close_handle()
