# RiftRail 开发变更记录

> 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。
> 补充：本文件从 v0.11.7 之后开始维护；当前 2026-03-02 的全部条目均归入 v0.11.8 发布内容。

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
