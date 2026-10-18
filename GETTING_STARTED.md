# 安装与演示（Windows源码预览）

本次审阅分支只更新源码和资源清单，未发布配套新版资源包。先做源码审阅；运行时需要与本分支清单匹配的资源，不能把旧预览资源包视作已验证匹配。

## 资源与引擎

1. 安装Godot 4.6.2，设置当前PowerShell会话的引擎路径：`$env:LEADER_GODOT = 'C:\Tools\Godot\Godot.exe'`。替换为自己的路径。
2. 下载与当前源码版本配套的 `leader-assets.zip`，解压到仓库根目录，保留`assets/`层级。大资源单独分发，Git源码中保留资源清单及SHA256。运行 `python tools/check_asset_pack.py` 检查。
3. 首次运行 `& $env:LEADER_GODOT --headless --editor --path . --import --quit` 导入资源。
4. 用README的`--outdoor-preview`或`rig_lab.tscn`入口离线查看。场景预览支持WASD与鼠标；Esc释放鼠标。不要把预览误认为人物AI已经启动。

## 本地执行与文字交互

需要Python 3.11或更高版本、Git、CMake、Ninja和可用的C++17编译器。Windows使用已配置编译环境的Developer PowerShell；构建产物必须是Windows `.exe`。

```powershell
py -3 -m venv services/text-gateway/.venv
$python = '.\services\text-gateway\.venv\Scripts\python.exe'
& $python -m pip install -r services/text-gateway/requirements.txt
& $python services/luau-runtime/build.py
```

构建脚本下载锁定版本的Luau和JSON依赖；不会使用仓库作者的运行目录。独立物理测试（不调用模型）：

```powershell
& $env:LEADER_GODOT --headless --path . --script res://tools/test_automatic_pickup.gd
```

将`config-examples/text_model.json`复制到`services/text-gateway/runtime/text_model.json`，自行填写端点、模型与密钥。示例使用Responses SSE协议，需要供应商支持完整`response.completed`事件与结构化人物输出，不保证任意兼容服务均可用。不能直接使用示例占位值。该目录被Git忽略。

```powershell
& $python services/text-gateway/launch_game.py --no-tts
```

按T输入，例如“石头，把附近一个空水袋拿起来，拿在手里就好”。当前版本 `--no-tts`关闭合成请求，公开文字及人物听闻仍继续；`--player-control`默认关闭TTS，限定试听时才显式使用 `--tts`。此入口不需要ASR；不要先运行个人环境取密钥脚本。

日常模型与动态技能开发独立。未配置开发后端时，已有技能继续执行，学习请求会明确失败。

## 动态技能开发（可选）

先自行安装并登录所选Codex/OpenCode执行器，配置Git作者身份供独立技能工程记录版本。将`config-examples/development_backend.json`复制到`services/skill-runtime/runtime/development_backend.json`。默认`disabled`；可改为`{"backend":"codex","runtime":"local","executable":"C:/Tools/Codex/codex.exe","model":"你的可用模型"}`，或使用`opencode`。路径必须真实存在。

执行器版本和账号模型权限会影响兼容性；不是安装任何同名CLI都保证可运行。当前Codex适配使用`exec`、JSON事件和命名权限配置，需要对应CLI支持。此源码预览没有打包CLI，也不要求所有用户使用同一家提供商。

阅读[隔离限制](ARCHITECTURE.md)后再启用。完整生成过程可能耗时数分钟并消耗账号额度；失败不会自动成为已掌握技能。

## 语音与VR（可选）

语音识别接本机CapsWriter服务（6016端口），另行安装与启动；按住V说话。未随源码提供其模型权重。使用自己的USB麦克风并核对游戏配置。

Cloud TTS需安装`services/gemini-tts/requirements.txt`，自行登录Google Cloud CLI，按`cloud_config.example.json`在忽略的runtime目录配置。当前实现保留试用金确认与带时区到期停用要求；只有实际核实试用额度后才能填写确认值。它不是免费服务，也不能用停用时间保证账单一定被赠金抵扣。首次预览建议使用文字，不配置TTS。

VR需要Windows OpenXR运行时与PC连接头显；此发布不提供独立Quest安装包。先完成桌面演示再启用`--vr`。
