# Leader：AI 人物与动态技能实验

基于 Godot 4.6 的三维实验原型：模型扮演人物、选择目标与技能；Godot 检查世界事实、空间移动和身体操作；Luau 技能执行具体方法。缺少方法时，可请求独立开发后端编写、验证并登记技能。

当前源码已切换到简化身体交互：普通三维场景、近身拿取、左右手持物与放置，不再使用旧精细 IK 实验台。它仍是开发者预览，Leader 1.0 的真实交互与持续运行验收尚未完成。

## 获取与运行

按[安装与演示](GETTING_STARTED.md)获取 Godot 4.6.2 和现有资源包，再打开 `project.godot`。资源包沿用 `v0.1.0-preview`；`asset-pack-manifest.json` 保留逐文件 SHA-256，资源不进入源码 Git。

仅查看室外场景：

```powershell
& $env:LEADER_GODOT --path . -- --outdoor-preview
```

完整人物交互需自行配置文字网关与 Luau 执行器。动态技能开发默认关闭；Codex/OpenCode 执行器、账号和额度均由使用者配置。TTS 当前入口使用 Gemini Interactions，接收公开台词与语气；首次开发建议关闭 TTS。

## 当前范围

- 人物相对空间、个人感知、经历与主动回忆。
- Luau 固定版本技能组合、取消、学习与修订；实际世界结果必须由 Godot 验证。
- 简化拿取与持物、容器、食物来源选择、储藏物资操作。
- 会话存取、玩家与人物持物恢复、未完成任务恢复为待判断状态。
- 退出存档期间阻止自主判断与新动作，保存失败时取消退出状态。

[开发接续与待验收清单](docs/DEVELOPMENT_HANDOFF.md) · [技能接口](services/skill-runtime/luau_sdk.md) · [架构](ARCHITECTURE.md) · [素材与依赖](THIRD_PARTY_NOTICES.md)

## 验证边界

主要游戏验证环境是 Windows、Godot 4.6.2。Linux 开发环境仍需适配启动与执行器路径；Godot 4.6.3 兼容性、云端音频、PCVR 和长期进程存活均未完成验证。离线测试不能代替真实 NPC 协作、玩家视觉、麦克风或长期游戏验收。

源码不包含私人会话、人物运行记忆、生成技能草稿、模型配置、账户或服务日志。恢复已有玩家世界需要单独、私密、可核验的数据备份，不能把真实存档提交到本公开仓库。

项目自有代码采用 [MIT](LICENSE)，署名 `Leader contributors`。第三方素材与依赖保留各自许可，见[第三方说明](THIRD_PARTY_NOTICES.md)。提交问题时只附脱敏复现与错误。
