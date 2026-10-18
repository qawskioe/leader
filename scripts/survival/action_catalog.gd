extends RefCounted
## 这里只保留调用控制；生活行为全部由个人Luau技能调用。
const IDS=["none","rest"]
const DESCRIPTIONS={"none":"不发起新动作；允许说话、等待当前动作。","rest":"取消当前动作并停下；已选择下一方法时可同时提交skill_call，旧执行退出后再调用。"}
