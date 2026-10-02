# 开发安装与离线验证

## 源码与资源

用 Git 获取本仓库及待审查分支；后续代码更新使用 Git 增量同步。资源不进入源码 Git，也无需重新压缩整个项目。下载已有 [v0.1.0-preview 资源包](https://github.com/qawskioe/leader/releases/tag/v0.1.0-preview)，解压到仓库根目录，保留 `assets/` 层级与许可文件。

`leader-assets.zip` 大小为 396887819 字节，发布摘要为 `1e2494d683de2a76091e995cbf69e95f48570fbd9c9989e15aef693257c9094e`。本次同步已对当前 128 个原始素材逐文件核验，全部与 `asset-pack-manifest.json` 一致，总计 756673432 字节。下载后还应核对包摘要并运行：

```text
python tools/check_asset_pack.py
```

## Windows 基线

使用 Godot 4.6.2，并将实际引擎路径放在当前终端环境变量中：

```powershell
$env:LEADER_GODOT = 'C:\Tools\Godot\Godot.exe'
& $env:LEADER_GODOT --headless --editor --path . --import --quit
& $env:LEADER_GODOT --path . -- --outdoor-preview
```

离线场景查看无需模型账号。完整交互需要 Python 3.11+、Git、CMake、Ninja、C++17 编译器与 Luau 服务。在自己的开发环境执行以下安装和构建步骤；构建产物位于忽略的 `runtime/`：

```powershell
py -3 -m venv services/text-gateway/.venv
$python = '.\services\text-gateway\.venv\Scripts\python.exe'
& $python -m pip install -r services/text-gateway/requirements.txt
& $python services/luau-runtime/build.py
```

`dependencies.json` 锁定 Luau 提交与 JSON 头文件摘要；第三方许可见 `licenses/`。Windows 构建应生成 `leader-skill-service.exe`。不要复制其他机器的虚拟环境、二进制或缓存作为 Linux 安装结果。

首次离线 fixture 验证前创建空的 `services/skill-runtime/runtime/jobs/`，避免目录扫描警告。这是可重建目录，不需要复制旧 jobs 或生成草稿。

```text
python -c "from pathlib import Path; Path('services/skill-runtime/runtime/jobs').mkdir(parents=True, exist_ok=True)"
```

## 文字交互与技能开发

将公开占位示例 `config-examples/text_model.json` 复制到忽略的 `services/text-gateway/runtime/text_model.json`，自行配置支持 Responses SSE 的模型端点、模型与密钥。占位值不能运行；配置文件不要提交。

```powershell
& $python services/text-gateway/launch_game.py --no-tts
```

按 T 输入文字。`--no-tts` 只跳过启动 TTS 服务；若另有 TTS 服务在运行，它仍可能收到请求。离线测试应使用自己的隔离环境并显式禁用自主判断与 TTS。

动态开发另用 `config-examples/development_backend.json` 创建 `services/skill-runtime/runtime/development_backend.json`，默认 `disabled`。需要开发时自行安装并登录所选执行器、填写实际路径与可用模型。Codex/OpenCode 适配的兼容性与账号权限需单独验证；模型调用和生成过程可能耗时并消耗额度。

## 当前 TTS 与可选输入

`services/gemini-tts/run.py` 当前导入 `provider.py`，使用官方 Gemini API 的 `/v1beta/interactions`；模型常量见源文件。这条入口读取忽略的 `runtime/api-key.txt`，不要求沿旧 Cloud TTS 说明填写试用金配置。密钥须由使用者私下配置。`cloud_provider.py` 是保留的另一条适配，当前 `run.py` 不使用它。

TTS 只接受 `text`、`style`、`voice` 三个公开字段，音频流必须明确完成；限流时遵守上游等待时间，冷却期间不发新请求。离线 fixture 可以检查协议与错误处理，不能证明真实配额、模型权限或音频播放已可用。

语音识别接本机 CapsWriter；麦克风与模型权重另行配置。PCVR 使用 OpenXR，头显与运行时另行验证；不提供独立 Quest APK。

## Linux 开发接续

先检出指定 Git 分支并核验资源包，再恢复可重建依赖。当前 Windows 启动脚本及代码中的 `.exe` 路径、`CREATE_NO_WINDOW` 和进程管理需要适配原生 Linux；不能直接把当前 Windows 启动命令当成已验证的 Linux 方案。

优先使用 Godot 4.6.2 建立可重复基线。已有 4.6.3 时，应分别记录导入、脚本、场景和存档兼容性结果。不要据此宣称云端音频、PCVR 或长期常驻服务已具备运行条件。

源码与资源包拥有外部持久副本；环境可能重置，依赖与引擎必须能按版本重新构建。私人存档需另选私密持久目标并核验恢复。本仓库不提供该备份，也不包含真实玩家数据。
