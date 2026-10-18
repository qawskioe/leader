"""官方 Gemini TTS：只接收公开台词与公开语气，逐块返回 PCM。"""
import base64
import json
import io
import math
import re
from pathlib import Path
import time
from datetime import datetime, timezone
import urllib.error
import urllib.request

from probe import NoRedirect, events

MODEL = "gemini-3.8-flash-tts"

ROOT = Path(__file__).resolve().parent
MAX_AUDIO_BYTES = 24_000 * 2 * 30
_retry_at = 0.0


class QuotaError(RuntimeError):
    def __init__(self, seconds, limit=None):
        self.retry_after_seconds = seconds
        self.code = 'quota_exceeded'
        limit_text = f'（上游报告限额 {limit}，未说明统计周期）' if limit else ''
        super().__init__(f'Gemini TTS 请求配额超限{limit_text}；至少等待 {seconds} 秒后再试。冷却期间不发送语音请求，恢复时间仍以上游为准。')


def quota_details(raw, retry_after=None):
    """Interactions 的 HTTP 错误正文也可能是 SSE；只提取配额字段。"""
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        try:
            value = next(events(io.BytesIO(raw)))
        except (ValueError, UnicodeError, StopIteration, AttributeError):
            value = {}
    error = value.get('error', {}) if isinstance(value, dict) else {}
    message = error.get('message', '') if isinstance(error, dict) else ''
    if not isinstance(message, str): message = ''
    delay = re.search(r'retry in\s+([0-9.]+)s', message, re.I)
    limit = re.search(r'limit:\s*(\d+)', message)
    try:
        seconds = math.ceil(float(retry_after or (delay.group(1) if delay else 60)))
    except (ValueError, OverflowError):
        seconds = 60
    return {'retry_after_seconds':max(1,min(seconds,86400)),
            'limit':int(limit.group(1)) if limit else None,
            'free_request_quota':'generate_content_free_tier_requests' in message}


def validate_request(value):
    if not isinstance(value, dict) or set(value) != {'text', 'style', 'voice'}:
        raise ValueError('只接受 text、style、voice 三个公开字段')
    if not isinstance(value['text'], str) or not 1 <= len(value['text'].strip()) <= 200:
        raise ValueError('公开台词需要为 1 至 200 字')
    if not isinstance(value['style'], str) or not 1 <= len(value['style'].strip()) <= 300:
        raise ValueError('公开语气需要为 1 至 300 字的表达描述')
    if not isinstance(value['voice'], str) or value['voice'] not in {'Kore', 'Puck', 'Aoede', 'Charon'}:
        raise ValueError('音色必须为已配置的 Kore、Puck、Aoede 或 Charon')
    return value


def packets(source):
    """供应商事件在入口校验；未明确完成的流绝不算成功。"""
    sequence = 0
    total = 0
    for event in source:
        if not isinstance(event, dict):
            raise ValueError('上游事件不是对象')
        kind = event.get('event_type')
        delta = event.get('delta', {})
        if kind == 'step.delta' and isinstance(delta, dict) and delta.get('type') == 'audio':
            mime = delta.get('mime_type', '').split(';', 1)[0].lower()
            if mime not in {'audio/l16', 'audio/pcm'}:
                raise ValueError('上游音频格式不匹配')
            data = base64.b64decode(delta['data'], validate=True)
            if not data or len(data) % 2:
                raise ValueError('上游 PCM 为空或字节数无效')
            total += len(data)
            if total > MAX_AUDIO_BYTES:
                raise ValueError('单句音频超过 30 秒上限')
            # 上游可以更换块大小，统一为最多 100ms 的本地分块。
            for offset in range(0, len(data), 4800):
                yield {'type': 'audio', 'sequence': sequence, 'sample_rate': 24000,
                       'pcm_base64': base64.b64encode(data[offset:offset + 4800]).decode('ascii')}
                sequence += 1
        elif kind == 'interaction.completed':
            if event.get('interaction', {}).get('status') != 'completed' or not total:
                raise ValueError('上游没有成功完成音频生成')
            yield {'type': 'done', 'chunks': sequence, 'audio_bytes': total}
            return
        elif kind in {'error', 'interaction.failed', 'interaction.cancelled'}:
            raise ValueError('上游 TTS 返回失败事件')
    raise ValueError('音频流中断：缺少明确完成标记')


def load_config():
    if not (ROOT / 'runtime/api-key.txt').read_text(encoding='utf-8').strip():
        raise ValueError('未配置官方 Gemini API Key')
    return {'configured': True}


def prepare():
    load_config()


def build_request(value):
    validate_request(value)
    return {
        'model': MODEL,
        'input': [{'type': 'user_input', 'content': [{
            'type': 'text', 'text': value['text'],
            'annotations': [{'type': 'speech_metadata', 'style': value['style']}],
        }]}],
        'response_format': {'type': 'audio', 'mime_type': 'audio/l16', 'sample_rate': 24000},
        'generation_config': {'speech_config': [{'voice': value['voice']}]},
        'stream': True, 'store': False,
    }


def synthesize(value):
    global _retry_at
    validate_request(value)
    remaining = math.ceil(_retry_at-time.monotonic())
    if remaining > 0:
        raise QuotaError(remaining)
    key = (ROOT / 'runtime/api-key.txt').read_text(encoding='utf-8').strip()
    if not key:
        raise ValueError('未配置 Gemini API Key')
    body = build_request(value)
    request = urllib.request.Request('https://generativelanguage.googleapis.com/v1beta/interactions',
                                    data=json.dumps(body).encode('utf-8'),
                                    headers={'x-goog-api-key': key, 'Content-Type': 'application/json',
                                             'Accept': 'text/event-stream'})
    started = time.monotonic()
    stage = 'connect_or_headers'
    sent = 0
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=45) as response:
            stage = 'stream'
            for packet in packets(events(response)):
                if time.monotonic() - started > 90:
                    raise TimeoutError('TTS 超过 90 秒总时限')
                packet['elapsed_ms'] = round((time.monotonic() - started) * 1000)
                if packet['type'] == 'audio': sent += 1
                yield packet
    except urllib.error.HTTPError as error:
        if error.code == 402:
            raise RuntimeError('Gemini API 预付款余额不足；请检查 AI Studio 结算状态') from None
        if error.code == 429:
            detail = quota_details(error.read(24000),error.headers.get('Retry-After'))
            _retry_at = time.monotonic()+detail['retry_after_seconds']
            (ROOT/'runtime/last_quota.json').write_text(json.dumps(detail,ensure_ascii=False,indent=2),encoding='utf-8')
            raise QuotaError(detail['retry_after_seconds'],detail['limit']) from None
        if error.code in (401,403):
            raise RuntimeError(f'Gemini TTS HTTP {error.code}：密钥或模型访问权限错误') from None
        raise RuntimeError(f'Gemini TTS HTTP {error.code}：上游服务拒绝了请求') from None
    except (urllib.error.URLError, OSError) as error:
        # 只保留传输诊断，不能写公开台词、提示词、请求头、网址或原始异常文本。
        reason = error.reason if isinstance(error, urllib.error.URLError) else error
        detail = {'time':datetime.now(timezone.utc).isoformat(), 'stage':stage,
                  'elapsed_ms':round((time.monotonic()-started)*1000), 'audio_packets_sent':sent,
                  'error_type':type(error).__name__, 'reason_type':type(reason).__name__,
                  'errno':reason.errno if isinstance(reason,OSError) else None}
        (ROOT/'runtime/last_transport_error.json').write_text(json.dumps(detail,indent=2),encoding='utf-8')
        raise RuntimeError('Gemini TTS 网络连接失败或超时') from None
