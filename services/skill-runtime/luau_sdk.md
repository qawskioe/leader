# 人物 Luau 世界操作

代码返回 `function(args, context)`。只使用 `world.request(name,args)` 和固定依赖 `skills.call(alias,args,context)`；依赖引用只能从本人掌握的版本选择。没有文件、网络、系统进程、任意 Godot 节点访问。人物身体由宿主绑定，不能传 actor/person_id 越权。世界拒绝的交互返回 ok=false/code；不能用代码自行宣称达成。Lua 表采用字符串键对象（数组可用于内部运算）。每次连续计算50ms、内存32MiB；世界等待期间挂起。

所有坐标是观察瞬间本人脚底原点、x右y上z前、米。空间目标必须 `{observation_id,position={x,y,z}}`，移动后重新 perceive；不能把旧局部坐标贴到新观察号。参数 reference 可以是已知对象ID、人物ID或空间目标；text/number/integer/boolean/hand 按声明验证。

- perceive {}：刷新本人感知，返回 observation_id、near（held_objects/ground_samples/landmarks）、known（本日已知或本次主动回忆的位置）、held_unit、needs。known 每项 position 或低精度 approx_position；它是记忆层，visible_now 固定为 false，即使同一物品本次已经看见也如此。判断当前可见必须读取 near.landmarks[id]；合并候选时，以 near.landmarks 的当前记录覆盖 known 中的同名旧记录。看不到不代表不存在。
- recall_locations {kind}：从本人记忆主动找最多4条指定类型线索。返回 locations，位置可能过时。
- look_toward {target}：按所选相对方向转身。
- approach {object:空间目标,distance?:0至2}：只走向一段可见地面，不自动找路。受阻返回触点和实际位置。
- observe {object}：返回grip_position（手接触点）、body_position（刚体原点）、bottom_position（真实最低高度与刚体水平位置的底部参考点）、speed_mps，均在返回的observation_id坐标系。落点检查用bottom_position，不用可能偏置的握持点；这些信息只对当前可见或本人持有物开放。只观察已知且当前可见/持有物。返回 grip_position（局部XYZ）、observation_id、held_by_self、hand、nearest_hand。
- reach {object,hand,seconds}：可选手臂IK，手实际到目标才ok。
- grasp {object,hand}：空手与物品真实接触才握持。hand为Hand.L/Hand.R。
- release {object}：仅松开本人持有物，随后服从物理。
- change_grip {object,hand}：另一只空手先真实接触，才能换手。
- handover {object,recipient}：近距离递交已有物体；接收人自己判断是否接受，不自动复制内容物。
- surface {target}：验证指定空间目标附近实际支撑面；不改写目标的水平位置。ground_samples是稀疏观察，不是仅允许行动的点列表；可根据已观察的地面高度和物体范围计算新的候选位置，再用surface确认视线及支撑。高度必须采用地面高度，不是物体握持点高度；未采样区域不能直接假定可通行。
- move_held {object,target,seconds}：持物手移到支撑目标；够不到/受阻返回失败。
- check_placement {object,target}：target必须是已观察的地面/支撑面坐标，不是物体中心或grip_position（握持点通常高于地面）。先用观察中的地面高度与物品水平位置构造目标，可用surface验证或校正。等待落稳后检查实际位置、支撑、速度与已松手。自然落下没有指定落点时，应在落下后重新观察真实落处，不能要求留在松手前的水平位置。
- inspect_body {}：body.bones中所有骨骼rest/current局部数据。
- pose_bones {pose,seconds}：pose键是已有骨名，值 {rotation:{x,y,z},position:{x,y,z}}；旋转是相对rest的XYZ度，位置相对rest米。未指定骨保持当前姿态；pose={}表示在指定时长内保持全部当前姿态，可用于短暂停留，仍受0.2至5秒时长边界约束。
- pose {pose,seconds}：可选辅助，lower_hips(0至.55米)降低骨盆并锁脚；Spine/Chest等骨为XYZ度。不是必须使用。
- relax {seconds}：恢复静止骨架。
- body_point {point:"mouth"或inspect_body列出的任意骨名，如Chest、Hips、Hand.R}：本人当前身体参照点；Chest等骨名返回骨骼原点，胸前目标应从实际Chest点向本人前方偏移，不要从嘴的位置猜胸高。Hand.R/Hand.L返回掌心接触点，返回 target空间目标；mouth采用嘴前约0.11米的饮用点，避免手穿头。consume_unit以手到解剖嘴点<=0.20米为实际接触判据。
- reach_point {hand,target,seconds}：手臂IK伸到已观察的接触点，距离<=.20米才ok。
- contact_point {source}：已知且当前可见/持有的资源或容器接触点，返回position空间目标。
- inspect_contents {object}：可见/持有容器，返回 quantity/capacity/material/opening空间目标。
- take_unit {source}：右手空闲且真实触及容器开口或资源才取一个单位。采果需要持篮子。不等于吃掉。
- put_unit {target}：右手所持单位真实触及同材料容器开口后存入。
- consume_unit {}：手中可食用单位送到嘴边才消耗，世界更新需求。
- consume_contents {object}：本人持有容器开口真实到嘴边才消耗一份。
- fill_container {source,target}：本人持有的同材料容器开口真实触及流动资源，结算填入的实际单位。
- transfer_contents {source,target,quantity}：两个容器真实接近、来源持有、材料匹配才转移实际内容物。
- give_unit {recipient}：交出本人手中的实际单位，接收者自己决定，保留来源。

动作时长0.2至5秒。各步可能失败，保留已发生的实际变化；失败不能回滚世界或伪造成功。双手、容器与身体会随骨骼移动；将左手容器送到胸前再用右手操作，比对身体侧面盲目反复弯腰可靠。

技能成功结束后宿主用1.2秒连续恢复待机，执行证据记为host_restore_idle；这不是人物可调用的新权限。取消会立即释放本次身体控制。

- walk_options {}：与perceive相同的本人观察，额外对当前可见地面采样做本人体积直行预测，path_clear=false表示当前身体过不去；不提供导航路径。perceive/walk_options的odometry仅给本次技能起点为原点的本人位移及局部right/forward方向，可在Luau中记录已经尝试过的局部位置；没有全地图坐标。

对记住但当前不可见的近处资源，可以用旧位置尝试接触；take_unit/fill_container只有手/开口实际接触才成功，不会提前返回不可见资源的实时位置。

## 通用拿取

正常拿取优先调用已掌握的`take_object`技能，参数只有`object`。它复用寻路和`take_in_hand`，在同一次程序执行内完成选空手、转向、接近、有限站位修正、身体配合、真实接触检查和抓握；不是每一步再调用日常模型。`perceive.available_hands`提供本人双手是否空闲；`observe.nearest_free_hand`为空字符串时表示没有空手。

`reach_with_body {object,hand,seconds}`为可复用的身体执行操作：只对当前观察到、未被占用的物品计算掌心接触，程序换算手腕目标并使用引擎IK协调身体。它不移动人物的物理根节点，也不转移物品所有权。成功要求掌心距接触点不超过0.06米；失败返回`body_out_of_reach`及误差。站位调整由调用它的拿取技能完成，最后仍经`grasp`检查持有状态。旧的单纯`reach`、`pose_bones`仍可用于明确需要直接身体控制的技能。

拿取先预检站位与姿态，最多两次身体接触尝试。目标丢失/被占用、没有安全站位、路线受阻或仍不可达时明确失败；不会瞬移、越过碰撞、复制物品或自动丢掉手中物品。取消后等待世界操作协程退出再释放执行器。

`plan_grasp {object,hand,exclude_current?:bool}`只对本人当前可见、未被占用的近处物品规划抓取。返回`stance`空间目标、`look_target`、`needs_move`和预计接触误差；不移动人物、骨骼或物品，不授予抓握成功。根据可见地面验证支撑与身体直行碰撞，用与执行器相同的运动学模型评估姿态。可用`approach`的`distance:0`走到候选站位，随后转向、`reach_with_body`、`grasp`，每步仍检查实际结果。超过局部规划范围返回`grasp_target_far`，没有可行站位返回`no_feasible_grasp_stance`，分帧期间目标改变返回`target_changed`。取消会退出预检。
