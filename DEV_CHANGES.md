# RiftRail 开发变更记录 / Development Changelog

> [CN] 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。语言不限（中英文皆可），可使用翻译工具阅读。
>
> [EN] Note: This file is used to record every change during the unreleased development phase.
> Rules: Append new changes to the very top (reverse chronological order), including the date, modified files, and details of the changes. You can write in any language (English, Chinese, etc.); others will use translation tools to read it.

### 2026-03-28（v0.13.7：TickDispatcher 调度器拆分与 on_tick 动态开关）

**改动摘要**：将原本内嵌在 `control.lua` 的传送 Tick 动态注册逻辑拆分为独立调度模块 `tick_dispatcher.lua`，并保留“有任务才轮询、空闲即注销”的运行策略。此次改动不改变传送业务行为，重点是提升结构清晰度与后续扩展性（为 GUI 或其他子系统新增调度器预留统一入口）。

- **调度职责外置**：新增 `TickDispatcher` 模块，统一管理 `on_tick` 的启停、状态同步与碰撞触发后的即时注册判断，避免 `control.lua` 继续膨胀。
- **按活跃状态动态轮询**：`Teleport.on_tick` 返回“是否仍有活跃任务”，`TickDispatcher` 在本帧处理后若发现任务清空则立即注销 `on_tick`，实现空闲零轮询回调。
- **接口语义补全**：在 `teleport.lua` 新增 `Teleport.has_active_work()`，并为相关函数补充了 `---@param / @return` 注解与中文说明，明确调度器与业务层之间的契约。
- **命名收敛**：调度模块命名从通用的 `scheduler` 收敛为 `tick_dispatcher`，与当前职责更匹配，也便于未来扩展多类 tick 分发策略。

### 具体改动
- `RiftRail/scripts/tick_dispatcher.lua`：新增运行时 Tick 分发器模块，提供 `init`、`enable_teleport_tick`、`disable_teleport_tick`、`sync_teleport_tick_registration`、`handle_collider_died`。
- `RiftRail/control.lua`：接入 `TickDispatcher`，删除原内联动态 tick 注册器；在 `on_entity_died`（collider 分支）和 `on_init`/`on_load`/`on_configuration_changed` 中改为调用分发器接口。
- `RiftRail/scripts/teleport.lua`：新增 `Teleport.has_active_work()`；`Teleport.on_tick(event)` 改为返回 `boolean`（本帧后是否仍有活跃任务），用于驱动自动注销逻辑。

### 2026-03-28（v0.13.7：GUI 可维护性重构与分发表改造）

**改动摘要**：本次版本不改业务行为，专注于 GUI 代码结构降噪。通过“公共查找函数 + 统计渲染配置化 + 点击事件分发表”三步重构，显著减少了 `gui.lua` 内部重复逻辑与长链式 `else if`，后续扩展按钮与统计项时只需局部增量维护。

- **递归查找函数统一**：将 GUI 内多处重复的局部递归函数（`find_dropdown` / `find_textfield` / `find_name_flow` 及 `update_camera_preview` 内部重复实现）收拢为统一的 `find_element_recursively(element, name, expected_type)`，并补充可选 `type` 过滤能力；新增 `set_control_enabled` 统一处理按钮组启用/禁用。
- **运行档案渲染配置化**：将入口/出口统计展示逻辑由双分支改为配置驱动。新增 `MODE_STATS_CONFIG` 常量（模块级）描述字段映射，渲染阶段统一走一套流程，同时抽出 `format_last_tick` 与 `add_positive_stat`，清理重复拼接与 `>0` 判断。
- **点击事件分发表重构**：将 `GUI.handle_click` 的长链分支改为 `CLICK_HANDLERS` 表驱动路由。新增 `build_click_context` 与 `get_context_portaldata` 统一前置校验与数据提取，主入口只保留“构建上下文 -> 查表 -> 调用”，新增按钮时无需改主干控制流。

### 具体改动
- `RiftRail/scripts/gui.lua`：
  - 统一元素查找：新增带 `expected_type` 的 `find_element_recursively`，删除多处局部同类函数。
  - 新增 `set_control_enabled(frame, names, enabled)`，替代选择状态变化时的重复禁用代码。
  - 统计面板重构：新增模块级常量 `MODE_STATS_CONFIG`；渲染时通过字段 key 映射读取 `stats`，移除 entry/exit 双分支重复实现。
  - 点击处理重构：新增 `build_click_context`、`get_context_portaldata`、`CLICK_HANDLERS`；`GUI.handle_click` 改为分发表调用模式。

### 2026-03-28（v0.13.6：拆除时横向建筑内列车未被清理的 Bug 修复）

**改动摘要**：修复了朝东（dir=4）或朝西（dir=12）放置的传送门在被拆除时，内部轨道上的列车无法被正确清理的问题。

**根因**：`builder.lua` 中的 `clear_trains_inside` 函数使用了硬编码的固定矩形搜索区域（以建筑中心为原点，X ±2.5，Y ±6.5），该矩形隐含了建筑永远竖向放置（dir=0/8）的错误假设。当建筑朝东或朝西时，内部铁轨沿 X 轴延伸，而搜索区域仍然是纵向的，导致横向轨道上的所有车厢完全处于搜索范围之外，拆除后遗留幽灵车厢。

**修复**：根据 `shell.direction` 动态选择搜索区域的朝向：横向建筑（dir=4/12）使用 X ±8 / Y ±2.5，竖向建筑（dir=0/8）使用 X ±2.5 / Y ±8，覆盖从死胡同端到入口外侧的完整铁轨长度，同时保持宽度方向足够窄（2.5 格）以避免误删相邻平行轨道上的列车。

### 具体改动
- `RiftRail/scripts/builder.lua`：重写 `clear_trains_inside`，以建筑方向为依据动态生成搜索矩形，替代原先的硬编码固定区域。

### 2026-03-28（v0.13.6：teleport.lua 冗余判空清理）

**改动摘要**：对 `teleport.lua` 中三处经调用链分析确认永远不会生效的判空逻辑进行了清理，降低代码噪音。

- **`process_transfer_step` 出口前置重复检查（已删除）**：函数入口处 L607 已直接访问 `exit_portaldata.shell.direction`，如果该表或字段为 nil 早在此前就会崩溃。L610 的 `if not (exit_portaldata and exit_portaldata.shell and exit_portaldata.shell.valid)` 判断在任何执行路径下都不可能触发，因为 `process_teleport_sequence` 在 L1048 已完成同等校验后才调用本函数。
- **`finalize_sequence` 中 `entry_portaldata` 的 if 包裹（已删除）**：该函数的所有调用点均由调用方保证 `entry_portaldata` 非 nil，if 包裹仅增加一层无意义的缩进。删除后将入口清理代码展平至函数体作用域。
- **`raise_arrived_event` 中 `exit_portaldata` 的二次 and 保护（已在上次操作中删除）**：函数顶部的卫语句（L63）已保证能执行到 L87 时 `exit_portaldata` 必然非 nil，`exit_portaldata and exit_portaldata.unit_number` 中的 `and` 判断属于重复防御。

### 具体改动
- `RiftRail/scripts/teleport.lua`：删除 `process_transfer_step` 中永远不会触发的出口有效性检查块；展平 `finalize_sequence` 入口清理代码，移除冗余 if 包裹；简化 `raise_arrived_event` 中 `exit_unit_number` 的赋值表达式。

### 2026-03-28（v0.13.6：车站查询公共化与 GUI 初始化崩溃修复）

**改动摘要**：将散落在各兼容模块中的重复车站查找逻辑统一收归至数据层，同时修复了新游戏首次打开传送门 GUI 时的崩溃问题。

- **车站查询公共化（`State.get_station` / `State.find_child_entity`）**：此前 `cs2.lua`、`ltn.lua`、`gui.lua`、`logic.lua`、`builder.lua` 各自持有私有或内联的 `get_station` 逻辑，实现完全相同却分散维护。本次将底层通用查找函数 `State.find_child_entity(portaldata, name)` 与车站快捷门面 `State.get_station(portaldata)` 提取至 `state.lua`，确立数据层作为子实体查询的唯一权威来源。按照架构分层约定，`teleport_system/` 子目录内的模块同步通过 `State` 注入使用，而非自持独立副本；`teleport.lua` 由于本身已持有 `State` 引用，直接调用 `State.get_station`，消除了经由 `TeleportUtils` 代理的多余跳转层。

- **GUI 初始化崩溃修复**：新游戏时打开任意传送门 GUI 会触发 `attempt to index field 'rift_rail_player_settings' (a nil value)` 错误。根因为 `storage.rift_rail_player_settings` 从未在任何初始化路径中被创建。在 `State.setup_new_game()`（新档）与 `State.patch_missing_root_tables()`（旧档迁移）中同步补全了该根表的初始化，彻底覆盖新旧存档的所有入口。

### 具体改动
- `RiftRail/scripts/state.lua`：新增 `State.find_child_entity(portaldata, name)` 与 `State.get_station(portaldata)` 两个公共函数；在 `setup_new_game` 和 `patch_missing_root_tables` 中补全 `rift_rail_player_settings` 初始化。
- `RiftRail/scripts/compat/cs2.lua`：删除私有 `get_station`，全部调用点改为 `State.get_station`。
- `RiftRail/scripts/compat/ltn.lua`：删除私有 `get_station`，全部调用点改为 `State.get_station`。
- `RiftRail/scripts/logic.lua`：`refresh_station_limit` 和 `update_name` 中的内联子实体遍历改为 `State.get_station`。
- `RiftRail/scripts/gui.lua`：两处内联子实体遍历改为 `State.get_station`。
- `RiftRail/scripts/builder.lua`：`on_settings_pasted` 中的内联子实体遍历改为 `State.get_station`。
- `RiftRail/scripts/teleport.lua`：直接使用 `State.get_station`，不再经由 `TeleportUtils` 代理。
- `RiftRail/scripts/teleport_system/teleport_utils.lua`：注入 `State`，删除已无调用者的 `TeleportUtils.find_child_entity` 导出函数；`get_real_station_name` 内部改用 `State.get_station`。
- `RiftRail/control.lua`：`TeleportUtils.init` 调用补充 `State` 参数传递。

### v0.13.5 附加更新：架构返璞归真与双轨制消除

**改动摘要**：彻底清除了 CS2 兼容模块中潜伏的“缓存更新双轨制”架构悖论，全面拥抱无状态（Stateless）的绝对强一致性，将潜在的寻路死锁概率降至零。
- **终结状态机分裂 (Eradicating Dual-Track Desync)**：修复了系统中“结构性操作全量重建（如新建/配对/拆除）”与“轻量级操作增量修补（如开关切换）”混用导致的拓扑状态割裂问题。原有的增量更新（Incremental Update）算法虽在理论时间复杂度上极具美感，但在 Factorio 引擎的现实约束下（极小规模的传送门数据集 + 极低频的玩家操作），其复杂的局部状态机极易在时序交错中与全局图产生脱节，进而滋生幽灵数据。本次重构果断斩断了这一过度设计，将所有开关触发器统一并入 `CS2.on_topology_changed()` 的全量重建轨道，确立了以真实物理实体快照为唯一真理的强一致性防线。
- **战略性代码雪藏 (Strategic Code Snowboxing)**：并未物理抹除那套极其精妙的增量维护算法（如抽屉节点重组与单边精准抹除逻辑），而是将其在调用入口处实施了静默剥离，转化为技术资产储备。这意味着当前的 RiftRail 模组以趋近于 0 的维护心智负担，换取了 100% 的物流拓扑准确率；而一旦未来第三方物流模组引入高频拓扑重组需求，这台封存的增量引擎随时可被唤醒重启。

### 2026-03-27（v0.13.5：热路径极简重构与反过度设计）

**改动摘要**：深入清理了 CS2 兼容模块中的“防御性妥协”与“过度设计（Over-engineering）”，在最核心的列车发车热路径（Hot Path）上确立了强一致性架构，并将状态同步的延迟压缩至物理极限的 0 帧。
- **废除拓扑防抖与状态幽灵消除 (Zero-Latency Topology Sync)**：彻底移除了原先设定的 120 Ticks（2秒）强制拓扑重建冷却（节流防抖）机制。原机制虽意在防范海量建筑瞬间摧毁带来的算力风暴，但在实际游玩中，若玩家在极短时间内快速反悔切换开关，该机制会无情吞噬真实操作，导致本地开关状态与 CS2 内部字典发生“状态不同步（Desync）”的致命 Bug。鉴于 CS2 引擎底层已具备极佳的脏标记整合能力，我们选择摒弃这一过度设计，转而拥抱绝对的实时同步。现在的拓扑变更指令将零延迟直达 CS2 主程序，彻底断绝了幽灵路线死锁的可能。
- **热路径“绝对信任缓存” (Absolute Cache Trust in Hot-Path)**：对决定列车走向的 `find_best_route` 核心派单函数实施了降维级别的瘦身。删除了原代码中因对增量更新缺乏安全感，而在列车发车瞬间强行执行 `rebuild_route_cache()` 的防御性兜底重算。正式确立了“相信地图（精准缓存），只看路标（微秒级实体存活性校验）”的极客级架构。现在列车发车时，仅需极速查表并执行 $O(1)$ 的 `portaldata.shell.valid` 存活性校验，将发车瞬间的 UPS 计算损耗彻底打穿至趋近于 0。
- **读时拓扑伪装与单向黑洞防御 (Read-Time Topology Masking & One-Way Defense)**：针对 CS2 寻路算法在跨地表物流中默认“必须原路返回”的逻辑硬伤（若无返回路径会强插原点车站导致 Factorio 引擎严重报错崩溃），我们拒绝了沉重且极易引发状态脱节的“写时严格双向缓存（Write-Time Filtering）”方案。取而代之的是极其优雅的“读时过滤（Read-Time Filtering）”：底层路由表依旧保持绝对真实的“有向图”刻画（完美保留了单向路线警告 UI 的数据基建），仅在向 CS2 提交拓扑接口（Callback）的瞬间，以极微小的开销执行反向探路校验。将单向路线悄无声息地隔离在 CS2 的寻路视界之外，兵不血刃地化解了由跨星系单行道引发的引擎级崩溃风险。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`：删除了 `REBUILD_DEBOUNCE_TICKS` 常量及其附带的时间戳记账逻辑，将 `request_cs2_topology_rebuild` 降维为纯粹的、无条件直通的 `pcall` 触发器。
- `RiftRail/scripts/compat/cs2.lua`：重构了 `find_best_route` 函数，剔除了末尾冗余的强制缓存重建与二次选路逻辑，仅保留极轻量的物理实体存活防线，实现发车逻辑的极限提速。
- `RiftRail/scripts/compat/cs2.lua`：在 `CS2.train_topology_callback` 拓扑出口函数中植入轻量级拦截网，利用 `has_direct_route` 校验 `to_surface` 到 `origin_surface` 的反向连通性，仅当物理路线双向贯通时，才向 CS2 注册该目标地表。

### 2026-03-27（v0.13.5：CS2 路由优先级抢占与可达性审查极简优化）

**核心聚焦**：彻底理清了在 Cybersyn 2 多模组跨表共存环境下的“路由抢单”与“发车安检”底层逻辑，解决被其他跨表模组（如太空电梯）霸占路由以及错误误伤其他模组的问题，将性能优化至 0 开销。
- **可达性审查零开销放权 (Zero-Cost Reachability Veto)**：深刻剖析了 CS2 `reachable_callback` 接口作为“一票否决/安检站”的本质设计。修正了旧版代码中极其危险的“自身无路线即全局否决”逻辑（该逻辑曾导致全图所有模组的跨表订单瘫痪）。鉴于 RiftRail 目前奉行“敞开大门，绝不拦截”的自由策略，直接在代码和注册表中彻底注释并注销了该安检接口。赋予了模组最完美的第三方兼容性（管不了就不干涉，让贤给其他有路线的模组）。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`：用块注释隐藏了 `CS2.reachable_callback` 函数本体及空壳，消除每一次发车时无意义的表计算与函数调用。
- `RiftRail/updates/cs2.lua`：删除了向 CS2 主程序注册 `reachable_callback` 的代码，彻底撤销发车安检口。
- `RiftRail/scripts/remote.lua`：同步注销 `cs2_reachable_callback` 的远程接口暴露。

###  2026-03-24（v0.13.4：运行档案数据追踪与防弹级深拷贝解耦）

**核心聚焦**：引入了全新的“运行档案”面板，实时掌握每一个传送门的后勤服役指标；同时通过只传递纯标量 ID 攻克了官方引擎事件 Payload 深拷贝造成的拦截黑洞。
- **智能化运行档案 (Dynamic Operational Statistics)**：在传送门 GUI 新增“显示运行档案”复选框。通过 `gui.lua` 中纯洁的判定树，面板能自动依据所在传送门身份变形：入口只展示“传送次数/上次传送时间”，出口只展示“接收次数/上次接收时间”，双端共享精准的“服役时长”雷达。
- **绕过深拷贝防守 (Bulletproof Decoupling)**：彻底剥离统计逻辑至全新的 `stats.lua` 观察者模块。由于 Factorio `script.raise_event` 会无差别静默舍弃含有复杂类型嵌套的数据表，修改 `teleport.lua` 的事件抛出物，使其从原本极其臃肿的 `portaldata` 实体指针群退化为极简干脆的 `unit_number` 数字标量。然后在接收端利用 ID 反查 `storage.rift_rails` 原始表，完美绕开深拷贝限制和垃圾回收噩梦。
- **高度剥离的全局化 (Refactoring Utility)**：对代码实施严苛的界限把控：将原本混杂在视图层内的 `format_duration` 算法硬生生抽离至 `util.lua` 变为顶级暴露工具 `Util.format_duration`；修复 `GUI.init()` 的依赖注入缝隙使得渲染面板与底层数学池畅通无阻，并连带重写了中日英三语对应的参数形态后缀。
- **专线物流白嫖追踪 (LTN & Cybersyn 2 Telemetry)**：借助传送门本就完美的兼容层拦截件，实现在 `LTN.on_train_teleport_transfer` 与 `CS2.on_train_arrived` 这两帧唯一的移交微秒中，一旦确认对方物流网关收发货单，当场白嫖底层数据源实施 `stats.ltn_sent += 1` 的铁证。再结合动态渲染技术将专属的数据槽位按需绽放在对应传送门的面板上。
- **极致的依赖倒置与权限收归 (Stats Decoupling)**：执行了彻底的外置模块越权清场，剥夺了 `ltn.lua` 与 `cs2.lua` 对底层运行记录表的直接写权限。将记账逻辑统一上收至独立的 `stats.lua` 并对外公开 `Stats.record_logistics_delivery` 抽象接口。现在，任何外挂组件只需要抛出前缀即可，所有的数据一致性检查与脏写排查完全由调度中心唯一接管。
- **API 文档与 Payload 同步更新 (API Docs Sync)**：将传送门独家的标量数据载荷（`entry_unit_number` 与 `exit_unit_number`）向外暴露给 `TrainArrived` 以及由其衍生出的 `TrainTeleportTransfer` 移交事件，并同步在 `doc/API(CN).md` / `doc/API(EN).md` 中完成了官方手册撰写。

### 技术变更细节
- 新建 `scripts/stats.lua`：独立负责统计量拦截与自增更新计算。
- 更改 `scripts/teleport.lua`：`raise_arrived_event` 货箱变更，从 `entry_portaldata` 改发 `entry_unit_number`。
- 更改 `scripts/builder.lua`：令新蓝图起建时自动带有天生的 `stats={}` 空核对象。
- 更改 `scripts/gui.lua`：接入 `Util.format_duration` 计算秒数，接管展示与状态逻辑，清理残存 `format_duration`。顺手修复了按下“传送玩家”按钮后画面残余瞄准高亮圈的 `clear_preview_render`。
- 更改 `scripts/migrations.lua`：撰写 `add_portal_stats` 洗礼脚本填补上古版本坑位，外挂一层 `portal_stats_migrated` 防护门彻底屏蔽往后大后期的每一次沙盒更新。
- 更改 `control.lua`：填补缺失的 `Util=Util` 初始化引用，加载 `Stats` 生命体。

###  2026-03-24（v0.13.4：GUI 专属工具栏与状态机图标化）

**核心聚焦**：为了将左下角的宝贵空间彻底释放给未来的“数据统计仪表盘”，对冗杂的操作控件实施了降维打击。
- **“双子星”快捷指令**：在“运行模式（入口/出口）”栏的最右侧，利用弹簧排版开辟了专属的工具栏区域。将原本占用极大的“传送玩家”文字按钮，以及用于控制右侧监控的“显示目标预览”复选框，全部重构为扁平、无框的 `tool_button` 图标（跑步小人与状态眼睛）。
- **无缝状态翻转**：彻底移除了底层的 Checkbox 控件与对应的 `on_gui_checked_state_changed` 监听。现在，监控画面的开关由“眼睛”图标的点击事件接管。通过纯代码驱动的布尔值翻转与瞬间重绘，实现了睁眼/闭眼图标的平滑切换，交互逻辑更加契合硬核工业控制台的直觉。

### 具体改动
- `RiftRail/scripts/gui.lua`：在 `build_or_update` 的模式切换流（`mode_flow`）最右侧，新增了基于 `sprite-button` 的 `rift_rail_toggle_preview_button` 和 `rift_rail_tp_player_button`。
- `RiftRail/scripts/gui.lua`：移除了旧版左下方的 `tool_flow` 传送按钮，以及 `rift_rail_preview_check` 复选框的渲染代码。
- `RiftRail/scripts/gui.lua`：在 `handle_click` 事件流末端接管了预览状态翻转逻辑（`show_preview = not show_preview`）并触发重绘；在 `handle_checked_state_changed` 中清除了已废弃的复选框事件拦截分支。


## 2026-03-23（v0.13.4：GUI 交互极简进化与视觉层级重构）

**核心聚焦**：深入挖掘 Factorio UI 引擎的 `ignored_by_interaction` 穿透特性与负边距排版魔法，彻底消灭了冗余的操作控件，并将左右面板的视觉层级与工业质感推向了新的高度。

### 触屏级极简交互 (Zero-Friction UX)
彻底移除了右侧监控室那颗极其违和的独立【远程观察】按钮。现在，目标名称的展示栏本身就是一个全宽的伪装交互按钮（利用 `list_box_item` 暗色下陷样式）。当玩家点击名称区域时，鼠标事件将直接穿透下方套件触发传送。这种“所见即所得”的触屏式交互逻辑，让远程监控的体验变得前所未有的丝滑。

### 负边距铭牌与物理分界 (Negative Margin & Physical Dividers)
- **右侧深槽切割**：弃用了刻意生硬的 `line` 画线方案，转而利用 `empty-widget` 与深色大坑（`inside_deep_frame`）的并排挤占效应，在标题区与摄像头画面之间，原生“挤”出了一道带有 Factorio 原生底色的横向物理深槽分隔线。
- **左侧悬浮铭牌**：为左侧深色操作区（`left_pane`）的顶部注入了 `subheader_frame` 浅色材质。通过施加极其凶悍的负边距（`-8` Margin）抵消父级框架的内边距限制，强行打造出了一块横向贯穿、左右死死贴紧边缘、且微微凸起的“铝制身份铭牌”。这不仅打破了深色大坑的沉闷感，还在不增加复杂嵌套结构的前提下，完美确立了“标题统领全局”的视觉统治力。

### 具体改动
- `RiftRail/scripts/gui.lua`：重构 `GUI.build_or_update` 右侧面板渲染流，将原本作为标题的 `Label` 替换为带有 `list_box_item` 样式的全宽 `Button`，并利用 `empty-widget` 切割出物理隔离带。
- `RiftRail/scripts/gui.lua`：重构左侧面板的门牌号（Rename Area）渲染层级，引入 `subheader_frame` 并应用负边距黑魔法，实现名牌的无缝嵌入与高亮凸起。
- `RiftRail/scripts/gui.lua`：同步更新 `GUI.update_camera_preview` 函数，确保在下拉框切换目标时，新架构下的按钮 `caption` 与其禁用/高亮状态能被实时且无闪烁地正确覆写。


## 2026-03-22（v0.13.3：GUI 彻底原生化重构与 Z 轴深坑美学）

**核心聚焦**：彻底抛弃早期悬浮、扁平的粗糙 UI 组件堆砌，全面引入 Factorio 官方重工业控制台的架构语言。通过精确剖析 `inside_shallow_frame` 的“挖坑”嵌套手法和 `frame_header` 等原生控件的直接复用，实现了控制面板界面在结构上的内嵌感和动态自适应。

### 真正的硬核沉浸感 (Layered UI & Insets)
通过给侧边栏限定死 `300px` 的装甲宽度，彻底处决了不同字号和多语言切换导致界面横向鬼畜抖动的顽疾。整个面板上空被加盖了一层包含隐形拖拽弹簧与原生 `[X]` 按钮的独立 Title Bar。
除此以外，核心参数区（左首）、功能操控区（右上）以及全息监控屏幕区（右下）被暴力开凿成了三个互不干扰但又紧密咬合的暗灰色下陷槽。现在，这台传送仪器的点击反馈、交互层次、乃至微操按钮的悬停底色与物理音效，均达到了与游戏原生加工厂界面 `100%` 毫无二致的真假难辨境界。

### 具体改动
- `RiftRail/scripts/gui.lua`：重构了 `GUI.build_or_update` 树形结构，拔除根节点 `caption` 强制接管外壳，自行注入完美匹配原版尺寸的 `frame_header` 与 `draggable_space_header`。
- `RiftRail/scripts/gui.lua`：实施多级 `inside_shallow_frame` / `inside_deep_frame` 嵌套，建立左右对称但深度独立的功能大坑。
- `RiftRail/scripts/gui.lua`：将 CS2 与 LTN 古板的拨动 `switch` 升级为紧凑聚合的 `checkbox` 复选结构。
- `RiftRail/scripts/gui.lua`：为重命名组件挖掘游戏底层，挂载了 `mini_button_aligned_to_text_vertically_when_centered` 原生样式。
- `RiftRail/scripts/gui.lua`：利用原生 `rendering.draw_circle` 黑科技，实现了跨地表监控摄像头内的单体视野目标高亮“双彩雷达”锁定效果，且生命周期与 GUI 开关彻底绑定。
- `RiftRail/scripts/state.lua`：移除了旧版 GUI 临时变量的懒加载防空逻辑，直接通过 `state.lua` 将 `storage.rift_rail_preview_renders` 字典拍平并兜底初始化，极大地提高了架构维度的查错收敛度。
- `RiftRail/locale/*/strings.cfg`：全域支持了包含 Japanese、English、Chinese 在内的新版控件术语（含 `Standby` 待机模式补全）。

## 2026-03-22（v0.13.3：蓝图系统与内部车站架构精简）

**核心聚焦**：由于现代 Factorio 的蓝图系统原生支持利用 `tags` 功能携带实体属性，本版本彻底废弃了“强行往蓝图中注入带位移的内部车站幽灵来保存数据”的历史冗余操作，蓝图机制变得空前清爽。

### 废弃蓝图车站幽灵注入
现在的配置恢复工作完全由外壳本身的持久化 `tags` 独立包办。这意味着无论玩家使用何种被加料的老蓝图，或者蓝图机器人参与修补，都不会再有任何游离于数据树之外的“孤儿隐形车站”遗留在地图上。此外去除了内部车站原型的 `placeable_by` 属性，从根源上断绝了机器人凭空违规建造该隐藏零件的可能。

### 具体改动
- `RiftRail/scripts/builder.lua`：删除了 `on_setup_blueprint` 中对 `rift-rail-station` 的强行注入与空间位移。
- `RiftRail/scripts/builder.lua`：清除了 `on_built` 阶段对旁侧空地的 `entity-ghost` 扫描与回读逻辑。
- `RiftRail/prototypes/internal/station.lua`：移除了 `placeable_by` 属性。


## 2026-03-22（v0.13.3：拆除监听与底层生命周期重构）

**核心聚焦**：为了极限压榨游戏 UPS 性能，永久性地移除了未配备原生过滤器的全局毁坏监听事件（`script_raised_destroy`），全面转型拥抱开销极低的底层兜底防线 —— `on_object_destroyed`。

### 底层静默清道夫机制
当传送门遭遇（如：地图编辑器强制选区刷除、SE跨星系强杀切片等）单纯的底层脚本突发死亡时，被销毁的注册对象会精准触发高响应级别的 `on_silent_destroyed` 清道夫机制。它将直接回溯数据树，对原本不在常规销毁队列中的核心轨道、信号灯、内部车站以及隐形物理碰撞壁（Collider）执行同步定点清算，实现真正的物理同生共死。

### 具体改动
- `RiftRail/control.lua`：移除了旧全局事件监听，全面接入 `on_object_destroyed`。
- `RiftRail/scripts/builder.lua`：新增 `on_silent_destroyed` 静态死亡回收控制器。
- `RiftRail/scripts/builder.lua`：在 `on_built` 与 `on_cloned` 中追加了相应的对象级防线注册器。
- `RiftRail/scripts/migrations.lua`：为全图旧档残存实体补发了生命周期钢印与主键结构向后兼容修补。

## 2026-03-21（v0.13.2：列车中断机制极客级优化——白名单靶向洗脱与语义重构）

**核心聚焦**：深入修复方案边缘死角，建立传送前的“合法临时站”快照护符机制，防止跨界时误删玩家合法存在的临时手操路标，并对相关高频核对代码域进行语义清洗。

### 白名单靶向洗脱（Selective Pruning）
在确认了“首节净化 + 后续硬抗”的终极机制后，发现原初阶段旨在全面扫除引擎强插假中断站的 `cleanup_interrupt_garbage` 与 `snap` 函数存在广撒网的误伤隐患：如果玩家在过门前临时手动增加了一个无真实轨道坐标的纯名字临时站，该站在过闸时也会被牵连删除而导致列车短暂失忆。
- **护身前置快照**：在引导车厢获取时刻表并即将挂载引爆引擎底层的“缺货假中断警报”的前一瞬间，先对原车厢时刻表进行合法特征提取。将所有已天然存在的合法“纯名字临时站”记录为 `safe_interrupt_names` 散列表册。
- **免死金牌下发**：将此护身册存入跨帧传输数据层 `portaldata` 并向下穿透传递给 `snap_pointer_past_interrupt` 拨正模块与终期 `cleanup_interrupt_garbage` 模块。判定逻辑全面升级：仅当排查游标不仅满足特征、且不在白名单内时，才精准定性为由引擎夹带的违禁私有产物并予以坚决铲除，实现精确清创。

### 代码可读性重构
- 为提升日后的模块化审查体验，全面消除了底层过滤器中因命名缩略带来的指代不明。将 `schedule.lua` 内横跨各个清洗、扫描遍历核心环节的单字母判定形参与迭代游标 `r` 统一重构为标准全拼 `record`，一举清扫了多级嵌套作用域内的心智盲区。
- 统一了首节车厢的判定语义：在 `teleport.lua` 的堵塞检测和时刻表转移逻辑中，移除了历史遗留的 `if not entry_portaldata.exit_car then` 间接判断，全面替换为已有的 `is_first_car` 变量，保持了代码风格的整体一致性。

### 具体改动
- `RiftRail/scripts/schedule.lua`：
  - 在 `copy_schedule` 中增加在时刻表赋值前夕遍历建立 `safe_interrupt_names` 白名单图册，并将其作为返回值抛出。
  - 修改 `snap_pointer_past_interrupt` 与 `cleanup_interrupt_garbage` 签出，新增 `safe_set` 拦截网；并执行了无死角的全文件 `record` 变量重命名字段清洗。
- `RiftRail/scripts/teleport.lua`：
  - 将核心传送循环中判断首节车厢的 `not entry_portaldata.exit_car` 统一替换为 `is_first_car`。
  - 在首节引导车 `spawn_car` 中接收 `copy_schedule` 的新增白名单返回值，并作为“一次性护符”锁入 `exit_portaldata.safe_interrupt_names`。
  - 全面改造 `spawn_car` 中对 `snap` 的调用，以及 `finalize_sequence` 末端对 `cleanup` 的调用，接驳并消耗白名单。随后在清理传送门状态对象时，同步实施了 `safe_interrupt_names = nil` 的析构动作。

## 2026-03-21（v0.13.2：列车中断指针抢夺战——极客级架构融合优化）

**核心聚焦**：基于此前完成的 `snap_pointer` 拨正逻辑，通过实机底层日志的解剖分析，确立了“首节净化 + 后续原生防线硬抗”的终极性能优化方案。

### 痛点与觉醒

在上一版修复中，我们通过在**每一节车厢拼接后**都执行一遍极其高效的 `snap_pointer_past_interrupt` 遍历，强行把引擎在对接瞬间新塞入的假中断站从执行指针上拨走。这虽然防备了引擎，但在机制上有点多余。

通过深度开启无视调试模式的强力日志检测，发现了一个惊人的事实：原有的核心数据暂存与恢复系统（`index_before_spawn` -> `restore_train_state`）**一直是完美且能自动抗击引擎打乱机制的**！它过去之所以失效，仅仅是因为它在第一节车厢错误地读取了被引擎污染的假中断指针当作“正确起点”。

### 终极方案

结合原有的状态同步恢复架构，对执行链实施了完美剥离：

1. **首节净化**：仅在第一节引导车厢完成 `copy_schedule` 后，调用一次 `snap_pointer_past_interrupt`。当引擎因货空强塞假中断站时，它能第一时间将指针推回真实的合法站点，并将这个**绝对正确的干净指针**存入 `saved_schedule_index`（作为后续全队列状态同步的纯净种子）。
2. **后续接力与硬抗**：从第二节车厢开始往后所有步骤，**彻底停用 `snap` 拨正函数**，完全沿用原先优秀的抗击打防线。每节车厢在拼接前准确读取了上一帧传承过来的干净指针（`index_before_spawn`）。在物理拼接瞬间（引擎此时虽然会再次发疯把指针跳回到假中断站）之后，原有的 `restore_train_state` 逻辑雷霆出击，把指针强硬、精准地恢复回刚刚安全读取到的真实目标。

### 优化成果

这套方案极其优雅地结合了“新写的单次查杀（净化源头）”与系统固有的“指针恢复体系（维持正确态）”。
不仅一劳永逸死死拿捏了指针漂移造成的死锁，也把后续哪怕长达几百节的星际重型列车的 CPU 对抗压力，从多重条件轮询扫描降维到了最极致的 $O(1)$ 标量级单纯内存赋值（真正的绝对 $0$ UPS 损耗）。

### 具体改动
- `RiftRail/scripts/teleport.lua`（`spawn_car`）：将 `Schedule.snap_pointer_past_interrupt` 函数调用及其附带的 `saved_schedule_index` 备份操作严格限制在首节车厢判定内（`if not exit_car then` 块内），后续车厢彻底放权给原生的 `restore_train_state` 进行状态防守。

## 2026-03-21（v0.13.2：列车中断机制（Interrupt）兼容性修复）

**核心聚焦**：正确处理 Factorio 引擎在列车逐节传送期间因货物不足而同步触发的「假中断」站点，确保指针正确、速度不丢失、LTN 能正常接管。

### 问题根源

Rift Rail 采用逐节传送模式：每一节车厢以独立实体生成于出口，然后依次拼接。在相邻两节车厢完成对接的瞬间，游戏引擎会因列车货仓尚未装满而立即同步评估中断条件。若玩家在时刻表中配置了「货物 < 1000 则前往 X 站」类型的中断，该判断在这一帧内通过，引擎随即在当前时刻表指针之前强制插入一个 `temporary = true`、无 `rail` 字段的临时站点，将原本正确的目标站顶后一位。

这直接导致以下问题链：
1. **指针错位**：传送期间的中断站占据了指针位置，列车以为自己该去"中断站"而非真正的目标。
2. **LTN 路标失效**：LTN 的 `get_or_create_next_temp_stop` API 遍历时刻表，见到已有 `temporary = true` 的站点就认定"路点已存在"，跳过插入真正的 rail 路标，造成跨地表调度失败。
3. **清洗索引位移**：传送完毕后的清洗函数使用「清洗前」记录的旧索引调用 `restore_train_state`，但清洗本身删除站点导致索引位移，旧索引所对应的站点已经不再是预期目标。
4. **速度骤降**：`restore_train_state`（恢复速度）在 `cleanup_interrupt_garbage`（内部调用 `go_to_station`，触发寻路重置）之前执行，使刚恢复的速度被立即打断。

### 解决方案

#### 新增 `Schedule.snap_pointer_past_interrupt`（`schedule.lua`）

不删除中断站，只用 `go_to_station` 单独移动指针跳过它：
- 检测当前 `schedule.current` 所指的站是否为假中断（`temporary = true` 且无 `rail`，且非传送门入口站名）。
- 若是，向后方向扫描，找到第一个合法的真实站点并调用 `go_to_station` 跳过去。
- **不调用 `set_records`**，避免触发引擎重新评估并立即重插中断站。

#### 修改 `spawn_car`（`teleport.lua`）

每节车厢拼接后都调用 `snap_pointer_past_interrupt`：
- 原逻辑：只在第一节车厢的 `copy_schedule` 之后执行一次清洗。
- 现逻辑：首节完成触发 LTN 移交事件后，以及后续每一节拼接完毕，统一执行 `snap_pointer_past_interrupt`，确保引擎每次重新触发的中断都能被及时跳过。
- `saved_schedule_index` 的备份紧跟在 snap 之后、而非在它之前，以保存矫正后的干净索引。

#### 修改 `finalize_sequence`（`teleport.lua`）

调整最终阶段的操作顺序：
1. **先 `cleanup_interrupt_garbage`**：全列车传送完毕、货仓已满，此时引擎不再会重插中断，可以安全地执行 `set_records` 彻底删除所有假中断站。
2. **读取清洗后的真实索引**：`cleanup_interrupt_garbage` 内部已经按删除后的正确偏移量调用了 `go_to_station` 并校正了 `schedule.current`，传送完毕后直接读取它，而不再使用「清洗前」记录的旧索引。
3. **后 `restore_train_state`**：速度恢复在所有时刻表操作完成之后，为最后一步，不会被任何后续 `go_to_station` 打断。

#### 文档与提示（Informatron）

- 在 LTN Informatron 页面新增了一段「中断机制兼容性说明」（中英文各一份），告知玩家：若 LTN 列车带中断条件，请在传送门设置中开启"传送后清理站"选项，使传送门提供无 `temporary` 属性的专用站点，消除引擎误判触发源头。

### 具体改动

- `RiftRail/scripts/schedule.lua`：新增 `Schedule.snap_pointer_past_interrupt` 函数；修复 `Schedule.cleanup_interrupt_garbage` 中指针校正的边界条件（`<=` 改为 `<`）。
- `RiftRail/scripts/teleport.lua`（`spawn_car`）：将每节车厢的 cleanup 替换为 `snap_pointer_past_interrupt`；`saved_schedule_index` 备份移至 snap 之后。
- `RiftRail/scripts/teleport.lua`（`finalize_sequence`）：调整顺序为「先 cleanup → 读取清洗后索引 → 再 restore_train_state 恢复速度」。
- `RiftRail/locale/zh-CN/informatron.cfg`、`locale/en/informatron.cfg`：LTN 页面新增中断机制使用说明。
- `RiftRail/scripts/compat/informatron.lua`：LTN 页面渲染追加 `text_2` 节点。

## 2026-03-21（v0.13.2：工具架构分层净化与依赖倒置）

**核心聚焦**：根据分层架构（Layered Architecture）规范，重新审视并净化全工程的模块职能，彻底杜绝下层对上层的反向业务依赖。

- **底层库黑盒化 (`util.lua`)**：作为被全工程踩在脚下的"零业务认知地基"，我们剪切了侵入它内部的 `rebuild_all_colliders` 业务逻辑，并拔除了它对 `TeleportMath` 等特定业务的倒置注入。现在 `util.lua` 实现了真正的完全脱敏。
- **功能所有权审计 (`teleport_system`)**：针对该隔离区执行了极其严格的高内聚排查。将唯一一个不被热路径调用、而是被初始化建筑调用的 `calculate_teleport_cache` 强制退回并让渡给 `builder.lua`（同时采用更高语意的名称 `Builder.compute_portal_geometry`）。
- **跨层级调用梳理 (`builder.lua` & `control.lua`)**：由 `Builder` 完全接管所有关于“建筑创建、重建与附带缓存计算”的底层工作，修正 `migrations.lua` 的异常越权索取，斩除不必要的依赖连线。
- **死代码极限压缩**：彻底移除全工程 0 调用的历史废弃渲染函数 `signal_to_richtext`。

### 具体改动
- `RiftRail/scripts/util.lua`：移除 `rebuild_all_colliders` 和 `signal_to_richtext`；完全移除 `TeleportMath` 的依赖注入。
- `RiftRail/scripts/builder.lua`：接手新增 `Builder.compute_portal_geometry`，并接管 `Builder.rebuild_all_colliders`；全面修正内部调用；移除对 `TeleportMath` 的使用。
- `RiftRail/scripts/teleport_system/teleport_math.lua`：删除越权的坐标计算逻辑 `calculate_teleport_cache`。
- `RiftRail/scripts/maintenance.lua` & `migrations.lua`：重建碰撞体的方法全部改道去呼叫 `Builder.rebuild_all_colliders`，同时在依赖中补充注入 `Builder`。
- `RiftRail/control.lua`：移除 `Util` 接收的 `TeleportMath` 和 `Builder` 接收的 `TeleportMath`；向 `Maintenance` 和 `Migrations` 新增 `Builder` 的依赖传递。

## 2026-03-21（v0.13.2：架构净身与底层废弃缓存重构）

**核心聚焦**：全面清除历史迭代中残留的“代码结石”与跨模块滥用的通用函数，彻底剥离为旧版 `can_place_entity` 而服役的数据结构。

- **死代码火化**：彻底删除了全工程0调用的冗余工具函数 `position_in_rect`、`get_rolling_stock_train_id`，为大杂烩模块 `util.lua` 瘦身。
- **传送几何法则归位**：将负责计算传送门包围盒核心坐标的 `calculate_teleport_cache` 函数从非相关的 `util.lua` 中抽离，完璧归赵至专属数学模型物理库 `teleport_math.lua`，理顺了调用层级关系。
- **旧版碰撞体系缓存（Cache Purge）连根拔除**：旧时代 `can_place_entity` 会引发显著 GC 的机制已被纯数学外接圆平替，因此我们连根拔除了服务于前者的所有预设字典和数据表打包，包含：
  - 取消了 `teleport.lua` 和 `builder.lua` 跨文件维护的 `cached_place_query`（原引擎实体放置指令打包缓存）。
  - 干掉了 `TeleportMath.GEOMETRY` 中多余的魔法向物理常量映射（如旧版速度修正因子、相对防碰撞区域硬编码偏移）。
  - 消灭了打包性质的 `cached_geo` 结构体，所有相关计算改为透明直读。
- **模块依赖清晰化**：为 `Builder`、`Migrations` 以及 `Util` 子模块全部实装了对最新版本 `TeleportMath` 的精确单向依赖注入层级，解决了代码分散隐患。

### 具体改动
- `RiftRail/scripts/util.lua`：移除 3 个冗余函数；初始化阶段增加 `TeleportMath` 依赖注入。
- `RiftRail/scripts/teleport_system/teleport_math.lua`：收纳 `TeleportMath.calculate_teleport_cache`；精简 `GEOMETRY` 常量枚举字段。
- `RiftRail/scripts/teleport.lua`：抹除涉及 `cached_place_query` 的相关缓存声明；移除了由于 `ensure_geometry_cache` 删去导致的 `geo` 对象获取断链。
- `RiftRail/scripts/builder.lua`：`Util.calculate_teleport_cache` 所有访问点转义为 `TeleportMath.calculate_teleport_cache`；移除多余的缓存重置指令。
- `RiftRail/scripts/migrations.lua`：向旧版缓存刷新接口引注入模块专属 API。
- `RiftRail/control.lua`：初始化引导链树补充传递 `TeleportMath` 到各个业务方。

## 2026-03-20（v0.13.1 开发中：零 GC 无视种类动静碰撞算法与无限车厢长度支持）

### 改动摘要
- **无限车厢长度兼容**：彻底解除了底层引擎对于“列车标准长度”的刻板印象。不管是小于原生尺寸的微型车厢，还是半长达到 6.0 的极限拼装车（总长 12 格），系统均能通过读取实际体积完美自适应安全距离。
- **动态引导车生成系统**：重写了原版固定死板的 `4.0` 偏移值生成引导机车的硬编码。改为基于最新一节真实克隆车厢的精确外接圆半径（`get_carriage_radius`），实施精准切入。在保留原生 `0.5` 的侵入挤压量的同时，利用游戏内的物理滑脱机制实现自然对接。
- **纯粹的纯数学零 GC 测距护盾**：这是本次更新最核心的提升。彻底删除了昂贵的跨引擎 API 调用 `can_place_entity`（它会触发大规模 C++ 构建和 GC 垃圾），用极为轻量的两点外接圆几何碰撞检测（`is_spawn_clear_math`）平替，单次检测性能开销极低。
- **完全解耦与缓存闭环**：伴随着新算法，我们将新车生成时刻的车厢尺寸和安全距离参数即时录入 `portaldata` 缓存，仅在一帧内发生读写，并在队列完成极速销毁，不再产生残留的历史脏数据。
- **JIT 内存化与局部性优化**：针对 `get_carriage_radius` 实现了基于 `car.name` 的半径查找表。同名车厢在传送时将直接命中缓存，彻底规避了对 `prototype` 属性的重复高频访问，计算密度进一步压降。
- **模块化瘦身与调用链扁平化**：将 GUI 追踪、时刻表索引读取、状态恢复等 5 个非核心辅助逻辑迁移至 `teleport_utils.lua`。同时移除了 `teleport.lua` 中的转发包装器，改为直接调用，消除了不必要的 Lua 栈帧压栈开销。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 核心循环的距离判定由 `surface.can_place_entity(...)` 替换为 `Math.is_spawn_clear_math(...)`。
  - 生成 `leader_train` 时，将硬编码 `4.0` 替换为了调用 `Math.get_dynamic_leader_offset(...)`。
  - 在 `process_transfer_step` 环节追加了新生成车厢的 `cached_exit_radius` 参数录入。
  - 实现了 `get_memoized_radius`，利用 `portaldata.last_car_name` 建立车厢尺寸 JIT 缓存。
  - 移除了 5 个辅助函数的转发包装器，所有调用点改为直连 `TeleportUtils` 模块。
- `RiftRail/scripts/teleport_system/teleport_math.lua`
  - 新增 `TeleportMath.get_carriage_radius`。
  - 新增 `TeleportMath.is_spawn_clear_math`。
  - 新增 `TeleportMath.get_dynamic_leader_offset` 并附带了对车身参数计算中 `2.8` 的保守平替支持。
- `RiftRail/scripts/teleport_system/teleport_utils.lua` [NEW]
  - 承载 `read_train_schedule_index`、`get_real_station_name`、`collect_gui_watchers`、`reopen_car_gui`、`restore_train_state` 等辅助逻辑。
  - 内部实现 `find_child_entity` 以保持模块自闭环。
- `RiftRail/control.lua`
  - 注册并注入 `TeleportUtils` 模块。

## 2026-03-19（v0.13.0 开发中：传送事件重构与LTN兼容优化）

### 改动摘要
- **全量无状态零拷贝（Zero-Copy）克隆架构**：完全废弃并删除了原代码中的 `create_entity` 及其附带的冗长属性搬运（`util.lua` 中的背包、燃烧室、装备网格等全部清空），现针对所有角度铁轨（包含平行与90度折角）采用基于纯数学演算预测引擎倾向的大一统方案，进行100%覆盖的原生高速深拷贝克隆。
- **传送事件生命周期解耦**：将列车离站（`TrainDeparting`）与列车跨地表物理移交（`TrainTeleportTransfer`）的事件触发点分离。
- 还原 `TrainDeparting` 事件：将其改回至传送会话阶段初始化（`initialize_teleport_session`）时触发。此时列车结构完好，方便外围通用模组执行清空车站、清理信号等逻辑，且不再附带 `new_train` 参数。
- 引入全新 `TrainTeleportTransfer` 事件：精确定位于出口第一节新车厢刚刚克隆生成、且入口原车厢尚未被销毁的微秒级瞬间触发。该事件专为对接移交设计，且去除了由于传递实体对象带来的 GC 性能开销，仅传递 `old_train_id` 和 `new_train_id` 确保无损转移数据。
- **LTN 兼容适配**：更新 LTN 模块监听路由，将其对接至新事件 `TrainTeleportTransfer`，彻底完成物流网络对接并维持零硬编码。
- **LTN 兼容热修复**：修正了 `TrainTeleportTransfer` 事件载荷。在原有仅下发 ID 的基础上，重新补充下发了 `new_train`（LuaTrain 实体本身），以严格符合 LTN 官方 API `reassign_delivery` 要求传入实体对象参数的约束要求。
- **API 文档更新**：增补对 `TrainTeleportTransfer` 的中英双语开发文档及相应的远程调用 `remote.call` 获取接口。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 修改 `raise_departing_event`：移除 `new_train` 等参数，移回 `initialize_teleport_session` 锁定阶段。
  - 新增 `raise_teleport_transfer_event`：在 `process_transfer_step` 首节新车生成后注入，并且精简了事件载荷参数。
- `RiftRail/control.lua`
  - 注册自定义事件 `RiftRail.Events.TrainTeleportTransfer`。
  - 更改绑定的监听器，将原来的 `LTN.on_train_departing` 替换为分发到 `LTN.on_train_teleport_transfer`。
- `RiftRail/scripts/compat/ltn.lua`
  - 将接收函数更名为 `LTN.on_train_teleport_transfer`，保证代码语义与参数一致。
- `RiftRail/scripts/remote.lua`
  - 增加 `get_train_teleport_transfer_event` 接口对接新事件。
- `RiftRail/doc/API(CN|EN).md`
  - 完善 `TrainDeparting` 和 `TrainTeleportTransfer` 事件信息与生命周期说明。

## 2026-03-18（v0.13.0 开发中：传送门核心逻辑深度瘦身与代码展平）
- **修复跨状态死锁漏洞**：修复了正在传送的列车因碾碎全局重建生成的碰撞器而触发 `on_collider_died` 事件，导致传送门状态意外降级并引发锁泄漏的逻辑漏洞。
- **模块结构归档**：在 `scripts` 下新建 `teleport_system` 目录，将抽离出的附加子模块（如数学与工厂逻辑）集中归档，保障代码树整洁。
- **模块化重构**：将臃肿的 `teleport.lua` 拆分为三层架构：主控制总线 (`teleport`)、物理几何算法 (`teleport_system/teleport_math`) 以及实体生成工厂 (`teleport_system/teleport_factory`)，实现性能无损解耦。
- **视觉展平与去嵌套**：重构了 `on_tick` 内部调度。通过提炼 `process_active_portal` 函数并使用提前 `return` 控制流（卫语句），彻底消灭了原有的 `else` 嵌套层级结构。
- **职责聚焦**：进一步剥离了 `release_exit_lock`（死锁清理）和 `spawn_leader_train`（引导车生成）等辅助细节，主流程可读性大幅跃升。
- **规范补全**：为全部新提炼出的控制函数和计算模块补齐了标准的 LuaLS 类型注解（`---@param`）。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `on_collider_died`：增加拦截逻辑，当传送门已处于 `TELEPORTING` 状态时，忽略后续多余的碰撞器销毁事件。
  - 删除冗余本地算法，全面接入 `Math` 和 `Factory` 的模块化调用。
  - 提炼 `release_exit_lock` 集中封装 GC 死锁清除逻辑。
  - 提炼 `process_active_portal` 负责单次传送门事件的调度流转工作。
  - 提炼 `spawn_leader_train` 分离牵引实体生成逻辑。
- `RiftRail/scripts/teleport_system/teleport_math.lua`（移入新目录）
  - 承载 `GEOMETRY` 常量阵列、意图向量获取与物理极性推力引擎。
- `RiftRail/scripts/teleport_system/teleport_factory.lua`（移入新目录）
  - 承载智能克隆/备份创建工厂方法。
- `RiftRail/scripts/util.lua`
  - `rebuild_all_colliders`：仅对原状态为 `REBUILDING(3)` 的瘫痪传送门解除锁定（置为 `0`）；去除无用的创建失败代码分支，保证运行期修改建筑设置时不会影响正常传送队列。
- `RiftRail/control.lua`
  - 同步更新传送门扩展模块的载入路径与依赖注入。

## 2026-03-17（v0.13.0 开发中：传送核心状态机重构）

### 改动摘要
- 彻底淘汰了基于多个布尔值（`is_teleporting`, `collider_needs_rebuild`）的"瀑布流"隐式状态判断，改为使用结构化的四态枚举状态机。
- `Teleport.on_tick` 调度器从多个并行 `if` 判断重构为互斥的 `if/elseif` 分支，杜绝了非预期状态冲突。
- 新增数据迁移脚本，确保存档无缝升级。
- **修复隐性死锁 Bug**：修复了通过菜单重置碰撞器时，如果因列车阻挡创建失败会导致传送门脱离活跃队列从而永久卡死的底层隐患。
- **修复 LTN 临时轨道坐标丢失问题**：修复了启用“清理车站”设置时，LTN 无法在目标站前正确生成临时轨道坐标的问题。通过取消 teleported 站点的临时属性确保时刻表以“传送门 -> teleported -> 临时轨道 -> 目标站点”的正确顺序生成。
- 完善并注入全套 LuaLS 类型注解，系统性消除编辑器告警。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 文件顶部定义 `Teleport.STATE = { DORMANT = 0, QUEUED = 1, TELEPORTING = 2, REBUILDING = 3 }`。
  - 移除了冗余的防御性状态恢复；移除了懒加载回退，直接读取 `portaldata.state`。
  - 补充了顶层依赖模块（State, Util, Schedule, AwCompat）的 `---@type` 依赖注入注解，消除编辑器报错。

- `RiftRail/scripts/migrations.lua`
  - 新增 `Migrations.state_machine_refactor()`: 遍历所有传送门清理旧字段并推齐 `state` 参数。

- `RiftRail/scripts/util.lua`
  - 修复 `rebuild_all_colliders()`：当碰撞器因受阻创建失败时，除了将 `state` 设为 `REBUILDING` 外，直接将其**推入** `storage.active_teleporters` 及列表，交由 `on_tick` 后续接管调度，解决了死锁 BUG。

- `RiftRail/scripts/builder.lua`
  - 严格遵守结构透明原则，在 `on_built` 数据初始化时显式插入 `state = 0` 取代懒加载。
  - 补充了 `State` 模块的 `---@type` 依赖注入注解。

- `RiftRail/scripts/compat/ltn.lua`
  - `insert_portal_sequence(...)`：移除了插入 `teleported` 站点时的 `temporary = true` 属性，让其作为普通临时站（停靠 0 帧）存在，以确保能够正确生成真实的临时轨道坐标。

- `RiftRail/types/`
  - 更新 `portaldata.annotations.lua`，将旧字段替换为 `state`，并清理了遗漏的 `cs2_enabled` 与 `cached_intent_vector`。
  - 更新 `modules.annotations.lua`，补全 `LogicModule` 等相关接口方法。


## 2026-03-15（v0.12.2 开发中：全局数据生命周期重构与兼容模块优化）

### 改动摘要
- **数据架构重构**：全面重构了全局数据的生命周期管理，确立了“新档创世蓝图”与“旧档兜底补丁”分离的标准规范。彻底消除了“数据结构唯一真理（Source of Truth）缺失”的问题。
- **性能与清洁度提升**：依托坚固的全局数据底座，大面积清除了散落在各业务模块高频循环中的冗余“懒加载防卫判断”（`if not storage.xxx`）。
- 优化了 LTN 兼容模块的加载逻辑，引入了“空壳模块（Stub Module）”模式。
- 实现了 LTN 的“优雅卸载”机制，保障玩家中途移除模组后的存档健康。
- 升级了“卸载清理”设置：现在除了 LTN 外，也能一键正确注销所有 Cybersyn 2 (CS2) 的本地和全局注册缓存。
- 修复了“卸载清理”功能的一个严重逻辑错位 Bug：旧版本在清理 LTN 时由于先发送销毁事件后才关闭本地开关，导致真实的底层连接断开指令（`disconnect_surfaces`）被拦截，致使出现“按钮关闭但列车依然跨星系接单”的幽灵连接现象。现在改为直接调用 `purge_legacy_connections` 实施彻底清洗。

### 具体改动
- `RiftRail/scripts/state.lua` 与 `RiftRail/control.lua`
  - 核心重构：废弃了职责模糊的 `ensure_storage()`，拆分为 `State.setup_new_game()` 和 `State.patch_missing_root_tables()` 两个严格隔离的函数。
  - `setup_new_game`：作为新开档专属的“创世蓝图”，无视环境条件、绝对暴力地声明了所有的顶级数据结构（包括散落的缓存表和所有第三方兼容表）。
  - `patch_missing_root_tables`：作为旧存档升级的“兜底补丁”，专门用于在 `on_configuration_changed` 时安全补齐缺失的根节点表。
  - 统一收编：将之前散落在各处的 `storage.active_teleporters`、`storage.rift_rail_player_settings`、LTN/CS2 的路由和连接池数据等“私生子”表全部收编到核心蓝图中统一管理。
- 各业务逻辑文件（`teleport.lua`, `builder.lua`, `gui.lua`, `util.lua`, `cs2.lua`, `ltn.lua`）
  - 代码清洁：大面积清除了冗余的防御性表创建代码（如 `storage.xxx = storage.xxx or {}`），利用新数据架构的“绝对存在”特性，使核心业务代码变得极度清爽。
- `RiftRail/scripts/compat/ltn.lua`
  - 新增顶层环境拦截：利用 `script.active_mods["LogisticTrainNetwork"]` 进行检测，若未安装 LTN，则直接返回空函数壳。
  - 性能提升：移除了 `LTN.on_dispatcher_updated` 高频调度回调中多余的 `is_ltn_active()` 检查，因为顶层硬拦截已确保该函数只在 LTN 存在时执行，从而降低了每次派单事件的函数栈开销。
  - 常量保护：在空壳中保留并导出 `BUTTON_NAME` 常量，防止 GUI 模块等外部调用时因 `nil` 导致崩溃。
  - 数据清理保留：特意在空壳中保留了 `purge_legacy_connections` 和 `rebuild_routing_table_from_storage` 的清空 `storage` 逻辑，确保玩家卸载 LTN 后，存档内的旧路由表和连接池废弃数据能被安全释放。

## 2026-03-14（v0.12.1 开发中：出口智能寻路意图嗅探与终极性能架构敲定）

### 改动摘要
- 彻底敲定出口列车动力维护（`maintain_exit_speed`）的最终重构方案，完美兼顾“复杂路网（如 U 型弯）准确度”、“跨星球（Space Age）坐标系绝对安全”与“极限 UPS 性能”。
- 确立了应对列车异常状态（如 `no_path`、`wait_signal`）的防御性设计哲学：不强行兜底，保留物理阻塞以自动挂起传送队列，完全尊重原版游戏的故障反馈机制。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 【算法升维】 新增 `get_ai_intent_vector(...)`：彻底抛弃基于“终点站绝对坐标”的危险预判，改为提取列车寻路底层 `path.rails` 中紧邻的两根铁轨坐标差，生成“局部物理意图向量”。完美绝杀 Factorio 2.0 跨地表坐标错乱问题，且精准攻克 U 型大回环、折返站等复杂铁路拓扑导致的逻辑反向灾难。
  - 【极致三层缓存架构】 将性能消耗严格分层，彻底消除核心循环的 GC 压力：
    1. **极低频（昂贵层）**：读取 `path.rails` 产生长数组 Table 的操作，被严格限制在列车目的地发生改变的瞬间（基于轻量级的 C++ 指针比对 `current_destination ~= cached_destination_stop`）。
    2. **低频（计算层）**：向量点积计算（`calculate_sign_from_intent`）仅在每次新车厢完成拼接（Splice）时执行一次，彻底免疫引擎底层首尾车厢判定翻转的隐患。
    3. **高频（零开销层）**：每 Tick 运行的推力循环仅包含极速的 Lua 变量乘法，达成 0 跨界 API 调用、0 内存分配。
  - 【安全降级】 在 AI 意图获取失败、寻路数组过短，或处于 `manual_mode` 时，自动无缝降级为 `calculate_speed_sign` 的纯几何兜底推离逻辑。
  - 【机制确立】 明确了 `on_the_path` 的严格拦截边界。当自动模式的列车遭遇断轨（`no_path`）或拥堵时，主动切断物理推力，允许故障车厢“占位停摆”以安全阻塞后续生成。此举避免了盲目推车导致的不可控脱轨，将铁路基建的维护责任原汁原味地交还给玩家。
  

## 2026-03-14（v0.12.1 开发中：出口速度维护逻辑重构与性能优化）

### 改动摘要
- 全面重构出口列车动力维护逻辑，从单一的“纯几何距离比对”升级为“AI 寻路意图嗅探 + 几何物理兜底”的双层架构。
- 彻底解决在复杂路网（如出口紧接急转弯或折返站）时，物理强制推离与列车自动寻路方向冲突导致的严重卡顿与打架问题。
- 引入严密的短生命周期双缓存机制（与车厢拼接事件绑定），在实现智能寻路预判的同时，将手动模式和自动模式的每 Tick（UPS）性能损耗重新压降。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 新增 `get_exit_native_speed_sign(...)`：引入基于目标坐标的向量点积（Dot Product）算法，通过比对列车当前朝向向量与目标站点向量，精准推断列车 AI 行驶意图，免疫任何复杂弯道和不规则建筑布局。
  - 重构 `maintain_exit_speed(...)`：
    - 引入双轨缓存：区分自动模式专属的意图缓存（`cached_exit_drive_sign`）与手动/兜底模式的物理缓存（`cached_speed_sign`）。
    - 抹除 GC 压力：手动模式改为严格读取缓存，彻底消灭每 tick 提取轨道实体坐标带来的海量 Lua Table 分配（GC 垃圾）。
    - 极致指针比对：自动模式下，使用极轻量的 C++ 对象指针比对（`current_destination ~= cached_destination_stop`）来代替高频的逻辑重算，精准拦截玩家中途修改时刻表的突发行为。
  - 增强 `process_transfer_step(...)`（车厢拼接安全防护）：
    - 核心机制修正：在新车厢完成拼接（Splice）时，强行清空上述所有动力与方向缓存。完美规避 Factorio 底层引擎在拼接双向列车时重置车头/车尾判定（Front/Back inversion），从而导致的灾难性物理反弹问题。


## 2026-03-14（v0.12.1 开发中：LTN 兼容模块深度精简与去防卫式编程）

### 改动摘要
- 移除了 `ltn.lua` 顶部基于 `script.active_mods` 的短路拦截机制，解决因模组内部名判定失败导致整个兼容文件静默失效的恶性 Bug。
- 全面清退 LTN 接口调用中的 `pcall`（保护模式调用）包裹，摒弃过度防卫式编程（Over-defensive Programming）。
- 确立以 `remote.interfaces` 存在性校验为唯一前置安全门的轻量化调用规范。

### 具体改动
- `RiftRail/scripts/compat/ltn.lua`
  - 移除文件顶部 15 行的 `if not script.active_mods["logistic-train-network"] then return {空壳} end` 拦截逻辑。
  - `logic_reassign(...)`：剥离 `pcall`，直接调用 `remote.call("logistic-train-network", "reassign_delivery", ...)`。
  - `p_join_pool(...)`：剥离 `pcall`，直接调用 `connect_surfaces`。
  - `p_leave_pool(...)`：剥离 `pcall`，直接调用 `disconnect_surfaces`。
  - `p_commit_all_ltn_connections(...)`：剥离批量连接循环中的 `pcall`。
  - `LTN.purge_legacy_connections()`：剥离清理旧连接双重循环中的 `pcall`。

### 设计优点
1. **Fail-Fast (快速失败) 原则**：LTN 接口极度稳定，一旦未来发生破坏性 API 变更，直接抛出红字报错，比 `pcall` 静默吞噬错误更容易在第一时间定位问题。
2. **零开销与高可读性**：移除了大量匿名函数和 `pcall` 的嵌套，避免了 Lua JIT 优化的打断，代码结构变得极其直观清爽。
3. **架构自洽**：依靠事件驱动本身（没装 LTN 就不会有相关事件触发）以及严谨的 `is_ltn_active()` 前置校验，已经构建了 100% 安全的运行环境，彻底摆脱了画蛇添足的代码设计。


## 2026-03-14（v0.12.1 开发中：LTN 兼容性重构与纯事件驱动）

### 改动摘要
- 重构自定义事件 `TrainDeparting` 的触发时机，精准定位在首节新车厢克隆完毕、旧车厢尚未销毁的“黄金微秒”。
- 事件载荷新增 `new_train` 与 `new_train_id` 字段，实现新旧列车实体状态的在同一帧内的无损暴露。
- 彻底解耦 LTN 兼容模块，移除 `teleport.lua` 中的硬编码回调，改为纯粹的事件总线监听。
- 彻底解决 LTN 跨表面传送时，因短暂的“状态真空期”导致运单被后台调度器错误注销（`has_delivery = false`）的问题。
- 无视且不再依赖第三方胶水模组（如 `se-ltn-glue`），确保在任何模组组合下运单移交的绝对稳定性。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `raise_departing_event(...)`（顶部包裹函数）：新增 `new_train` 参数，并在 `script.raise_event` 的载荷中追加 `new_train` 和 `new_train_id` 字段。
  - `process_transfer_step(...)`：将 `raise_departing_event` 的触发位置，精确移动到时刻表复制完毕后、`car.destroy()` 销毁旧车厢执行前。

- `RiftRail/scripts/compat/ltn.lua`
  - 移除底部对 `se-ltn-glue` 的兼容判断逻辑（不再“躺平”指望第三方抛事件）。
  - 新增 `LTN.on_train_departing(event)` 专属事件处理器，直接提取 `event.new_train` 与 `event.train_id` 并交由 `logic_reassign` 执行极速接管。
  - 调整初始化日志位置，将 `ltn_log` 移出事件处理器外部，避免传送频繁触发导致控制台刷屏。

- `RiftRail/control.lua`
  - `Teleport.init(...)`：彻底移除 `LtnCompat = LTN` 的硬编码依赖注入。
  - 新增对 `RiftRail.Events.TrainDeparting` 的事件总线监听，并将 `LTN.on_train_departing` 挂载其中。

- `RiftRail/doc/API(CN).md` & `RiftRail/doc/API(EN).md`
  - 更新 `TrainDeparting` 事件参数列表，追加 `new_train` 及 `new_train_id` 字段。
  - 新增斜体说明段落，明确指出该事件在“新车已生、旧车未死”的微秒级窗口触发，指导其他物流/调度模组开发者进行正确的生命周期接管。

### 设计优点
1. **零硬编码**：物理传送模块（teleport）不再感知 LTN，回归纯粹的物理引擎定位。
2. **极高鲁棒性**：完美契合 LTN 极其严苛的后台巡逻判定逻辑，用原生的 Factorio 事件机制平替了之前存在隐患的代码调用。
3. **生态闭环**：扩充后的 `TrainDeparting` 载荷成为了 Rift Rail 极其强大的标准 API，为后续接入其他同类模组铺平了道路。


## 2026-03-12（v0.12.0 开发中：CS2 传送后 GUI 刷新逻辑）

### 改动摘要
- 采用"状态驱动（State-Driven）"极简设计，解决 CS2 传送后玩家 GUI 界面过期的问题。
- 由传送发生者（teleport.lua）记录"实时状态"（玩家正在看谁），而非"身份追踪"（谁叫什么）。
- 传送完成后，接管方（cs2.lua）直接对着"当前看着什么"的名单进行"闭眼睁眼"刷新，零性能消耗、零耦合。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `process_transfer_step(...)`（~L1203）：每次生成新车厢后，将成功恢复 GUI 的玩家记录到 `entry_portaldata.restored_guis` 列表（格式：`{ player, entity }`）。
  - `finalize_sequence(...)`（~L1005）：阅后即焚，清理 `entry_portaldata.restored_guis = nil`。
  - `raise_arrived_event(...)` 调用（L981）：修复参数传递，加入第 4 参数 `entry_portaldata.restored_guis`，使事件携带最新玩家状态名单。

- `RiftRail/scripts/compat/cs2.lua`
  - `CS2.on_train_arrived(...)`（~L735）：已实现 GUI 刷新逻辑，对每个玩家进行"闭眼睁眼"操作：
    ```lua
    if event.restored_guis then
        for _, gui_data in ipairs(event.restored_guis) do
            local p = gui_data.player
            local e = gui_data.entity
            -- 最终安全检查：玩家在线、实体健在、玩家依然在看着这个车厢
            if p and p.valid and e and e.valid and p.opened == e then
                p.opened = nil
                p.opened = e  -- Factorio 自动刷新 UI
            end
        end
    end
    ```

### 设计优点
1. **零性能消耗**：没人看 → 列表为空 → 跳过整个刷新逻辑。
2. **零耦合**：teleport 和 cs2 只需通过事件传递数据，不存在消息重复或重发。
3. **零风险**：玩家中间切了界面（`p.opened != e`）→ 判断失败 → 不会强行覆盖，尊重用户操作。
4. **数据极简**：不追踪"谁之前叫什么"，仅记录"玩家此刻看着什么"，权责清晰。

### 闭环完成
传送流程从"发生者记录状态"到"接管者消费状态"形成单向信息流，堪称"极简优雅"的事件驱动设计。


## 2026-03-11（v0.12.0 开发中：CS2 单向路径提醒）

### 改动摘要
- 新增 CS2 单向路径检测：玩家切换传送门 CS2 开关后，若存在 A→B 但不存在 B→A 的回程路径，立即向操作玩家发出提示。
- 仅提醒"单向可达"场景，不提醒"完全无路线"（如玩家刚刚开始建造），避免误导。
- 提示不做持续刷屏，仅在玩家手动操作时触发一次。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`
  - 新增 `add_surface_pair(...)`：向受影响方向对集合中安全插入唯一方向对（防重复）。
  - 新增 `collect_impacted_surface_pairs(portal)`：按操作传送门的 mode/target_ids/source_ids 收集此次开关操作可能影响到的地表方向对，出口侧含全量入口兜底扫描。
  - 新增 `CS2.get_one_way_pairs_for_portal(portal_id)`：基于受影响方向对，用路由缓存判断哪些方向是"有去无回"，返回单向方向对列表。

- `RiftRail/scripts/logic.lua`
  - `Logic.set_cs2_enabled(...)` 新增：调用 `CS2.get_one_way_pairs_for_portal` 取单向方向对，并对操作玩家逐条输出提示消息 `messages.rift-rail-warning-cs2-one-way`。

- `RiftRail/locale/en/strings.cfg`、`locale/zh-CN/strings.cfg`、`locale/ja/strings.cfg`
  - 新增本地化键 `rift-rail-warning-cs2-one-way`，参数：__1__=出发地表名，__2__=目标地表名。

## 2026-03-11（v0.12.0 开发中：CS2 路由缓存增量更新）

### 改动摘要
- CS2 路由缓存新增“按 portal_id 精准增量清理/补写”能力，避免 `set_cs2_enabled` 时全量重建缓存。
- 缓存结构保持 `from_surface -> to_surface` 大表，桶内包含 `by_entry` 入口抽屉与 `flat_edges` 平铺边索引。
- 严格执行开关条件：入口与出口必须同时开启 `cs2_enabled` 才写入缓存；关闭后立即从缓存中清除相关边。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`
  - 新增增量更新辅助函数：
    - `remove_portal_edges_from_cache(...)`：按 portal_id 精准移除相关边与空抽屉。
    - `append_enabled_edges_for_entry(...)`：入口开启时重建该入口抽屉。
    - `append_enabled_edges_for_exit(...)`：出口开启时重建所有指向该出口的边（含 source_ids 不完整兜底扫描）。
    - `refresh_cache_for_toggled_portal(...)`：组合“先清理后补写”的增量流程。
  - 新增 `CS2.on_portal_cs2_toggle(portal_id)`，供开关事件直接触发增量缓存更新。
  - 拆分并复用 `request_cs2_topology_rebuild()`，在增量/全量路径都保持 CS2 拓扑重建节流逻辑。

- `RiftRail/scripts/logic.lua`
  - `Logic.set_cs2_enabled(...)` 改为优先调用 `CS2.on_portal_cs2_toggle(my_data.id)`。
  - 保留旧接口兜底：若无增量接口则回退到 `CS2.on_topology_changed()` 全量重建。

## 2026-03-11（v0.12.0 开发中：诊断完成 - 跨地表传送短暂 no-path 警告根因）

### 改动摘要
- 完整诊断了跨地表 complete 阶段出现短暂 "no-path" 警告的根本原因。
- 确认此现象为 Factorio 引擎级别的架构约束，而非 RiftRail 代码缺陷。
- 验证了完成阶段车库名兜底逻辑（2026-03-10 新增）确实有效解决了车厢头停靠问题。
- 确认 CS2 GUI 面板显示"未由 Cybersyn 2 管理"为 GUI panel 的陈旧状态引用，非所有权问题。

### 根因分析

**No-Path Alert 触发链条：**
1. 列车离开投递目标站 → Factorio 引擎立即运行寻路评估（基于当前时刻表）
2. 此时刻表仅包含目标地表上的车库站（跨地表，无法到达）
3. 寻路失败，触发 "no-path" 警告
4. 同一帧内，CS2 的 `notify_departed` → `delivery.complete` → `query_route_plugins` 链条执行
5. RiftRail route_plugin_callback 接管，覆写时刻表为"入口 -> 目标实名站"
6. 寻路重新计算，恢复正常；警告解除

**关键观察：**
- 该间隙是 Factorio 同步寻路引擎 + 异步插件回调模型的必然结果
- 不在 RiftRail 代码执行过程中，而在 Factorio 引擎代码执行时间窗口中
- 警告持续时间约 1 tick，对功能无任何影响（投递正常完成）

**改进可能性：**
需要 Factorio 引擎层面支持"延迟寻路至插件回调后"的 API，RiftRail 插件层不可单独解决。

### 测试验证
- ✅ 已确认 SE 插件模型同样会遭遇此现象（SE 未使用 group 绑定时亦有同样间隙）
- ✅ CS2 内部调用链同步无延迟
- ✅ 完成阶段车库名兜底确实使用了正确的目标站

### 文档更新
已为 CS2 开发团队准备了英文技术文档，描述该现象的根因、影响范围与架构背景。
- 目标：帮助 CS2 团队了解此为跨引擎的设计约束，非插件层缺陷
- 格式：技术观察报告，非功能请求

## 2026-03-10（v0.12.0 开发中：CS2 传送流程收敛为 SE 同款闭环）

### 改动摘要
- 将 CS2 跨地表接管逻辑收敛为“入口传送站 + 下一实名站”的过渡调度。
- 移除第一节车厢阶段的临时回填钩子，避免与最终 handoff 流程形成混合路径。
- 保留“传送完成后清理过渡临时站，再 `route_plugin_handoff` 交还 CS2”的闭环，避免重复生成临时站。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`
  - `route_train_to_entry(...)` 新增 `continuation_station_name` 参数。
  - 接管时按顺序写入：
    - 入口传送站（带 `riftrail-go-to-id` 条件）。
    - 下一实名站（由 CS2 传入 `stop_entity.backer_name`）。
  - `complete` 场景新增车库名兜底：当 `stop_entity` 缺失时，优先读取当前时刻表末站作为 `continuation_station_name`（通常为车库站）；仅在读取失败时回退为出口站并输出调试日志。
  - 删除 `restore_dropoff_schedule(...)` 与 `rr_cs2_dropoff_info_by_train_id` 缓存路径。
  - `on_train_arrived(...)` 仅执行“先清理临时站，再 handoff”，不再二次补站。
  - 进一步对齐 SE 车组生命周期：
    - 接管时暂时解绑 `luatrain.group`，并覆盖为“两站过渡调度（入口 -> 下一实名站）”。
    - 传送完成后先 `new_train.schedule = nil`，恢复原车组，再 `route_plugin_handoff` 交还 CS2。

- `RiftRail/scripts/teleport.lua`
  - 移除 `CS2Compat.restore_dropoff_schedule(...)` 的第一节回填调用。
  - 移除 `CS2Compat` 依赖注入接收字段。

- `RiftRail/control.lua`
  - `Teleport.init(...)` 移除 `CS2Compat` 注入参数。

## 2026-03-09（v0.12.0 开发中：CS2 兼容骨架接入）

### 改动摘要
- 接入 Cybersyn2 route plugin 骨架，实现 `topology / reachable / route` 三类回调。
- 增加 RiftRail 传送完成后的 CS2 handback 闭环：在 `TrainArrived` 事件中按旧车 ID 归还 delivery。
- 完成运行时接线：`control -> compat.cs2 -> logic/remote`，并在拓扑变化操作后触发 CS2 拓扑重建（带节流）。
- 完成 data 阶段注册：在检测到 `cybersyn2` 时将 RiftRail 回调写入 `mod-data["cybersyn2"].data.route_plugins`。

### 具体改动
- `RiftRail/scripts/compat/cs2.lua`（新文件）
  - 新增 `CS2.init(...)`。
  - 新增 `train_topology_callback(origin_surface_index)`：按 `cs2_enabled` 的 Entry/Exit 连接返回可达 surface 集合。
  - 新增 `reachable_callback(...)`：对不可跨地表路径执行 veto（返回 `true`）。
  - 新增 `route_callback(...)`：跨地表时接管列车，插入前往入口站的调度并记录 handoff 上下文。
  - 新增 `on_train_arrived(event)`：使用 `old_train_id` 定位待归还 delivery，调用 `remote.call("cybersyn2", "route_plugin_handoff", ...)`。
  - 新增 `on_topology_changed()`：节流调用 `remote.call("cybersyn2", "rebuild_train_topologies")`。

- `RiftRail/control.lua`
  - 新增 `require("scripts.compat.cs2")` 并初始化 `CS2Compat`。
  - 将 `CS2Compat` 注入 `Logic.init(...)` 与 `Remote.init(...)`。
  - 新增 `RiftRail.Events.TrainArrived` 监听并转发至 `CS2Compat.on_train_arrived`。

- `RiftRail/scripts/remote.lua`
  - `RiftRail` remote interface 新增：
    - `cs2_train_topology_callback`
    - `cs2_reachable_callback`
    - `cs2_route_callback`
  - 以上回调均转发到 `CS2Compat`。

- `RiftRail/scripts/logic.lua`
  - `Logic.init(...)` 新增 `CS2` 依赖注入。
  - 在 `set_mode / pair_portals / unpair_portals_specific / set_cs2_enabled` 后触发 `CS2.on_topology_changed()`。

- `RiftRail/data-updates.lua`
  - 新增 `has_cs2 = mods["cybersyn2"]` 检测。
  - 在 `has_RiftRail and has_cs2` 时加载 `updates.cs2`。

- `RiftRail/updates/cs2.lua`（新文件）
  - 向 `cybersyn2` 的 `route_plugins` 注册 RiftRail 三个回调：
    - `train_topology_callback = { "RiftRail", "cs2_train_topology_callback" }`
    - `reachable_callback = { "RiftRail", "cs2_reachable_callback" }`
    - `route_callback = { "RiftRail", "cs2_route_callback" }`

## 2026-03-09（v0.12.0 开发中：旧存档 CS2 字段补齐迁移）

### 改动摘要
- 为旧存档中的传送门数据补充 `cs2_enabled` 字段，默认值为 `false`。
- 迁移为一次性任务，在 `on_configuration_changed` 路径执行并写入完成标记，避免重复运行。

### 具体改动
- `RiftRail/scripts/migrations.lua`
  - 新增 `Migrations.patch_cs2_enabled_default()`。
  - 遍历 `storage.rift_rails`，对缺失 `cs2_enabled` 的旧数据补齐 `false`。
  - 新增标志位 `storage.rift_rail_cs2_toggle_migrated`。
  - 在 `Migrations.run_all()` 中接入该迁移任务。

## 2026-03-09（v0.12.0 开发中：新增 CS2 按钮与本地开关链路）

### 改动摘要
- 在传送门 GUI 中新增 CS2 开关，位置位于 LTN 开关上方，仅在安装 `cybersyn2` 时显示。
- 打通 CS2 开关的本地状态链路：`GUI -> Remote -> Logic`，用于保存 `cs2_enabled` 并刷新界面。
- 新增英/日/简中本地化条目，覆盖 CS2 开关标签、状态与提示文案。
- 本次不包含 CS2 路由/拓扑/handoff 兼容逻辑，仅实现按钮与按钮功能。

### 具体改动
- `RiftRail/scripts/gui.lua`
  - 新增 `rift_rail_cs2_switch` 开关组件，显示条件为 `script.active_mods["cybersyn2"]`。
  - 将 CS2 区块放置于 LTN 区块上方。
  - 在 `handle_switch_state_changed` 中新增 `rift_rail_cs2_switch` 分支，调用 `remote.call("RiftRail", "set_cs2_enabled", ...)`。

- `RiftRail/scripts/remote.lua`
  - `RiftRail` remote interface 新增 `set_cs2_enabled(player_index, portal_id, enabled)`，转发到 `Logic.set_cs2_enabled`。

- `RiftRail/scripts/logic.lua`
  - 新增 `Logic.set_cs2_enabled(...)`，负责保存 `portaldata.cs2_enabled` 并刷新 GUI。
  - 在连接归零自动复位逻辑中加入 `portaldata.cs2_enabled = false`。

- `RiftRail/scripts/builder.lua`
  - 新建传送门数据时新增默认字段 `cs2_enabled = false`。

- `RiftRail/locale/en/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

- `RiftRail/locale/ja/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

- `RiftRail/locale/zh-CN/strings.cfg`
  - 新增 `rift-rail-cs2-label / connected / disconnected / tooltip`。

## 2026-03-06（v0.11.10 开发中：入口拆除时的出口锁泄漏修复）

### 改动摘要
- 修复入口传送门在传送中被拆除后，出口 `locking_entry_id` 可能残留导致后续长期无法抢锁的问题。
- 采用最小改动策略：仅在 `on_tick` 的“无效 portal 清理”分支增加一次临终解锁。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `Teleport.on_tick(event)`：当活跃列表中的入口 `portaldata` 已失效时，若其记录了 `locked_exit_unit_number`，则尝试定位出口并在 `locking_entry_id == 该入口unit_number` 时释放锁，随后再执行原有活跃列表清理。

## 2026-03-06（v0.11.10 开发中：修正放置间隔缓存读写对象不一致）

### 改动摘要
- 修正 `placement_interval` 缓存写在出口、读取在入口导致缓存不命中的问题。
- 保持现有流程不变，仅统一为“入口侧写入 + 入口侧读取 + 会话结束清理”。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `process_transfer_step(...)`：首节车时将 `placement_interval` 写入 `entry_portaldata`（与 `process_teleport_sequence(...)` 读取对象一致）。
  - `finalize_sequence(...)`：将 `placement_interval` 清理从 `exit_portaldata` 调整为 `entry_portaldata`。

## 2026-03-06（v0.11.10 开发中：出口速度方向缓存更新时机优化）

### 改动摘要
- 将出口速度方向计算从 `maintain_exit_speed` 的每 tick 重算，调整为“拼接成功后更新缓存，tick 内直接读取缓存”。
- 结合实测结论（拼接会触发 `train_id` 变化），采用单一触发点策略，不再引入额外的 `train_id` 变化判断分支。
- 保留“缓存缺失时兜底重算”以覆盖极端首帧/异常路径，保证稳定性。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `process_transfer_step(...)`：在新车厢创建并拼接完成后，写入 `exit_portaldata.cached_speed_sign`。
  - `maintain_exit_speed(...)`：优先读取 `cached_speed_sign`，不再每 tick 调用 `calculate_speed_sign(...)`；仅在缓存为空时兜底计算一次并回填。
  - `finalize_sequence(...)`：新增 `exit_portaldata.cached_speed_sign = nil` 清理，避免跨会话残留。

## 2026-03-04（v0.11.9 开发中：Kux-SlimInserters 兼容修复）

### 改动摘要
- 修复与 `Kux-SlimInserters` 并用时，`rift-rail-core` 可选区域被缩小导致核心点击困难、GUI 难以打开的问题。
- 在 `data-final-fixes` 中增加条件恢复逻辑：仅当检测到 `Kux-SlimInserters` 时恢复核心 `selection_box`。

### 具体改动
- `RiftRail/data-final-fixes.lua`
  - 新增 `KUX_SLIM_INSERTERS_INSTALLED` 检测（`mods["Kux-SlimInserters"]`）。
  - 若已安装该模组，则将 `data.raw["container"]["rift-rail-core"].selection_box` 恢复为 `{{-2,-2},{2,2}}`。
  - 保留调试日志输出，便于在启用 `rift-rail-debug-mode` 时追踪兼容修复是否生效。

## 2026-03-04（v0.11.9 开发中：日语本地化首版与术语修正）

### 改动摘要
- 新增 `ja` 本地化目录并完成首版文本，覆盖 `strings / informatron / tips` 三类文件。
- 日语文案保持 `Rift Rail` 英文名不变，同时统一保留原有占位符与富文本标记格式。
- 根据审阅反馈修正术语自然度与残留拼写问题（如 `Entry（送信）/Exit（受信）` 改为 `入口/出口`）。

### 具体改动
- `RiftRail/locale/ja/strings.cfg`
  - 新建日语版 `strings` 文案（与 `en` 键集合保持一致）。
  - 调整模式命名：`rift-rail-mode-entry=入口`、`rift-rail-mode-exit=出口`。
  - 清理错误拼接残留：`rift-rail-error-station-missing` 行内重复脏串已移除。

- `RiftRail/locale/ja/informatron.cfg`
  - 新建日语版 Informatron 页面文案。

- `RiftRail/locale/ja/tips.cfg`
  - 新建日语版 Tips 文案。

- `doc/unused-locale-keys-2026-03-04.md`
  - 生成未使用本地化键扫描报告（用于清理决策与后续审查）。

## 2026-03-04（v0.11.9 开发中：索引命名可读性整理）

### 改动摘要
- 不改动任何传送逻辑，仅优化索引参数命名，降低“目标索引/回退索引”语义歧义。
- 保持调用链与行为完全一致，仅在函数签名和注释层面做可读性增强。
- `read_train_schedule_index(...)` 改为仅读取真实 `schedule.current`，不再按列车状态分支推断索引。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `read_train_schedule_index(train)`：
    - 移除 `wait_station / on_the_path / wait_signal / arrive_*` 的状态分支。
    - 统一返回真实时刻表指针 `train.schedule.current`。
    - 增加记录表与索引范围校验，异常时返回 `nil`。
  - `restore_train_state(train, portaldata, apply_speed, ...)`：
    - 参数名由 `target_index` 调整为 `preferred_index`。
    - 对应注释同步更新为“优先恢复索引”。
    - 函数内部变量计算保持不变：仍为“优先参数，其次 `saved_schedule_index`”。

## 2026-03-04（v0.11.9 开发中：传送缓存与出口速度维护重构）

### 改动摘要
- 删除传送结束阶段的两处冗余/误导清理：`exit_portaldata.entry_car` 与 `exit_portaldata.cached_geo`。
- 保留 `cached_place_query` 的运行期复用，并在建筑克隆后强制失效，避免深拷贝带入旧坐标查询参数。
- 修正文案注释，明确 `cached_place_query` 只在当前门坐标/朝向下有效。
- 修正 `entry_portaldata.exit_car` 的注释语义，明确其用于入口侧流程状态判定。
- 将出口速度函数改为卫语句结构并重命名为 `maintain_exit_speed`，同时移除每 60 tick 的调试打印。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - `finalize_sequence(...)`：
    - 删除 `exit_portaldata.entry_car = nil`（exit 侧无该活跃字段）。
    - 删除 `exit_portaldata.cached_geo = nil`（几何缓存由懒加载维护）。
    - 更新 `entry_portaldata.exit_car` 清理注释，明确是“上一节已生成替身”状态标记。
  - `process_transfer_step(...)`：
    - 更新 `cached_place_query` 初始化注释，明确克隆/重建后需失效再懒加载。
    - 更新 `entry_portaldata.exit_car = new_car` 注释，去除“没什么用”的误导描述。
    - 将出口速度缓存注释中的函数名更新为 `maintain_exit_speed`。
  - `sync_momentum(...)` -> `maintain_exit_speed(...)`：
    - 重构为卫语句，提前返回无效 `exit_portal/car/train` 分支，减少嵌套。
    - 删除每 60 tick 调试日志打印，保留核心速度维护逻辑。

- `RiftRail/scripts/builder.lua`
  - `on_cloned(event)`：
    - 在重建 `cached_spawn_pos/cached_check_area` 后，新增 `new_data.cached_place_query = nil`，防止深拷贝脏缓存。

## 2026-03-02（v0.11.8：多出口路由逻辑更新，加入入口信号与缓存优先）

### 改动摘要
- 多出口路由优先级更新为：列车时刻表信号 > 入口电路信号 > 默认出口（默认失效则首个可用出口）。
- 在碰撞触发时预选出口并写入缓存，等待阶段优先命中缓存，缓存失效时再重选。
- 新增无效 `go-to-id` 提示（列车信号 / 入口信号），用于提示“信号存在但目标出口无效”的情况。

### 具体改动
- `RiftRail/scripts/teleport.lua`
  - 新增 `get_entry_circuit_go_to_id(entry_portaldata)`：读取入口侧电路网络 `riftrail-go-to-id`。
  - 新增 `resolve_valid_target(entry_portaldata, target_id)`：统一目标出口有效性校验。
  - 更新 `select_target_exit(entry_portaldata)`：
    - 单出口快速通道保持不变；
    - 多出口场景先尝试缓存 `waiting_target_exit_id`；
    - 列车信号无效时继续尝试入口信号；
    - 信号均无效时回退默认出口/首个可用出口。
  - 更新 `Teleport.on_collider_died(event)`：入队时预选出口并缓存。
  - 更新 `process_waiting_logic(portaldata)`：每 tick 优先使用缓存目标，失效后重选并回写缓存。
  - 更新 `initialize_teleport_session(...)`：会话启动后清理 `waiting_target_exit_id`。

- `RiftRail/locale/zh-CN/strings.cfg`
  - 新增：
    - `rift-rail-error-invalid-go-to-id-train`
    - `rift-rail-error-invalid-go-to-id-entry`

- `RiftRail/locale/en/strings.cfg`
  - 新增：
    - `rift-rail-error-invalid-go-to-id-train`
    - `rift-rail-error-invalid-go-to-id-entry`

## 2026-03-02（v0.11.8：路由文案与高级用法说明同步）

### 改动摘要
- 将路由说明统一为实际实现：列车时刻表信号 > 入口电路信号 > 默认出口（默认不可用则首个可用出口）。
- 更新高级用法中的路由优先级描述，移除旧的 LTN 自动路由描述。

### 具体改动
- `RiftRail/locale/zh-CN/informatron.cfg`
  - 更新 `page_routing_text_2` 路由优先级与兜底行为。

- `RiftRail/locale/en/informatron.cfg`
  - 更新 `page_routing_text_2` 路由优先级与兜底行为。

- `RiftRail/locale/zh-CN/tips.cfg`
  - 更新 `item-description-advanced` 的路由优先级说明。

- `RiftRail/locale/en/tips.cfg`
  - 更新 `item-description-advanced` 的路由优先级说明。

## 2026-03-01（AW桥接参数改为实体对象）

### 改动摘要
- 将 AW 兼容桥接调用参数从 `unit_number` 改为 `LuaEntity`，以支持 AW 侧完整更新反向映射。

### 具体改动
- `scripts/compat/aw.lua`
  - `remote.call("AssemblyWagon", "transfer_binding", ...)` 参数由
    - `old_car.unit_number, new_car.unit_number`
    改为
    - `old_car, new_car`。

### 备注
- 该调整用于配合 AssemblyWagon 新增的 `transfer_binding(old_wagon, new_wagon)` 接口实现。

## 2026-03-01（Informatron兼容文件归档到compat）

### 改动摘要
- 将 Informatron 适配脚本移动到 `scripts/compat` 目录，统一兼容模块结构。
- 同步更新 `control.lua` 中的加载路径，保持运行逻辑不变。

### 具体改动
- `scripts/compat/informatron.lua`
  - 由原 `scripts/informatron.lua` 迁移而来（仅路径调整）。

- `control.lua`
  - `require("scripts.informatron")` 改为 `require("scripts.compat.informatron")`。

## 2026-03-01（compat目录重构 + AW兼容接入）

### 改动摘要
- 在 `scripts` 下建立 `compat` 目录，统一管理兼容模块。
- 将 LTN 兼容模块迁移到 `scripts/compat/ltn.lua`。
- 新增 AssemblyWagon 兼容模块 `scripts/compat/aw.lua`，用于车厢传送后 old/new 映射桥接。
- 在传送主流程中加入单点兼容调用，统一覆盖 clone/create 两种创建路径。

### 具体改动
- `scripts/compat/ltn.lua`
  - 由原 `scripts/ltn_compat.lua` 迁移而来（文件路径调整）。

- `scripts/compat/aw.lua`（新文件）
  - 新增 `AW.init(deps)`：缓存 `script.active_mods["AssemblyWagon"]` 状态。
  - 新增 `AW.on_car_replaced(old_car, new_car)`：
    - 仅在 AssemblyWagon 已启用且 `old/new` 均为 `assembly-wagon` 时执行。
    - 检查 `remote.interfaces["AssemblyWagon"].transfer_binding` 是否存在。
    - 使用 `pcall(remote.call, ...)` 调用接口并在调试模式下记录失败日志。

- `control.lua`
  - `require("scripts.ltn_compat")` 改为 `require("scripts.compat.ltn")`。
  - 新增 `local AWCompat = require("scripts.compat.aw")`。
  - 启动时调用 `AWCompat.init({ log_debug = log_debug })`。
  - 向 `Teleport.init(...)` 注入 `AwCompat = AWCompat`。

- `scripts/teleport.lua`
  - 新增依赖字段 `AwCompat` 并在 `Teleport.init(deps)` 中接收。
  - 在 `new_car` 创建成功后、`car.destroy()` 前调用：
    - `AwCompat.on_car_replaced(car, new_car)`
  - 该调用点统一适配 clone/create 路径，无需在多处分支重复判断。

### 备注
- 目前仅完成 RiftRail 侧兼容桥接；AssemblyWagon 侧 `remote interface` 后续再接。
