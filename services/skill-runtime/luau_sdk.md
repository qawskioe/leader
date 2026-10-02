> 2026-09-27简化基线：普通生活技能使用稳定的世界能力组合，禁止为了普通拿取增加精细骨骼步骤。拿取、放置和生活结算已简化；默认验收仅检查世界事实与行为语义，不需要截图或骨骼。不存在需要默认维护的精细模式。

# 人物 Luau 世界操作

公共生活技能职责：`find_resource`只回忆候选线索，`go_to_known`只按线索走近，均不证明物品当前存在。需要实际找到可用资源时复用本人掌握的`locate_resource`（有限检查候选并要求当前观察）；它不承诺拿取成功。`store_food`负责实际入库并保留持有的容器，放下容器由独立动作决定，不将额外收尾失败覆盖为存储失败。组合技能优先复用这些已掌握能力，不复制其寻路实现。

代码返回 `function(args, context)`。只使用 `world.request(name,args)` 和固定依赖 `skills.call(alias,args,context)`；依赖引用只能从本人掌握的版本选择。没有文件、网络、系统进程、任意 Godot 节点访问。人物身体由宿主绑定，不能传 actor/person_id 越权。世界拒绝的交互返回 ok=false/code；不能用代码自行宣称达成。Lua 表采用字符串键对象（数组可用于内部运算）。每次连续计算50ms、内存32MiB；世界等待期间挂起。

所有坐标是观察瞬间本人脚底原点、x右y上z前、米。空间目标必须 `{observation_id,position={x,y,z}}`，移动后重新 perceive；不能把旧局部坐标贴到新观察号。参数 reference 可以是已知对象ID、人物ID或空间目标；text/number/integer/boolean/hand 按声明验证。

- perceive {}：刷新本人感知，返回 observation_id、near（held_objects/ground_samples/landmarks）、known（本日已知或本次主动回忆的位置）、held_unit、needs。known 每项 position 或低精度 approx_position；它是记忆层，visible_now 固定为 false，即使同一物品本次已经看见也如此。判断当前可见必须读取 near.landmarks[id]；合并候选时，以 near.landmarks 的当前记录覆盖 known 中的同名旧记录。看不到不代表不存在。
- recall_locations {kind}：从本人记忆主动找最多4条指定类型线索。返回 locations，位置可能过时。
- look_toward {target}：按绑定观察时刻的相对坐标转身；允许使用远处记忆的approx_position，坐标必须为有限数。近距离移动的10米坐标限制不适用于转身。转身不代表看见目标，也不授予直达目标或操作目标的能力。
- approach {object:空间目标,distance?:0至2}：只走向一段可见地面，不自动找路。受阻返回触点和实际位置。
- observe {object}：返回grip_position（手接触点）、body_position（刚体原点）、bottom_position（真实最低高度与刚体水平位置的底部参考点）、speed_mps，均在返回的observation_id坐标系。落点检查用bottom_position，不用可能偏置的握持点；这些信息只对当前可见或本人持有物开放。只观察已知且当前可见/持有物。返回 grip_position（局部XYZ）、observation_id、held_by_self、hand、nearest_hand。
- grasp {object,hand}：物品当前可见、未被占用、指定手空闲且人物躯干中心（脚底上方0.9米）到握持参考点不超过1.6米时直接建立固定持有连接；另检查视线遮挡。hand为Hand.L/Hand.R。不需要先reach或plan_grasp，不以手掌距离判定。
- release {object}：仅松开本人持有物，随后服从物理。若物体当前穿入人物或环境，返回release_overlapping和contacts类别，保留持有关系；先通过身体/持物操作移出重叠再释放，不能把失败当作已放下。成功返回release_location：松手瞬间抓握点的本人坐标及相对于近处已知参考点的距离/偏移；坐标绑定observation_id，known_references注明参考点当时是否可见及最后观察来源/时间。不读取未知物体或远处物体的实时位置。这是松手证据，不是落稳或整个任务完成证明；需要时用observe/check_placement核实，不能为了核实先重新拿起。
- change_grip {object,hand}：本人持有且目标手空闲时直接换手，不需要先伸手。
- handover {object,recipient}：近距离递交已有物体；接收人自己判断是否接受，不自动复制内容物。
- surface {target}：验证指定空间目标附近实际支撑面；不改写目标的水平位置。ground_samples是稀疏观察，不是仅允许行动的点列表；可根据已观察的地面高度和物体范围计算新的候选位置，再用surface确认视线及支撑。高度必须采用地面高度，不是物体握持点高度；未采样区域不能直接假定可通行。
- move_held {object,target,seconds}：等待指定操作时间后重新验证支撑面、视线和1.6米操作距离，再检查物品在终点无重叠，直接移动到该处但仍保持持有；随后release恢复物理。失败不改变原持有位置，取消不移动。没有手臂IK和持物扫掠路径。
- check_placement {object,target}：target必须是已观察的地面/支撑面坐标，不是物体中心或grip_position（握持点通常高于地面）。先用观察中的地面高度与物品水平位置构造目标，可用surface验证或校正。等待落稳后检查实际位置、支撑、速度与已松手。自然落下没有指定落点时，应在落下后重新观察真实落处，不能要求留在松手前的水平位置。
- access_source {source}：检查来源当前可见/本人持有、归属及1.6米操作距离，只返回是否可操作，不伪造接触。
- inspect_contents {object}：可见/持有容器，返回 quantity/capacity/material/opening空间目标。
- take_unit {source}：NPC选择空闲手（玩家入口仍为右手），来源当前可见且在1.6米内，经过0.3秒后重新验证并取一份；采果仍需要篮子。不等于吃掉。
- put_unit {target}：经过0.3秒，向当前可操作的同材料容器存入手中物资，检查容量与归属。
- consume_unit {}：经过1秒后消耗手中一份可食用物资，降低对应需求；不要求手嘴接触，取消不消耗。
- consume_contents {object}：经过1秒后消耗本人持有容器的一份内容，检查材料与实际数量，不要求容器口接触嘴。
- fill_container {source,target}：经过1秒后，从当前可见且1.6米内的流动来源装填本人持有的同材料容器。按实际空余容量与来源供给结算。
- transfer_contents {source,target,quantity}：两个容器均近距可操作、来源本人持有、材料匹配时转移内容；不要求开口对齐，保留容量和归属限制。
- give_unit {recipient}：交出本人手中的实际单位，接收者自己决定，保留来源。

操作等待期间暂停不推进时间，取消后不结算；结算时重新检查当前世界事实。已发生的变化不因后续失败回滚。普通生活不调用骨骼操作。

- walk_options {}：与perceive相同的本人观察，额外对当前可见地面采样做本人体积直行预测，path_clear=false仅表示当前位置直达这个采样点的线段受阻，不表示这个目的地不能绕行到达。样本只覆盖当前视野；没有可走样本不能推出四周无路，角色可自主选择转身重新观察其他方向，再根据新观察决定下一步。接口不自动环视或提供导航路径。perceive/walk_options的odometry仅给本次技能起点为原点的本人位移及局部right/forward方向，可在Luau中记录已经尝试过的局部位置；没有全地图坐标。

记忆仅用于寻找，不能代替当前可见性与近距检查。普通拿取调用take_object，程序选空手并按需走近；普通容器和物资操作不用reach_point、pose或开口对齐。

近处ground_samples是可见表面采样，不保证每项都是地面：state=visible_surface才是静态地面候选（仍需支撑与路线检查）；state=visible_object_surface且surface_kind=movable_object/person表示首个可见命中是物品或人物表面，不能拿它的高度当脚下地面。unknown不代表空地；不会透过物品提供其下隐藏地面。

## 自然松手后的落稳确认

`check_settled {object}`只检查本人当前可见的物体，目标不含坐标，也不要求先调用surface。最多观察2秒，要求物体已解除持有且未冻结、局部支撑得到确认、低线速度/角速度与位置稳定持续至少0.3秒；成功返回settled，超时返回not_settled及支撑/速度/观测时长。仍被持有返回still_held，未知或遮挡物体不会提供当前物理状态，取消立即退出。

支撑采用实际碰撞形状最低点附近的保守采样，不公开隐藏地面的坐标。未确认支撑不能推断整个物体没有支撑。settled只证明物体在当前位置落稳，不代表到达玩家指定地点；有明确落点的放置仍使用check_placement。自然松手后不要为调用落稳检查而猜测篮下看不见的地面坐标。松手成功本身也不等于已经落稳。

固定携带连接不执行持物外形的逐帧绕障；人物本体通行仍由世界检查。模型不可调用精细骨骼接口。

通用操作距离以脚底上方0.9米的简化躯干点为球心、1.6米为半径；不是骨骼接触点。地面物与正常高度果实使用同一规则。
