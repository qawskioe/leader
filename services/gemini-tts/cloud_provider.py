"""Cloud Text-to-Speech 官方双向流；沿用现有 Godot PCM 协议。"""
import base64
import atexit
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

from google.auth import credentials, exceptions as auth_errors
from google.api_core import exceptions as api_errors
from google.cloud import texttospeech

from provider import MODEL, MAX_AUDIO_BYTES, validate_request

ROOT = Path(__file__).resolve().parent
CONFIG = ROOT/'runtime/cloud_config.json'
_client = None
_client_identity = None
_client_credentials = None


def load_config():
    if not CONFIG.is_file():
        raise ValueError('Cloud TTS 尚未配置项目和试用金到期时间')
    value = json.loads(CONFIG.read_text(encoding='utf-8'))
    for name in ['project_id','account','gcloud_script','stop_at_utc']:
        if not isinstance(value.get(name),str) or not value[name].strip():
            raise ValueError('Cloud TTS 配置缺少 '+name)
    if value.get('trial_credit_confirmed') is not True:
        raise ValueError('Cloud TTS 暂未启用：还需确认关联结算账号的试用金余额和到期日期')
    cutoff = datetime.fromisoformat(value['stop_at_utc'].replace('Z','+00:00'))
    if cutoff.tzinfo is None:
        raise ValueError('Cloud TTS 停用时间必须包含时区')
    if datetime.now(timezone.utc) >= cutoff:
        raise ValueError('Cloud TTS 已到预定停用时间，不再发送计费请求')
    if not Path(value['gcloud_script']).is_file():
        raise ValueError('未找到配置中的 Google Cloud CLI')
    return value


class GcloudCredentials(credentials.Credentials):
    """复用已登录 CLI；令牌和实际到期时间仅在本进程内读取。"""
    def __init__(self, config):
        super().__init__()
        self.config = config

    def refresh(self, request):
        try:
            result = subprocess.run([sys.executable,self.config['gcloud_script'],
                '--account='+self.config['account'],'config','config-helper',
                '--format=json(credential)'],capture_output=True,text=True,encoding='utf-8',
                timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
            if result.returncode:
                raise ValueError('CLI authentication failed')
            value = json.loads(result.stdout)['credential']
            self.token = value['access_token']
            self.expiry = datetime.fromisoformat(value['token_expiry'].replace('Z','+00:00')).astimezone(timezone.utc).replace(tzinfo=None)
            if not self.token: raise ValueError('Empty token')
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
            raise auth_errors.RefreshError('无法刷新 GCP 登录，请检查本机 gcloud 登录状态') from None


def close_client():
    global _client, _client_identity, _client_credentials
    if _client is not None:
        _client.transport.close()
    _client = None
    _client_identity = None
    _client_credentials = None


atexit.register(close_client)


def get_client(config):
    global _client, _client_identity, _client_credentials
    identity = (config['project_id'],config['account'],config['gcloud_script'])
    if _client is None or _client_identity != identity:
        close_client()
        _client_credentials = GcloudCredentials(config)
        _client = texttospeech.TextToSpeechClient(credentials=_client_credentials,
            client_options={'api_endpoint':'texttospeech.googleapis.com'})
        _client_identity = identity
    return _client


def prepare():
    get_client(load_config())
    _client_credentials.refresh(None)  # 仅刷新登录，不生成音频，不产生 TTS 调用。


def requests_for(value):
    yield texttospeech.StreamingSynthesizeRequest(
        streaming_config=texttospeech.StreamingSynthesizeConfig(
            voice=texttospeech.VoiceSelectionParams(name=value['voice'],language_code='cmn-CN',model_name=MODEL),
            streaming_audio_config=texttospeech.StreamingAudioConfig(
                audio_encoding=texttospeech.AudioEncoding.PCM,sample_rate_hertz=24000)))
    yield texttospeech.StreamingSynthesizeRequest(input=texttospeech.StreamingSynthesisInput(
        text=value['text'],prompt='只朗读 text 中的原文，不朗读语气描述，不补充台词。公开表达方式：'+value['style']))
    # 生成器结束即 half-close：这是完整台词边界，不在玩家说完前合成。


def packets_for(responses):
    sequence = 0
    total = 0
    pending = b''
    for response in responses:
        data = pending + response.audio_content
        if not data: continue
        pending = data[-1:] if len(data)%2 else b''
        data = data[:len(data)-len(pending)]
        total += len(data)
        if total > MAX_AUDIO_BYTES:
            raise ValueError('Cloud TTS 音频超过单句 30 秒上限')
        for offset in range(0,len(data),4800):
            yield {'type':'audio','sequence':sequence,'sample_rate':24000,
                   'pcm_base64':base64.b64encode(data[offset:offset+4800]).decode('ascii')}
            sequence += 1
    # gRPC 迭代仅在 OK 状态正常结束；失败／截断由 SDK 抛错，不发送 done。
    if not total or pending:
        raise ValueError('Cloud TTS 返回空音频或不完整 PCM')
    yield {'type':'done','chunks':sequence,'audio_bytes':total}


def synthesize(value):
    validate_request(value)
    config = load_config()  # 每句检查到期，不把试用金有效性缓存为永久有效。
    started = time.monotonic()
    client = get_client(config)
    responses = None
    try:
        responses = client.streaming_synthesize(requests=requests_for(value),
            metadata=(('x-goog-user-project',config['project_id']),),timeout=90,retry=None)
        for packet in packets_for(responses):
            packet['elapsed_ms'] = round((time.monotonic()-started)*1000)
            yield packet
    except api_errors.ResourceExhausted:
        raise RuntimeError('Cloud TTS 请求配额或容量已耗尽；请查看 GCP 项目配额，不是 AI Studio 每日十次限制') from None
    except (api_errors.PermissionDenied,api_errors.Unauthenticated,auth_errors.GoogleAuthError):
        raise RuntimeError('Cloud TTS 认证或权限不足；检查 GCP 登录、结算状态和 Vertex AI 调用权限') from None
    except api_errors.InvalidArgument as error:
        # 参数错误也可能是单次生成拒绝；保留服务端原因，不能一律归咎配置。
        reason = str(error.message).replace('\n', ' ')[:600]
        raise RuntimeError('Cloud TTS 本句生成被拒绝：'+reason) from None
    except api_errors.GoogleAPICallError:
        raise RuntimeError('Cloud TTS 请求失败或超时；本句未自动重试') from None
    finally:
        if responses is not None:
            responses.cancel()
