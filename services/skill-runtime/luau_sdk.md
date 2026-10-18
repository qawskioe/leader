> 当前普通生活技能组合世界操作，程序处理移动、碰撞、持有关系与物资结算；动作表现近似，验收依据实际世界事实和请求目标。

# 人物 Luau 世界操作

## 隔离验证场景

`skill.json`可增加`verification_cases`数组（最多4项）；它是宿主测试配置，不进入人物技能定义，不授予候选额外世界权限。原始快照的baseline始终执行并独立验收，不能以安全停止替代正常成功。

独立验收规划器可在编写前声明 `participant_behaviors`：已知参与者 `stay`（停留）或 `follow_actor`（沿受检角色已实际走过的轨迹，以正常速度及碰撞跟随）。视线受遮挡时替身会沿旧轨迹接近，恢复视线后保持原跟随距离；真实碰撞仍可使配合失败。原快照不变，参与者只通过实际移动配合；行为声明和移动记录标为测试替身，不证明真实人物愿意配合。编写者不能改变baseline声明，也不能在技能代码中控制这些替身。
本次实际采用的baseline参与者前提、历史版本来源及规划器的调整理由在只读 `reference/verification_preconditions.json`，`verify_skill(mode="inspect")` 返回同一份 `verification_preconditions`。新增验证场景不改变baseline；调整理由只供审查，不能替代本次目标完成证据。

额外场景可使用 `{"kind":"participant_occluded","person":"已知参与者ID"}`：宿主在1至8米内寻找真实地形遮挡且身体能站立的位置；可选distance_m要求指定的水平距离。只需要遮挡时使用范围搜索，有明确距离要求时才指定数值。不能设置可见性布尔值、移除碰撞或创建遮挡物；找不到就报告前提失败。先用stay保持遮挡，下一步用participant_distance及follow_actor恢复，验证看不见时的停止和重新看见后的续办。

每项为`{"name":"场景名","steps":[步骤]}`，最多3步。每步含`conditions`数组（最多4项）以及完整`arguments`；同一场景第二步起可用`"resume_previous":true`替代arguments，宿主只使用上一步返回的resume_arguments。每个场景重新恢复原快照，同一场景的步骤连续执行并保留物资和已发生进展。

步骤可用`"request":"another_order"`切换为新的隔离请求标签（ASCII标识，最多64字符），`"request":"original"`回到原请求。省略时沿用上一步请求。世界状态与旧请求记录保留，但新请求的`context.task_execution.calls`为空；宿主保存每次实际传入及执行后的记录，供审查新请求与旧续办是否混淆。这只是测试请求标签，不冒充玩家在正式场景发言。

隔离条件另可用`{"kind":"reference_distance","person":"人物ID或player","reference":"本人原本已知对象ID","distance_m":1至8,"bearing_degrees":-180至180}`。0度沿原快照中受检人物相对参考点的方向，指定距离/方位必须有真实地面支撑和身体净空，否则前提失败；不偷偷换方位。布置受检本人时同时朝向该已知点，并重基替身的跟随轨迹；只能在调用前布置本人，操作期间只能布置其他已知参与者。布置不提供候选新的世界权限，不证明参考点仍存在、当前可见或已经抵达；这些必须核对后续真实观察。检验单方抵达时须确认目标和参与者当前可见及双方目标距离；仅玩家先到后，正确方法可以真实走近再共同完成，不能要求整个调用永远失败。

条件包括：`{"kind":"consume_to_quantity","object":"本人原本持有的容器ID","quantity":0}`通过真实消耗降低库存；`{"kind":"participant_distance","person":"本人已知的其他参与者ID","distance_m":6}`设置隔离距离（1至8米）；`participant_occluded`设置上述真实遮挡；`{"kind":"restore_participant","person":"相同参与者ID"}`回到原快照位置；`{"kind":"participant_behavior","person":"相同参与者ID","behavior":"stay或follow_actor"}`在额外场景中控制配合前提。需要让参与者掉队时，先设stay再设置距离；续办时可恢复follow_actor。不能补造物资、修改世界规则或设置未知人物。前提设置与候选操作分别留证；额外场景中的失败返回可以证明安全停止，是否满足要求仍由独立审查判定。

步骤还可加入`after_operations`（最多3项），在指定世界操作的第N次成功结果之后应用同样的隔离条件。例如`{"operation":"consume_contents","occurrence":1,"conditions":[{"kind":"participant_distance","person":"player","distance_m":6}]}`模拟饮用之后玩家走远；下一步恢复玩家位置并使用`resume_previous`。操作须来自当前目录，N为1至4，同一步不能重复触发点。宿主保存变化发生前的真实结果、之后的位置条件、每步请求来源及续办来自哪一步；不得把调用前的远距离冒充执行中走远。

步骤可加入`"cancel_after_operation":{"operation":"take_unit","occurrence":2}`，在本次调用指定世界操作的第N次成功结算后取消真实运行器，验证实际中断与续办；操作须来自当前目录，N为1至4，若该成功调用没有发生，报告测试前提失败。取消保留已经发生的物资变化、手中物品及本请求进展，不补造候选返回值。下一步使用完整`arguments`并沿用当前请求，重新观察后只完成剩余步骤；被取消步骤没有返回`resume_arguments`，不能用`resume_previous`读取它。宿主证据同时保留取消触发操作、真实`cancelled`状态、前后世界事实与后续调用，候选没有取消其他人物或修改执行器的权限。

额外场景可用`{"kind":"participant_handover_answer","person":"本人已知的其他NPC ID","answer":"decline"}`设置拒绝递交，用`answer:"accept"`恢复接受。回复经真实handover.respond结算，并保留同一物品与内容物，不改归属或库存规则；同一场景后续步骤保持该回复，重置场景时恢复baseline接受替身。可验证拒绝后保留物资、接受后续办及已交付后的再次调用。候选获得的仍是正常递交结果，测试回复策略只在宿主证据中记录。玩家接收遵循下方handover接口的现有规则，此条件不适用于玩家。

例如某方法返回归还受阻及resume_arguments后，可设置参与者远离、执行初次参数，随后恢复参与者并以resume_previous续办。不要为了证明失败分支去改正常方法；通过增加这些隔离证据验证同一份源码。

公共生活技能职责：`find_resource`只回忆候选线索，`go_to_known`只按线索走近，均不证明物品当前存在。需要实际找到可用资源时复用本人掌握的`locate_resource`（有限检查候选并要求当前观察）；它不承诺拿取成功。`store_food`负责实际入库并保留持有的容器，放下容器由独立动作决定，不将额外收尾失败覆盖为存储失败。组合技能优先复用这些已掌握能力，不复制其寻路实现。

代码返回 `function(args, context)`。只使用 `world.request(name,args)` 和固定依赖 `skills.call(alias,args,context)`；依赖引用只能从本人掌握的版本选择。没有文件、网络、系统进程、任意 Godot 节点访问。人物身体由宿主绑定，不能传 actor/person_id 越权。世界拒绝的交互返回 ok=false/code；不能用代码自行宣称达成。Lua 表采用字符串键对象（数组可用于内部运算）。每次连续计算50ms、内存32MiB；世界等待期间挂起。

返回值及单次world.request参数最多4096个数据值（包含表本身）、嵌套深度20层，单字符串最多65536字节；数值须为有限数，表使用字符串键，返回值是JSON可表示的数据。方法返回本次结果摘要、必要续办参数及关键终点依据；完整世界调用轨迹和实际变化由宿主自动保存，并交给后续续办与独立审查。返回格式或容量不符时，本次候选不批准，具体错误与已发生的操作证据交回编写者修订。

`context.task_execution={request_id,calls}`是宿主保存并按当前请求隔离的只读进展。request_id标识整条请求；每个call的source_event_id标识其中一次动作提交，skill_ref标识方法版本，status标识代码状态，phases记录实际操作回执，facts记录实际物资变化。一次请求可包含多个不同source_event_id，calls已由宿主按request_id分区。taken含source，表示从来源实际取出；stored含target，表示实际存入容器；given含recipient_id、material、quantity，表示向该接收人实际交付；consumed含material、quantity，容器消费还含source，表示实际消耗。依据原目标、接收人和同次调用的操作回执区分已完成的取出、装填、交付及消费；例如向目标玩家given两份水是交付进展，而不是消费进展。同一请求续办先核对这些事实，再观察当前持有，只执行剩余步骤。新请求没有旧请求calls，独立行动也不读取另一个任务的进展。记录在程序结束、失败或取消时自动保存，并随任务进入现有存档；技能不需要写自报进度。修改本次Lua上下文不会改宿主记录。方法参数或自身返回的成功标记不能替代这些回执；进展说明过去做过什么，不保证物品现在仍可操作。

`calls[].phases[]`是扁平动作摘要，直接读取`phase.operation`、`phase.ok`、`phase.code`，例如`{operation="approach",ok=false,code="movement_failed",elapsed_ms=5000}`。字段按实际回执提供，包含物品、数量、交接及动作时间等已发生的结果；`facts`保留实际物资结算。感知和选路数据由本次`perceive`、`walk_options`获得，历史phases只保留动作摘要；跨调用不能据此恢复完整观察帧或空间轨迹。

`call.arguments`保留该次调用的已验证参数；`call.movements`按顺序保留真实approach摘要：ok/code、requested_target、standing_position、匹配请求观察号的observation_odometry，以及本次reference参数关联的references。references只复制当时本人已见或已知位置，保留position/approx_position、visible_now、来源、时间和误差，不查询目标现状。`evidence_complete`表示原观察坐标帧与实际站位匹配；`observation_source`为execution_query时有本次执行中的观察内容，retained_argument_frame表示日常模型直接选点所用的合法旧帧，仅有本人运动坐标，references为空。`observation_immediately_preceded`只在移动前一操作就是该观察时为true，保留参数帧不会伪装成紧邻观察。站位绑定原观察，不是当前局部坐标；odometry原点每次调用独立。`movements_complete=false`表示历史缺项或调用未正常结束，尤其取消中的最后一步可能已经部分移动却没有返回回执。缺项不表示未移动。旧记录可辅助有限避错、核对累计实际进展，不能证明当前阻挡、抵达或复用旧空间目标。同请求内切换目标时先按arguments和参考身份区分；单目标的相对距离/夹角不能精确对齐不同调用，粗略/过期线索不得当作精确位置。

perceive/walk_options另含`request_odometry={request_id,position,right,forward}`：本人在该请求首次执行时的脚底坐标系内的自身位置和朝向。同一请求续办与保存恢复保持原点；新请求与独立行动有各自原点。movement.request_odometry保留请求点所属观察时的同一测量，只有request_id一致才可对齐；将局部点换算为请求坐标时用position+right×局部x+forward×局部z+(0,局部y,0)。它可关联已尝试路线、实际进退，不提供全地图、他人隐藏位置或目标现状，也不能直接作为approach空间目标。实际行动仍须使用当前观察号和当前可见地面；完成仍须当前目标及参与者的实际证据。

所有坐标是观察瞬间本人脚底原点、x右y上z前、米。空间目标必须 `{observation_id,position={x,y,z}}`，移动后重新 perceive；不能把旧局部坐标贴到新观察号。参数 reference 可以是已知对象ID、人物ID或空间目标；text/number/integer/boolean/hand 按声明验证。

主动回忆选中的地标会进入本人的执行知识及当天位置记忆，保留原来的位置与证据时间。回忆仍是旧线索，visible_now=false；新的实际目击和位置核查优先。未选择的长期地标不会全部进入执行上下文。

- perceive {}：刷新本人感知，返回 observation_id、near（held_objects/ground_samples/landmarks）、known（本日已知或本次主动回忆的位置）、held_unit、needs。视野随身体朝向改变，当前范围与夹角见本人interaction_rules.vision；目标可能因转身、距离或实际遮挡离开视野。known 每项 position 或低精度 approx_position；它是记忆层，visible_now 固定为 false，即使同一物品本次已经看见也如此。判断当前可见必须读取 near.landmarks[id]；合并候选时，以 near.landmarks 的当前记录覆盖 known 中的同名旧记录。看不到不代表不存在。
- recall_locations {kind}：从本人记忆主动找最多4条指定类型线索。返回 locations，位置可能过时。
- look_toward {target}：按绑定观察时刻的相对坐标转身；允许使用远处记忆的approx_position，坐标必须为有限数。近距离移动的10米坐标限制不适用于转身。转身不代表看见目标，也不授予直达目标或操作目标的能力。
- approach {object:空间目标,distance?:0至2,keep_heading?:布尔}：只走向一段可见地面，不自动找路。默认随移动方向转身；keep_heading=true时保持当前身体朝向，沿选定方向侧走或后退，速度、碰撞与支撑规则相同。开始移动仍要求目标地面当前可见；朝向选项不扩大视野。distance是本人脚底到所选点的水平停止半径（米），可以从任意方向进入；到点最小容差0.04米。受阻返回触点和实际位置；到达该范围不等于物品已经可以取用，须核对后续操作的实际距离和条件。
- observe {object}：返回grip_position（手接触点）、body_position（刚体原点）、bottom_position（真实最低高度与刚体水平位置的底部参考点）、speed_mps，均在返回的observation_id坐标系。落点检查用bottom_position，不用可能偏置的握持点；这些信息只对当前可见或本人持有物开放。只观察已知且当前可见/持有物。返回 grip_position（局部XYZ）、observation_id、held_by_self、hand、nearest_hand。
- grasp {object,hand}：物品当前可见、未被占用、指定手空闲且人物躯干中心（脚底上方0.9米）到握持参考点不超过1.6米时直接建立固定持有连接；另检查视线遮挡。hand为Hand.L/Hand.R。
- release {object}：仅松开本人持有物，随后服从物理。若物体当前穿入人物或环境，返回release_overlapping和contacts类别，保留持有关系；先通过身体/持物操作移出重叠再释放，不能把失败当作已放下。成功返回release_location：松手瞬间抓握点的本人坐标及相对于近处已知参考点的距离/偏移；坐标绑定observation_id，known_references注明参考点当时是否可见及最后观察来源/时间。不读取未知物体或远处物体的实时位置。这是松手证据，不是落稳或整个任务完成证明；需要时用observe/check_placement核实，不能为了核实先重新拿起。
- change_grip {object,hand}：本人持有且目标手空闲时直接换手，不需要先伸手。
- handover {object,recipient}：近距离递交已有物体。NPC通过接受/拒绝回复决定；玩家在合法近距且右手接物槽空闲时直接接收，否则返回对应条件失败。成功只转移同一物品和原内容物，返回transferred及recipient_id，并记录物资given事实。
- surface {target}：验证指定空间目标附近实际支撑面；不改写目标的水平位置。ground_samples是稀疏观察，不是仅允许行动的点列表；可根据已观察的地面高度和物体范围计算新的候选位置，再用surface确认视线及支撑。高度必须采用地面高度，不是物体握持点高度；未采样区域不能直接假定可通行。
- move_held {object,target,seconds}：等待指定操作时间后重新验证支撑面、视线和1.6米操作距离，再检查物品在终点无重叠。落点仅被本人身体占据时，程序按双方碰撞外框沿正常碰撞运动调整站位，并重新检查落点；环境或他人阻挡仍返回失败。成功将物品移到选定位置并保持持有，随后release恢复物理。失败或取消保留持有关系及已发生的真实位移；下一步可重新观察现场。
- check_placement {object,target}：target必须是已观察的地面/支撑面坐标，不是物体中心或grip_position（握持点通常高于地面）。先用观察中的地面高度与物品水平位置构造目标，可用surface验证或校正。等待落稳后检查实际位置、支撑、速度与已松手。自然落下没有指定落点时，应在落下后重新观察真实落处，不能要求留在松手前的水平位置。
- access_source {source}：检查来源当前可见/本人持有、归属及1.6米操作距离，只返回是否可操作，不伪造接触。
- inspect_contents {object}：查看本人持有或无人持有、可见且可达的容器，返回 quantity/capacity/material/opening空间目标。交给他人后由对方持有，此接口返回held_by_other；当前可见外部信息从perceive的near.landmarks中读取，转移事实以handover回执确认。
- take_unit {source}：选择实际空闲手，来源当前可见且在1.6米内，经过0.3秒后重新验证并取一份；采果仍需要篮子。不等于吃掉。
- put_unit {target}：经过0.3秒，向当前可操作的同材料容器存入手中物资，检查容量与归属。
- consume_unit {}：经过1秒后消耗手中一份可食用物资，降低对应需求；不要求手嘴接触，取消不消耗。
- consume_contents {object}：经过1秒后消耗本人持有容器的一份内容，检查材料与实际数量，不要求容器口接触嘴。
- fill_container {source,target}：经过1秒后，从当前可见且1.6米内的流动来源装填本人持有的同材料容器。按实际空余容量与来源供给结算。
- transfer_contents {source,target,quantity}：两个容器均近距可操作、来源本人持有、材料匹配时转移内容；不要求开口对齐，保留容量和归属限制。
- give_unit {recipient}：交出本人手中的实际单位，保留来源。NPC通过接受/拒绝回复决定；玩家满足近距和空闲接物手时直接接收。成功返回transferred_unit及recipient_id，并记录given事实。

操作等待期间暂停不推进时间，取消后不结算；结算时重新检查当前世界事实。已发生的变化不因后续失败回滚。

- walk_options {}：与perceive相同的本人观察，额外对当前可见地面采样做本人体积直行及碰撞滑动预判。path_clear=false表示预判未确认直达，不是approach调用的权限门槛，也不能证明目的地不可到达；真正的移动仍受实际碰撞和支撑检查。样本只覆盖当前视野；没有可走样本不能推出四周无路，角色可自主选择转身重新观察其他方向，再根据新观察决定下一步。接口不自动环视或提供导航路径。perceive/walk_options的odometry仅给本次技能起点为原点的本人位移及局部right/forward方向，可在Luau中记录已经尝试过的局部位置；没有全地图坐标。

记忆仅用于寻找，不能代替当前可见性与近距检查。普通拿取调用已掌握的take_object技能，程序选空手并按需走近；容器和物资操作依据近距、归属、材料和容量结算。

近处ground_samples是可见表面采样，不保证每项都是地面：state=visible_surface才是静态地面候选（仍需支撑与路线检查）；state=visible_object_surface且surface_kind=movable_object/person表示首个可见命中是物品或人物表面，不能拿它的高度当脚下地面。unknown不代表空地；不会透过物品提供其下隐藏地面。

## 自然松手后的落稳确认

`check_settled {object}`只检查本人当前可见的物体，目标不含坐标，也不要求先调用surface。最多观察2秒，要求物体已解除持有且未冻结、局部支撑得到确认、低线速度/角速度与位置稳定持续至少0.3秒；成功返回settled，超时返回not_settled及支撑/速度/观测时长。仍被持有返回still_held，未知或遮挡物体不会提供当前物理状态，取消立即退出。

支撑采用实际碰撞形状最低点附近的保守采样，不公开隐藏地面的坐标。未确认支撑不能推断整个物体没有支撑。settled只证明物体在当前位置落稳，不代表到达玩家指定地点；有明确落点的放置仍使用check_placement。自然松手后不要为调用落稳检查而猜测篮下看不见的地面坐标。松手成功本身也不等于已经落稳。

固定携带连接下，通行预判和实际移动使用人物本体的碰撞体，持物外形不计入身体寻路。

通用操作距离以脚底上方0.9米的简化躯干点为球心、1.6米为半径；不是骨骼接触点。地面物与正常高度果实使用同一规则。
