"""仅提供角色文字决策；不包含音频、浏览器或 Live 接口。"""
import asyncio
import json
import secrets
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from typing import Literal
from starlette.middleware.trustedhost import TrustedHostMiddleware
import uvicorn
from text_model import complete

ROOT = Path(__file__).resolve().parent
app = FastAPI(docs_url=None, redoc_url=None)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=['127.0.0.1', 'localhost', 'testserver'])
gate = asyncio.Semaphore(2)

def authorize(authorization):
    key = (ROOT/'runtime/gateway-key.txt').read_text(encoding='utf-8').strip()
    if not key or not secrets.compare_digest(authorization or '', 'Bearer '+key):
        raise HTTPException(401, detail='Unauthorized')

class DecisionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    mode: Literal['decision', 'memory']
    prompt: str = Field(min_length=1, max_length=250000)

@app.post('/game/exchange')
async def decision(body: DecisionRequest, authorization: str | None = Header(default=None)):
    authorize(authorization)
    if not body.prompt.strip():
        raise HTTPException(422, detail='Prompt is empty')
    async with gate:
        if body.mode == 'memory':
            path = ROOT/'runtime/memory_model.json'
            if not path.is_file():
                return {'ok': False, 'error': '未配置回忆阶段模型 memory_model.json'}
            config = json.loads(path.read_text(encoding='utf-8'))
            return await asyncio.to_thread(complete, body.prompt, config)
        return await asyncio.to_thread(complete, body.prompt)

@app.get('/local/status')
def status(authorization: str | None = Header(default=None)):
    authorize(authorization)
    return {'service':'leader-text-gateway', 'text_model_configured':(ROOT/'runtime/text_model.json').is_file()}

if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=18090, access_log=False, log_level='warning')
